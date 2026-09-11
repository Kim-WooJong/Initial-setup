#!/usr/bin/env nu

def machine-config-path [] {
    $nu.home-path
    | path join ".config" "dotfiles" "config.nuon"
}

def run-script [
    tools_root: path
    name: string
] {
    let script = ($tools_root | path join "scripts" $name)

    if not ($script | path exists) {
        print ("[WARN] Repair script missing: " + $name)
        return false
    }

    ^nu $script

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print ("[WARN] Repair failed: " + $name)
        return false
    }

    true
}

def main [
    --fix
] {
    let config_file = (machine-config-path)

    print ("Nushell      : " + $env.NU_VERSION)
    print ("OS           : " + $nu.os-info.name)
    print ("Machine cfg  : " + ($config_file | into string))

    if not ($config_file | path exists) {
        print "[FAIL] Machine config is missing"
        print "[info] Run nu setup.nu first."
        return
    }

    let context = (open $config_file)
    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)

    print ("Machine      : " + $context.machine.name)
    print ("Profile      : " + $context.machine.profile)
    print ("Private data : " + ($data_root | into string))
    print ("Sync         : " + ($context.sync.enabled | into string) + " / " + ($context.sync.interval_minutes | into string) + " min")
    print ""

    if ($data_root | path exists) {
        print "[ok] Private data root exists"
    } else {
        print "[FAIL] Private data root unavailable"
    }

    for tool in [
        "git"
        "chezmoi"
        "nvim"
        "starship"
        "wezterm"
        "code"
        "rg"
        "fd"
        "fzf"
        "bat"
        "zoxide"
        "direnv"
        "delta"
        "lazygit"
        "rustup"
        "cargo"
        "juliaup"
        "julia"
    ] {
        if (which $tool | is-empty) {
            print ("[--] " + $tool + " not found")
        } else {
            print ("[ok] " + $tool)
        }
    }

    let git_local = ($nu.home-path | path join ".gitconfig.local")
    let ssh_local = ($nu.home-path | path join ".ssh" "config.local")
    let secrets = ($nu.data-dir | path join "vendor" "autoload" "dotfiles-secrets.nu")
    let state = ($nu.home-path | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict = ($nu.home-path | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")

    if ($git_local | path exists) {
        print "[ok] Git machine-local override exists"
    } else {
        print "[--] Git machine-local override missing"
    }

    if ($ssh_local | path exists) {
        print "[ok] SSH machine-local override exists"
    } else {
        print "[--] SSH machine-local override missing"
    }

    if ($secrets | path exists) {
        print "[ok] Machine-local secrets autoload exists"
    } else {
        print "[--] Machine-local secrets autoload missing"
    }

    if ($state | path exists) {
        let sync_state = (open $state)
        print ("[ok] Last sync: " + ($sync_state.last_sync? | default "unknown"))
        print ("[ok] Last writer: " + ($sync_state.last_writer? | default "unknown"))
    } else {
        print "[--] Automatic sync baseline missing"
    }

    if ($conflict | path exists) {
        print "[WARN] Automatic sync conflict exists"
    } else {
        print "[ok] No automatic sync conflict"
    }

    if $fix {
        print ""
        print "Repair"
        print "------"

        run-script $tools_root "init-private-data.nu" | ignore
        run-script $tools_root "setup-platform-shims.nu" | ignore
        run-script $tools_root "enable-nushell-dotfiles.nu" | ignore
        run-script $tools_root "setup-local-overrides.nu" | ignore
        run-script $tools_root "setup-secrets.nu" | ignore

        if $context.features.cli_tools {
            run-script $tools_root "install-cli-tools.nu" | ignore
        }

        if $context.features.starship {
            run-script $tools_root "install-starship.nu" | ignore
            run-script $tools_root "setup-starship.nu" | ignore
        }

        if $context.features.wezterm and $context.machine.install_gui_apps {
            run-script $tools_root "install-wezterm.nu" | ignore
        }

        if not ($state | path exists) {
            run-script $tools_root "update-sync-state.nu" | ignore
        }

        if $context.sync.enabled {
            run-script $tools_root "install-auto-sync.nu" | ignore
        }

        print "[ok] Repair pass completed"
    }

    print ""
    print "chezmoi status:"

    if not (which chezmoi | is-empty) and ($data_root | path exists) {
        let args = [
            "--source"
            ($data_root | into string)
            "status"
        ]

        ^chezmoi ...$args
    }
}
