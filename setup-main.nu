#!/usr/bin/env nu

const CLOUD_CONFIG = path self ./scripts/modules/cloud-wins-config.nu
use $CLOUD_CONFIG [cloud-mode-active]
const CORE_MODULE = path self ./scripts/modules/core.nu
const PROFILES_MODULE = path self ./scripts/modules/profiles.nu
const SETUP_POLICY_MODULE = path self ./scripts/modules/setup-policy.nu
const RUN_STATE_MODULE = path self ./scripts/modules/run-state.nu
const CONFLICTS_MODULE = path self ./scripts/modules/conflicts.nu
const RCLONE_INSTALL_MODULE = path self ./scripts/modules/rclone-install.nu

use $CORE_MODULE [nu-home machine-config-path detect-machine-name failure-envelope captured-failure]
use $PROFILES_MODULE [profile-defaults profile-layers profile-forced-features]
use $SETUP_POLICY_MODULE [config-policy-names normalize-config-policy choose-config-policy choose-reviewed-policy local-config-exists private-config-exists]
use $RUN_STATE_MODULE [create-run load-run update-run-context stage-status mark-stage finish-run resolve-resume-run]
use $CONFLICTS_MODULE [protected-conflicts print-protected-conflicts]
use $RCLONE_INSTALL_MODULE [refresh-rclone-path ensure-rclone]
# ============================================================
# Initial-setup
#
# Cross-platform development environment bootstrap and
# configuration synchronization.
# ============================================================

const TOOLS_ROOT = path self .
const DEFAULT_DATA_ROOT = path self ..

def section [title: string] {
    print ""
    print "============================================================"
    print (" " + $title)
    print "============================================================"
    print ""
}

def require [name: string] {
    if (which $name | is-empty) {
        error make {
            msg: ("Required command not found: " + $name)
        }
    }
}

def old-machine-config [] {
    let file = (machine-config-path)

    if ($file | path exists) {
        open $file
    } else {
        {}
    }
}

def feature-value [
    old_features: record
    preset_features: record
    key: string
    reset_to_profile: bool
] {
    if $reset_to_profile {
        return ($preset_features | get $key)
    }

    let old_value = ($old_features | get --optional $key)

    if $old_value == null {
        $preset_features | get $key
    } else {
        $old_value
    }
}

def app-version [] {
    let version_file = ($TOOLS_ROOT | path join "VERSION")
    open $version_file --raw | into string | str trim
}

def schema-version [] {
    let schema_file = ($TOOLS_ROOT | path join "SCHEMA_VERSION")
    open $schema_file --raw | into string | str trim | into int
}

