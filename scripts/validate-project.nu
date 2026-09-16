#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def useful-lines [file: path] {
    open --raw $file
    | lines
    | each { |line| $line | str trim }
    | where { |line| not ($line | is-empty) and not ($line | str starts-with "#") }
}

def fail [message: string] {
    print ("[FAIL] " + $message)
    exit 1
}

def main [] {
    let version = (
        open --raw ($TOOLS_ROOT | path join "VERSION")
        | decode utf-8
        | str trim
    )

    let schema = (
        open --raw ($TOOLS_ROOT | path join "SCHEMA_VERSION")
        | decode utf-8
        | str trim
        | into int
    )

    if ($version | is-empty) {
        fail "VERSION is empty."
    }

    if $schema < 4 {
        fail "SCHEMA_VERSION must be at least 4."
    }

    let readme = (open --raw ($TOOLS_ROOT | path join "README.md"))

    if not ($readme | str starts-with ("# Initial-setup v" + $version)) {
        fail "README version heading does not match VERSION."
    }

    for required in [
        "VERSION"
        "SCHEMA_VERSION"
        "setup.nu"
        "README.md"
        "CHANGELOG.md"
        "scripts/migrate-config.nu"
        "scripts/capture-tool-state.nu"
        "scripts/audit.nu"
        "scripts/setup-machine-local.nu"
        "scripts/rclone-config-path.nu"
        "scripts/capture-rclone-config.nu"
        "scripts/restore-rclone-config.nu"
        "scripts/setup-onedrive-ignore-upload.nu"
        "scripts/windows/set-onedrive-ignore-upload-policy.ps1"
        "defaults/onedrive-ignore-upload-patterns.txt"
        "scripts/winget-package-state.nu"
        "scripts/windows/winget-package-state.ps1"
        "scripts/modules/core.nu"
        "scripts/modules/profiles.nu"
        "scripts/modules/setup-policy.nu"
        "scripts/modules/git-identities.nu"
        "scripts/modules/ssh-keys.nu"
        "scripts/modules/dotfiles.nu"
        "scripts/setup-git-identities.nu"
        "scripts/setup-ssh-keys.nu"
        "scripts/backup-local-config.nu"
        "scripts/preflight.nu"
        "scripts/resolve-config.nu"
        "profiles/common.nuon"
        "profiles/workstation.nuon"
        "profiles/laptop.nuon"
        "profiles/server.nuon"
        "profiles/minimal.nuon"
        "templates/git-identities.nuon.example"
    ] {
        let file = ($TOOLS_ROOT | path join $required)

        if not ($file | path exists) {
            fail ("Required file missing: " + $required)
        }
    }

    let common_profile = (open ($TOOLS_ROOT | path join "profiles" "common.nuon"))
    let common_features = ($common_profile.features? | default {})

    for required_feature in [
        "neovim"
        "fonts"
        "cli_tools"
        "vscode"
        "wezterm"
        "starship"
        "rust"
        "julia"
        "git_config"
        "ssh_config"
        "rclone_config"
        "onedrive_ignore_uploads"
    ] {
        if ($common_features | get --optional $required_feature) == null {
            fail ("profiles/common.nuon is missing feature: " + $required_feature)
        }
    }

    for profile_name in ["workstation" "laptop" "server" "minimal"] {
        let profile_file = ($TOOLS_ROOT | path join "profiles" ($profile_name + ".nuon"))
        let profile = (open $profile_file)

        if $profile.install_gui_apps? == null {
            fail ("Profile is missing install_gui_apps: " + $profile_name)
        }

        if $profile.features? == null {
            fail ("Profile is missing features record: " + $profile_name)
        }
    }

    let git_identity_template = (open ($TOOLS_ROOT | path join "templates" "git-identities.nuon.example"))

    if ($git_identity_template.version? | default 0) != 1 {
        fail "Git identity example manifest must use version 1."
    }

    if (($git_identity_template.identities? | default []) | is-empty) {
        fail "Git identity example manifest must contain at least one example."
    }

    let setup_source = (open --raw ($TOOLS_ROOT | path join "setup.nu"))

    for required_setup_token in [
        "profiles.nu"
        "setup-policy.nu"
        "--config-policy"
        "choose-config-policy"
        "choose-reviewed-policy"
        "normalize-config-policy"
        "push-local"
        "pull-private"
        "backup-local-config.nu"
        "--force-source"
        "setup-git-identities.nu"
        "setup-ssh-keys.nu"
    ] {
        if not ($setup_source | str contains $required_setup_token) {
            fail ("setup.nu is missing v0.11.x integration: " + $required_setup_token)
        }
    }

    let bootstrap_ps1 = (open --raw ($TOOLS_ROOT | path join "bootstrap.ps1"))
    let bootstrap_sh = (open --raw ($TOOLS_ROOT | path join "bootstrap.sh"))

    if not ($bootstrap_ps1 | str contains "ConfigPolicy") {
        fail "bootstrap.ps1 must pass through the configuration policy."
    }

    if not ($bootstrap_sh | str contains "--config-policy") {
        fail "bootstrap.sh must pass through the configuration policy."
    }

    let dotfiles_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "dotfiles.nu"))

    for required_sync_token in [
        "dotresolve"
        "dotpush"
        "dotpull"
        "--backup"
        "--force"
    ] {
        if not ($dotfiles_module | str contains $required_sync_token) {
            fail ("Bidirectional sync command integration is incomplete: " + $required_sync_token)
        }
    }

    let local_backup = (open --raw ($TOOLS_ROOT | path join "scripts" "backup-local-config.nu"))

    for forbidden_secret_token in [
        "id_ed25519"
        "id_rsa"
        "private_dot_ssh"
        ".env"
    ] {
        if ($local_backup | str contains $forbidden_secret_token) {
            fail ("Local configuration backups must not reference secret/private-key payloads: " + $forbidden_secret_token)
        }
    }

    for required_backup_token in [
        ".ssh"
        "config.local"
        "local-backups"
        "--force"
    ] {
        if not ($local_backup | str contains $required_backup_token) {
            fail ("Local backup implementation is incomplete: " + $required_backup_token)
        }
    }

    let common = (useful-lines ($TOOLS_ROOT | path join "packages" "common.txt"))

    for mapping_file in [
        "packages/windows.txt"
        "packages/macos.txt"
        "packages/linux.txt"
    ] {
        let rows = (
            useful-lines ($TOOLS_ROOT | path join $mapping_file)
            | each { |line| $line | split row "|" | get 0 }
        )

        for package in $common {
            if not ($package in $rows) {
                fail ($mapping_file + " has no mapping for " + $package)
            }
        }
    }

    let forbidden_home_path = ("$nu." + "home-path")
    let forbidden_home_dir = ("$nu." + "home-dir")
    let forbidden_nu_version = ("$nu." + "version")
    let deprecated_downcase = ("str " + "downcase")
    let deprecated_upcase = ("str " + "upcase")
    let auto_sync_installer = (open --raw ($TOOLS_ROOT | path join "scripts" "install-auto-sync.nu"))

    for required_scheduler_token in [
        "auto-sync-hidden.vbs"
        "wscript.exe"
        "//B"
        "//Nologo"
        "shell.Run(commandLine, 0, True)"
    ] {
        if not ($auto_sync_installer | str contains $required_scheduler_token) {
            fail ("Windows hidden scheduler support is missing: " + $required_scheduler_token)
        }
    }

    let forbidden_git_network = [
        ("git " + "pull")
        ("git " + "fetch")
        ("git " + "push")
        ("git " + "clone")
    ]

    for auto_sync_file in [
        "scripts/auto-sync.nu"
        "scripts/auto-sync-worker.nu"
        "scripts/sync-up.nu"
        "scripts/sync-down.nu"
    ] {
        let source = (open --raw ($TOOLS_ROOT | path join $auto_sync_file))

        for forbidden in $forbidden_git_network {
            if ($source | str contains $forbidden) {
                fail ($auto_sync_file + " contains forbidden scheduled Git network operation: " + $forbidden)
            }
        }
    }

    let onedrive_patterns = (
        open --raw ($TOOLS_ROOT | path join "defaults" "onedrive-ignore-upload-patterns.txt")
        | lines
        | where { |line| not ($line | str trim | is-empty) }
    )

    let expected_onedrive_patterns = ["*.log" "*.tmp" "*.cache" "*.bak"]

    if $onedrive_patterns != $expected_onedrive_patterns {
        fail "OneDrive exclusion patterns must be *.log, *.tmp, *.cache, *.bak in that order."
    }

    let onedrive_helper = (
        open --raw ($TOOLS_ROOT | path join "scripts" "windows" "set-onedrive-ignore-upload-policy.ps1")
    )

    if not ($onedrive_helper | str contains "EnableODIgnoreListFromGPO") {
        fail "OneDrive exclusion helper is missing the official policy registry path."
    }

    if ($onedrive_helper | str contains "Remove-ItemProperty") {
        fail "OneDrive exclusion helper must preserve unrelated registry values."
    }

    let rclone_capture = (open --raw ($TOOLS_ROOT | path join "scripts" "capture-rclone-config.nu"))
    let rclone_restore = (open --raw ($TOOLS_ROOT | path join "scripts" "restore-rclone-config.nu"))
    let rclone_mount_command = ("rclone " + "mount")

    if ($rclone_capture | str contains $rclone_mount_command) or ($rclone_restore | str contains $rclone_mount_command) {
        fail "rclone config synchronization must not invoke rclone mount."
    }

    if not ($rclone_capture | str contains "rclone config file") {
        fail "rclone capture must resolve the active config path through rclone."
    }

    if not ($rclone_restore | str contains "rclone config file") {
        fail "rclone restore must resolve the active config path through rclone."
    }

    let local_setup_script = (open --raw ($TOOLS_ROOT | path join "scripts" "setup-machine-local.nu"))
    let machine_local_leaf = ("dotfiles" + "/local.nu")

    if not ($local_setup_script | str contains "if ($file | path exists)") {
        fail "Machine-local setup initializer must preserve an existing local.nu file."
    }

    if ($local_setup_script | str contains "save --force") {
        fail "Machine-local setup initializer must never force-overwrite local.nu."
    }

    for excluded_file in [
        "scripts/sync-fingerprint.nu"
        "scripts/sync-up.nu"
        "scripts/sync-down.nu"
        "scripts/create-snapshot.nu"
        "scripts/rollback.nu"
        "scripts/init-private-data.nu"
        "scripts/capture-vscode-config.nu"
    ] {
        let source = (open --raw ($TOOLS_ROOT | path join $excluded_file))

        if ($source | str contains $machine_local_leaf) {
            fail ($excluded_file + " must not manage machine-local local.nu.")
        }
    }

    let git_identity_local_leaf = ("dotfiles" + "/git-identities.nuon")

    for excluded_file in [
        "scripts/sync-fingerprint.nu"
        "scripts/sync-up.nu"
        "scripts/sync-down.nu"
        "scripts/create-snapshot.nu"
        "scripts/rollback.nu"
        "scripts/init-private-data.nu"
        "scripts/migrate-dotfiles.nu"
    ] {
        let source = (open --raw ($TOOLS_ROOT | path join $excluded_file))

        if ($source | str contains $git_identity_local_leaf) {
            fail ($excluded_file + " must not manage machine-local git-identities.nuon.")
        }

        if ($source | str contains "initial-setup-identities.gitconfig") {
            fail ($excluded_file + " must not manage generated Git identity dispatchers.")
        }
    }

    let sync_fingerprint = (open --raw ($TOOLS_ROOT | path join "scripts" "sync-fingerprint.nu"))

    if ($sync_fingerprint | lines | any { |line| ($line | str trim | str starts-with "+") }) {
        fail "sync-fingerprint.nu contains a physical line beginning with `+`."
    }

    if not ($sync_fingerprint | str contains "into glob") {
        fail "sync-fingerprint.nu must convert variable glob patterns with `into glob`."
    }

    let exists_guard = ($sync_fingerprint | str index-of "path exists")
    let expand_call = ($sync_fingerprint | str index-of "path expand")
    let type_call = ($sync_fingerprint | str index-of "path type")

    if $exists_guard == -1 {
        fail "sync-fingerprint.nu must check path existence before fingerprint inspection."
    }

    if $expand_call == -1 or $type_call == -1 {
        fail "sync-fingerprint.nu is missing path inspection commands."
    }

    if $exists_guard > $expand_call {
        fail "sync-fingerprint.nu must check path existence before path expansion."
    }

    if $exists_guard > $type_call {
        fail "sync-fingerprint.nu must check path existence before path type detection."
    }

    let normalized_root = ($TOOLS_ROOT | into string | str replace --all '\' '/')
    let pattern = ($normalized_root + "/**/*.nu" | into glob)
    let nu_files = (glob $pattern)

    if ($nu_files | is-empty) {
        fail "No Nushell source files were found."
    }

    for file in $nu_files {
        let normalized = ($file | into string | str replace --all '\' '/')
        let is_module = ($normalized | str contains "/scripts/modules/")
        let parsed = (
            if $is_module {
                nu-check --as-module $file
            } else {
                nu-check $file
            }
        )

        if not $parsed {
            print ("[FAIL] Nushell parser rejected: " + ($file | into string))

            if $is_module {
                nu-check --debug --as-module $file | ignore
            } else {
                nu-check --debug $file | ignore
            }

            exit 1
        }

        let source = (open --raw $file)

        if ($source | str contains $deprecated_downcase) {
            fail (($file | into string) + " uses a deprecated lowercase conversion command.")
        }

        if ($source | str contains $deprecated_upcase) {
            fail (($file | into string) + " uses a deprecated uppercase conversion command.")
        }

        if ($source | str contains $forbidden_home_path) {
            fail (($file | into string) + " contains direct version-specific home-path access.")
        }

        if ($source | str contains $forbidden_home_dir) {
            fail (($file | into string) + " contains direct version-specific home-dir access.")
        }

        if ($source | str contains $forbidden_nu_version) {
            fail (($file | into string) + " contains invalid Nushell version-field access.")
        }

        for line in ($source | lines) {
            let trimmed = ($line | str trim)

            if ($trimmed | str starts-with "and ") {
                fail (($file | into string) + " starts a physical line with `and`.")
            }

            if ($trimmed | str starts-with "or ") {
                fail (($file | into string) + " starts a physical line with `or`.")
            }

            if ($trimmed | str starts-with "+ ") {
                fail (($file | into string) + " starts a physical line with `+`.")
            }

            if ($trimmed | str starts-with "* ") {
                fail (($file | into string) + " starts a physical line with `*`.")
            }

            if ($trimmed | str starts-with "/ ") {
                fail (($file | into string) + " starts a physical line with `/`.")
            }

            if ($trimmed | str starts-with "% ") {
                fail (($file | into string) + " starts a physical line with `%`.")
            }

            if ($trimmed | str starts-with "== ") {
                fail (($file | into string) + " starts a physical line with `==`.")
            }

            if ($trimmed | str starts-with "!= ") {
                fail (($file | into string) + " starts a physical line with `!=`.")
            }

            if ($trimmed | str starts-with "<= ") {
                fail (($file | into string) + " starts a physical line with `<=`.")
            }

            if ($trimmed | str starts-with ">= ") {
                fail (($file | into string) + " starts a physical line with `>=`.")
            }
        }
    }

    print ("[ok] VERSION = " + $version)
    print ("[ok] SCHEMA_VERSION = " + ($schema | into string))
    print "[ok] Profile manifests are complete."
    print "[ok] Git identity template is valid."
    print ("[ok] Package manifests are complete.")
    print ("[ok] Nushell parser validation passed for " + (($nu_files | length) | into string) + " files.")
    print "[ok] Project validation passed."
}
