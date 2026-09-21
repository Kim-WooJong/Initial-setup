#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
const DIAGNOSTICS = path self ./modules/diagnostics.nu
use $SUBPROCESS [run-command command-failure-message]
use $INSTALL_UTILS [probe-tool]
use $DIAGNOSTICS [tool-diagnostic print-diagnostic]

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

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
    | into string
    | str trim
    | into int
}

def run-script [tools_root: path name: string ...args: string] {
    let script = ($tools_root | path join "scripts" $name)

    if not ($script | path exists) {
        print ("[WARN] Repair/check script missing: " + $name)
        return false
    }

    let result = (run-command ($nu.current-exe | into string) (["--no-config-file" ($script | into string)] | append $args) --live)
    if not $result.ok {
        print --stderr ("[WARN] " + (command-failure-message $name $result))
        return false
    }

    true
}

const PROVIDER = path self ./modules/sync-provider.nu
const VAULT = path self ./modules/vault.nu
use $PROVIDER [load-provider load-provider-state provider-head]
use $VAULT [vault-configured]

def main [--fix] {
    let config_file = (machine-config-path)

    print ("Nushell      : " + $env.NU_VERSION)
    print ("OS           : " + $nu.os-info.name)
    print ("Machine cfg  : " + ($config_file | into string))

    if not ($config_file | path exists) {
        print "[FAIL] Machine config is missing"
        if $nu.os-info.name in ["linux" "macos"] {
            print "[info] From the Initial-setup project root run: nu setup.nu"
        } else {
            print "[info] From the Initial-setup project root run: nu setup.nu"
        }
        exit 1
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

    print "Tool health:"
    for tool in [
        {name: "git" args: ["--version"]}
        {name: "chezmoi" args: ["--version"]}
        {name: "nvim" args: ["--version"]}
        {name: "starship" args: ["--version"]}
        {name: "wezterm" args: ["--version"]}
        {name: "code" args: ["--version"]}
        {name: "rg" args: ["--version"]}
        {name: "fd" args: ["--version"]}
        {name: "fzf" args: ["--version"]}
        {name: "bat" args: ["--version"]}
        {name: "zoxide" args: ["--version"]}
        {name: "delta" args: ["--version"]}
        {name: "lazygit" args: ["--version"]}
        {name: "rustup" args: ["--version"]}
        {name: "cargo" args: ["--version"]}
        {name: "juliaup" args: ["--version"]}
        {name: "julia" args: ["--version"]}
    ] {
        let tool_check = (tool-diagnostic $tool.name $tool.args "warning")
        print-diagnostic $tool_check
    }
    let chezmoi_probe = (probe-tool "chezmoi" ["--version"])

    let git_local = ((nu-home) | path join ".gitconfig.local")
    let ssh_local = ((nu-home) | path join ".ssh" "config.local")
    let secrets = ($nu.data-dir | path join "vendor" "autoload" "dotfiles-secrets.nu")
    let state = ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")
    let sync_lock = ((nu-home) | path join ".config" "dotfiles" "locks" "auto-sync.lock")
    let tool_state = ((nu-home) | path join ".config" "dotfiles" "state" "tools.nuon")
    let windows_sync_launcher = ((nu-home) | path join ".config" "dotfiles" "scheduler" "auto-sync-hidden.vbs")
    let machine_local_setup = ((nu-home) | path join ".config" "dotfiles" "local.nu")
    let platform_env = ((nu-home) | path join ".config" "dotfiles" "platform.nu")
    let linux_sync_service = ((nu-home) | path join ".config" "systemd" "user" "dotfiles-auto-sync.service")
    let linux_sync_timer = ((nu-home) | path join ".config" "systemd" "user" "dotfiles-auto-sync.timer")
    let font_marker = ((nu-home) | path join ".config" "dotfiles" "fonts" "d2coding.nuon")
    let rust_state = ($data_root | path join "toolchains" "rust" "state.nuon")
    let julia_envs = ($data_root | path join "toolchains" "julia" "environments")
    let local_backup_root = ((nu-home) | path join ".config" "dotfiles" "local-backups")

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

    if $context.features.git_config {
        print ""
        print "Git folder identities:"
        if not (run-script $tools_root "setup-git-identities.nu" "--check") {
            print "[WARN] Git folder identity check failed"
        }
    }

    if $context.features.ssh_config {
        print ""
        print "SSH key pairs:"
        if not (run-script $tools_root "setup-ssh-keys.nu" "--check") {
            print "[WARN] SSH key check failed"
        }
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

    if $nu.os-info.name == "windows" and ($context.features.onedrive_ignore_uploads? | default false) {
        run-script $tools_root "setup-onedrive-ignore-upload.nu" "--check" | ignore
    }

    if ($context.features.rclone_config? | default false) {
        let rclone_probe = (probe-tool "rclone" ["version"])
        if $rclone_probe.healthy {
            print ("[ok] rclone config synchronization enabled | " + $rclone_probe.version)
        } else if $rclone_probe.found {
            print ("[WARN] rclone config sync enabled, but the executable is unhealthy: " + ($rclone_probe.result.diagnostic? | default "unknown error"))
        } else {
            print "[--] rclone config sync enabled, but rclone is not installed"
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

    print ""
    print "Toolchain desired state:"
    run-script $tools_root "toolchain-state.nu" "--status" | ignore

    if $context.features.neovim and $chezmoi_probe.healthy {
        print ""
        print "Chezmoi merge tool:"
        run-script $tools_root "setup-merge-tool.nu" "--check" | ignore
    }

    let machine_overlay = ((nu-home) | path join ".config" "dotfiles" "machine-overlay.nuon")
    if ($machine_overlay | path exists) {
        print ("[ok] Machine profile overlay: " + ($machine_overlay | into string))
    } else {
        print "[--] No machine-local profile overlay"
    }

    if ($tool_state | path exists) {
        print "[ok] Tool-version snapshot exists"
    } else {
        print "[--] Tool-version snapshot missing"
    }

    if ($machine_local_setup | path exists) {
        print "[ok] Machine-local Nushell setup exists"
    } else {
        print "[--] Machine-local Nushell setup missing"
    }

    if $nu.os-info.name in ["linux" "macos"] {
        if ($platform_env | path exists) {
            print "[ok] POSIX user-tool PATH bridge exists"
        } else {
            print "[--] POSIX user-tool PATH bridge missing"
        }
    }

    if $nu.os-info.name == "linux" and $context.sync.enabled {
        if ($linux_sync_service | path exists) and ($linux_sync_timer | path exists) {
            print "[ok] Linux auto-sync systemd unit files exist"
        } else {
            print "[--] Linux auto-sync systemd unit files missing"
        }

        let systemctl_probe = (probe-tool "systemctl" ["--version"])
        if not $systemctl_probe.healthy {
            print "[--] systemctl not available/healthy; use dotsync manually"
        } else {
            let status = (run-command $systemctl_probe.path ["--user" "is-active" "dotfiles-auto-sync.timer"])
            if $status.ok and (($status.stdout | str trim) == "active") {
                print "[ok] Linux auto-sync timer is active"
            } else {
                let reason = ($status.diagnostic? | default "" | str trim)
                print ("[--] Linux auto-sync timer is not active; manual dotsync remains available" + (if ($reason | is-empty) { "" } else { " | " + $reason }))
            }
        }
    }

    if ($local_backup_root | path exists) {
        let local_backups = (ls $local_backup_root | where type == dir | sort-by name | reverse)
        if ($local_backups | is-empty) {
            print "[--] No local configuration backups"
        } else {
            print ("[ok] Local configuration backups: " + (($local_backups | length) | into string))
            print ("[ok] Latest local backup: " + (($local_backups | first | get name) | path basename))
        }
    } else {
        print "[--] No local configuration backups"
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

        if $context.features.git_config {
            run-script $tools_root "setup-git-identities.nu" "--apply" | ignore
        }

        if $context.features.ssh_config {
            run-script $tools_root "setup-ssh-keys.nu" "--generate" | ignore
        }

        run-script $tools_root "setup-secrets.nu" | ignore
        run-script $tools_root "setup-machine-local.nu" | ignore
        run-script $tools_root "cleanup-direnv.nu" | ignore

        if $nu.os-info.name == "windows" and ($context.features.onedrive_ignore_uploads? | default false) {
            run-script $tools_root "setup-onedrive-ignore-upload.nu" | ignore
        }

        if $context.features.neovim {
            run-script $tools_root "install-neovim.nu" | ignore
        }

        if $context.features.neovim {
            run-script $tools_root "setup-merge-tool.nu" | ignore
        }

        if $context.features.rust or $context.features.julia {
            run-script $tools_root "install-language-tools.nu" | ignore
            run-script $tools_root "toolchain-state.nu" "--apply" | ignore
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
        print "[info] Repair pass finished. Review any warnings above; individual repair failures are not reported as success."
    }

    print ""
    print "Secure synchronization:"
    print ("Vault configured: " + ((vault-configured) | into string))
    for optional in [
        {name: "age" args: ["--version"]}
        {name: "age-keygen" args: ["--version"]}
        {name: "rclone" args: ["version"]}
    ] {
        let probe = (probe-tool $optional.name $optional.args)
        print ($optional.name + ": " + (if $probe.healthy { "healthy" } else if $probe.found { "found but unhealthy" } else { "not installed" }))
    }
    try {
        let provider = (load-provider)
        let head = (provider-head $provider)
        let baseline = (load-provider-state $provider)
        print ("Provider: " + $provider.kind)
        print ("Current revision: " + $head.revision)
        print ("Baseline: " + ($baseline.revision? | default "uninitialized; review dotbackend status"))
        if ($data_root | path join "rclone" "rclone.conf" | path exists) {
            print "[WARN] Legacy plaintext rclone.conf exists; review dotvault migrate-rclone before publishing."
        }
    } catch {|err|
        print ("[WARN] Provider is not reachable or has invalid metadata. No baseline was reset. " + ($err.msg? | default "unknown provider error"))
    }
    print ""
    print "chezmoi status:"

    if $chezmoi_probe.healthy and ($data_root | path exists) {
        let args = [
            "--source"
            ($data_root | into string)
            "status"
        ]
        let status = (run-command $chezmoi_probe.path $args --live)
        if not $status.ok {
            print --stderr ("[WARN] " + (command-failure-message "chezmoi status" $status))
        }
    } else {
        print "[--] chezmoi status unavailable because chezmoi/private data is not healthy."
    }
}
