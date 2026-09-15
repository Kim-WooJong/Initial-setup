#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def powershell-command [] {
    if not (which pwsh | is-empty) { return "pwsh" }
    if not (which powershell | is-empty) { return "powershell" }
    ""
}

def remove-source-line [file: path] {
    if not ($file | path exists) { return }

    let current = (open --raw $file)
    let lines = (
        $current
        | lines
        | where { |line| not ($line | str contains "source ~/.config/nushell/modules/direnv.nu") }
        | where { |line| not ($line | str contains "# direnv integration") }
    )

    ($lines | str join (char nl) | str trim --right) + (char nl)
    | save --force $file
}

def cleanup-private-source [] {
    let machine_file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    if not ($machine_file | path exists) { return }

    let context = (open $machine_file)
    let data_root = ($context.data_root | path expand)

    let targets = [
        ($data_root | path join "home" "dot_config" "nushell" "modules" "direnv.nu")
        ($data_root | path join "home" "dot_config" "nushell" "autoload" "initial-setup-direnv.nu")
    ]

    for target in $targets {
        if ($target | path exists) {
            rm $target
            print ("[migrate] Removed legacy private direnv file: " + ($target | into string))
        }
    }
}

def cleanup-live-files [] {
    let targets = [
        ((nu-home) | path join ".config" "nushell" "modules" "direnv.nu")
        ((nu-home) | path join ".config" "nushell" "autoload" "initial-setup-direnv.nu")
    ]

    for target in $targets {
        if ($target | path exists) {
            rm $target
            print ("[migrate] Removed legacy live direnv file: " + ($target | into string))
        }
    }

    let config_file = ((nu-home) | path join ".config" "nushell" "config.nu")
    remove-source-line $config_file
}

def cleanup-windows-env [] {
    if $nu.os-info.name != "windows" { return }

    let shell = (powershell-command)
    if ($shell | is-empty) {
        print "[warn] PowerShell not found; legacy direnv User-scope cleanup skipped."
        return
    }

    let script = ($TOOLS_ROOT | path join "scripts" "windows" "cleanup-direnv-env.ps1")
    let args = ["-NoProfile" "-ExecutionPolicy" "Bypass" "-File" ($script | into string)]
    let output = (^$shell ...$args | str trim)

    if ($env.LAST_EXIT_CODE | default 0) != 0 {
        print "[warn] Legacy direnv environment cleanup failed."
        return
    }

    if ($output | is-empty) { return }

    let result = ($output | from json)

    for item in $result.variables {
        if $item.action == "removed-old-managed-value" {
            print ("[migrate] Removed old Initial-setup User-scope " + $item.name)
        } else if $item.action == "preserved-custom-value" {
            print ("[keep] Preserved custom User-scope " + $item.name + " = " + $item.previous)
        }
    }
}

def main [] {
    cleanup-private-source
    cleanup-live-files
    cleanup-windows-env

    print "[ok] Legacy Initial-setup direnv integration cleanup complete."
    print "[info] direnv is no longer installed or configured by Initial-setup."
}
