#!/usr/bin/env nu

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

def require [name: string] {
    if (which $name | is-empty) {
        error make {
            msg: ("Required command not found: " + $name)
        }
    }
}

def machine-config-path [] {
    nu-home
    | path join ".config" "dotfiles" "config.nuon"
}

def detect-machine-name [] {
    let computer_name = ($env.COMPUTERNAME? | default "" | str trim)

    if not ($computer_name | is-empty) {
        return $computer_name
    }

    let host_name = ($env.HOSTNAME? | default "" | str trim)

    if not ($host_name | is-empty) {
        return $host_name
    }

    if not (which hostname | is-empty) {
        let external_name = (^hostname | str trim)

        if not ($external_name | is-empty) {
            return $external_name
        }
    }

    "unknown-machine"
}

def profile-defaults [profile: string] {
    match $profile {
        "workstation" => {
            {
                install_gui_apps: true
                features: {
                    cli_tools: true
                    vscode: true
                    wezterm: true
                    starship: true
                    rust: true
                    julia: true
                    git_config: true
                    ssh_config: true
                }
            }
        }

        "laptop" => {
            {
                install_gui_apps: true
                features: {
                    cli_tools: true
                    vscode: true
                    wezterm: true
                    starship: true
                    rust: true
                    julia: true
                    git_config: true
                    ssh_config: true
                }
            }
        }

        "server" => {
            {
                install_gui_apps: false
                features: {
                    cli_tools: true
                    vscode: false
                    wezterm: false
                    starship: true
                    rust: true
                    julia: true
                    git_config: true
                    ssh_config: true
                }
            }
        }

        "minimal" => {
            {
                install_gui_apps: false
                features: {
                    cli_tools: true
                    vscode: false
                    wezterm: false
                    starship: true
                    rust: false
                    julia: false
                    git_config: true
                    ssh_config: true
                }
            }
        }

        _ => {
            error make {
                msg: (
                    "Unknown profile '"
                    + $profile
                    + "'. Use workstation, laptop, server, or minimal."
                )
            }
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

    let reset_to_profile = (
        not ($requested_profile | is-empty)
        or ($old | is-empty)
    )

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
    const TOOLS_ROOT = path self .

    {
        version: (app-version)
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
        }

        maintenance: {
            snapshots_enabled: ($old_maintenance.snapshots_enabled? | default true)
            snapshot_keep: ($old_maintenance.snapshot_keep? | default 20)
            log_keep_lines: ($old_maintenance.log_keep_lines? | default 2000)
        }

        features: {
            cli_tools: (feature-value $old_features $preset_features "cli_tools" $reset_to_profile)
            vscode: (feature-value $old_features $preset_features "vscode" $reset_to_profile)
            wezterm: (feature-value $old_features $preset_features "wezterm" $reset_to_profile)
            starship: (feature-value $old_features $preset_features "starship" $reset_to_profile)
            rust: (feature-value $old_features $preset_features "rust" $reset_to_profile)
            julia: (feature-value $old_features $preset_features "julia" $reset_to_profile)
            git_config: (feature-value $old_features $preset_features "git_config" $reset_to_profile)
            ssh_config: (feature-value $old_features $preset_features "ssh_config" $reset_to_profile)
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
        "[save] Machine config -> "
        + ($config_file | into string)
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

def private-source-has-user-config [data_root: path] {
    let markers = [
        ($data_root | path join "home" "dot_config" "nvim" "init.lua")
        ($data_root | path join "home" "dot_config" "nushell" "config.nu")
        ($data_root | path join "home" "dot_config" "nushell" "env.nu")
        ($data_root | path join "home" "dot_gitconfig")
        ($data_root | path join "home" "private_dot_ssh" "config")
    ]

    $markers | any { |item| $item | path exists }
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
            if (private-source-has-user-config $data_root) {
                "existing"
            } else {
                "initial"
            }
        }

        _ => {
            error make {
                msg: (
                    "Unknown mode '"
                    + $requested
                    + "'. Use auto, initial, or existing."
                )
            }
        }
    }
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

def apply-private-source [data_root: path] {
    let args = [
        "--source"
        ($data_root | into string)
        "apply"
    ]

    ^chezmoi ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        error make {
            msg: "chezmoi apply failed"
        }
    }
}

def print-dry-run [
    context: record
    mode: string
] {
    section "Dry run"

    print "No files, packages, or scheduler entries will be changed."
    print ""
    print "Resolved configuration:"
    print $context
    print ""
    print ("Mode          : " + $mode)
    print ("Profile       : " + $context.machine.profile)
    print ("Private data  : " + $context.data_root)
    print ("Auto sync     : " + ($context.sync.enabled | into string))
    print ("Sync interval : " + ($context.sync.interval_minutes | into string) + " minute(s)")
    print ""
    print "Planned stages:"
    print "  - initialize private source"
    print "  - install enabled toolchains / CLI tools"
    print "  - import or apply configuration"
    print "  - configure platform shims"
    print "  - configure local Git / SSH overrides"
    print "  - configure local secrets autoload"
    print "  - configure Starship / WezTerm when enabled"
    print "  - initialize sync baseline"
    print "  - install automatic sync scheduler when enabled"
    print "  - run environment doctor"
}

def main [
    --mode: string = "auto"
    --data-dir: string = ""
    --profile: string = ""
    --no-auto-sync
    --dry-run
] {
    section $"Initial-setup (app-version)"
    require chezmoi

    let scripts = ($TOOLS_ROOT | path join "scripts")
    let data_root = (resolve-data-root $data_dir)
    let proposed_context = (build-machine-config $data_root $no_auto_sync $profile)
    let resolved_mode = (resolve-mode $mode $data_root)

    if $dry_run {
        print-dry-run $proposed_context $resolved_mode
        return
    }

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

    run-script "Initializing private data structure" ($scripts | path join "init-private-data.nu")
    run-script "Configuring local secrets autoload" ($scripts | path join "setup-secrets.nu")

    run-script "Installing Neovim" ($scripts | path join "install-neovim.nu")
    if $features.rust or $features.julia {
        run-script "Installing Rust and Julia toolchains" ($scripts | path join "install-language-tools.nu")
    }

    if $features.cli_tools {
        run-script "Installing package manifests" ($scripts | path join "install-cli-tools.nu")
    }

    if $features.vscode and $install_gui {
        run-script "Installing VS Code" ($scripts | path join "install-vscode.nu")
    }

    section ("Selected mode: " + $resolved_mode)

    if $resolved_mode == "initial" {
        run-script "Importing existing local configuration" ($scripts | path join "migrate-dotfiles.nu")

        section "Applying imported/private configuration"
        apply-private-source $data_root

        run-script "Configuring platform-specific paths" ($scripts | path join "setup-platform-shims.nu")
        run-script "Enabling Nushell dotfiles commands" ($scripts | path join "enable-nushell-dotfiles.nu")
        run-script "Configuring machine-local Git and SSH overrides" ($scripts | path join "setup-local-overrides.nu")

        if $features.vscode {
            run-script "Capturing VS Code extensions" ($scripts | path join "capture-vscode-extensions.nu")
            run-script "Capturing VS Code settings" ($scripts | path join "capture-vscode-config.nu")
        }

        run-script "Recording initial sync writer" ($scripts | path join "write-sync-meta.nu") "--action" "initial"
    } else {
        section "Applying private cloud configuration"
        apply-private-source $data_root

        run-script "Configuring platform-specific paths" ($scripts | path join "setup-platform-shims.nu")
        run-script "Enabling Nushell dotfiles commands" ($scripts | path join "enable-nushell-dotfiles.nu")
        run-script "Configuring machine-local Git and SSH overrides" ($scripts | path join "setup-local-overrides.nu")

        if $features.vscode {
            run-script "Applying VS Code settings" ($scripts | path join "apply-vscode-config.nu")
            run-script "Installing VS Code extensions" ($scripts | path join "install-vscode-extensions.nu")
        }
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
    print "  dotconfig / dotsecrets"
    print "  dotgitlocal / dotsshlocal"
    print "  newproj"
}
