#!/usr/bin/env nu

const ROOT = path self ..

# Traverse literal paths so Windows separators and brackets are never glob syntax.
def nu-files [directory: path] {
    mut files = []
    for item in (ls --all $directory) {
        if $item.type == "dir" { $files = ($files | append (nu-files $item.name)) }
        if $item.type == "file" and ($item.name | str ends-with ".nu") {
            $files = ($files | append $item.name)
        }
    }
    $files
}


# Production subprocess policy:
# - captured/non-interactive child processes use the shared subprocess contract;
# - the runtime gate keeps a self-contained equivalent because seed Nushell must
#   parse it before project modules;
# - edit-managed keeps one direct editor invocation so the editor owns the TTY.

def expect [ok: bool label: string] {
    if not $ok { error make {msg: ("FAILED: " + $label)} }
    print ("[pass] " + $label)
}

def rel [path: path] {
    $path | path relative-to $ROOT | into string | str replace --all '\' '/'
}

def production-files [] {
    nu-files ($ROOT | path join "scripts")
    | where {|file|
        let name = ($file | path basename)
        not (
            ($name | str contains "test") or ($name | str contains "fixture") or ($name in ["validate-syntax.nu" "check-compatibility.nu" "syntax-self-test.nu"])
        )
    }
}

def main [] {
    mut last_exit_offenders = []
    mut capture_offenders = []

    for file in (production-files) {
        let relative = (rel $file)
        let text = (open --raw $file)

        if ($text | str contains '$env.LAST_EXIT_CODE') and $relative not-in ["scripts/edit-managed.nu" "scripts/resolve-config.nu"] {
            $last_exit_offenders = ($last_exit_offenders | append $relative)
        }

        let direct_capture = (($text | str contains 'do { ^') or ($text | str contains 'do -i { ^'))
        if $direct_capture and not ($relative in ["scripts/modules/subprocess.nu" "scripts/modules/nu-runtime.nu"]) {
            $capture_offenders = ($capture_offenders | append $relative)
        }
    }

    expect ($last_exit_offenders | is-empty) ("no unapproved production LAST_EXIT_CODE use: " + ($last_exit_offenders | str join ", "))
    expect ($capture_offenders | is-empty) ("no unapproved production command capture bypass: " + ($capture_offenders | str join ", "))

    let editor = (open --raw ($ROOT | path join "scripts" "edit-managed.nu"))
    expect (($editor | find '$env.LAST_EXIT_CODE' | length) == 1) "managed editor has exactly one TTY exit-code exception"
    expect ($editor | str contains "Interactive editors need the real terminal") "managed editor documents the TTY exception"

    let resolver = (open --raw ($ROOT | path join "scripts" "resolve-config.nu"))
    expect (($resolver | lines | where {|line| $line | str contains '$env.LAST_EXIT_CODE' } | length) == 1) "merge editor has exactly one direct TTY status check"
    expect ($resolver | str contains 'interactive-merge ["--source" ($data_root | into string) "merge-all"]') "merge-all uses the interactive boundary"
    expect ($resolver | str contains 'interactive-merge ["--source" ($data_root | into string) "merge"') "single-target merge uses the interactive boundary"

    let runtime = (open --raw ($ROOT | path join "scripts" "modules" "nu-runtime.nu"))
    expect ($runtime | str contains "Bootstrap boundary runner") "runtime gate documents its self-contained subprocess boundary"
    expect ($runtime | str contains "def runtime-run") "runtime gate centralizes bootstrap child execution"
    expect (not ($runtime | str contains '$env.LAST_EXIT_CODE')) "runtime gate does not depend on LAST_EXIT_CODE"
    expect ($runtime | str contains "exec $exe --no-config-file $script") "runtime gate transfers final TTY ownership with exec"

    for relative in [
        "scripts/update.nu"
        "scripts/cleanup-direnv.nu"
        "scripts/auto-sync-main.nu"
        "scripts/capture-work-environment.nu"
        "scripts/capture-rust-state.nu"
        "scripts/restore-rust-state.nu"
        "scripts/capture-tool-state.nu"
        "scripts/capture-vscode-extensions.nu"
        "scripts/install-vscode-extensions.nu"
        "scripts/migrate-dotfiles.nu"
        "scripts/setup-merge-tool.nu"
        "scripts/setup-onedrive-ignore-upload.nu"
        "scripts/setup-platform-shims.nu"
        "scripts/resolve-config.nu"
        "scripts/modules/core.nu"
        "scripts/modules/planner.nu"
        "scripts/modules/ssh-keys.nu"
        "scripts/modules/toolchains.nu"
        "scripts/modules/upgrade.nu"
        "scripts/modules/dotfiles.nu"
    ] {
        let text = (open --raw ($ROOT | path join $relative))
        expect ($text | str contains "run-command") ($relative + " uses the shared subprocess contract")
    }

    print "[ok] Production subprocess policy regressions passed."
}
