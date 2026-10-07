#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-config-path project-schema-version fixed-private-context]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
const DIAGNOSTICS = path self ./modules/diagnostics.nu
const CONSOLE = path self ./modules/console.nu
const SYNC_STATE = path self ./modules/sync-state.nu
const STATE_SCHEMA_HEALTH = path self ./modules/state-schema-health.nu
use $SUBPROCESS [run-command command-failure-message]
use $INSTALL_UTILS [probe-tool]
use $DIAGNOSTICS [tool-diagnostic print-diagnostic]
use $CONSOLE [print-heading print-key-value print-status print-text]
use $SYNC_STATE [read-sync-state]
use $STATE_SCHEMA_HEALTH [schema-health]

def run-script [tools_root: path name: string ...args: string] {
    let script = ($tools_root | path join "scripts" $name)

    if not ($script | path exists) {
        print-status "warn" "WARN" ("Repair/check script missing: " + $name)
        return false
    }

    let result = (run-command ($nu.current-exe | into string) (["--no-config-file" ($script | into string)] | append $args) --live)
    if not $result.ok {
        print-status "warn" "WARN" (command-failure-message $name $result) --stderr
        return false
    }

    true
}



def print-schema-health [rows: list] {
    print-heading "Schema health"
    mut migration_count = 0
    mut blocked_count = 0
    mut invalid_count = 0

    for row in $rows {
        let location = if $row.file == null {
            ""
        } else {
            " | " + ($row.file | path basename)
        }
        if $row.status == "current" {
            print-status "ok" "CURRENT" (
                $row.kind + " | schema " + ($row.detected | into string) + " / " + ($row.current | into string) + $location
            )
        } else if $row.status == "migration-required" {
            $migration_count = $migration_count + 1
            if ($row.migration_enabled? | default false) {
                print-status "warn" "MIGRATION NEEDED" (
                    $row.kind + " | schema " + ($row.detected | into string) + " -> " + ($row.current | into string) + $location
                )
            } else {
                print-status "warn" "PENDING" (
                    $row.kind + " | schema " + ($row.detected | into string) + " -> " + ($row.current | into string) + $location
                )
            }
        } else if $row.status == "newer-than-supported" {
            $blocked_count = $blocked_count + 1
            print-status "error" "BLOCKED" (
                $row.kind + " | schema " + ($row.detected | into string) + " > supported " + ($row.current | into string) + $location
            )
        } else if $row.status == "not-initialized" {
            print-status "info" "NOT INITIALIZED" (
                $row.kind + " | target schema " + ($row.current | into string)
            )
        } else {
            $invalid_count = $invalid_count + 1
            let detail = ($row.detail? | default "invalid state")
            print-status "error" "INVALID" ($row.kind + $location + " | " + $detail)
        }
    }

    if $migration_count > 0 {
        print-status "warn" "schema" (
            ($migration_count | into string) + " schema item(s) require migration. Review with `dotmigrate --check`, then run `dotmigrate`."
        )
    }
    if $blocked_count > 0 or $invalid_count > 0 {
        print-status "error" "schema" "One or more schema items are blocked or invalid; do not migrate until they are resolved."
    }
    {migration_count: $migration_count blocked_count: $blocked_count invalid_count: $invalid_count}
}

const PROVIDER = path self ./modules/sync-provider.nu
const RCLONE_READINESS = path self ./modules/rclone-readiness.nu
use $PROVIDER [load-provider load-provider-state provider-head]
use $RCLONE_READINESS [print-rclone-readiness]

