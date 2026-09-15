#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def machine-config-path [] {
    (nu-home)
    | path join ".config" "dotfiles" "config.nuon"
}

def schema-version [] {
    open --raw ($TOOLS_ROOT | path join "SCHEMA_VERSION")
    | decode utf-8
    | str trim
    | into int
}

def run-script [tools_root: path name: string] {
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

def main [--fix] {
    let config_file = (machine-config-path)

    print ("Nushell      : " + $env.NU_VERSION)
    print ("OS           : " + $nu.os-info.name)
    print ("Machine cfg  : " + ($config_file | into string))

    if not ($config_file | path exists) {
        print "[FAIL] Machine config is missing"
        print "[info] Run nu setup.nu first."
        return
    }

    if $fix {
        run-script $TOOLS_ROOT "migrate-config.nu" | ignore
    }

    let context = (open $config_file)
    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)
    let actual_schema = ($context.schema_version? | default 0)
    let expected_schema = (schema-version)

    print ("App version  : " + ($context.app_version? | default (($context | get --optional version) | default "legacy")))
    print ("Schema       : " + ($actual_schema | into string) + " / " + ($expected_schema | into string))
    print ("Machine      : " + $context.machine.name)
    print ("Profile      : " + $context.machine.profile)
    print ("Private data : " + ($data_root | into string))
    print ("Sync         : " + ($context.sync.enabled | into string) + " / " + ($context.sync.interval_minutes | into string) + " min")
    print ("Prune extras : " + (($context.sync.prune_extras? | default false) | into string))
    print ""

    if $actual_schema == $expected_schema {
        print "[ok] Machine config schema is current"
    } else {
        print "[WARN] Machine config schema is not current"
    }

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

    let git_local = ((nu-home) | path join ".gitconfig.local")
    let ssh_local = ((nu-home) | path join ".ssh" "config.local")
    let secrets = ($nu.data-dir | path join "vendor" "autoload" "dotfiles-secrets.nu")
    let state = ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")
    let sync_lock = ((nu-home) | path join ".config" "dotfiles" "locks" "auto-sync.lock")
    let tool_state = ((nu-home) | path join ".config" "dotfiles" "state" "tools.nuon")
    let windows_sync_launcher = ((nu-home) | path join ".config" "dotfiles" "scheduler" "auto-sync-hidden.vbs")
    let font_marker = ((nu-home) | path join ".config" "dotfiles" "fonts" "d2coding.nuon")
    let rust_state = ($data_root | path join "toolchains" "rust" "state.nuon")
    let julia_envs = ($data_root | path join "toolchains" "julia" "environments")

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

    if $context.features.fonts {
        if ($font_marker | path exists) {
            print "[ok] D2Coding installation marker exists"
        } else {
            print "[--] D2Coding installation marker missing"
        }
    }

    if $context.features.rust {
        if ($rust_state | path exists) {
            print "[ok] Captured Rust toolchain state exists"
        } else {
            print "[--] Captured Rust toolchain state missing"
        }
    }

    if $context.features.julia {
        if ($julia_envs | path exists) {
            print "[ok] Julia environment metadata directory exists"
        } else {
            print "[--] Julia environment metadata missing"
        }
    }

    if ($tool_state | path exists) {
        print "[ok] Tool-version snapshot exists"
    } else {
        print "[--] Tool-version snapshot missing"
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

    if ($sync_lock | path exists) {
        print "[info] Automatic sync lock currently exists"
    } else {
        print "[ok] No automatic sync lock"
    }

    if $nu.os-info.name == "windows" and $context.sync.enabled {
        if ($windows_sync_launcher | path exists) {
            print "[ok] Windows auto-sync hidden launcher exists"
        } else {
            print "[--] Windows auto-sync hidden launcher missing"
        }
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
        run-script $tools_root "cleanup-direnv.nu" | ignore

        if $context.features.neovim {
            run-script $tools_root "install-neovim.nu" | ignore
        }

        if $context.features.fonts and $context.machine.install_gui_apps {
            run-script $tools_root "install-fonts.nu" | ignore
        }

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

        run-script $tools_root "capture-tool-state.nu" | ignore
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
