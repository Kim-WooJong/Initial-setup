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



def fail [message: string] {
    print --stderr ("[FAIL] " + $message)
    exit 1
}


def require-text [text: string needle: string label: string] {
    if not ($text | str contains $needle) { fail $label }
}


def forbid-text [text: string needle: string label: string] {
    if ($text | str contains $needle) { fail $label }
}


def production-nu-files [] {
    let root_files = [($ROOT | path join "setup.nu") ($ROOT | path join "setup-main.nu")]
    let scripts = (
        nu-files ($ROOT | path join "scripts")
        | where {|file|
            let name = ($file | path basename)
            not (($name | str contains "test") or ($name | str contains "fixture"))
        }
    )
    $root_files | append $scripts
}


def main [] {
    let entry = (open --raw ($ROOT | path join "setup.nu"))
    let orchestration = (open --raw ($ROOT | path join "setup-main.nu"))
    let run_state = (open --raw ($ROOT | path join "scripts" "modules" "run-state.nu"))

    require-text $entry "def interactive-child" "setup.nu must have an explicit interactive child boundary"
    require-text $entry "exec $exe --no-config-file $script ...$args" "interactive setup must transfer native TTY ownership with exec"
    require-text $entry 'interactive-child ($ROOT | path join "setup-main.nu") $args' "setup-main.nu must use the interactive TTY boundary"
    let captured_setup_main = (
        $entry | lines | where {|line| ($line | str trim) == 'child ($ROOT | path join "setup-main.nu") $args' }
    )
    if not ($captured_setup_main | is-empty) { fail "setup-main.nu must not run through captured child()" }

    forbid-text $entry 'run-command $bash_exe' "POSIX bootstrap must not wrap the re-entered interactive setup in captured output"
    forbid-text $entry 'run-command $shell_exe' "Windows bootstrap must not wrap the re-entered interactive setup in captured output"
    require-text $entry 'exec $bash_exe $bootstrap ...$args' "POSIX bootstrap must receive the real terminal"
    require-text $entry 'exec $shell_exe ...$args' "Windows bootstrap must receive the real terminal"

    require-text $orchestration "is-user-interruption" "setup-main.nu must classify user interruptions"
    require-text $orchestration 'finish-run $failed_run $final_status $detail' "setup-main.nu must persist interrupted/failed state distinctly"
    require-text $orchestration 'exit 130' "Ctrl+C must terminate with the conventional interrupted exit code"
    require-text $run_state '"running" "failed" "interrupted"' "interrupted runs must remain resumable"

    let dotfiles = (open --raw ($ROOT | path join "scripts" "modules" "dotfiles.nu"))
    let sync_up = (open --raw ($ROOT | path join "scripts" "sync-up.nu"))
    let sync_down = (open --raw ($ROOT | path join "scripts" "sync-down.nu"))
    let transport = (open --raw ($ROOT | path join "scripts" "sync-transport.nu"))
    let runtime = (open --raw ($ROOT | path join "scripts" "modules" "nu-runtime.nu"))
    let local_guard = (open --raw ($ROOT | path join "scripts" "modules" "sync-local-guard.nu"))
    require-text $dotfiles '"--manual"' "manual dotpush/dotpull must enter the explicit manual sync path"
    require-text $sync_up 'exec $exe ...$args' "manual dotpush must preserve native terminal ownership through sync-up"
    require-text $sync_down 'exec $nu.current-exe ...$args' "manual dotpull must preserve native terminal ownership through sync-down"
    require-text $transport 'runtime-execute $IMPL $args' "sync transport must delegate through the runtime TTY boundary"
    require-text $runtime 'exec $exe --no-config-file $script ...$args' "selected runtime must receive native terminal ownership"
    require-text $local_guard 'let choice = (input | str trim)' "manual pull confirmation must read from the native terminal"

    # Captured setup leaves must not gain interactive input or import the menu.
    # Scan the actual run-script call sites, including future additions.
    let leaves = ($orchestration | parse --regex 'run-script [^\r\n]*\(\$scripts \| path join "(?P<name>[^\"]+\.nu)"\)' | get name | uniq)
    if ($leaves | is-empty) { fail "No setup leaf calls were inspected" }
    for name in $leaves {
        let leaf = (open --raw ($ROOT | path join "scripts" $name))
        let code = ($leaf | lines | where {|line| not ($line | str trim | str starts-with "#") } | str join (char nl))
        if $code =~ '\binput\b' or ($code | str contains "setup-policy.nu") or ($code | str contains "setup-reconcile.nu") {
            fail ("Captured setup leaf may request interactive input: " + $name)
        }
    }

    for relative in ["setup-main.nu" "scripts/preflight.nu" "scripts/modules/conflicts.nu" "scripts/modules/planner.nu" "scripts/resolve-config.nu"] {
        let source = (open --raw ($ROOT | path join $relative))
        for line in ($source | lines | where {|line| $line | str contains '"diff"' }) {
            if not ($line | str contains '"--no-pager" "--use-builtin-diff"') {
                fail ("Captured diff must not launch a pager or external editor: " + $relative)
            }
        }
    }

    mut prompt_offenders = []
    for file in (production-nu-files) {
        let text = (open --raw $file)
        for line in ($text | lines) {
            let trimmed = ($line | str trim)
            if (($trimmed | str contains '(input "') or ($trimmed | str contains '(input ("') or ($trimmed | str contains '(input $')) {
                $prompt_offenders = ($prompt_offenders | append (($file | path relative-to $ROOT | into string) + ": " + $trimmed))
            }
        }
    }
    if not ($prompt_offenders | is-empty) {
        fail ("interactive prompts must be printed explicitly before bare input; offenders: " + ($prompt_offenders | str join " | "))
    }

    print "[pass] interactive TTY and explicit-prompt policy"
}