def main [--fix] {
    let config_file = (machine-config-path)

    print-key-value "Nushell      : " $env.NU_VERSION
    print-key-value "OS           : " $nu.os-info.name
    print-key-value "Machine cfg  : " ($config_file | into string)

    let schema_rows = (schema-health)
    print ""
    let schema_summary = (print-schema-health $schema_rows)
    let machine_schema = ($schema_rows | where kind == "machine-config" | first)

    if not ($config_file | path exists) {
        print-status "error" "FAIL" "Machine config is missing"
        print-status "info" "info" "From the Initial-setup project root run: nu setup.nu"
        exit 1
    }

    if $fix and $schema_summary.migration_count > 0 {
        print-status "warn" "schema" "dotdoctor --fix does not change schema versions; run dotmigrate first. Repair actions were skipped."
        return
    }
    if $fix and ($schema_summary.blocked_count > 0 or $schema_summary.invalid_count > 0) {
        print-status "error" "schema" "Repair actions were skipped because one or more schema items are blocked or invalid."
        return
    }
    if $machine_schema.status == "newer-than-supported" or $machine_schema.status == "invalid" {
        print-status "error" "FAIL" "Machine config cannot be interpreted safely. Resolve the schema issue before running repair actions."
        return
    }
    if $machine_schema.status == "migration-required" {
        print-status "warn" "schema" "Machine config migration is required before the remaining doctor checks can safely interpret the current config."
        return
    }

    let context = (fixed-private-context (open $config_file))
    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)
    let actual_schema = ($context.schema_version? | default 0)
    let expected_schema = (project-schema-version $TOOLS_ROOT)

    print-key-value "App version  : " ($context.app_version? | default (($context | get --optional version) | default "legacy"))
    print-key-value "Schema       : " (($actual_schema | into string) + " / " + ($expected_schema | into string))
    print-key-value "Machine      : " $context.machine.name
    print-key-value "Profile      : " $context.machine.profile
    print-key-value "Private data : " ($data_root | into string)
    print-key-value "Sync         : " (($context.sync.enabled | into string) + " / " + ($context.sync.interval_minutes | into string) + " min")
    print-key-value "Prune extras : " (($context.sync.prune_extras? | default false) | into string)
    print ""

    if ($data_root | path exists) {
        print-status "ok" "ok" "Private data root exists"
    } else {
        print-status "error" "FAIL" "Private data root unavailable"
    }

    print-heading "Tool health"
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
        print-status "ok" "ok" "Git machine-local override exists"
    } else {
        print-status "warn" "--" "Git machine-local override missing"
    }

    if ($ssh_local | path exists) {
        print-status "ok" "ok" "SSH machine-local override exists"
    } else {
        print-status "warn" "--" "SSH machine-local override missing"
    }

    if $context.features.git_config {
        print ""
        print-heading "Git folder identities"
        if not (run-script $tools_root "setup-git-identities.nu" "--check") {
            print-status "warn" "WARN" "Git folder identity check failed"
        }
    }

    if $context.features.ssh_config {
        print ""
        print-heading "SSH key pairs"
        if not (run-script $tools_root "setup-ssh-keys.nu" "--check") {
            print-status "warn" "WARN" "SSH key check failed"
        }
    }

    if ($secrets | path exists) {
        print-status "ok" "ok" "Machine-local secrets autoload exists"
    } else {
        print-status "warn" "--" "Machine-local secrets autoload missing"
    }

    if $context.features.fonts {
        if ($font_marker | path exists) {
            print-status "ok" "ok" "D2Coding installation marker exists"
        } else {
            print-status "warn" "--" "D2Coding installation marker missing"
        }
    }

    if $nu.os-info.name == "windows" and ($context.features.onedrive_ignore_uploads? | default false) {
        run-script $tools_root "setup-onedrive-ignore-upload.nu" "--check" | ignore
    }

    if $context.features.rust {
        if ($rust_state | path exists) {
            print-status "ok" "ok" "Captured Rust toolchain state exists"
        } else {
            print-status "warn" "--" "Captured Rust toolchain state missing"
        }
    }

    if $context.features.julia {
        if ($julia_envs | path exists) {
            print-status "ok" "ok" "Julia environment metadata directory exists"
        } else {
            print-status "warn" "--" "Julia environment metadata missing"
        }
    }

    print ""
    print-heading "Toolchain desired state"
    run-script $tools_root "toolchain-state.nu" "--status" | ignore

    if $context.features.neovim and $chezmoi_probe.healthy {
        print ""
        print-heading "Chezmoi merge tool"
        run-script $tools_root "setup-merge-tool.nu" "--check" | ignore
    }

    let machine_overlay = ((nu-home) | path join ".config" "dotfiles" "machine-overlay.nuon")
    if ($machine_overlay | path exists) {
        print-status "ok" "ok" ("Machine profile overlay: " + ($machine_overlay | into string))
    } else {
        print-status "warn" "--" "No machine-local profile overlay"
    }

    if ($tool_state | path exists) {
        print-status "ok" "ok" "Tool-version snapshot exists"
    } else {
        print-status "warn" "--" "Tool-version snapshot missing"
    }

    if ($machine_local_setup | path exists) {
        print-status "ok" "ok" "Machine-local Nushell setup exists"
    } else {
        print-status "warn" "--" "Machine-local Nushell setup missing"
    }

    if $nu.os-info.name in ["linux" "macos"] {
        if ($platform_env | path exists) {
            print-status "ok" "ok" "POSIX user-tool PATH bridge exists"
        } else {
            print-status "warn" "--" "POSIX user-tool PATH bridge missing"
        }
    }

    if $nu.os-info.name == "linux" and $context.sync.enabled {
        if ($linux_sync_service | path exists) and ($linux_sync_timer | path exists) {
            print-status "ok" "ok" "Linux auto-sync systemd unit files exist"
        } else {
            print-status "warn" "--" "Linux auto-sync systemd unit files missing"
        }

        let systemctl_probe = (probe-tool "systemctl" ["--version"])
        if not $systemctl_probe.healthy {
            print-status "warn" "--" "systemctl not available/healthy; use dotsync manually"
        } else {
            let status = (run-command $systemctl_probe.path ["--user" "is-active" "dotfiles-auto-sync.timer"])
            if $status.ok and (($status.stdout | str trim) == "active") {
                print-status "ok" "ok" "Linux auto-sync timer is active"
            } else {
                let reason = ($status.diagnostic? | default "" | str trim)
                print-status "warn" "--" ("Linux auto-sync timer is not active; manual dotsync remains available" + (if ($reason | is-empty) { "" } else { " | " + $reason }))
            }
        }
    }

    if ($local_backup_root | path exists) {
        let local_backups = (ls $local_backup_root | where type == dir | sort-by name | reverse)
        if ($local_backups | is-empty) {
            print-status "warn" "--" "No local configuration backups"
        } else {
            print-status "ok" "ok" ("Local configuration backups: " + (($local_backups | length) | into string))
            print-status "ok" "ok" ("Latest local backup: " + (($local_backups | first | get name) | path basename))
        }
    } else {
        print-status "warn" "--" "No local configuration backups"
    }

    if ($state | path exists) {
        let sync_state = (read-sync-state $state)
        print-status "ok" "ok" ("Last sync: " + ($sync_state.last_sync? | default "unknown"))
        print-status "ok" "ok" ("Last writer: " + ($sync_state.last_writer? | default "unknown"))
    } else {
        print-status "warn" "--" "Automatic sync baseline missing"
    }

    if ($conflict | path exists) {
        print-status "warn" "WARN" "Automatic sync conflict exists"
    } else {
        print-status "ok" "ok" "No automatic sync conflict"
    }

    if ($sync_lock | path exists) {
        print-status "info" "info" "Automatic sync lock currently exists"
    } else {
        print-status "ok" "ok" "No automatic sync lock"
    }

    if $nu.os-info.name == "windows" and $context.sync.enabled {
        if ($windows_sync_launcher | path exists) {
            print-status "ok" "ok" "Windows auto-sync hidden launcher exists"
        } else {
            print-status "warn" "--" "Windows auto-sync hidden launcher missing"
        }
    }

    if $fix {
        print ""
        print-heading "Repair"
        print-text "heading" "------"

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
        print-status "info" "info" "Repair pass finished. Review any warnings above; individual repair failures are not reported as success."
    }

    print ""
    print-rclone-readiness --heading | ignore
    try {
        let provider = (load-provider)
        let head = (provider-head $provider)
        let baseline = (load-provider-state $provider)
        print-key-value "Provider         : " $provider.kind
        print-key-value "Current revision : " $head.revision
        print-key-value "Baseline         : " ($baseline.revision? | default "uninitialized; review dotbackend status")
        if ($data_root | path join "rclone" "rclone.conf" | path exists) {
            print-status "warn" "WARN" "Legacy plaintext rclone.conf exists; review dotvault migrate-rclone before publishing."
        }
    } catch {|err|
        print-status "warn" "WARN" ("Provider is not reachable or has invalid metadata. No baseline was reset. " + ($err.msg? | default "unknown provider error"))
    }
    print ""
    print-heading "chezmoi status"

    if $chezmoi_probe.healthy and ($data_root | path exists) {
        let args = [
            "--source"
            ($data_root | into string)
            "status"
        ]
        let status = (run-command $chezmoi_probe.path $args --live)
        if not $status.ok {
            print-status "warn" "WARN" (command-failure-message "chezmoi status" $status) --stderr
        }
    } else {
        print-status "warn" "--" "chezmoi status unavailable because chezmoi/private data is not healthy."
    }
}
