#!/usr/bin/env nu

const ROOT = path self ..

# Static regression guard for the synchronization/recovery transaction boundary.
# Runtime behavior is tested separately when Nushell/Cargo are available.
def fail [message: string] {
    print --stderr ("[FAIL] " + $message)
    exit 1
}

def require-text [text: string needle: string label: string] {
    if not ($text | str contains $needle) { fail $label }
}

def forbid-text [text: string needle: string label: string] {
    if ($text | str contains $needle) { fail $label }
}

def read-source [relative: string] {
    open --raw ($ROOT | path join $relative)
}

def main [] {
    let phase4_files = [
        "scripts/sync-up.nu"
        "scripts/sync-down.nu"
        "scripts/sync-transport.nu"
        "scripts/rclone-sync.nu"
        "scripts/sync-up-local.nu"
        "scripts/sync-down-local.nu"
        "scripts/sync-transport-main.nu"
        "scripts/backup-local-config.nu"
        "scripts/create-snapshot.nu"
        "scripts/rollback.nu"
        "scripts/write-sync-meta.nu"
        "scripts/update-sync-state.nu"
        "scripts/cloud-wins-build.nu"
        "scripts/cloud-wins-main.nu"
        "scripts/modules/cloud-wins-engine.nu"
        "scripts/modules/sync-provider.nu"
        "scripts/modules/sync-conflict.nu"
        "scripts/modules/conflicts.nu"
        "scripts/modules/sync-local-guard.nu"
        "scripts/auto-sync-worker.nu"
        "scripts/run-control.nu"
    ]

    for relative in $phase4_files {
        let text = (read-source $relative)
        forbid-text $text '$env.LAST_EXIT_CODE' ($relative + " must not use LAST_EXIT_CODE")
        forbid-text $text 'do { ^' ($relative + " must use the shared subprocess layer for captured external commands")
    }

    let transport = (read-source "scripts/sync-transport-main.nu")
    require-text $transport "stable-provider-head $config" "pull must start from a stable provider observation"
    require-text $transport "fetch-revision $config $head $stage" "directory pulls must stage one verified provider snapshot"
    require-text $transport '"--source-root"' "directory pulls must apply from the staged source root"
    require-text $transport "assert-same-head $config $head" "pull must re-check the provider before advancing its baseline"
    require-text $transport "last-transport-error.nuon" "failed transports must retain a recovery diagnostic record"
    require-text $transport "guard-pull-local" "manual pulls must guard live changes before apply"
    require-text $transport "assert-local-unchanged" "manual pulls must recheck live state immediately before apply"
    require-text $transport "--discard-local" "non-interactive local overwrite must retain the explicit pull flag"
    require-text $transport "preserve-provider-recovery" "manual directory-provider push must preserve a changed provider before local-wins capture"
    require-text $transport '$manual' "manual and automatic push policy must remain explicitly separated"

    let local_guard = (read-source "scripts/modules/sync-local-guard.nu")
    require-text $local_guard "state.local_hash" "local pull guard must compare against the saved local baseline"
    require-text $local_guard "print-diff-text" "blocked manual pulls must show the incoming managed-file diff"
    require-text $local_guard "dotctl pull --discard-local" "local overwrite guidance must name the explicit override"
    require-text $local_guard "confirm-private-authority" "manual pull must require an explicit confirmation before replacing changed local state"
    require-text $local_guard "is-terminal --stdin" "interactive pull confirmation must require a real terminal"

    let provider = (read-source "scripts/modules/sync-provider.nu")
    require-text $provider "stable-provider-head" "directory providers must have a settling check"
    require-text $provider '".partial-" + $revision' "local revision publication must stage before commit"
    require-text $provider "verify-tree ($partial | path join \"data\") $entries" "staged revisions must be verified before commit"
    require-text $provider "Workspace rollback verification failed." "workspace replacement must verify automatic rollback"
    require-text $provider "Previous workspace was restored automatically." "workspace replacement must report successful rollback"

    let conflict = (read-source "scripts/modules/sync-conflict.nu")
    require-text $conflict "assert-same-head $config $head" "manual local-wins recovery must recheck the provider around its copy"
    require-text $conflict "copy-workspace $config.data_root $destination" "manual local-wins recovery must preserve the provider payload"
    require-text $conflict "recovery.nuon" "manual local-wins recovery must record self-describing metadata"

    let down = (read-source "scripts/sync-down-local.nu")
    require-text $down "--source-root: string" "sync-down-local must accept an immutable staged source"
    require-text $down "source_root" "sync-down-local must use the selected source root"

    let backup = (read-source "scripts/backup-local-config.nu")
    require-text $backup '".partial-"' "local backups must use hidden partial staging"
    require-text $backup "version: 3" "new local backups must record checksum metadata"
    require-text $backup "Backup file checksum mismatch:" "local restore must verify backup file checksums"
    require-text $backup '".restore-recovery-"' "local restore must capture pre-restore recovery state"
    require-text $backup "restore-from-recovery" "local restore must provide automatic rollback"
    require-text $backup "Backup must be selected by its backup name" "local restore must reject arbitrary backup paths"

    let snapshot = (read-source "scripts/create-snapshot.nu")
    require-text $snapshot "version: 3" "private snapshots must use the hashed v3 format"
    require-text $snapshot "tree_hash" "private snapshots must record a tree hash"
    require-text $snapshot '".partial-"' "private snapshots must stage before commit"

    let rollback = (read-source "scripts/rollback.nu")
    require-text $rollback "Snapshot payload no longer matches its recorded SHA-256 manifest." "rollback must verify snapshot content before restore"
    require-text $rollback "install-workspace $provider $apply_source" "rollback must use transactional workspace replacement"
    require-text $rollback "v1 predates the encrypted vault" "legacy rollback must preserve vault ciphertext"

    let run_control = (read-source "scripts/run-control.nu")
    require-text $run_control "run-command" "run-control rollback must preserve child diagnostics"
    forbid-text $run_control '$env.LAST_EXIT_CODE' "run-control rollback must not infer child status from LAST_EXIT_CODE"

    let meta = (read-source "scripts/write-sync-meta.nu")
    require-text $meta "atomic-record $file" "sync metadata must use an atomic state write"
    forbid-text $meta "save --force $file" "sync metadata must not overwrite state directly"

    let cloud = (read-source "scripts/modules/cloud-wins-engine.nu")
    require-text $cloud "run-command" "cloud-wins engine wrapper must use the shared subprocess contract"
    require-text $cloud "command-failure-message" "cloud-wins failures must preserve child diagnostics"

    for relative in ["scripts/sync-up-local.nu" "scripts/sync-down-local.nu" "scripts/auto-sync-worker.nu"] {
        let text = (read-source $relative)
        require-text $text "Event logging failed:" ($relative + " must treat event logging as diagnostic-only")
    }

    print ("[pass] synchronization/recovery transaction policy (" + (($phase4_files | length) | into string) + " guarded files)")
}