def build-machine-config [
    data_root: path
    disable_auto_sync: bool
    requested_profile: string
] {
    let old = (old-machine-config)
    let old_machine = ($old.machine? | default {})
    let old_sync = ($old.sync? | default {})
    let old_features = ($old.features? | default {})
    let old_maintenance = ($old.maintenance? | default {})

    let old_profile = ($old_machine.profile? | default "workstation")

    let profile = (
        if ($requested_profile | is-empty) {
            $old_profile
        } else {
            $requested_profile
        }
    )

    let reset_to_profile = (not ($requested_profile | is-empty) or ($old | is-empty))

    let old_name = ($old_machine.name? | default "")
    let machine_name = (
        if ($old_name | is-empty) {
            detect-machine-name
        } else {
            $old_name
        }
    )

    let preset = (profile-defaults $profile $machine_name)
    let layers = (profile-layers $profile $machine_name)
    let forced_features = (profile-forced-features $profile $machine_name)
    let preset_features = $preset.features

    let sync_enabled = (
        if $disable_auto_sync {
            false
        } else {
            $old_sync.enabled? | default true
        }
    )
    {
        app_version: (app-version)
        schema_version: (schema-version)
        data_root: ($data_root | path expand | into string)
        tools_root: ($TOOLS_ROOT | path expand | into string)

        machine: {
            name: $machine_name
            profile: $profile
            layers: $layers
            install_gui_apps: (
                if $reset_to_profile {
                    $preset.install_gui_apps
                } else {
                    $old_machine.install_gui_apps? | default $preset.install_gui_apps
                }
            )
        }

        sync: {
            enabled: $sync_enabled
            interval_minutes: ($old_sync.interval_minutes? | default 1)
            auto_push: ($old_sync.auto_push? | default true)
            auto_pull: ($old_sync.auto_pull? | default true)
            conflict_policy: ($old_sync.conflict_policy? | default "stop")
            stability_delay_seconds: ($old_sync.stability_delay_seconds? | default 3)
            prune_extras: ($old_sync.prune_extras? | default false)
        }

        maintenance: {
            snapshots_enabled: ($old_maintenance.snapshots_enabled? | default true)
            snapshot_keep: ($old_maintenance.snapshot_keep? | default 20)
            log_keep_lines: ($old_maintenance.log_keep_lines? | default 2000)
        }

        features: {
            neovim: (feature-value $old_features $preset_features "neovim" ($reset_to_profile or (($forced_features | get --optional "neovim") != null)))
            fonts: (feature-value $old_features $preset_features "fonts" ($reset_to_profile or (($forced_features | get --optional "fonts") != null)))
            cli_tools: (feature-value $old_features $preset_features "cli_tools" ($reset_to_profile or (($forced_features | get --optional "cli_tools") != null)))
            vscode: (feature-value $old_features $preset_features "vscode" ($reset_to_profile or (($forced_features | get --optional "vscode") != null)))
            wezterm: (feature-value $old_features $preset_features "wezterm" ($reset_to_profile or (($forced_features | get --optional "wezterm") != null)))
            starship: (feature-value $old_features $preset_features "starship" ($reset_to_profile or (($forced_features | get --optional "starship") != null)))
            rust: (feature-value $old_features $preset_features "rust" ($reset_to_profile or (($forced_features | get --optional "rust") != null)))
            julia: (feature-value $old_features $preset_features "julia" ($reset_to_profile or (($forced_features | get --optional "julia") != null)))
            git_config: (feature-value $old_features $preset_features "git_config" ($reset_to_profile or (($forced_features | get --optional "git_config") != null)))
            ssh_config: (feature-value $old_features $preset_features "ssh_config" ($reset_to_profile or (($forced_features | get --optional "ssh_config") != null)))
            rclone_config: (feature-value $old_features $preset_features "rclone_config" ($reset_to_profile or (($forced_features | get --optional "rclone_config") != null)))
            onedrive_ignore_uploads: (feature-value $old_features $preset_features "onedrive_ignore_uploads" ($reset_to_profile or (($forced_features | get --optional "onedrive_ignore_uploads") != null)))
        }
    }
}

def save-machine-config [context: record] {
    let config_file = (machine-config-path)

    mkdir ($config_file | path dirname)

    $context
    | to nuon
    | save --force $config_file

    print (
        "[save] Machine config -> " + ($config_file | into string)
    )
}

def load-saved-data-root [] {
    let config_file = (machine-config-path)

    if not ($config_file | path exists) {
        return null
    }

    let config = (open $config_file)
    let data_root = ($config.data_root? | default "")

    if ($data_root | is-empty) {
        return null
    }

    $data_root | path expand
}

def resolve-data-root [requested: string] {
    if not ($requested | is-empty) {
        return ($requested | path expand)
    }

    let saved = (load-saved-data-root)

    if $saved != null {
        return $saved
    }

    $DEFAULT_DATA_ROOT | path expand
}

def resolve-mode [
    requested: string
    data_root: path
] {
    match $requested {
        "initial" => {
            "initial"
        }

        "existing" => {
            "existing"
        }

        "auto" => {
            if (private-config-exists $data_root) {
                "existing"
            } else {
                "initial"
            }
        }

        _ => {
            error make {
                msg: (
                    "Unknown mode '" + $requested + "'. Use auto, initial, or existing."
                )
            }
        }
    }
}

def validate-config-policy [policy: string] {
    let allowed = (config-policy-names)

    if not ($policy in $allowed) {
        error make {
            msg: (
                "Unknown config policy '" + $policy + "'. Use " + ($allowed | str join ", ") + "."
            )
        }
    }
}

def resolve-config-policy [
    requested_policy: string
    requested_mode: string
    first_run: bool
    data_root: path
] {
    validate-config-policy $requested_policy

    if $requested_policy != "ask" {
        return (normalize-config-policy $requested_policy)
    }

    if $requested_mode == "initial" {
        return "push-local"
    }

    if $requested_mode == "existing" {
        return "review"
    }

    let local_exists = (local-config-exists)
    let private_exists = (private-config-exists $data_root)

    # When both sides exist, always resolve direction before invoking chezmoi.
    # This prevents the raw overwrite-only chezmoi prompt from becoming the
    # primary synchronization UX on later setup runs.
    if $local_exists and $private_exists {
        return (choose-config-policy $data_root)
    }

    if $private_exists {
        return "pull-private"
    }

    if $local_exists or $first_run {
        return "push-local"
    }

    "standard"
}

