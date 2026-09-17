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

# Keep checkout paths literal: [brackets] are directory names, not glob syntax.
def regular-files [directory: path] {
    mut files = []
    for item in (ls --all $directory) {
        if ($item.name | path basename) == ".git" { continue }
        if $item.type == "dir" {
            $files = ($files | append (regular-files $item.name))
        } else if $item.type == "file" {
            $files = ($files | append $item.name)
        }
    }
    $files
}

def main [] {
    # Validate all source files before any structural/version early-exit. This
    # standalone child does not import setup.nu or a project module itself.
    let syntax = ($TOOLS_ROOT | path join "scripts" "validate-syntax.nu")
    let exe = $nu.current-exe
    ^$exe --no-config-file $syntax
    if ($env.LAST_EXIT_CODE | default 1) != 0 {
        fail "Nushell syntax/startup validation failed; all diagnostics are listed above."
    }

    let version = (
        open --raw ($TOOLS_ROOT | path join "VERSION")
        | into string
        | str trim
    )

    let schema = (
        open --raw ($TOOLS_ROOT | path join "SCHEMA_VERSION")
        | into string
        | str trim
        | into int
    )

    if ($version | is-empty) {
        fail "VERSION is empty."
    }

    if $schema < 5 {
        fail "SCHEMA_VERSION must be at least 5."
    }

    let github_dir = ($TOOLS_ROOT | path join ".github")

    if ($github_dir | path exists) {
        fail ".github must remain absent from this repository."
    }

    let readme = (open --raw ($TOOLS_ROOT | path join "README.md"))

    if not ($readme | str starts-with ("# Initial-setup v" + $version)) {
        fail "README version heading does not match VERSION."
    }

    for required in [
        "VERSION"
        "RELEASE-MANIFEST.json"
        "scripts/modules/safety.nu"
        "scripts/modules/process-output.nu"
        "scripts/process-output-test.nu"
        "scripts/modules/vault.nu"
        "scripts/modules/sync-provider.nu"
        "scripts/modules/upgrade.nu"
        "scripts/secret-vault.nu"
        "scripts/backend-control.nu"
        "scripts/safe-upgrade.nu"
        "scripts/sync-transport.nu"
        "scripts/sync-up-local.nu"
        "scripts/sync-down-local.nu"
        "scripts/security-self-test.nu"
        "scripts/validate-syntax.nu"
        "scripts/syntax-check-file.nu"
        "scripts/syntax-self-test.nu"
        "scripts/modules/text-case.nu"
        "scripts/modules/compat/case-legacy.nu"
        "scripts/modules/compat/case-modern.nu"
        "scripts/check-compatibility.nu"
        "scripts/regression-test.nu"
        "scripts/install-rclone.nu"
        "scripts/modules/rclone-install.nu"
        "scripts/rclone-install-test.nu"
        "scripts/make-release-manifest.nu"
        "scripts/windows/acquire-operation-lock.ps1"
        "scripts/posix/acquire-operation-lock.sh"
        "scripts/lock-status.nu"
        "scripts/lock-test.nu"
        "scripts/windows/protect-secret-path.ps1"
        "templates/vault.nuon.example"
        "templates/sync-provider.nuon.example"
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
        "scripts/modules/run-state.nu"
        "scripts/modules/planner.nu"
        "scripts/modules/toolchains.nu"
        "scripts/plan.nu"
        "scripts/apply-plan.nu"
        "scripts/verify-plan.nu"
        "scripts/toolchain-state.nu"
        "scripts/setup-merge-tool.nu"
        "toolchains/lock.nuon"
        "profiles/os/windows.nuon"
        "profiles/os/macos.nuon"
        "profiles/os/linux.nuon"
        "templates/machine-overlay.nuon.example"
        "templates/toolchains.lock.nuon.example"
        "scripts/modules/conflicts.nu"
        "scripts/modules/git-identities.nu"
        "scripts/modules/ssh-keys.nu"
        "scripts/modules/dotfiles.nu"
        "scripts/setup-git-identities.nu"
        "scripts/setup-ssh-keys.nu"
        "scripts/backup-local-config.nu"
        "scripts/preflight.nu"
        "scripts/self-test.nu"
        "scripts/resolve-config.nu"
        "scripts/run-control.nu"
        "defaults/conflict-policy.nuon"
        "profiles/common.nuon"
        "profiles/workstation.nuon"
        "profiles/laptop.nuon"
        "profiles/server.nuon"
        "profiles/minimal.nuon"
        "templates/git-identities.nuon.example"
        "templates/conflict-policy.nuon.example"
    ] {
        let file = ($TOOLS_ROOT | path join $required)

        if not ($file | path exists) {
            fail ("Required file missing: " + $required)
        }
    }

    let templates_root = ($TOOLS_ROOT | path join "templates")
    for example in (ls --all $templates_root | where type == "file" | get name | where {|file| $file | str ends-with ".nuon.example" }) {
        open --raw $example | from nuon | ignore
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

    let git_identity_template = (open --raw ($TOOLS_ROOT | path join "templates" "git-identities.nuon.example") | from nuon)

    if ($git_identity_template.version? | default 0) != 1 {
        fail "Git identity example manifest must use version 1."
    }

    if (($git_identity_template.identities? | default []) | is-empty) {
        fail "Git identity example manifest must contain at least one example."
    }

    let release_source = (open --raw ($TOOLS_ROOT | path join "scripts" "release.nu"))

    if not ($release_source | str contains "self-test.nu") {
        fail "Release gate must run the sandbox self-test."
    }

    if not ($release_source | str contains "--sandbox") {
        fail "Release gate must invoke self-test.nu with --sandbox."
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
        "validate-project.nu"
        "run-state.nu"
        "--resume"
        "--run-id"
        "Creating transaction configuration backup"
        "protected-conflicts"
        "Ensuring rclone is available"
        "install-rclone.nu"
        "refresh-rclone-path"
        "ensure-rclone --check"
    ] {
        if not ($setup_source | str contains $required_setup_token) {
            fail ("setup.nu is missing v0.12.x integration: " + $required_setup_token)
        }
    }

    let bootstrap_ps1 = (open --raw ($TOOLS_ROOT | path join "bootstrap.ps1"))
    let bootstrap_sh = (open --raw ($TOOLS_ROOT | path join "bootstrap.sh"))

    if not ($bootstrap_ps1 | str contains "ConfigPolicy") {
        fail "bootstrap.ps1 must pass through the configuration policy."
    }

    for required_bootstrap_ps1_token in ["Resume" "RunId" "--resume" "--run-id"] {
        if not ($bootstrap_ps1 | str contains $required_bootstrap_ps1_token) {
            fail ("bootstrap.ps1 is missing transaction resume passthrough: " + $required_bootstrap_ps1_token)
        }
    }

    for required_bootstrap_sh_token in ["--config-policy" "--resume" "--run-id"] {
        if not ($bootstrap_sh | str contains $required_bootstrap_sh_token) {
            fail ("bootstrap.sh is missing setup passthrough: " + $required_bootstrap_sh_token)
        }
    }

    let dotfiles_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "dotfiles.nu"))

    for required_sync_token in [
        "dotresolve"
        "dotpush"
        "dotpull"
        "dotvalidate"
        "dottest"
        "self-test.nu"
        "dotrun"
        "--rollback"
        "--policy"
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
        "machine-config"
        "sync-state"
        "present: false"
        "version: 2"
        "--force"
    ] {
        if not ($local_backup | str contains $required_backup_token) {
            fail ("Local backup implementation is incomplete: " + $required_backup_token)
        }
    }

    let self_test = (open --raw ($TOOLS_ROOT | path join "scripts" "self-test.nu"))

    for required_self_test_token in [
        "INITIAL_SETUP_TEST_MODE"
        "INITIAL_SETUP_HOME_OVERRIDE"
        "--dry-run"
        "push-local"
        "pull-private"
        "Dry-run unexpectedly wrote a machine configuration file"
        "create-run"
        "Transaction checkpoint/history lifecycle passed"
        "Transaction local backup/restore semantics passed"
        "Protected-file policy loading passed"
        "Machine-local profile overlay was not applied"
        "Desired-state planner did not persist a sandbox plan"
        "setup-merge-tool.nu"
    ] {
        if not ($self_test | str contains $required_self_test_token) {
            fail ("Sandbox self-test is incomplete: " + $required_self_test_token)
        }
    }

    let core_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "core.nu"))
    let policy_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "setup-policy.nu"))

    for sandbox_token in ["INITIAL_SETUP_TEST_MODE" "INITIAL_SETUP_HOME_OVERRIDE"] {
        if not ($core_module | str contains $sandbox_token) {
            fail ("core.nu must support guarded sandbox home isolation: " + $sandbox_token)
        }

        if not ($policy_module | str contains $sandbox_token) {
            fail ("setup-policy.nu must support guarded sandbox home isolation: " + $sandbox_token)
        }
    }

    let run_state_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "run-state.nu"))
    for required_run_token in [
        "create-run"
        "mark-stage"
        "finish-run"
        "latest-resumable-run"
        "events.log"
    ] {
        if not ($run_state_module | str contains $required_run_token) {
            fail ("Run-state module is incomplete: " + $required_run_token)
        }
    }

    let conflict_policy = (open ($TOOLS_ROOT | path join "defaults" "conflict-policy.nuon"))
    if ($conflict_policy.version? | default 0) != 1 {
        fail "Conflict policy must use version 1."
    }
    if not (".ssh/config" in ($conflict_policy.protected? | default [])) {
        fail "Conflict policy must protect .ssh/config by default."
    }

    let conflict_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "conflicts.nu"))
    for required_conflict_token in ["protected-conflicts" "is-protected-target" "merge_preferred" "source-path"] {
        if not ($conflict_module | str contains $required_conflict_token) {
            fail ("Conflict module is incomplete: " + $required_conflict_token)
        }
    }

    let resolver = (open --raw ($TOOLS_ROOT | path join "scripts" "resolve-config.nu"))
    for required_resolver_token in ["merge-all" "Three-way merge" "Explicitly force one protected file"] {
        if not ($resolver | str contains $required_resolver_token) {
            fail ("Three-way resolver is incomplete: " + $required_resolver_token)
        }
    }

    let sync_down = (open --raw ($TOOLS_ROOT | path join "scripts" "sync-down-local.nu"))
    if not ($sync_down | str contains "--allow-protected") {
        fail "sync-down.nu must guard protected targets before private-authoritative apply."
    }

    let run_control = (open --raw ($TOOLS_ROOT | path join "scripts" "run-control.nu"))
    for required_run_control_token in ["--rollback" "--source-only" "setup-" "rollback-failed"] {
        if not ($run_control | str contains $required_run_control_token) {
            fail ("Transaction rollback integration is incomplete: " + $required_run_control_token)
        }
    }

    let rollback_source = (open --raw ($TOOLS_ROOT | path join "scripts" "rollback.nu"))
    for required_rollback_token in ["--source-only" ".dotfiles-sync-meta.nuon"] {
        if not ($rollback_source | str contains $required_rollback_token) {
            fail ("Private snapshot rollback is incomplete: " + $required_rollback_token)
        }
    }


    let dotfiles_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "dotfiles.nu"))
    for token in ["dotplan" "dotapply" "dotverify" "dottoolchain" "dotmergecfg"] {
        if not ($dotfiles_module | str contains $token) { fail ("Dotfiles command surface is incomplete: " + $token) }
    }

    let planner_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "planner.nu"))
    for token in ["build-plan" "save-plan" "missing_packages" "protected_conflicts" "toolchain_drift" "verify_ok"] {
        if not ($planner_module | str contains $token) { fail ("Planner module is incomplete: " + $token) }
    }

    let profile_module = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "profiles.nu"))
    for token in ["os_file" "repo_machine" "machine-overlay.nuon" "profile-layers" "profile-forced-features"] {
        if not ($profile_module | str contains $token) { fail ("Layered profile support is incomplete: " + $token) }
    }

    let toolchain_lock = (open ($TOOLS_ROOT | path join "toolchains" "lock.nuon"))
    if ($toolchain_lock.version? | default 0) != 1 { fail "Toolchain lock must use version 1." }
    for key in ["rust" "julia" "nushell"] {
        if ($toolchain_lock | get --optional $key) == null { fail ("Toolchain lock is missing: " + $key) }
    }

    let merge_setup = (open --raw ($TOOLS_ROOT | path join "scripts" "setup-merge-tool.nu"))
    for token in ["[merge]" "command = \"nvim\"" "{{ .Destination }}" "{{ .Source }}" "{{ .Target }}"] {
        if not ($merge_setup | str contains $token) { fail ("Neovim merge-tool setup is incomplete: " + $token) }
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

    let rclone_installer = (open --raw ($TOOLS_ROOT | path join "scripts" "modules" "rclone-install.nu"))
    for token in ["--no-upgrade" "--dry-run" "--check" "INITIAL_SETUP_TEST_MODE" "rclone version" "perform-rclone-install" "refresh-rclone-path"] {
        if not ($rclone_installer | str contains $token) { fail ("rclone installer is missing safety contract: " + $token) }
    }
    if not ($self_test | str contains "syntax-self-test.nu") { fail "Sandbox gate must test the syntax validator itself." }
    if not ($self_test | str contains "rclone-install-test.nu") { fail "Sandbox gate must include mocked rclone dependency regressions." }
    if not ("rclone" in (useful-lines ($TOOLS_ROOT | path join "packages" "common.txt"))) { fail "rclone is missing from the common package manifest." }

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

    # Compare the target-entries operations, not unrelated nu-home/normalize-path
    # helpers earlier in the file. The previous global search rejected a valid guard.
    let exists_guard = ($sync_fingerprint | str index-of "if not ($target_text | path exists)")
    let expand_call = ($sync_fingerprint | str index-of "let expanded = ($target_text | path expand)")
    let type_call = ($sync_fingerprint | str index-of "$expanded | path type")

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

    for contract in [
        {file: "scripts/modules/safety.nu" tokens: ["lock-acquire" "validate-relative" "verify-tree"]}
        {file: "scripts/modules/vault.nu" tokens: ["--encrypt" "--decrypt" "recipients" "disjoint-paths" "remove_legacy"]}
        {file: "scripts/modules/sync-provider.nu" tokens: ["assert-expected-head" "assert-same-head" "--download" "revisions/" "audit-export"]}
        {file: "scripts/sync-transport.nu" tokens: ["operation-lock" "assert-expected-head" "record-provider-state" "--source-only"]}
        {file: "scripts/safe-upgrade.nu" tokens: ["verify-release" "validate-candidate" "rollback-files" "--keep" "--manifest-sha256"]}
        {file: "scripts/release.nu" tokens: ["security-self-test.nu" "--require-age" "--require-rclone" "make-release-manifest.nu"]}
        {file: "scripts/security-self-test.nu" tokens: ["RCLONE_CONFIG" "Corrupt ciphertext" "Mid-operation HEAD" "Wrong trusted manifest" "User-edited file"]}
    ] {
        let source = (open --raw ($TOOLS_ROOT | path join $contract.file))
        for token in $contract.tokens {
            if not ($source | str contains $token) { fail ($contract.file + " lacks contract: " + $token) }
        }
    }
    let vault_source = (open --raw ($TOOLS_ROOT | path join "scripts" "capture-rclone-config.nu"))
    if not ($vault_source | str contains "capture-secret") { fail "rclone capture must use the encrypted vault." }
    if ($vault_source | str contains "cp ") { fail "Plaintext rclone copying is forbidden." }

    # All shared code uses text-case.nu. Each interpreter checks its active
    # case adapter; the syntax report records the other adapter as inactive.
    let nu_files = (regular-files $TOOLS_ROOT | where {|file| $file | str ends-with ".nu" } | sort)

    if ($nu_files | is-empty) {
        fail "No Nushell source files were found."
    }

    for file in $nu_files {
        let source = (open --raw $file)

        if ($source | str contains $forbidden_home_path) {
            fail (($file | into string) + " contains direct version-specific home-path access.")
        }

        if ($source | str contains $forbidden_home_dir) {
            fail (($file | into string) + " contains direct version-specific home-dir access.")
        }

        if ($source | str contains $forbidden_nu_version) {
            fail (($file | into string) + " contains invalid Nushell version-field access.")
        }

        # These are repository formatting guards, separate from nu-check.
        # Report the physical line so a passing parser is not mistaken for failure.
        for row in ($source | lines | enumerate) {
            let trimmed = ($row.item | str trim)
            let location = (($file | into string) + ":" + (($row.index + 1) | into string))

            if ($trimmed | str starts-with "and ") {
                fail ($location + " [repository-format] starts a physical line with `and`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "or ") {
                fail ($location + " [repository-format] starts a physical line with `or`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "+ ") {
                fail ($location + " [repository-format] starts a physical line with `+`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "* ") {
                fail ($location + " [repository-format] starts a physical line with `*`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "/ ") {
                fail ($location + " [repository-format] starts a physical line with `/`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "% ") {
                fail ($location + " [repository-format] starts a physical line with `%`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "== ") {
                fail ($location + " [repository-format] starts a physical line with `==`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "!= ") {
                fail ($location + " [repository-format] starts a physical line with `!=`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with "<= ") {
                fail ($location + " [repository-format] starts a physical line with `<=`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }

            if ($trimmed | str starts-with ">= ") {
                fail ($location + " [repository-format] starts a physical line with `>=`; avoid operator-leading continuation lines. This is not a nu-check error.")
            }
        }
    }

    print ("[ok] VERSION = " + $version)
    print ("[ok] SCHEMA_VERSION = " + ($schema | into string))
    print "[ok] Profile manifests are complete."
    print "[ok] Git identity template is valid."
    print ("[ok] Package manifests are complete.")
    print "[ok] Active-source parser validation passed; see the syntax summary for checked/inactive counts."
    print "[ok] Project validation passed."
}
