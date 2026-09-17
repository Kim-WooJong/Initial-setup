#!/usr/bin/env nu
const PROCESS_OUTPUT = path self ./modules/process-output.nu
use $PROCESS_OUTPUT [output-text]

const TOOLS_ROOT = path self ..
const CORE_MODULE = path self ./modules/core.nu
const POLICY_MODULE = path self ./modules/setup-policy.nu
const RUN_MODULE = path self ./modules/run-state.nu
const CONFLICTS_MODULE = path self ./modules/conflicts.nu
const PROFILES_MODULE = path self ./modules/profiles.nu
const PLANNER_MODULE = path self ./modules/planner.nu
const TOOLCHAINS_MODULE = path self ./modules/toolchains.nu

use $CORE_MODULE [nu-home]
use $POLICY_MODULE [local-config-exists private-config-exists]
use $RUN_MODULE [create-run mark-stage finish-run load-run list-runs]
use $CONFLICTS_MODULE [load-conflict-policy]
use $PROFILES_MODULE [profile-defaults]
use $PLANNER_MODULE [build-plan save-plan]
use $TOOLCHAINS_MODULE [load-toolchain-lock]

def fail [message: string] {
    print ("[FAIL] " + $message)
    exit 1
}

def run-nu [label: string args: list] {
    print ("[test] " + $label)

    let nu_exe = $nu.current-exe
    let result = (do { ^$nu_exe --no-config-file ...$args } | complete)
    let stdout = ($result.stdout? | output-text | str trim)
    let stderr = ($result.stderr? | output-text | str trim)

    if $result.exit_code != 0 {
        if not ($stdout | is-empty) {
            print $stdout
        }

        if not ($stderr | is-empty) {
            print $stderr
        }

        fail ($label + " failed with exit code " + ($result.exit_code | into string))
    }

    $result
}

def temp-base [] {
    match $nu.os-info.name {
        "windows" => {
            let candidate = ($env.TEMP? | default ($env.TMP? | default ""))

            if not ($candidate | is-empty) {
                return ($candidate | path expand)
            }

            return ((nu-home) | path join "AppData" "Local" "Temp")
        }
        _ => {
            let candidate = ($env.TMPDIR? | default "")

            if not ($candidate | is-empty) {
                return ($candidate | path expand)
            }

            "/tmp"
        }
    }
}

