const CORE = path self ./core.nu
use $CORE [nu-home machine-context]
# ============================================================
# Initial-setup Nushell convenience commands.
# ============================================================

const SUBPROCESS = path self ./subprocess.nu
const CONSOLE = path self ./console.nu
const RCLONE_READINESS = path self ./rclone-readiness.nu
const SYNC_STATE = path self ./sync-state.nu
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [style print-heading print-info print-diff-text print-command print-text print-key-value print-status print-output-text]
use $RCLONE_READINESS [print-rclone-readiness]
use $SYNC_STATE [read-sync-state]

def data-root [] {
    let config = (machine-context)
    $config.data_root | path expand
}

def tools-root [] {
    let config = (machine-context)
    $config.tools_root | path expand
}

def tool-script [name: string] {
    let script = (tools-root | path join "scripts" $name)
    if not ($script | path exists) or ($script | path type) != "file" {
        error make {msg: ("TOOL_SCRIPT_MISSING: " + ($script | into string) + "\nThe checkout may have moved or the archive may be incomplete. Run scripts/refresh-commands.nu from the new complete checkout; do not rerun setup just to repair this path.")}
    }
    $script
}


def completion-item [value: string description: string] {
    {value: $value description: $description}
}

def complete-vault-entries [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "vault.nuon")
    if not ($file | path exists) or ($file | path type) != "file" { return [] }
    try {
        let config = (open --raw $file | from nuon)
        $config.entries?
        | default []
        | where {|entry| not (($entry.name? | default "" | into string | str trim) | is-empty) }
        | each {|entry| completion-item ($entry.name | into string) "Registered vault entry" }
    } catch { [] }
}

def complete-backend-kinds [] {
    [
        (completion-item "directory" "Cloud-synced/local directory provider")
        (completion-item "local" "Local or shared-filesystem revision store")
        (completion-item "rclone" "rclone-backed revision store")
    ]
}

def complete-release-modes [] {
    [
        (completion-item "patch" "Increment the patch version")
        (completion-item "minor" "Increment the minor version")
        (completion-item "major" "Increment the major version")
        (completion-item "set" "Set an explicit version")
    ]
}

def complete-project-kinds [] {
    [
        (completion-item "rust" "Create a Rust project")
        (completion-item "julia" "Create a Julia project")
        (completion-item "python" "Create a Python project")
        (completion-item "generic" "Create a minimal generic project")
    ]
}

def complete-plan-directions [] {
    [
        (completion-item "none" "Inspect desired state without choosing sync direction")
        (completion-item "pull" "Plan private/provider state toward the local machine")
        (completion-item "push" "Plan local/private state toward the provider")
    ]
}

def completed-state-directories [root: path marker: string description: string] {
    if not ($root | path exists) or ($root | path type) != "dir" { return [] }
    try {
        ls $root
        | where type == dir
        | where {|row|
            let name = ($row.name | path basename)
            not ($name | str starts-with ".") and (($row.name | path join $marker) | path exists)
        }
        | sort-by name
        | reverse
        | each {|row| completion-item ($row.name | path basename) $description }
    } catch { [] }
}

def complete-snapshots [] {
    completed-state-directories ((nu-home) | path join ".config" "dotfiles" "snapshots") "snapshot.nuon" "Completed private-source snapshot"
}

def complete-local-backups [] {
    completed-state-directories ((nu-home) | path join ".config" "dotfiles" "local-backups") "manifest.nuon" "Completed local configuration backup"
}

def complete-run-ids [] {
    let root = ((nu-home) | path join ".config" "dotfiles" "runs")
    if not ($root | path exists) or ($root | path type) != "dir" { return [] }
    try {
        ls $root
        | where type == dir
        | where {|row| ($row.name | path join "state.nuon") | path exists }
        | sort-by name
        | reverse
        | each {|row|
            let file = ($row.name | path join "state.nuon")
            let status = (try { open --raw $file | from nuon | get --optional status | default "unknown" } catch { "unknown" })
            completion-item ($row.name | path basename) ("Setup run (" + $status + ")")
        }
    } catch { [] }
}

def complete-plan-files [] {
    let root = ((nu-home) | path join ".config" "dotfiles" "plans")
    if not ($root | path exists) or ($root | path type) != "dir" { return [] }
    try {
        ls $root
        | where type == file
        | where {|row| ($row.name | path basename) != "latest.nuon" and ($row.name | str ends-with ".nuon") }
        | sort-by name
        | reverse
        | each {|row| let plan = (try { open --raw $row.name | from nuon } catch { {} })
            let direction = ($plan.direction? | default "unknown" | into string)
            completion-item ($row.name | into string) ("Saved desired-state plan (" + $direction + ")")
        }
    } catch { [] }
}

def complete-upgrade-ids [] {
    let root = ((nu-home) | path join ".config" "dotfiles" "upgrades")
    if not ($root | path exists) or ($root | path type) != "dir" { return [] }
    try {
        ls $root
        | where type == dir
        | where {|row| ($row.name | path join "upgrade.nuon") | path exists }
        | where {|row|
            let record = (try { open --raw ($row.name | path join "upgrade.nuon") | from nuon } catch { {} })
            let status = ($record.status? | default "unknown" | into string)
            $status in ["applied" "rollback-needed"]
        }
        | sort-by name
        | reverse
        | each {|row| let record = (try { open --raw ($row.name | path join "upgrade.nuon") | from nuon } catch { {} })
            let status = ($record.status? | default "unknown" | into string)
            let from_version = ($record.from_version? | default "?" | into string)
            let to_version = ($record.to_version? | default "?" | into string)
            completion-item ($row.name | path basename) ("Upgrade " + $from_version + " -> " + $to_version + " (" + $status + ")")
        }
    } catch { [] }
}

def cloud-invoke [action: string args: list<string>] {
    let exe = $nu.current-exe
    let script = (tool-script "cloud-wins.nu")
    if $action == "help" {
        ^$exe --no-config-file $script help
        return
    }
    let result = (run-command $exe (["--no-config-file" $script $action] | append $args))
    if not ($result.stderr | str trim | is-empty) { print-output-text ($result.stderr | str trim --right) --stderr }
    if not $result.ok { error make {msg: ((command-failure-message ("dotcloud " + $action) $result) + (char nl) + "No success is assumed.")} }
    let output = ($result.stdout | str trim)
    if ($output | is-empty) { return null }
    $output | from json
}