def mode-for-policy [
    policy: string
    fallback_mode: string
] {
    match $policy {
        "push-local" => { "initial" }
        "pull-private" => { "existing" }
        "review" => { "existing" }
        "backup-private" => { "existing" }
        "preview" => { $fallback_mode }
        "standard" => { $fallback_mode }
        _ => { $fallback_mode }
    }
}

def policy-needs-private-source [policy: string] {
    $policy in ["pull-private" "review" "backup-private"]
}

def active-run-id [] {
    $env.INITIAL_SETUP_RUN_ID? | default "" | str trim
}

def resume-enabled [] {
    ($env.INITIAL_SETUP_RESUME? | default "") == "1"
}

def run-stage [title: string action: closure] {
    let run_id = (active-run-id)

    section $title

    if not ($run_id | is-empty) and (resume-enabled) {
        let previous = (stage-status $run_id $title)
        let always_run = ($title == "Ensuring rclone is available")
        if $previous == "success" and not $always_run {
            print ("[skip] Checkpoint already completed in run " + $run_id)
            return
        }
    }

    if not ($run_id | is-empty) {
        mark-stage $run_id $title "running"
    }

    try {
        do $action

        if not ($run_id | is-empty) {
            mark-stage $run_id $title "success"
        }
    } catch { |err|
        print ""
        print ("[error] Stage failed: " + $title)
        print $err
        let message = ("Stage failed: " + $title)

        if not ($run_id | is-empty) {
            mark-stage $run_id $title "failed" $message
            print ""
            print ("[resume] nu setup.nu --resume --run-id " + $run_id)
        }

        error make { msg: $message }
    }
}

def run-script [
    title: string
    file: path
    ...args: string
] {
    let script = ($file | path expand)

    if not ($script | path exists) {
        error make {
            msg: ("Required script not found: " + ($script | into string))
        }
    }

    run-stage $title {||
        print ("[run] " + ($script | into string))
        ^$nu.current-exe --no-config-file $script ...$args

        let exit_code = ($env.LAST_EXIT_CODE | default 0)
        if $exit_code != 0 {
            error make { msg: ("Script failed: " + ($script | into string)) }
        }
    }
}

def protected-apply-choices [
    data_root: path
    conflicts: list
] {
    mut keep_local = []

    print ""
    print "Protected-file review"
    print "────────────────────────────────────────────────────────────"
    print "Each protected file differs from the private source."
    print "The diff is shown before you choose what to do."
    print ""

    for conflict in $conflicts {
        let target = ($conflict.target | path expand)

        print ("Protected target: " + ($target | into string))
        print "────────────────────────────────────────────────────────────"

        if not (($conflict.error? | default "") | is-empty) {
            error make {
                msg: ("Unable to inspect protected target safely: " + ($target | into string) + "\n" + $conflict.error)
            }
        }

        let diff_args = [
            "--source"
            ($data_root | into string)
            "diff"
            ($target | into string)
        ]
        let resolved_diff_args = $diff_args
        let diff_result = (
            do { ^chezmoi ...$resolved_diff_args }
            | complete
        )

        if $diff_result.exit_code != 0 {
            error make {
                msg: ("chezmoi diff failed for protected target: " + ($target | into string))
            }
        }

        let diff_text = ($diff_result.stdout? | default "")
        if ($diff_text | is-empty) {
            print "(No textual diff was returned.)"
        } else {
            print $diff_text
        }

        print ""
        print "  [K] Keep the current local file (default)"
        print "  [O] Overwrite it with the private-source version"
        print "  [C] Cancel setup without changing this protected file"

        mut decision = ""
        while ($decision | is-empty) {
            let answer = (input "Choose [K]: " | str trim | str lowercase)
            let choice = if ($answer | is-empty) { "k" } else { $answer }

            if $choice in ["k" "keep"] {
                let kind = (try { $target | path type } catch { "" })
                if $kind != "file" {
                    print "[warn] Automatic keep-local restore supports regular files only."
                    print "       Choose overwrite or cancel for this target."
                    continue
                }

                $keep_local = ($keep_local | append ($target | into string))
                $decision = "keep"
                print "[keep] Current local protected file will be restored after private apply."
            } else if $choice in ["o" "overwrite"] {
                $decision = "overwrite"
                print "[overwrite] Private-source version will replace the local protected file."
            } else if $choice in ["c" "cancel" "q" "quit"] {
                error make {
                    msg: "Protected-file review was cancelled. No private-authoritative apply was performed."
                }
            } else {
                print "Choose K, O, or C."
            }
        }

        print ""
    }

    $keep_local
}

