#!/usr/bin/env nu
# All normal manual/automatic pushes and pulls pass through this boundary.
const ROOT = path self ..
const PROVIDER = path self ./modules/sync-provider.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
use $PROVIDER *
use $SAFETY [operation-lock lock-release state-root atomic-record]
use $CORE [error-message failure-envelope captured-failure]

def run-local [name: string args: list] {
    let script = ($ROOT | path join "scripts" $name)
    ^nu --no-config-file $script ...$args
    if ($env.LAST_EXIT_CODE | default 1) != 0 { error make { msg: ("Local sync phase failed: " + $name) } }
}

def main [action: string --force --prune --allow-protected --source-only --discard-source] {
    if not ($action in ["push" "pull"]) { error make { msg: "Choose push or pull." } }
    if $action == "push" and ($force or $source_only or $discard_source or $allow_protected or $prune) {
        error make { msg: "Push has no force/bypass flag. Review and acknowledge conflicts explicitly." }
    }
    let lock = (operation-lock)
    mut store_lock = null
    let operation_result = (try {
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lock.token
        let config = (load-provider)
        provider-probe $config
        $store_lock = (remote-lock $config)
        if $action == "push" {
            let expected = (assert-expected-head $config)
            audit-export $config.data_root
            # Check the baseline BEFORE re-add/capture changes any source file.
            run-local "sync-up-local.nu" []
            if $config.kind != "directory" { assert-same-head $config $expected }
            let head = (publish-revision $config $expected)
            record-provider-state $config $head
            run-local "update-sync-state.nu" []
            if $config.kind == "directory" {
                print "[ok] Local cloud-mirror files updated. Server upload completion is controlled by the cloud client."
            } else { print ("[ok] Verified published revision: " + $head.revision) }
        } else {
            let head = (provider-head $config)
            if $config.kind != "directory" {
                let state = (load-provider-state $config)
                let workspace = (workspace-hash $config.data_root)
                let known = ($state.source_hash? | default "")
                let has_files = (workspace-manifest $config.data_root | is-not-empty)
                if $has_files and $workspace != $known and $workspace != $head.tree_hash and not $discard_source {
                    error make { msg: "Unpublished workspace changes would be replaced. Review them; --discard-source explicitly permits a backed-up replacement." }
                }
                let stage = (new-transfer-dir)
                let fetched = (fetch-revision $config $head $stage)
                assert-same-head $config $head
                install-workspace $config $fetched
                rm --recursive --force $stage
            }
            if not $source_only {
                run-local "backup-local-config.nu" ["--label" "before-verified-pull" "--quiet"]
                mut args = []
                if $force { $args = ($args | append "--force") }
                if $prune { $args = ($args | append "--prune") }
                if $allow_protected { $args = ($args | append "--allow-protected") }
                run-local "sync-down-local.nu" $args
            }
            assert-same-head $config $head
            record-provider-state $config $head
            if not $source_only { run-local "update-sync-state.nu" [] }
            print ("[ok] " + (if $source_only { "Fetched source only; live configuration was not applied." } else { "Private configuration applied; baseline recorded." }))
        }
        null
    } catch {|err| failure-envelope $err })
    let operation_failure = (captured-failure $operation_result)

    # Snapshot the error in catch; inspect mutable handles in the outer block.
    # Attempt both releases, including when the remote lock cannot be removed.
    let remote_cleanup_result = (try { release-remote-lock $store_lock; null } catch {|err| failure-envelope $err })
    let local_cleanup_result = (try { lock-release $lock; null } catch {|err| failure-envelope $err })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)
    if $operation_failure != null {
        let message = (error-message $operation_failure "Synchronization failed.")
        # Error reports contain no command arguments, credentials or file contents.
        atomic-record ((state-root) | path join "last-transport-error.nuon") {version: 1 action: $action message: $message at: (date now | format date "%+")}
        error make { msg: $message }
    }
    if $remote_cleanup_error != null { error make {msg: (error-message $remote_cleanup_error "Remote-lock cleanup failed.")} }
    if $local_cleanup_error != null { error make {msg: (error-message $local_cleanup_error "Local-lock cleanup failed.")} }
}