def main [
    --sandbox
    --keep
    --setup-only
] {
    # Dedicated editor regression uses its own temporary HOME.
    let validator = ($TOOLS_ROOT | path join "scripts" "validate-project.nu")
    let setup = ($TOOLS_ROOT | path join "setup.nu")

    run-nu "project validation" [$validator] | ignore

    if not $sandbox {
        print "[ok] Static/project validation passed."
        print "[info] Run `dottest --sandbox` for isolated setup smoke tests."
        return
    }

    if not $setup_only {
        run-nu "capture/sync failure propagation" [($TOOLS_ROOT | path join "scripts" "subprocess-chain-test.nu")] | ignore
        run-nu "entrypoint diagnostics" [($TOOLS_ROOT | path join "scripts" "entrypoint-test.nu")] | ignore
        run-nu "active cloud command refresh" [($TOOLS_ROOT | path join "scripts" "refresh-commands-test.nu")] | ignore
        run-nu "run-state checkpoint integrity" [($TOOLS_ROOT | path join "scripts" "run-state-test.nu")] | ignore
        run-nu "syntax-validator regression fixtures" [($TOOLS_ROOT | path join "scripts" "syntax-self-test.nu")] | ignore
        run-nu "offline latest-Nushell runtime regressions" [($TOOLS_ROOT | path join "scripts" "nu-runtime-test.nu")] | ignore
        if $nu.os-info.name != "windows" {
            ^bash ($TOOLS_ROOT | path join "scripts" "posix" "prepare-nu-cargo-test.sh")
            if ($env.LAST_EXIT_CODE | default 1) != 0 { fail "Cargo native bootstrap fixture failed." }
        }
        run-nu "language and failure-path regressions" [($TOOLS_ROOT | path join "scripts" "regression-test.nu")] | ignore
        run-nu "offline rclone dependency regressions" [($TOOLS_ROOT | path join "scripts" "rclone-install-test.nu")] | ignore
        run-nu "binary subprocess diagnostic regressions" [($TOOLS_ROOT | path join "scripts" "process-output-test.nu") "--external"] | ignore
        run-nu "offline lock lifecycle and diagnostic regressions" [($TOOLS_ROOT | path join "scripts" "lock-test.nu")] | ignore
        run-nu "cloud-wins control/optional engine regressions" [($TOOLS_ROOT | path join "scripts" "cloud-wins-test.nu")] | ignore
    
        run-nu "local editor regression" [($TOOLS_ROOT | path join "scripts" "edit-managed-test.nu")] | ignore
        run-nu "local vault initialization regressions" [($TOOLS_ROOT | path join "scripts" "vault-init-test.nu")] | ignore
    }
    let stamp = (random uuid)
    let sandbox_root = ((temp-base) | path join ("initial-setup-selftest-" + $stamp))
    let sandbox_home = ($sandbox_root | path join "home")
    let sandbox_private = ($sandbox_root | path join "private")
    let sandbox_config = ($sandbox_root | path join "xdg-config")
    let sandbox_data = ($sandbox_root | path join "xdg-data")
    let sandbox_state = ($sandbox_root | path join "xdg-state")

    mkdir $sandbox_home
    mkdir $sandbox_private
    mkdir $sandbox_config
    mkdir $sandbox_data
    mkdir $sandbox_state

    $env.INITIAL_SETUP_TEST_MODE = "1"
    $env.INITIAL_SETUP_HOME_OVERRIDE = ($sandbox_home | into string)
    $env.HOME = ($sandbox_home | into string)
    $env.USERPROFILE = ($sandbox_home | into string)
    $env.XDG_CONFIG_HOME = ($sandbox_config | into string)
    $env.XDG_DATA_HOME = ($sandbox_data | into string)
    $env.XDG_STATE_HOME = ($sandbox_state | into string)
    let appdata = ($sandbox_home | path join "AppData" "Roaming")
    let localappdata = ($sandbox_home | path join "AppData" "Local")
    let cache = ($sandbox_root | path join "xdg-cache")
    mkdir $appdata $localappdata $cache
    $env.APPDATA = ($appdata | into string)
    $env.LOCALAPPDATA = ($localappdata | into string)
    $env.XDG_CACHE_HOME = ($cache | into string)


    if (nu-home) != ($sandbox_home | path expand) {
        fail "Sandbox home override was not honored by the shared core module."
    }

    let transaction_run = (create-run "self-test" "auto" "push-local" "minimal" ($sandbox_private | into string) true)
    mark-stage $transaction_run "sandbox-stage" "running"
    mark-stage $transaction_run "sandbox-stage" "success"
    finish-run $transaction_run "success"

    let transaction_state = (load-run $transaction_run)
    if ($transaction_state.status? | default "") != "success" {
        fail "Transaction state lifecycle did not finish successfully."
    }

    if ((list-runs) | where run_id == $transaction_run | is-empty) {
        fail "Transaction run history did not retain the sandbox run."
    }

    let conflict_policy = (load-conflict-policy)
    if not (".ssh/config" in ($conflict_policy.protected? | default [])) {
        fail "Default protected-file policy is missing .ssh/config."
    }

    let toolchain_lock = (load-toolchain-lock)
    if ($toolchain_lock.version? | default 0) != 1 {
        fail "Toolchain lock could not be loaded in the sandbox."
    }

    let overlay_file = ($sandbox_home | path join ".config" "dotfiles" "machine-overlay.nuon")
    mkdir ($overlay_file | path dirname)
    '{ features: { wezterm: true } }' | save --force $overlay_file
    let layered_profile = (profile-defaults "minimal" "sandbox-machine")
    if not ($layered_profile.features.wezterm? | default false) {
        fail "Machine-local profile overlay was not applied."
    }

    let local_marker = ($sandbox_home | path join ".gitconfig")
    "# Initial-setup sandbox local marker" | save $local_marker

    if not (local-config-exists) {
        fail "Local configuration detection did not see the sandbox marker."
    }

    # Verify manifest-v2 transaction backup semantics: an existing file must be
    # restored, while a machine-config file that did not exist at backup time
    # must be removed again during rollback.
    let backup_script = ($TOOLS_ROOT | path join "scripts" "backup-local-config.nu")
    run-nu "transaction local backup" [$backup_script "--label" "self-test-transaction" "--quiet"] | ignore

    let backup_root = ($sandbox_home | path join ".config" "dotfiles" "local-backups")
    let backup_rows = (ls $backup_root | where type == dir | sort-by name | reverse)
    if ($backup_rows | is-empty) {
        fail "Transaction local backup was not created."
    }
    let backup_name = ($backup_rows | first | get name | path basename)

    "# changed after transaction backup" | save --force $local_marker
    let machine_config = ($sandbox_home | path join ".config" "dotfiles" "config.nuon")
    mkdir ($machine_config | path dirname)
    "{ synthetic: true }" | save --force $machine_config

    run-nu "transaction local restore" [$backup_script "--restore" $backup_name "--force"] | ignore

    if ($machine_config | path exists) {
        fail "Transaction restore did not remove a machine config that was absent before backup."
    }
    if not ((open --raw $local_marker) | str contains "sandbox local marker") {
        fail "Transaction restore did not restore the original local configuration."
    }

    if (private-config-exists $sandbox_private) {
        fail "Private configuration should not exist before the sandbox marker is created."
    }

    let push_result = (run-nu "local-authoritative setup dry-run" [
        $setup
        "--dry-run"
        "--mode"
        "auto"
        "--data-dir"
        ($sandbox_private | into string)
        "--profile"
        "minimal"
        "--config-policy"
        "push-local"
        "--no-auto-sync"
    ])

    let push_stdout = ($push_result.stdout? | output-text)

    if not ($push_stdout | str contains "Mode          : initial") {
        print $push_stdout
        fail "Local-authoritative dry-run did not resolve to initial mode."
    }

    let private_home = ($sandbox_private | path join "home")
    mkdir $private_home
    "# Initial-setup sandbox private marker" | save ($private_home | path join "dot_gitconfig")

    if not (private-config-exists $sandbox_private) {
        fail "Private configuration detection did not see the sandbox marker."
    }

    let pull_result = (run-nu "private-authoritative setup dry-run" [
        $setup
        "--dry-run"
        "--mode"
        "auto"
        "--data-dir"
        ($sandbox_private | into string)
        "--profile"
        "minimal"
        "--config-policy"
        "pull-private"
        "--no-auto-sync"
    ])

    let pull_stdout = ($pull_result.stdout? | output-text)

    if not ($pull_stdout | str contains "Mode          : existing") {
        print $pull_stdout
        fail "Private-authoritative dry-run did not resolve to existing mode."
    }

    if ($machine_config | path exists) {
        fail "Dry-run unexpectedly wrote a machine configuration file."
    }

    {
        app_version: "self-test"
        schema_version: 5
        data_root: ($sandbox_private | into string)
        tools_root: ($TOOLS_ROOT | into string)
        machine: { name: "sandbox-machine" profile: "minimal" install_gui_apps: false }
        sync: { enabled: false interval_minutes: 1 auto_push: false auto_pull: false conflict_policy: "stop" stability_delay_seconds: 0 prune_extras: false }
        maintenance: { snapshots_enabled: false snapshot_keep: 2 log_keep_lines: 100 }
        features: { neovim: true fonts: false cli_tools: true vscode: false wezterm: true starship: true rust: false julia: false git_config: true ssh_config: true rclone_config: false onedrive_ignore_uploads: false }
    } | to nuon | save --force $machine_config

    let sandbox_plan = (build-plan "none")
    let sandbox_plan_file = (save-plan $sandbox_plan)
    if not ($sandbox_plan_file | path exists) {
        fail "Desired-state planner did not persist a sandbox plan."
    }

    run-nu "merge-tool configuration inspection" [($TOOLS_ROOT | path join "scripts" "setup-merge-tool.nu") "--check"] | ignore

    print "[ok] Sandbox home isolation passed."
    print "[ok] Transaction local backup/restore semantics passed."
    print "[ok] Transaction checkpoint/history lifecycle passed."
    print "[ok] Protected-file policy loading passed."
    print "[ok] Layered profile overlay passed."
    print "[ok] Toolchain lock loading passed."
    print "[ok] Desired-state planner persistence passed."
    print "[ok] Local/private source detection passed."
    print "[ok] push-local dry-run passed."
    print "[ok] pull-private dry-run passed."
    print "[ok] Dry-run produced no machine config side effect."

    if $keep {
        print ("[info] Sandbox kept at: " + ($sandbox_root | into string))
    } else {
        rm -r $sandbox_root
        print "[ok] Sandbox removed."
    }

    print "[ok] Sandbox self-test passed."
}