def backup-protected-local [targets: list] {
    if ($targets | is-empty) {
        return { dir: null items: [] }
    }

    let dir = (
        (nu-home)
        | path join ".config" "dotfiles" "protected-apply-backups" (random uuid)
    )
    mkdir $dir

    mut items = []
    for row in ($targets | enumerate) {
        let target = ($row.item | path expand)
        let backup = ($dir | path join (($row.index | into string) + ".bak"))
        cp $target $backup
        $items = ($items | append {
            target: ($target | into string)
            backup: ($backup | into string)
        })
    }

    { dir: ($dir | into string) items: $items }
}

def restore-protected-local [backup: record] {
    for item in ($backup.items? | default []) {
        let target = ($item.target | path expand)
        let saved = ($item.backup | path expand)
        mkdir ($target | path dirname)
        cp --force $saved $target
        print ("[restored] Local protected file: " + ($target | into string))
    }

    let dir = ($backup.dir? | default null)
    if $dir != null and ($dir | path exists) {
        rm --recursive --force $dir
    }
}

def apply-private-source [
    data_root: path
    policy: string = "standard"
] {
    let keep_local = if $policy != "push-local" {
        let protected = (protected-conflicts $data_root)
        if ($protected | is-empty) {
            []
        } else {
            print-protected-conflicts $protected
            protected-apply-choices $data_root $protected
        }
    } else {
        []
    }

    let protected_backup = (backup-protected-local $keep_local)

    let base_args = [
        "--source"
        ($data_root | into string)
    ]

    let apply_args = if $policy in ["pull-private" "backup-private" "push-local"] {
        $base_args | append "--force" | append "apply"
    } else {
        $base_args | append "apply"
    }

    let resolved_apply_args = $apply_args
    let apply_result = (
        do { ^chezmoi ...$resolved_apply_args }
        | complete
    )

    # Local-protected selections are restored regardless of apply success so a
    # partial chezmoi failure cannot silently leave a protected file overwritten.
    restore-protected-local $protected_backup

    if not (($apply_result.stdout? | default "") | is-empty) {
        print $apply_result.stdout
    }
    if not (($apply_result.stderr? | default "") | is-empty) {
        print $apply_result.stderr
    }

    if $apply_result.exit_code != 0 {
        error make {
            msg: "chezmoi apply failed. Protected local selections were restored."
        }
    }
}

def preview-private-source [data_root: path] {
    section "Private configuration preview"

    if not (private-config-exists $data_root) {
        print "No existing private configuration was detected."
        print "This machine would become the initial configuration source."
        return
    }

    if (which chezmoi | is-empty) {
        print "[warn] chezmoi is not installed; a detailed diff cannot be shown."
        return
    }

    print "chezmoi status:"
    let status_args = [
        "--source"
        ($data_root | into string)
        "status"
    ]
    ^chezmoi ...$status_args

    print ""
    print "chezmoi diff:"
    let diff_args = [
        "--source"
        ($data_root | into string)
        "diff"
    ]
    ^chezmoi ...$diff_args
}

def print-dry-run [
    context: record
    mode: string
    policy: string = "standard"
] {
    section "Dry run"

    print "No files, packages, or scheduler entries will be changed."
    print ""
    print "Resolved configuration:"
    print $context
    print ""
    print ("Mode          : " + $mode)
    print ("Config policy : " + $policy)
    print ("Profile       : " + $context.machine.profile)
    print ("Private data  : " + $context.data_root)
    print ("Auto sync     : " + ($context.sync.enabled | into string))
    print ("Sync interval : " + ($context.sync.interval_minutes | into string) + " minute(s)")
    print ("Prune extras  : " + ($context.sync.prune_extras | into string))
    print ""
    print "Planned stages:"
    print "  - optional full project validation only when --validate is requested"
    print "  - create transaction Run ID/checkpoints and configuration backups"
    print "  - protect SSH/Git targets from unreviewed private overwrite"
    print "  - ensure rclone is installed and usable (existing package manager; no auto-upgrade)"
    print "  - initialize private source"
    print "  - install Neovim and D2Coding when enabled"
    print "  - install enabled toolchains / CLI tools"
    print "  - validate/migrate machine config schema"
    print "  - import or apply configuration"
    print "  - configure platform shims"
    print "  - configure local Git / SSH overrides"
    print "  - apply folder-specific Git identities and recover SSH public keys"
    print "  - configure local secrets autoload"
    print "  - capture/restore Rust, Julia, and rclone configuration state"
    print "  - configure Starship / WezTerm when enabled"
    print "  - initialize sync baseline"
    print "  - install automatic sync scheduler when enabled"
    print "  - capture tool-version state"
    print "  - run environment doctor and audit"
}

