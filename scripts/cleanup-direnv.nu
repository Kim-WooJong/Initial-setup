#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home try-machine-context]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

def migration-marker [] {
    (nu-home)
    | path join ".config" "dotfiles" "migrations" "direnv-removed-v0.8.9.nuon"
}

def powershell-command [] {
    if not (which pwsh | is-empty) { return "pwsh" }
    if not (which powershell | is-empty) { return "powershell" }
    ""
}

def remove-direnv-source-line [file: path] {
    if not ($file | path exists) { return false }

    let current = (open --raw $file)
    let filtered = (
        $current
        | lines
        | where { |line| not ($line | str contains "source ~/.config/nushell/modules/direnv.nu") }
        | where { |line| not ($line | str contains "# direnv integration") }
        | str join (char nl)
    )

    if $filtered == ($current | str trim --right) {
        return false
    }

    ($filtered | str trim --right) + (char nl)
    | save --force $file

    print ("[migrate] Removed legacy direnv source line from " + ($file | into string))
    true
}

def nushell-config-dirs [] {
    let canonical = ((nu-home) | path join ".config" "nushell")
    let default_dir = ($nu | get --optional default-config-dir)
    let config_path = ($nu | get --optional config-path)

    mut dirs = [$canonical]

    if $default_dir != null {
        let expanded = ($default_dir | path expand)

        if not ($expanded in $dirs) {
            $dirs = ($dirs | append $expanded)
        }
    }

    if $config_path != null {
        let parent = ($config_path | path dirname | path expand)

        if not ($parent in $dirs) {
            $dirs = ($dirs | append $parent)
        }
    }

    $dirs
}

def cleanup-live-nushell [] {
    mut changed = false

    for config_dir in (nushell-config-dirs) {
        let targets = [
            ($config_dir | path join "modules" "direnv.nu")
            ($config_dir | path join "autoload" "initial-setup-direnv.nu")
        ]

        for target in $targets {
            if ($target | path exists) {
                rm $target
                print ("[migrate] Removed legacy direnv file: " + ($target | into string))
                $changed = true
            }
        }

        let config_file = ($config_dir | path join "config.nu")

        if (remove-direnv-source-line $config_file) {
            $changed = true
        }
    }

    $changed
}

def cleanup-private-source [] {
    let context = ((try-machine-context) | default {})
    let data_root_value = ($context | get --optional data_root)

    if $data_root_value == null {
        return false
    }

    let data_root = ($data_root_value | path expand)
    mut changed = false

    let targets = [
        ($data_root | path join "home" "dot_config" "nushell" "modules" "direnv.nu")
        ($data_root | path join "home" "dot_config" "nushell" "autoload" "initial-setup-direnv.nu")
    ]

    for target in $targets {
        if ($target | path exists) {
            rm $target
            print ("[migrate] Removed legacy private direnv file: " + ($target | into string))
            $changed = true
        }
    }

    let private_config = ($data_root | path join "home" "dot_config" "nushell" "config.nu")

    if (remove-direnv-source-line $private_config) {
        $changed = true
    }

    $changed
}

def cleanup-windows-env [] {
    if $nu.os-info.name != "windows" {
        return {
            changed: false
            preserved_custom: false
        }
    }

    let shell = (powershell-command)

    if ($shell | is-empty) {
        print "[warn] PowerShell not found; legacy User-scope direnv environment cleanup skipped."

        return {
            changed: false
            preserved_custom: false
        }
    }

    let script = ($TOOLS_ROOT | path join "scripts" "windows" "cleanup-direnv-env.ps1")
    let args = ["-NoProfile" "-ExecutionPolicy" "Bypass" "-File" ($script | into string)]
    let result = (run-command $shell $args)
    if not $result.ok {
        print --stderr ("[warn] " + (command-failure-message "Legacy direnv environment cleanup" $result))
        return {
            changed: false
            preserved_custom: false
        }
    }
    let output = ($result.stdout | str trim)
    if ($output | is-empty) {
        return {
            changed: false
            preserved_custom: false
        }
    }

    let payload = ($output | from json)
    mut changed = false
    mut preserved_custom = false

    for item in $payload.variables {
        if $item.action == "removed-old-managed-value" {
            print ("[migrate] Removed old Initial-setup User-scope " + $item.name)
            $changed = true
        } else if $item.action == "preserved-custom-value" {
            print ("[keep] Preserved custom User-scope " + $item.name + " = " + $item.previous)
            $preserved_custom = true
        }
    }

    {
        changed: $changed
        preserved_custom: $preserved_custom
    }
}

def external-direnv-path [] {
    let rows = (
        which --all direnv
        | where { |row| ($row.type? | default "") == "external" }
    )

    if ($rows | is-empty) {
        return ""
    }

    $rows | get 0.path | into string
}

def looks-like-winget-direnv [path: string] {
    if ($path | is-empty) { return false }

    let normalized = ($path | str replace --all '\' '/')
    (($normalized | str contains --ignore-case "/microsoft/winget/packages/direnv.direnv_") or ($normalized | str contains --ignore-case "/microsoft/winget/packages/direnv.direnv/"))
}

def uninstall-old-winget-direnv [] {
    if $nu.os-info.name != "windows" {
        return false
    }

    if (which winget | is-empty) {
        return false
    }

    let executable = (external-direnv-path)

    if not (looks-like-winget-direnv $executable) {
        if not ($executable | is-empty) {
            print ("[keep] External direnv is not the former Winget package path: " + $executable)
        }

        return false
    }

    print ("[migrate] Removing former Initial-setup Winget direnv package: " + $executable)

    let args = [
        "uninstall"
        "--id"
        "direnv.direnv"
        "--exact"
        "--source"
        "winget"
        "--accept-source-agreements"
        "--disable-interactivity"
    ]

    let result = (run-command "winget" $args --live)

    if $result.ok {
        print "[ok] Winget direnv package removed."
        return true
    }

    print ("[warn] " + (command-failure-message "Winget direnv removal" $result))
    false
}

def save-marker [
    files_changed: bool
    env_changed: bool
    custom_env_preserved: bool
    package_removed: bool
] {
    let file = (migration-marker)
    mkdir ($file | path dirname)

    {
        version: "0.8.9"
        completed_at: (date now)
        legacy_files_changed: $files_changed
        legacy_env_changed: $env_changed
        custom_env_preserved: $custom_env_preserved
        winget_package_removed: $package_removed
    }
    | to nuon
    | save --force $file
}

def main [
    --force
] {
    let marker = (migration-marker)

    if ($marker | path exists) and not $force {
        print "[ok] Legacy direnv migration already completed."
        return
    }

    let live_changed = (cleanup-live-nushell)
    let private_changed = (cleanup-private-source)
    let env_result = (cleanup-windows-env)

    # This uninstall is deliberately one-time. After the migration marker is
    # written, Initial-setup will never remove a later manual direnv install.
    let package_removed = (uninstall-old-winget-direnv)
    let files_changed = ($live_changed or $private_changed)

    save-marker $files_changed $env_result.changed $env_result.preserved_custom $package_removed

    print "[ok] Legacy Initial-setup direnv migration complete."
    print "[info] Restart the terminal once so any already-loaded PWD hook disappears from the parent shell."
    print "[info] direnv is no longer part of Initial-setup's managed environment."
}