def fingerprint [kind: string] {
    let script = (tool-script "sync-fingerprint.nu")
    let args = [
        $script
        "--kind"
        $kind
    ]

    let result = (run-command $nu.current-exe (["--no-config-file"] | append $args))
    if not $result.ok {
        error make {
            msg: (command-failure-message ("sync fingerprint: " + $kind) $result)
        }
    }

    $result.stdout | str trim
}

def edit-file [target: path] {
    mkdir ($target | path dirname)

    if not ($target | path exists) {
        "" | save $target
    }

    ^nvim $target
}

# This module is copied into the local Nushell configuration by setup/refresh.
# Put the implementation in a checkout script so later bug fixes are not frozen
# in the copied command module. Default editing never publishes implicitly.
def edit-managed-target [target: path --push --path] {
    if $path { return ($target | path expand --no-symlink) }
    let script = (tool-script "edit-managed.nu")
    if not ($script | path exists) {
        error make {msg: "edit-managed.nu is missing from tools_root. Run scripts/refresh-commands.nu from the updated checkout and restart Nushell."}
    }
    let exe = $nu.current-exe
    mut args = ["--no-config-file" $script ($target | into string)]
    if $push { $args = ($args | append "--push") }
    let result = (run-command $exe $args --interactive)
    if not $result.ok { error make {msg: ((command-failure-message "Managed editor" $result) + (char nl) + "Any local edit is preserved.")} }
}

# Show synchronization state, fingerprints, conflicts, and chezmoi status.
def cmd-status [] {
    let context = (machine-context)
    let state_file = ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict_file = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")

    print-heading "Automatic Sync"
    print-text "heading" "────────────────────────────────"
    print-key-value "Machine       : " $context.machine.name
    print-key-value "Profile       : " $context.machine.profile
    print-key-value "Enabled       : " ($context.sync.enabled | into string)
    print-key-value "Interval      : " (($context.sync.interval_minutes | into string) + " minute(s)")
    print-key-value "Auto push     : " ($context.sync.auto_push | into string)
    print-key-value "Auto pull     : " ($context.sync.auto_pull | into string)
    print-key-value "Conflict mode : " $context.sync.conflict_policy

    if ($state_file | path exists) {
        let state = (read-sync-state $state_file)
        let local_now = (fingerprint "local")
        let cloud_now = (fingerprint "cloud")
        let local_status = (if $local_now == $state.local_hash { style "ok" "clean" } else { style "warn" "changed" })
        let cloud_status = (if $cloud_now == $state.cloud_hash { style "ok" "clean" } else { style "warn" "changed" })

        print-key-value "Last sync     : " ($state.last_sync? | default "unknown")
        print-key-value "Last writer   : " ($state.last_writer? | default "unknown")
        print-key-value "Writer time   : " ($state.last_write_time? | default "unknown")
        print-key-value "Last action   : " ($state.last_action? | default "unknown")
        print-key-value "Local         : " $local_status
        print-key-value "Cloud         : " $cloud_status
    } else {
        print-key-value "Last sync     : " "not initialized"
        print-key-value "Last writer   : " "unknown"
        print-key-value "Local         : " "unknown"
        print-key-value "Cloud         : " "unknown"
    }

    if ($conflict_file | path exists) {
        print-key-value "Conflict      : " (style "error" "YES")
        print-key-value "Details       : " ($conflict_file | into string)
    } else {
        print-key-value "Conflict      : " (style "ok" "none")
    }

    print ""
    print-key-value "Private data  : " (data-root | into string)
    print ""
    print-heading "chezmoi status"

    let args = [
        "--source"
        (data-root | into string)
        "status"
    ]

    ^chezmoi ...$args
}

# Compatibility wrapper. Prefer `dotctl status` for new interactive use.
export def dotstatus [] { cmd-status }

# Show managed-file differences without opening an external pager.
def cmd-diff [] {
    let root = (data-root)
    let args = [
        "--source"
        ($root | into string)
        "--no-pager"
        "--use-builtin-diff"
        "diff"
    ]
    let result = (run-command "chezmoi" $args)
    if not $result.ok {
        error make {msg: (command-failure-message "chezmoi diff" $result)}
    }
    let text = ($result.stdout | str trim --right)
    if ($text | is-empty) {
        print-info "No managed-file differences."
    } else {
        print-diff-text $text
    }
}

# Compatibility wrapper. Prefer `dotctl diff`.
export def dotdiff [] { cmd-diff }

# Publish the current private source through the configured synchronization path.
def cmd-push [] {
    let exe = $nu.current-exe
    ^$exe --no-config-file (tool-script "sync-up.nu") --manual
}

# Compatibility wrapper. Prefer `dotctl push`.
export def dotpush [] { cmd-push }

# Pull private/provider state to this machine with explicit conflict and backup controls.
def cmd-pull [
    --prune # Remove managed targets that no longer exist in the source.
    --force # Allow the pull to apply without the normal conservative stop.
    --backup # Create a named local backup before pulling; also enables the required force path.
    --source-only # Refresh the private source without applying it to local targets.
    --discard-source # Explicitly discard conflicting source-side changes when supported.
    --discard-local # Explicitly discard conflicting local changes when supported.
    --reload # Restart Nushell only after a successful pull.
] {
    let script = (tool-script "sync-down.nu")

    if $backup {
        let backup = (run-command $nu.current-exe ["--no-config-file" (tool-script "backup-local-config.nu") "--label" "before-private-pull"] --live)
        if not $backup.ok {
            error make { msg: ((command-failure-message "Local backup" $backup) + (char nl) + "Private pull was not started.") }
        }
    }

    mut args = [$script "--manual"]

    if $prune {
        $args = ($args | append "--prune")
    }
    if $source_only { $args = ($args | append "--source-only") }
    if $discard_source { $args = ($args | append "--discard-source") }
    if $discard_local { $args = ($args | append "--discard-local") }

    if $force or $backup {
        $args = ($args | append "--force")
    }
    if $reload {
        $args = ($args | append "--reload")
        exec $nu.current-exe --no-config-file ...$args
    }

    ^$nu.current-exe --no-config-file ...$args
}


# Compatibility wrapper. Prefer `dotctl pull`; --backup remains legacy-only.
export def dotpull [
    --prune # Remove managed targets that no longer exist in the source.
    --force # Allow the pull to apply without the normal conservative stop.
    --backup # Compatibility-only extra named backup; also enables the force path.
    --source-only # Refresh the private source without applying it to local targets.
    --discard-source # Explicitly discard conflicting source-side changes when supported.
    --discard-local # Explicitly discard conflicting local changes when supported.
    --reload # Restart Nushell only after a successful pull.
] {
    cmd-pull --prune=$prune --force=$force --backup=$backup --source-only=$source_only --discard-source=$discard_source --discard-local=$discard_local --reload=$reload
}