def --env setup-impl [
    --mode: string = "auto"
    --data-dir: string = ""
    --profile: string = ""
    --config-policy: string = "ask"
    --no-auto-sync
    --dry-run
    --resume
    --run-id: string = ""
] {
    if (cloud-mode-active) and not $dry_run and $config_policy != "preview" {
        error make {msg: "cloud-wins is active. Use dotcloud plan/apply + dotpull, or deactivate explicitly before running setup."}
    }
    section ("Initial-setup " + (app-version))

    if $dry_run and $resume {
        error make { msg: "--dry-run and --resume cannot be used together." }
    }

    let scripts = ($TOOLS_ROOT | path join "scripts")
    mut active_run_id = ""
    mut resume_state = {}

    if not $dry_run {
        if $resume {
            $active_run_id = (resolve-resume-run $run_id)
            $resume_state = (load-run $active_run_id)
            let run_version = ($resume_state.version? | default "")
            if $run_version != (app-version) {
                error make { msg: ("Run " + $active_run_id + " was created by Initial-setup " + $run_version + "; resume it with the same version or rollback/start a new run.") }
            }
            $env.INITIAL_SETUP_RUN_ID = $active_run_id
            $env.INITIAL_SETUP_RESUME = "1"

            section "Resuming setup transaction"
            print ("Run ID : " + $active_run_id)
            print ("Status : " + ($resume_state.status? | default "unknown"))
        } else {
            let preliminary_data_root = (resolve-data-root $data_dir)
            $active_run_id = (create-run (app-version) $mode $config_policy $profile ($preliminary_data_root | into string) $no_auto_sync)
            $env.INITIAL_SETUP_RUN_ID = $active_run_id
            $env.INITIAL_SETUP_RESUME = "0"
            print ("Run ID       : " + $active_run_id)
        }
    }

    let first_run = (not ((machine-config-path) | path exists))

    if not $dry_run {
        run-script "Migrating machine config schema" ($scripts | path join "migrate-config.nu")
    }

    let saved_data_root = ($resume_state.data_root? | default "")
    let effective_data_dir = (if $resume and not ($saved_data_root | is-empty) { $saved_data_root } else { $data_dir })
    let saved_profile = ($resume_state.profile? | default "")
    let effective_profile = (if $resume and not ($saved_profile | is-empty) { $saved_profile } else { $profile })
    let effective_no_auto_sync = (if $resume { $resume_state.no_auto_sync? | default $no_auto_sync } else { $no_auto_sync })
    let data_root = (resolve-data-root $effective_data_dir)
    let proposed_context = (build-machine-config $data_root $effective_no_auto_sync $effective_profile)
    let saved_mode = ($resume_state.resolved_mode? | default "")
    let auto_mode = (if $resume and not ($saved_mode | is-empty) { $saved_mode } else { resolve-mode $mode $data_root })
    validate-config-policy $config_policy

    if $dry_run {
        let dry_policy = (if $config_policy == "ask" { "no-change-preview" } else { $config_policy })
        print-dry-run $proposed_context $auto_mode $dry_policy
        preview-private-source $data_root
        return
    }

    let saved_policy = ($resume_state.resolved_policy? | default "")
    mut config_policy = (
        if $resume and not ($saved_policy | is-empty) {
            $saved_policy
        } else {
            resolve-config-policy $config_policy $mode $first_run $data_root
        }
    )

    if $config_policy == "cancel" {
        section "Setup cancelled"
        print "No setup changes were applied."
        if not ($active_run_id | is-empty) { finish-run $active_run_id "cancelled" }
        return
    }

    if (policy-needs-private-source $config_policy) and not (private-config-exists $data_root) {
        error make {
            msg: ("Config policy '" + $config_policy + "' requires an existing private configuration source. Use push-local or preview instead.")
        }
    }

    if $config_policy == "preview" {
        let preview_mode = (mode-for-policy $config_policy $auto_mode)
        print-dry-run $proposed_context $preview_mode $config_policy
        preview-private-source $data_root
        if not ($active_run_id | is-empty) { finish-run $active_run_id "preview" }
        return
    }

    require chezmoi

    if $config_policy == "review" {
        preview-private-source $data_root
        $config_policy = (choose-reviewed-policy)

        if $config_policy == "cancel" {
            section "Setup cancelled"
            print "No setup changes were applied."
            if not ($active_run_id | is-empty) { finish-run $active_run_id "cancelled" }
            return
        }
    }

    # Closures cannot capture a mut binding. Freeze the final menu choice once,
    # after review/resume resolution; both apply stages use this immutable value.
    let resolved_config_policy = $config_policy

    let resolved_mode = (if $resume and not ($saved_mode | is-empty) { $saved_mode } else { mode-for-policy $config_policy $auto_mode })

    if not ($active_run_id | is-empty) {
        update-run-context $active_run_id $resolved_mode $config_policy $proposed_context.machine.profile ($data_root | into string) $effective_no_auto_sync
    }

    section "Configuration policy"
    print ("Policy        : " + $config_policy)
    print ("Resolved mode : " + $resolved_mode)
    print ("Local config  : " + (if (local-config-exists) { "detected" } else { "not detected" }))
    print ("Private config: " + (if (private-config-exists $data_root) { "detected" } else { "not detected" }))

    if not ($active_run_id | is-empty) {
        run-script "Creating transaction configuration backup" ($scripts | path join "backup-local-config.nu") "--label" ("setup-" + $active_run_id) "--quiet"
    }

    # Kept intentionally on one line for Nushell 0.109 compatibility.
    run-stage "Saving machine configuration" {|| save-machine-config $proposed_context }

    let context = (open (machine-config-path))
    let features = $context.features
    let install_gui = $context.machine.install_gui_apps

    # Core dependency, independent of cli_tools/rclone_config. This executes only
    # after validation, preview/cancel exits, and the local transaction backup.
    # Re-check on resume: an old successful checkpoint is not proof of availability.
    refresh-rclone-path
    run-script "Ensuring rclone is available" ($scripts | path join "install-rclone.nu")
    # Child processes cannot update PATH in this parent; propagate newly registered
    # WinGet/Homebrew locations before snapshot/configuration/sync subprocesses.
    refresh-rclone-path
    ensure-rclone --check | ignore

    if not ($active_run_id | is-empty) {
        run-script "Creating transaction private snapshot" ($scripts | path join "create-snapshot.nu") "--label" ("setup-" + $active_run_id) "--quiet"
    }

    print ("Tools root   : " + ($TOOLS_ROOT | into string))
    print ("Private data : " + ($data_root | into string))
    print ("Machine      : " + $context.machine.name)
    print ("Profile      : " + $context.machine.profile)
    print ("OS           : " + $nu.os-info.name)
    print ("Home         : " + (nu-home | into string))
    print ("Nushell      : " + $env.NU_VERSION)
    print ("App version  : " + $context.app_version)
    print ("Config schema: " + ($context.schema_version | into string))
    print ("Prune extras : " + ($context.sync.prune_extras | into string))

    run-script "Initializing private data structure" ($scripts | path join "init-private-data.nu")
    run-script "Configuring local secrets autoload" ($scripts | path join "setup-secrets.nu")
    run-script "Cleaning legacy direnv integration" ($scripts | path join "cleanup-direnv.nu")

    if $features.neovim {
        run-script "Installing Neovim" ($scripts | path join "install-neovim.nu")
    }

    if $features.neovim {
        run-script "Configuring Neovim as chezmoi merge tool" ($scripts | path join "setup-merge-tool.nu")
    }

    if $features.fonts and $install_gui {
        run-script "Installing D2Coding font" ($scripts | path join "install-fonts.nu")
    }

    if $features.rust or $features.julia {
        run-script "Installing Rust and Julia toolchains" ($scripts | path join "install-language-tools.nu")
    }

    if $features.rust or $features.julia {
        run-script "Applying toolchain lock" ($scripts | path join "toolchain-state.nu") "--apply"
    }

    if $features.cli_tools {
        run-script "Installing package manifests" ($scripts | path join "install-cli-tools.nu")
    }

    if $features.vscode and $install_gui {
        run-script "Installing VS Code" ($scripts | path join "install-vscode.nu")
    }

    run-script "Preparing machine-local Nushell setup" ($scripts | path join "setup-machine-local.nu")

    if ($features.onedrive_ignore_uploads? | default false) {
        run-script "Configuring OneDrive upload exclusions" ($scripts | path join "setup-onedrive-ignore-upload.nu")
    }

    section ("Selected mode: " + $resolved_mode)

    if $resolved_mode == "initial" {
        if $config_policy == "push-local" {
            run-script "Importing local configuration (local wins)" ($scripts | path join "migrate-dotfiles.nu") "--force-source"
        } else {
            run-script "Importing existing local configuration" ($scripts | path join "migrate-dotfiles.nu")
        }

        run-stage "Applying imported/private configuration" {|| apply-private-source $data_root $resolved_config_policy }

        run-script "Configuring platform-specific paths" ($scripts | path join "setup-platform-shims.nu")
        run-script "Enabling Nushell dotfiles commands" ($scripts | path join "enable-nushell-dotfiles.nu")
        run-script "Configuring machine-local Git and SSH overrides" ($scripts | path join "setup-local-overrides.nu")

        if $features.vscode {
            run-script "Capturing VS Code extensions" ($scripts | path join "capture-vscode-extensions.nu")
            run-script "Capturing VS Code settings" ($scripts | path join "capture-vscode-config.nu")
        }

        if $features.rust or $features.julia {
            run-script "Capturing language environment state" ($scripts | path join "capture-work-environment.nu")
        }

        if ($features.rclone_config? | default false) {
            run-script "Capturing rclone config" ($scripts | path join "capture-rclone-config.nu")
        }

        run-script "Recording initial sync writer" ($scripts | path join "write-sync-meta.nu") "--action" "initial"
    } else {
        if $config_policy == "backup-private" {
            run-script "Backing up current local configuration" ($scripts | path join "backup-local-config.nu") "--label" "before-private-apply"
        }

        run-stage "Applying private cloud configuration" {|| apply-private-source $data_root $resolved_config_policy }

        if $features.rust or $features.julia {
            run-script "Restoring language environment state" ($scripts | path join "restore-work-environment.nu")
        }

        if ($features.rclone_config? | default false) {
            run-script "Restoring rclone config" ($scripts | path join "restore-rclone-config.nu")
        }

        run-script "Configuring platform-specific paths" ($scripts | path join "setup-platform-shims.nu")
        run-script "Enabling Nushell dotfiles commands" ($scripts | path join "enable-nushell-dotfiles.nu")
        run-script "Configuring machine-local Git and SSH overrides" ($scripts | path join "setup-local-overrides.nu")

        if $features.vscode {
            run-script "Applying VS Code settings" ($scripts | path join "apply-vscode-config.nu")
            run-script "Installing VS Code extensions" ($scripts | path join "install-vscode-extensions.nu")
        }
    }

    if $features.git_config {
        run-script "Applying folder-specific Git identities" ($scripts | path join "setup-git-identities.nu") "--apply"
    }

    if $features.ssh_config {
        run-script "Checking SSH keys and recovering public keys" ($scripts | path join "setup-ssh-keys.nu") "--generate"
    }

    if $features.starship {
        run-script "Installing Starship" ($scripts | path join "install-starship.nu")
        run-script "Configuring Starship for Nushell" ($scripts | path join "setup-starship.nu")
    }

    if $features.wezterm and $install_gui {
        run-script "Installing WezTerm" ($scripts | path join "install-wezterm.nu")
    }

    run-script "Initializing synchronization baseline" ($scripts | path join "update-sync-state.nu")

    if $context.sync.enabled {
        run-script "Installing automatic synchronization" ($scripts | path join "install-auto-sync.nu")
    } else {
        section "Automatic synchronization"
        print "[skip] sync.enabled is false"
    }

    run-script "Final environment check" ($scripts | path join "doctor.nu")
    run-script "Capturing tool-version state" ($scripts | path join "capture-tool-state.nu")
    run-script "Auditing managed environment" ($scripts | path join "audit.nu")
    run-script "Showing post-setup checklist" ($scripts | path join "post-setup-checklist.nu")

    if not ($active_run_id | is-empty) {
        finish-run $active_run_id "success"
    }

    $env.INITIAL_SETUP_SETUP_COMPLETED = "1"
    section "Setup complete"

    print ("Public tools : " + ($TOOLS_ROOT | into string))
    print ("Private data : " + ($data_root | into string))
    print ""
    print "Restart Nushell once:"
    print "  exec nu"
    print ""
    print "Useful commands:"
    print "  dotstatus / dotsync / dotpush / dotpull"
    print "  dotsnapshot / dotrollback"
    print "  dotdoctor / dotupdate / dotreport / dotlog"
    print "  dotversion / dotrepo / dotrelease / dotaudit / dotstate"
    print "  dotmigrate / dotcleanup / dotlocal / dotchecklist"
    print ""
    print "  dotcapture / dotrestoreenv"
    print "  dotconfig / dotsecrets"
    print "  dotgitids / dotsshkeys / dotgitlocal / dotsshlocal"
    print "  dotpreflight / dotlocalbackup / dotlocalrestore"
    print "  dotvalidate / dottest --sandbox"
    print "  dotrun --status / dotrun --list / dotrun --resume / dotrun --rollback"
    print "  dotresolve (3-way merge + protected-file handling)"
    print "  dotplan / dotapply / dotverify"
    print "  dottoolchain / dotmergecfg"
    print "  dotvault / dotbackend / dotupgrade / dotsecuritytest"
    print "  newproj"
}


