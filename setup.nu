#!/usr/bin/env nu

const CORE_MODULE = path self ./scripts/modules/core.nu
const PROFILES_MODULE = path self ./scripts/modules/profiles.nu
const SETUP_POLICY_MODULE = path self ./scripts/modules/setup-policy.nu

use $CORE_MODULE [nu-home machine-config-path detect-machine-name]
use $PROFILES_MODULE [profile-defaults]
use $SETUP_POLICY_MODULE [config-policy-names normalize-config-policy choose-config-policy choose-reviewed-policy local-config-exists private-config-exists]
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
    open $version_file --raw | decode utf-8 | str trim
}

def schema-version [] {
    let schema_file = ($TOOLS_ROOT | path join "SCHEMA_VERSION")
    open $schema_file --raw | decode utf-8 | str trim | into int
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

    let preset = (profile-defaults $profile)
    let preset_features = $preset.features

    let old_name = ($old_machine.name? | default "")
    let machine_name = (
        if ($old_name | is-empty) {
            detect-machine-name
        } else {
            $old_name
        }
    )

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
            neovim: (feature-value $old_features $preset_features "neovim" $reset_to_profile)
            fonts: (feature-value $old_features $preset_features "fonts" $reset_to_profile)
            cli_tools: (feature-value $old_features $preset_features "cli_tools" $reset_to_profile)
            vscode: (feature-value $old_features $preset_features "vscode" $reset_to_profile)
            wezterm: (feature-value $old_features $preset_features "wezterm" $reset_to_profile)
            starship: (feature-value $old_features $preset_features "starship" $reset_to_profile)
            rust: (feature-value $old_features $preset_features "rust" $reset_to_profile)
            julia: (feature-value $old_features $preset_features "julia" $reset_to_profile)
            git_config: (feature-value $old_features $preset_features "git_config" $reset_to_profile)
            ssh_config: (feature-value $old_features $preset_features "ssh_config" $reset_to_profile)
            rclone_config: (feature-value $old_features $preset_features "rclone_config" $reset_to_profile)
            onedrive_ignore_uploads: (feature-value $old_features $preset_features "onedrive_ignore_uploads" $reset_to_profile)
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

def run-script [
    title: string
    file: path
    ...args: string
] {
    section $title

    let script = ($file | path expand)

    if not ($script | path exists) {
        error make {
            msg: ("Required script not found: " + ($script | into string))
        }
    }

    print ("[run] " + ($script | into string))

    ^nu $script ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        error make {
            msg: ("Script failed: " + ($script | into string))
        }
    }
}

def apply-private-source [
    data_root: path
    policy: string = "standard"
] {
    mut args = [
        "--source"
        ($data_root | into string)
    ]

    if $policy in ["pull-private" "backup-private" "push-local"] {
        $args = ($args | append "--force")
    }

    $args = ($args | append "apply")

    ^chezmoi ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        error make {
            msg: "chezmoi apply failed"
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

def main [
    --mode: string = "auto"
    --data-dir: string = ""
    --profile: string = ""
    --config-policy: string = "ask"
    --no-auto-sync
    --dry-run
] {
    section ("Initial-setup " + (app-version))

    let scripts = ($TOOLS_ROOT | path join "scripts")
    let first_run = (not ((machine-config-path) | path exists))

    if not $dry_run {
        run-script "Migrating machine config schema" ($scripts | path join "migrate-config.nu")
    }

    let data_root = (resolve-data-root $data_dir)
    let proposed_context = (build-machine-config $data_root $no_auto_sync $profile)
    let auto_mode = (resolve-mode $mode $data_root)
    validate-config-policy $config_policy

    if $dry_run {
        let dry_policy = (if $config_policy == "ask" { "no-change-preview" } else { $config_policy })
        print-dry-run $proposed_context $auto_mode $dry_policy
        preview-private-source $data_root
        return
    }

    mut config_policy = (resolve-config-policy $config_policy $mode $first_run $data_root)

    if $config_policy == "cancel" {
        section "Setup cancelled"
        print "No setup changes were applied."
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
        return
    }

    require chezmoi

    if $config_policy == "review" {
        preview-private-source $data_root
        $config_policy = (choose-reviewed-policy)

        if $config_policy == "cancel" {
            section "Setup cancelled"
            print "No setup changes were applied."
            return
        }
    }

    let resolved_mode = (mode-for-policy $config_policy $auto_mode)

    section "Configuration policy"
    print ("Policy        : " + $config_policy)
    print ("Resolved mode : " + $resolved_mode)
    print ("Local config  : " + (if (local-config-exists) { "detected" } else { "not detected" }))
    print ("Private config: " + (if (private-config-exists $data_root) { "detected" } else { "not detected" }))

    # Kept intentionally on one line for Nushell 0.109 compatibility.
    save-machine-config $proposed_context

    let context = (open (machine-config-path))
    let features = $context.features
    let install_gui = $context.machine.install_gui_apps

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

    if $features.fonts and $install_gui {
        run-script "Installing D2Coding font" ($scripts | path join "install-fonts.nu")
    }

    if $features.rust or $features.julia {
        run-script "Installing Rust and Julia toolchains" ($scripts | path join "install-language-tools.nu")
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

        section "Applying imported/private configuration"
        apply-private-source $data_root $config_policy

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

        section "Applying private cloud configuration"
        apply-private-source $data_root $config_policy

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
    print "  newproj"
}