# Publish only the current private source snapshot to an rclone revision store.
# This does not replace/capture the normal provider source.
export def dotrpush [
    --remote: string = ""
    --save-remote
] {
    let script = (tool-script "rclone-sync.nu")
    mut args = ["--no-config-file" $script "push"]
    if not ($remote | str trim | is-empty) { $args = ($args | append ["--remote" $remote]) }
    if $save_remote { $args = ($args | append "--save-remote") }
    let result = (run-command $nu.current-exe $args --live)
    if not $result.ok { error make {msg: (command-failure-message "dotrpush" $result)} }
}

# Pull/apply from an rclone revision store without replacing the normal
# provider's private source. The transport itself also creates a verified
# pre-apply backup; --backup adds an explicit named local backup first.
export def dotrpull [
    --remote: string = ""
    --save-remote
    --prune
    --force
    --backup
    --discard-local
] {
    if $backup {
        let backup_result = (run-command $nu.current-exe ["--no-config-file" (tool-script "backup-local-config.nu") "--label" "before-rclone-only-pull"] --live)
        if not $backup_result.ok {
            error make {msg: ((command-failure-message "Local backup" $backup_result) + (char nl) + "rclone-only pull was not started.")}
        }
    }
    let script = (tool-script "rclone-sync.nu")
    mut args = ["--no-config-file" $script "pull"]
    if not ($remote | str trim | is-empty) { $args = ($args | append ["--remote" $remote]) }
    if $save_remote { $args = ($args | append "--save-remote") }
    if $prune { $args = ($args | append "--prune") }
    if $force or $backup { $args = ($args | append "--force") }
    if $discard_local { $args = ($args | append "--discard-local") }
    let result = (run-command $nu.current-exe $args --live)
    if not $result.ok { error make {msg: (command-failure-message "dotrpull" $result)} }
}