const SAFETY_MODULE = path self ./scripts/modules/safety.nu
const PROVIDER_MODULE = path self ./scripts/modules/sync-provider.nu
use $SAFETY_MODULE [operation-lock lock-release]
use $PROVIDER_MODULE [load-provider load-provider-state assert-expected-head provider-head assert-same-head record-provider-state remote-lock release-remote-lock]

# A normal first setup is an explicitly reviewed initialization. Existing
# trusted baselines are never silently reset by a repeated setup invocation.
def main [
    --mode: string = "auto"
    --data-dir: string = ""
    --profile: string = ""
    --config-policy: string = "ask"
    --no-auto-sync
    --dry-run
    --resume
    --run-id: string = ""
    --validate
] {
    if $validate {
        section "Explicit project validation"
        ^$nu.current-exe --no-config-file ($TOOLS_ROOT | path join "scripts" "validate-project.nu")
        if ($env.LAST_EXIT_CODE | default 1) != 0 {
            error make { msg: "Project validation failed; setup did not start." }
        }
    }

    if $dry_run {
        setup-impl --mode $mode --data-dir $data_dir --profile $profile --config-policy $config_policy --no-auto-sync=$no_auto_sync --dry-run --resume=$resume --run-id $run_id
        return
    }
    let lock = (operation-lock)
    mut shared_lock = null
    let operation_result = (try {
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lock.token
        let previous = (old-machine-config)
        let root = (resolve-data-root $data_dir)
        let provider = if ($previous | is-empty) {
            {version: 1 kind: "directory" remote: "" data_root: ($root | into string)}
        } else { load-provider }
        if ($root | path expand) != ($provider.data_root | path expand) {
            error make { msg: "Changing data_root requires an explicit provider reconfiguration; refusing to reset an existing baseline." }
        }
        mkdir $root
        $shared_lock = (remote-lock $provider)
        let before = (provider-head $provider)
        let state = (load-provider-state $provider)
        if $state != null { assert-expected-head $provider | ignore }
        if $provider.kind != "directory" and $state == null and not $before.empty {
            error make { msg: "Fetch the configured remote with dotpull --source-only before running setup." }
        }
        $env.INITIAL_SETUP_SETUP_COMPLETED = "0"
        setup-impl --mode $mode --data-dir $data_dir --profile $profile --config-policy $config_policy --no-auto-sync=$no_auto_sync --resume=$resume --run-id $run_id
        if ($env.INITIAL_SETUP_SETUP_COMPLETED? | default "0") == "1" {
            let after = if $provider.kind == "directory" { provider-head $provider } else {
                assert-same-head $provider $before
                $before
            }
            if $provider.kind == "directory" { record-provider-state $provider $after }
            if $provider.kind != "directory" { print "[info] Setup changed only this workspace. Run dotpush to publish reviewed source changes." }
        }
        null
    } catch {|err|
        print ""
        print "[error] Original setup failure:"
        print $err
        failure-envelope true
    })
    let operation_failure = (captured-failure $operation_result)

    # Snapshot the error in catch; inspect mutable handles in the outer block.
    # Attempt both releases, including when the remote lock cannot be removed.
    let remote_cleanup_result = (try { release-remote-lock $shared_lock; null } catch {|err|
        print "[warn] Remote-lock cleanup failed:"
        print $err
        failure-envelope true
    })
    let local_cleanup_result = (try { lock-release $lock; null } catch {|err|
        print "[warn] Local-lock cleanup failed:"
        print $err
        failure-envelope true
    })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)
    if $operation_failure != null {
        error make { msg: "Setup operation failed. The original diagnostic was printed above." }
    }
    if $remote_cleanup_error != null {
        error make { msg: "Remote-lock cleanup failed. The original cleanup diagnostic was printed above." }
    }
    if $local_cleanup_error != null {
        error make { msg: "Local-lock cleanup failed. The original cleanup diagnostic was printed above." }
    }
}