# Resolve protected-file conflicts using the configured three-way merge policy.
export def dotresolve [
    --policy # Show the effective protected-file conflict policy instead of resolving.
] {
    let script = (tool-script "resolve-config.nu")
    if $policy {
        ^$nu.current-exe --no-config-file $script --policy
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

# Run one automatic synchronization cycle using the configured sync policy.
def cmd-sync [] {
    ^$nu.current-exe --no-config-file (tool-script "auto-sync.nu")
}

# Compatibility wrapper. Prefer `dotctl sync`.
export def dotsync [] { cmd-sync }

# Create a completed private-source snapshot for later rollback.
def cmd-backup [
    --label: string = "manual" # Human-readable snapshot label.
] {
    let args = [
        (tool-script "create-snapshot.nu")
        "--label"
        $label
    ]

    ^$nu.current-exe --no-config-file ...$args
}

# Compatibility wrapper. Prefer `dotctl backup`.
export def dotsnapshot [
    --label: string = "manual" # Human-readable snapshot label.
] {
    cmd-backup --label $label
}

# List snapshots or roll the private source back to a selected completed snapshot.
def cmd-restore [
    --list # List available completed snapshots without changing state.
    --snapshot: string@complete-snapshots = "" # Snapshot ID to restore; Tab lists completed snapshots.
] {
    let script = (tool-script "rollback.nu")

    if $list {
        ^$nu.current-exe --no-config-file $script --list
        return
    }

    if ($snapshot | is-empty) {
        ^$nu.current-exe --no-config-file $script
    } else {
        ^$nu.current-exe --no-config-file $script --snapshot $snapshot
    }
}

# Compatibility wrapper. Prefer `dotctl restore`.
export def dotrollback [
    --list # List available completed snapshots without changing state.
    --snapshot: string@complete-snapshots = "" # Snapshot ID to restore; Tab lists completed snapshots.
] {
    cmd-restore --list=$list --snapshot $snapshot
}

# Show the installed Initial-setup version and schema information.
export def dotversion [] {
    ^$nu.current-exe --no-config-file (tool-script "version-info.nu")
}

# Show repository status for the active Initial-setup checkout.
export def dotrepo [] {
    ^$nu.current-exe --no-config-file (tool-script "repo-status.nu")
}

# Create a validated project release and optionally publish its Git changes.
export def dotrelease [
    mode: string@complete-release-modes # Version action: patch, minor, major, or set.
    requested: string = "" # Explicit version when mode is set.
    --push # Push the resulting release commit/tag after local validation.
    --no-tag # Create the release changes without creating a Git tag.
] {
    let script = (tool-script "release.nu")
    mut args = [$script $mode]

    if not ($requested | is-empty) {
        $args = ($args | append $requested)
    }

    if $push {
        $args = ($args | append "--push")
    }

    if $no_tag {
        $args = ($args | append "--no-tag")
    }

    ^$nu.current-exe --no-config-file ...$args
}

# Clean stale direnv/environment integration created by Initial-setup.
export def dotcleanup [
    --force # Apply cleanup instead of using the conservative/default behavior.
] {
    let script = (tool-script "cleanup-direnv.nu")

    if $force {
        ^$nu.current-exe --no-config-file $script --force
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

# Audit the managed/private source for unsafe or unexpected content.
export def dotaudit [] {
    ^$nu.current-exe --no-config-file (tool-script "audit.nu")
}

# Capture current managed tool and environment state without synchronizing it.
export def dotstate [] {
    ^$nu.current-exe --no-config-file (tool-script "capture-tool-state.nu")
}

# Migrate machine configuration and state schemas as one recoverable transaction.
# --check is read-only and prints the exact transaction plan without changing files.
export def dotmigrate [
    --check # Inspect the complete migration plan without creating backups or changing state.
] {
    let script = (tool-script "migrate-state-transaction.nu")
    let args = if $check { ["--no-config-file" $script "--check"] } else { ["--no-config-file" $script] }
    let result = (run-command $nu.current-exe $args --live)
    if not $result.ok {
        error make {msg: (command-failure-message "Schema migration transaction" $result)}
    }
}

# Show the post-setup checklist for this machine.
export def dotchecklist [] {
    ^$nu.current-exe --no-config-file (tool-script "post-setup-checklist.nu")
}

# Capture current managed tool state and then synchronize it upward.
export def dotcapture [] {
    let capture = (run-command $nu.current-exe ["--no-config-file" (tool-script "capture-tool-state.nu")] --live)
    if not $capture.ok {
        error make {msg: ("CAPTURE_FAILED: synchronization was not started." + (char nl) + (command-failure-message "Capture tool state" $capture))}
    }
    let sync = (run-command $nu.current-exe ["--no-config-file" (tool-script "sync-up.nu")] --live)
    if not $sync.ok {
        error make {msg: ("CAPTURE_SYNC_FAILED: local capture remains, but synchronization did not complete." + (char nl) + (command-failure-message "Capture synchronization" $sync))}
    }
}

# Restore the recorded work/language environment for this machine.
export def dotrestoreenv [] {
    ^$nu.current-exe --no-config-file (tool-script "restore-work-environment.nu")
}

# Diagnose Initial-setup health and optionally repair supported local issues.
def cmd-doctor [
    --fix # Apply supported local repairs after diagnosis.
] {
    let script = (tool-script "doctor.nu")

    if $fix {
        ^$nu.current-exe --no-config-file $script --fix
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

# Compatibility wrapper. Prefer `dotctl doctor`.
export def dotdoctor [--fix # Apply supported local repairs after diagnosis.
] { cmd-doctor --fix=$fix }

# Run safe maintenance for tools and managed configuration; project upgrades remain explicit.
def cmd-update [
    --repo # Show the safe project-upgrade path instead of performing a blind Git pull.
    --tools # Update supported system/CLI tools for the current platform.
    --config # Re-apply supported managed configuration maintenance.
    --all # Run all maintenance categories.
] {
    let script = (tool-script "update.nu")
    mut args = [$script]

    if $repo {
        $args = ($args | append "--repo")
    }

    if $tools {
        $args = ($args | append "--tools")
    }

    if $config {
        $args = ($args | append "--config")
    }

    if $all {
        $args = ($args | append "--all")
    }

    ^$nu.current-exe --no-config-file ...$args
}

# Compatibility wrapper. Prefer `dotctl update`.
export def dotupdate [
    --repo # Show the safe project-upgrade path instead of performing a blind Git pull.
    --tools # Update supported system/CLI tools for the current platform.
    --config # Re-apply supported managed configuration maintenance.
    --all # Run all maintenance categories.
] {
    cmd-update --repo=$repo --tools=$tools --config=$config --all=$all
}

# Generate an Initial-setup environment and synchronization report.
export def dotreport [
    --save # Save the report to the project-defined report location.
] {
    let script = (tool-script "report.nu")

    if $save {
        ^$nu.current-exe --no-config-file $script --save
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

# Show or clear the local synchronization log.
export def dotlog [
    --lines: int = 50 # Number of trailing log lines to display.
    --clear # Clear the local sync log before returning.
] {
    let file = ((nu-home) | path join ".config" "dotfiles" "logs" "sync.log")

    if $clear {
        if ($file | path exists) {
            "" | save --force $file
        }

        print-status "ok" "ok" "Sync log cleared"
        return
    }

    if not ($file | path exists) {
        print-status "info" "info" "No sync log."
        return
    }

    let content = (open --raw $file | lines)
    let count = ($content | length)
    let start = (if $count > $lines { $count - $lines } else { 0 })

    $content
    | skip $start
    | str join (char nl)
    | print
}

# Edit the machine configuration file used by Initial-setup.
def cmd-config [] {
    edit-file ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    print ""
    print-status "info" "info" "Run `nu setup.nu` after changing profile, scheduler interval, or feature switches."
}

# Compatibility wrapper. Prefer `dotctl config`.
export def dotconfig [] { cmd-config }

# Check or apply the supported OneDrive ignore-upload policy.
export def dotonedrive [
    --apply # Apply the policy instead of only checking it.
] {
    let script = (tool-script "setup-onedrive-ignore-upload.nu")

    if $apply {
        ^$nu.current-exe --no-config-file $script
    } else {
        ^$nu.current-exe --no-config-file $script --check
    }
}

# Inspect rclone integration or capture/restore its config through the encrypted vault.
def cmd-config-rclone [
    --capture # Encrypt and capture the active rclone config as the rclone vault entry.
    --restore # Restore the encrypted rclone vault entry to the active local config path.
] {
    if $capture and $restore {
        error make { msg: "Use either --capture or --restore, not both." }
    }

    if $capture {
        ^$nu.current-exe --no-config-file (tool-script "capture-rclone-config.nu") --manual
        return
    }

    if $restore {
        ^$nu.current-exe --no-config-file (tool-script "restore-rclone-config.nu") --manual
        return
    }

    print-rclone-readiness --heading | ignore
    let sync_config = ((nu-home) | path join ".config" "dotfiles" "rclone-sync.nuon")
    if ($sync_config | path exists) {
        let saved = (open --raw $sync_config | from nuon)
        print-key-value "rclone-only sync remote: " ($saved.remote? | default "<invalid>")
    }
}

# Compatibility wrapper. Prefer `dotctl config rclone`.
export def dotrclone [
    --capture # Encrypt and capture the active rclone config.
    --restore # Restore the encrypted rclone config.
] {
    cmd-config-rclone --capture=$capture --restore=$restore
}

# Edit machine-local Nushell overrides stored outside synchronized configuration.
def cmd-config-local [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "local.nu")

    if not ($file | path exists) {
        ^$nu.current-exe --no-config-file (tool-script "setup-machine-local.nu")
    }

    edit-file $file
}

# Compatibility wrapper. Prefer `dotctl config local`.
export def dotlocal [] { cmd-config-local }

# Edit the machine-local autoload file for shell secrets.
def cmd-config-secrets [] {
    let target = ($nu.data-dir | path join "vendor" "autoload" "dotfiles-secrets.nu")
    mkdir ($target | path dirname)
    if not ($target | path exists) { "" | save $target }
    # Holds API tokens; never leave it at the default umask (often 0644).
    # Windows keeps this under the per-user profile ACL.
    if $nu.os-info.name != "windows" {
        let result = (run-command "chmod" ["600" $target])
        if $result.exit_code != 0 {
            print-status "warn" "secrets" "Could not restrict dotfiles-secrets.nu to owner-only permissions."
        }
    }
    edit-file $target
}

# Compatibility wrapper. Prefer `dotctl config secrets`.
export def dotsecrets [] { cmd-config-secrets }

# Check, edit, or apply machine-local Git identity dispatch configuration.
export def dotgitids [
    --edit # Open the Git identity configuration for editing.
    --apply # Apply generated Git identity dispatch configuration after validation.
] {
    let script = (tool-script "setup-git-identities.nu")

    if $edit {
        if $apply {
            ^$nu.current-exe --no-config-file $script --edit --apply
        } else {
            ^$nu.current-exe --no-config-file $script --edit
        }
        return
    }

    if $apply {
        ^$nu.current-exe --no-config-file $script --apply
    } else {
        ^$nu.current-exe --no-config-file $script --check
    }
}

# Check machine-local SSH keys or generate the configured key set.
export def dotsshkeys [
    --generate # Generate missing configured SSH keys instead of only checking them.
] {
    let script = (tool-script "setup-ssh-keys.nu")

    if $generate {
        ^$nu.current-exe --no-config-file $script --generate
    } else {
        ^$nu.current-exe --no-config-file $script --check
    }
}

# Edit the machine-local Git configuration overlay.
export def dotgitlocal [] {
    edit-file ((nu-home) | path join ".gitconfig.local")
}

# Edit the machine-local SSH configuration overlay.
export def dotsshlocal [] {
    edit-file ((nu-home) | path join ".ssh" "config.local")
}

# Edit managed Neovim configuration, optionally publishing the edit.
export def dotnvim [
    --push # Publish the managed edit after the editor exits successfully.
    --path # Print the managed target path instead of editing it.
] {
    edit-managed-target ((nu-home) | path join ".config" "nvim") --push=$push --path=$path
}

# Edit managed Nushell config.nu, optionally publishing the edit.
export def dotnu [
    --push # Publish the managed edit after the editor exits successfully.
    --path # Print the managed target path instead of editing it.
] {
    edit-managed-target ((nu-home) | path join ".config" "nushell" "config.nu") --push=$push --path=$path
}

# Edit managed Nushell env.nu, optionally publishing the edit.
export def dotenv [
    --push # Publish the managed edit after the editor exits successfully.
    --path # Print the managed target path instead of editing it.
] {
    edit-managed-target ((nu-home) | path join ".config" "nushell" "env.nu") --push=$push --path=$path
}

# Edit managed WezTerm configuration, optionally publishing the edit.
export def dotwezterm [
    --push # Publish the managed edit after the editor exits successfully.
    --path # Print the managed target path instead of editing it.
] {
    edit-managed-target ((nu-home) | path join ".config" "wezterm" "wezterm.lua") --push=$push --path=$path
}

# Edit managed Starship configuration, optionally publishing the edit.
export def dotstarship [
    --push # Publish the managed edit after the editor exits successfully.
    --path # Print the managed target path instead of editing it.
] {
    edit-managed-target ((nu-home) | path join ".config" "starship.toml") --push=$push --path=$path
}



# Inspect, resume, or roll back recorded setup transaction runs.
export def dotrun [
    --list # List recorded setup runs.
    --status # Show status for the selected or latest run.
    --logs # Show logs for the selected or latest run.
    --resume # Resume a resumable setup transaction.
    --rollback # Roll back the selected setup transaction where supported.
    --run-id: string@complete-run-ids = "" # Run ID to inspect/operate on; Tab lists recorded runs.
] {
    let script = (tool-script "run-control.nu")
    mut args = [$script]

    if $list { $args = ($args | append "--list") }
    if $status { $args = ($args | append "--status") }
    if $logs { $args = ($args | append "--logs") }
    if $resume { $args = ($args | append "--resume") }
    if $rollback { $args = ($args | append "--rollback") }
    if not ($run_id | is-empty) {
        $args = ($args | append "--run-id")
        $args = ($args | append $run_id)
    }

    ^$nu.current-exe --no-config-file ...$args
}

# Run static project validation for the active Initial-setup checkout.
export def dotvalidate [] {
    ^$nu.current-exe --no-config-file (tool-script "validate-project.nu")
}

# Run project regression tests, optionally including isolated sandbox setup tests.
export def dottest [
    --sandbox # Include isolated setup/integration smoke tests.
    --keep # Preserve the sandbox when supported for debugging.
] {
    let script = (tool-script "self-test.nu")
    mut args = [$script]

    if $sandbox {
        $args = ($args | append "--sandbox")
    }

    if $keep {
        $args = ($args | append "--keep")
    }

    ^$nu.current-exe --no-config-file ...$args
}

# Run preflight checks before applying setup or synchronization changes.
def cmd-preflight [
    --diff # Include managed configuration differences in the preflight report.
] {
    let script = (tool-script "preflight.nu")

    if $diff {
        ^$nu.current-exe --no-config-file $script --diff
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

# Compatibility wrapper. Prefer `dotctl preflight`.
export def dotpreflight [--diff # Include managed configuration differences in the preflight report.
] { cmd-preflight --diff=$diff }

# Back up machine-local configuration that is intentionally excluded from sync.
export def dotlocalbackup [
    --label: string = "manual" # Human-readable label stored with the backup.
] {
    let script = (tool-script "backup-local-config.nu")
    ^$nu.current-exe --no-config-file $script --label $label
}

# List or restore machine-local configuration backups.
export def dotlocalrestore [
    --list # List completed local backups without restoring anything.
    --backup: string@complete-local-backups = "" # Backup ID to restore; defaults to latest when omitted.
    --force # Allow replacement of existing local configuration during restore.
] {
    let script = (tool-script "backup-local-config.nu")

    if $list {
        ^$nu.current-exe --no-config-file $script --list
        return
    }

    mut args = [$script]

    if ($backup | is-empty) {
        $args = ($args | append "--restore-latest")
    } else {
        $args = ($args | append "--restore")
        $args = ($args | append $backup)
    }

    if $force {
        $args = ($args | append "--force")
    }

    ^$nu.current-exe --no-config-file ...$args
}

# Create a new project from the built-in Rust, Julia, Python, or generic templates.
export def newproj [
    kind: string@complete-project-kinds # Project template kind; Tab lists supported kinds.
    name: string # New project directory/package name.
    --path: string = "" # Parent directory; defaults to the configured project location.
] {
    let args = [
        (tool-script "new-project.nu")
        $kind
        $name
        "--path"
        $path
    ]

    ^$nu.current-exe --no-config-file ...$args
}

# Open the managed private-data root in Neovim.
export def dotdata [] {
    ^nvim (data-root)
}

# Open the active Initial-setup tools checkout in Neovim.
export def dottools [] {
    ^nvim (tools-root)
}

# Build a desired-state plan before applying package, toolchain, or sync changes.
export def dotplan [
    --direction: string@complete-plan-directions = "none" # Configuration direction: none, pull, or push.
    --no-save # Print the plan without saving it as the latest plan.
] {
    let script = (tool-script "plan.nu")
    mut args = [$script "--direction" $direction]
    if $no_save { $args = ($args | append "--no-save") }
    ^$nu.current-exe --no-config-file ...$args
}

# Apply a previously reviewed desired-state plan.
export def dotapply [
    --plan: string@complete-plan-files = "" # Saved plan file; defaults to latest when omitted.
    --yes # Apply without the interactive confirmation prompt.
] {
    let script = (tool-script "apply-plan.nu")
    mut args = [$script]
    if not ($plan | is-empty) {
        $args = ($args | append "--plan")
        $args = ($args | append $plan)
    }
    if $yes { $args = ($args | append "--yes") }
    ^$nu.current-exe --no-config-file ...$args
}

# Verify that the machine now matches a saved desired-state plan.
export def dotverify [
    --plan: string@complete-plan-files = "" # Saved plan file; defaults to latest when omitted.
] {
    let script = (tool-script "verify-plan.nu")
    if ($plan | is-empty) { ^$nu.current-exe --no-config-file $script } else { ^$nu.current-exe --no-config-file $script --plan $plan }
}

# Inspect, apply, or update the recorded Rust/Julia/Nushell toolchain state.
export def dottoolchain [
    --status # Show toolchain drift/status (default action).
    --apply # Apply the recorded toolchain requirements.
    --lock-current # Record the current supported toolchain versions into the lock state.
] {
    let script = (tool-script "toolchain-state.nu")
    if $lock_current { ^$nu.current-exe --no-config-file $script --lock-current } else if $apply { ^$nu.current-exe --no-config-file $script --apply } else { ^$nu.current-exe --no-config-file $script --status }
}

# Check or configure the Neovim-based merge tool used for managed conflicts.
export def dotmergecfg [
    --check # Check merge-tool configuration without changing it.
    --force # Reconfigure the merge tool even when configuration already exists.
] {
    let script = (tool-script "setup-merge-tool.nu")
    if $check { ^$nu.current-exe --no-config-file $script --check } else if $force { ^$nu.current-exe --no-config-file $script --force } else { ^$nu.current-exe --no-config-file $script }
}

# Canonical implementations shared by the primary `dotctl` surface and
# compatibility command names. These functions are intentionally private so
# legacy wrappers cannot become implementation dependencies again.
def cmd-vault-status [] {
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") status
}

def cmd-vault-init [--recipient: string = "" --check] {
    mut args = ["init"]
    if not ($recipient | str trim | is-empty) { $args = ($args | append ["--recipient" $recipient]) }
    if $check { $args = ($args | append "--check") }
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ...$args
}

def cmd-backend-status [] {
    ^$nu.current-exe --no-config-file (tool-script "backend-control.nu") status
}

def cmd-cloud-help [] {
    cloud-invoke "help" []
}

# ------------------------------------------------------------
# Primary dotctl command family
# ------------------------------------------------------------
# The legacy dot* commands remain supported for compatibility. New interactive
# use should prefer this smaller `dotctl ...` surface.
export def dotctl [] {
    print-heading "Initial-setup"
    print-text "info" "Routine commands"
    print-command "dotctl status                  # sync/provider summary"
    print-command "dotctl diff                    # managed-file diff"
    print-command "dotctl push                    # local -> private source"
    print-command "dotctl pull                    # private source -> local; verified backup is automatic"
    print-command "dotctl sync                    # run one configured sync cycle"
    print-command "dotctl config                  # edit machine configuration"
    print-command "dotctl doctor                  # diagnose local health"
    print-command "dotctl verify                  # check rclone/rpool match the private source (read-only)"
    print-command "dotctl update                  # guarded maintenance"
    print ""
    print-text "info" "Recovery / configuration"
    print-command "dotctl backup                  # create a private-source snapshot"
    print-command "dotctl restore --list          # list/restore snapshots"
    print-command "dotctl preflight --diff        # review before changing state"
    print-command "dotctl config rclone           # encrypted rclone readiness/capture/restore"
    print-command "dotctl config rpool            # portable rpool configuration"
    print-command "dotctl config wireguard        # encrypted native WireGuard synchronization"
    print-command "dotctl config vault            # encrypted-vault status"
    print ""
    print-text "warn" "Legacy dot* commands remain supported for advanced/compatibility workflows."
    print-text "muted" "See docs/wiki/Command-Reference.md for the complete command inventory."
}

# Show synchronization and chezmoi state.
export def "dotctl status" [] { cmd-status }

# Show the managed-file diff.
export def "dotctl diff" [] { cmd-diff }

# Publish local configuration, including an encrypted rclone.conf when enabled.
export def "dotctl push" [] { cmd-push }

# Pull private configuration, including authenticated rclone.conf restore.
# A verified local backup is created automatically by the pull transport before
# any live configuration is changed. The legacy `dotpull --backup` option stays
# available only as a compatibility path for workflows that want an extra named
# backup in addition to the built-in verified backup.
export def "dotctl pull" [
    --prune # Remove managed extras when the configured pull policy allows it.
    --force # Advanced chezmoi apply override; local/protected-file guards still apply.
    --source-only # Refresh the private source without applying it to live configuration.
    --discard-source # Explicitly permit backed-up replacement of conflicting source-side changes.
    --discard-local # Explicitly permit replacement of conflicting local changes.
    --reload # Restart Nushell only after a successful pull.
] {
    cmd-pull --prune=$prune --force=$force --source-only=$source_only --discard-source=$discard_source --discard-local=$discard_local --reload=$reload
}

# Run one synchronization cycle according to the configured policy.
export def "dotctl sync" [] { cmd-sync }

# Create a private-source snapshot.
export def "dotctl backup" [--label: string = "manual"] { cmd-backup --label $label }

# List or restore private-source snapshots.
export def "dotctl restore" [--list --snapshot: string@complete-snapshots = ""] {
    cmd-restore --list=$list --snapshot $snapshot
}

# Edit the machine configuration.
export def "dotctl config" [] { cmd-config }

# Edit machine-local Nushell overrides.
export def "dotctl config local" [] { cmd-config-local }

# Edit machine-local shell secrets.
export def "dotctl config secrets" [] { cmd-config-secrets }

# Inspect or manually synchronize the encrypted rclone configuration.
export def "dotctl config rclone" [
    --capture # Encrypt/capture the active rclone config using the same path as dotpush.
    --restore # Authenticate/restore the encrypted rclone config using the same path as dotpull.
] {
    if $capture and $restore {
        error make { msg: "Use either --capture or --restore, not both." }
    }
    cmd-config-rclone --capture=$capture --restore=$restore
}

# Inspect or manually synchronize rpool's portable configuration and age-encrypted crypt passwords.
export def "dotctl config rpool" [
    --capture # Export the current portable rpool configuration into the private source.
    --restore # Import the synchronized portable rpool configuration on this machine.
    --dry-run # Validate/show the import without changing rpool configuration.
] {
    let script = (tool-script "rpool-config-sync.nu")
    mut args = [$script]
    if $capture { $args = ($args | append "--capture") }
    if $restore { $args = ($args | append "--restore") }
    if $dry_run { $args = ($args | append "--dry-run") }
    ^$nu.current-exe --no-config-file ...$args
}

# Show encrypted-vault status.
export def "dotctl config vault" [] { cmd-vault-status }

# Explicit device enrollment is required before native WireGuard access.
export def "dotctl config wireguard" [--capture --restore --check] {
    mut args = ["--no-config-file" (tool-script "wireguard-config-sync.nu")]
    if $capture { $args = ($args | append "--capture") }
    if $restore { $args = ($args | append "--restore") }
    if $check { $args = ($args | append "--check") }
    ^$nu.current-exe ...$args
}

# Initialize the encrypted vault used by automatic rclone sync.
export def "dotctl config vault init" [--recipient: string = "" --check] {
    cmd-vault-init --recipient $recipient --check=$check
}

# Run preflight checks before synchronization/setup changes.
export def "dotctl preflight" [--diff] { cmd-preflight --diff=$diff }

# Diagnose Initial-setup health.
export def "dotctl doctor" [--fix] { cmd-doctor --fix=$fix }

# Check that this machine's rclone.conf and rpool settings match the private
# source (read-only; decrypts in memory, prints no secret values).
export def "dotctl verify" [--json] {
    let args = if $json { ["--json"] } else { [] }
    ^$nu.current-exe --no-config-file (tool-script "verify-sync.nu") ...$args
}

# Run safe maintenance.
export def "dotctl update" [--repo --tools --config --all] {
    cmd-update --repo=$repo --tools=$tools --config=$config --all=$all
}

# Vault status. Native subcommands below provide Nushell-owned Tab completion.
export def dotvault [] { cmd-vault-status }

# Show encrypted-vault status and registered entries.
export def "dotvault status" [] { cmd-vault-status }

# Initialize the local age-backed vault policy.
export def "dotvault init" [--recipient: string = "" --check] {
    cmd-vault-init --recipient $recipient --check=$check
}

# Make this machine's age identity the only vault recipient after a key
# mismatch (preview unless --execute); then dotpush re-encrypts the copies.
export def "dotvault rekey" [--execute] {
    let args = if $execute { ["rekey" "--execute"] } else { ["rekey"] }
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ...$args
}

# Open the age vault identity in an editor to set it to another machine's
# shared private key. Local only; owner-only permissions; no secret is printed.
export def "dotvault edit-identity" [--editor: string = "nvim" --editor-argument: string = ""] {
    let script = (tool-script "edit-identity.nu")
    mut args = ["--no-config-file" $script "--editor" $editor]
    if not ($editor_argument | str trim | is-empty) { $args = ($args | append ["--editor-argument" $editor_argument]) }
    let result = (run-command $nu.current-exe $args --live)
    if not $result.ok { error make {msg: ((command-failure-message "Vault identity editor" $result) + (char nl) + "Any saved identity edit is preserved.")} }
}

# Encrypt a registered local secret into the private source.
export def "dotvault capture" [name: string@complete-vault-entries] {
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") capture $name
}

# Restore a registered encrypted secret to its machine-local destination.
export def "dotvault restore" [name: string@complete-vault-entries --force] {
    mut args = ["restore" $name]
    if $force { $args = ($args | append "--force") }
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ...$args
}

# Install or update the RPool binary from its public GitHub releases.
export def "rpool-install" [--version: string = "" --check] {
    mut args = []
    if not ($version | str trim | is-empty) { $args = ($args | append ["--version" $version]) }
    if $check { $args = ($args | append "--check") }
    ^$nu.current-exe --no-config-file (tool-script "rpool-install.nu") ...$args
}

# Enroll / unenroll / list SSH private keys that are age-encrypted and synced.
export def "dotvault ssh-key add" [name: string] {
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ssh-key-add $name
}

export def "dotvault ssh-key add-all" [] {
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ssh-key-add-all
}

export def "dotvault ssh-key remove" [name: string] {
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ssh-key-remove $name
}

export def "dotvault ssh-key list" [] {
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ssh-key-list
}

# Migrate the legacy plaintext rclone config into the encrypted vault.
export def "dotvault migrate-rclone" [--remove-legacy] {
    mut args = ["migrate-rclone"]
    if $remove_legacy { $args = ($args | append "--remove-legacy") }
    ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") ...$args
}

# Show the active synchronization backend status.
export def dotbackend [] { cmd-backend-status }

# Show provider revision, baseline, lock, and export status.
export def "dotbackend status" [] { cmd-backend-status }

# Configure the synchronization provider without moving data.
export def "dotbackend configure" [--kind: string@complete-backend-kinds = "directory" --remote: string = "" --force] {
    mut args = ["configure" "--kind" $kind]
    if not ($remote | str trim | is-empty) { $args = ($args | append ["--remote" $remote]) }
    if $force { $args = ($args | append "--force") }
    ^$nu.current-exe --no-config-file (tool-script "backend-control.nu") ...$args
}

# Initialize the configured revision store.
export def "dotbackend init" [] {
    ^$nu.current-exe --no-config-file (tool-script "backend-control.nu") init
}

# Record a reviewed provider revision as the expected baseline.
export def "dotbackend acknowledge" [--expected: string = ""] {
    mut args = ["acknowledge"]
    if not ($expected | str trim | is-empty) { $args = ($args | append ["--expected" $expected]) }
    ^$nu.current-exe --no-config-file (tool-script "backend-control.nu") ...$args
}

# Safely validate, apply, list, or roll back Initial-setup releases.
export def dotupgrade [
    --from: string = "" # Extracted candidate release directory for artifact-based upgrades.
    --manifest-sha256: string = "" # Trusted SHA-256 of the candidate release manifest.
    --ref: string = "" # Remote Git tag/branch/ref to fetch for a Git-based upgrade.
    --commit: string = "" # Trusted full 40-character commit expected for --ref.
    --yes # Promote the validated candidate or confirm an explicit rollback.
    --list # List recorded upgrade history.
    --rollback: string@complete-upgrade-ids = "" # Upgrade ID to roll back; Tab lists recorded upgrades.
] {
    let script = (tool-script "safe-upgrade.nu")
    mut args = [$script]
    if not ($from | str trim | is-empty) { $args = ($args | append ["--from" $from]) }
    if not ($manifest_sha256 | str trim | is-empty) { $args = ($args | append ["--manifest-sha256" $manifest_sha256]) }
    if not ($ref | str trim | is-empty) { $args = ($args | append ["--ref" $ref]) }
    if not ($commit | str trim | is-empty) { $args = ($args | append ["--commit" $commit]) }
    if $yes { $args = ($args | append "--yes") }
    if $list { $args = ($args | append "--list") }
    if not ($rollback | str trim | is-empty) { $args = ($args | append ["--rollback" $rollback]) }
    ^$nu.current-exe --no-config-file ...$args
}

# Run isolated security regressions for vault, provider, upgrade, and transport safeguards.
export def dotsecuritytest [
    --require-age # Fail instead of skipping encrypted-vault tests when age tooling is unavailable.
    --require-rclone # Fail instead of skipping rclone transport tests when rclone is unavailable.
    --keep # Preserve the temporary security-test sandbox for inspection.
] {
    let script = (tool-script "security-self-test.nu")
    mut args = [$script]
    if $require_age { $args = ($args | append "--require-age") }
    if $require_rclone { $args = ($args | append "--require-rclone") }
    if $keep { $args = ($args | append "--keep") }
    ^$nu.current-exe --no-config-file ...$args
}

# Verify/update the managed runtime without synchronizing settings.
export def dotnuupdate [--check --shell] {
    if $check and $shell { error make {msg: "Choose --check or --shell."} }
    let exe = $nu.current-exe
    let script = (tool-script "update-nushell.nu")
    if $check { ^$exe --no-config-file $script --check } else if $shell { ^$exe --no-config-file $script --shell } else { ^$exe --no-config-file $script }
}

# Show Cloud-wins usage. Native subcommands provide Nushell-owned Tab completion.
export def dotcloud [] { cmd-cloud-help }

# Show Cloud-wins command usage.
export def "dotcloud help" [] { cmd-cloud-help }

# Configure a read-only mirror source and local workspace target.
export def "dotcloud configure" [--source: string = "" --target: string = "" --execute] {
    mut args = []
    if not ($source | str trim | is-empty) { $args = ($args | append ["--source" $source]) }
    if not ($target | str trim | is-empty) { $args = ($args | append ["--target" $target]) }
    if $execute { $args = ($args | append "--execute") }
    cloud-invoke "configure" $args
}

# Probe the configured cloud mirror for a stable readable state.
export def "dotcloud probe" [--source: string = "" --target: string = "" --settle-ms: int = 1500] {
    mut args = ["--settle-ms" ($settle_ms | into string)]
    if not ($source | str trim | is-empty) { $args = ($args | append ["--source" $source]) }
    if not ($target | str trim | is-empty) { $args = ($args | append ["--target" $target]) }
    cloud-invoke "probe" $args
}

# Create a local Cloud-wins change plan.
export def "dotcloud plan" [--source: string = "" --target: string = "" --settle-ms: int = 1500] {
    mut args = ["--settle-ms" ($settle_ms | into string)]
    if not ($source | str trim | is-empty) { $args = ($args | append ["--source" $source]) }
    if not ($target | str trim | is-empty) { $args = ($args | append ["--target" $target]) }
    cloud-invoke "plan" $args
}

# Verify the configured source and target without applying changes.
export def "dotcloud verify" [--source: string = "" --target: string = "" --settle-ms: int = 1500] {
    mut args = ["--settle-ms" ($settle_ms | into string)]
    if not ($source | str trim | is-empty) { $args = ($args | append ["--source" $source]) }
    if not ($target | str trim | is-empty) { $args = ($args | append ["--target" $target]) }
    cloud-invoke "verify" $args
}

# Show Cloud-wins control and local engine status.
export def "dotcloud status" [--target: string = ""] {
    mut args = []
    if not ($target | str trim | is-empty) { $args = ($args | append ["--target" $target]) }
    cloud-invoke "status" $args
}

# Apply a reviewed Cloud-wins plan.
export def "dotcloud apply" [--plan: string = "" --execute --confirm: string = ""] {
    mut args = []
    if not ($plan | str trim | is-empty) { $args = ($args | append ["--plan" $plan]) }
    if $execute { $args = ($args | append "--execute") }
    if not ($confirm | str trim | is-empty) { $args = ($args | append ["--confirm" $confirm]) }
    cloud-invoke "apply" $args
}

# Activate the approved local Cloud-wins workspace.
export def "dotcloud activate" [--execute --confirm: string = "" --settle-ms: int = 1500] {
    mut args = ["--settle-ms" ($settle_ms | into string)]
    if $execute { $args = ($args | append "--execute") }
    if not ($confirm | str trim | is-empty) { $args = ($args | append ["--confirm" $confirm]) }
    cloud-invoke "activate" $args
}

# Roll back one Cloud-wins apply run using local recovery state.
export def "dotcloud rollback" [--run: string = "" --target: string = "" --execute --confirm: string = ""] {
    mut args = []
    if not ($run | str trim | is-empty) { $args = ($args | append ["--run" $run]) }
    if not ($target | str trim | is-empty) { $args = ($args | append ["--target" $target]) }
    if $execute { $args = ($args | append "--execute") }
    if not ($confirm | str trim | is-empty) { $args = ($args | append ["--confirm" $confirm]) }
    cloud-invoke "rollback" $args
}

# Deactivate Cloud-wins and restore the previous machine/provider policy.
export def "dotcloud deactivate" [--execute --confirm: string = ""] {
    mut args = []
    if $execute { $args = ($args | append "--execute") }
    if not ($confirm | str trim | is-empty) { $args = ($args | append ["--confirm" $confirm]) }
    cloud-invoke "deactivate" $args
}
