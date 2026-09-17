#!/usr/bin/env nu
# All normal manual/automatic pushes and pulls pass through this boundary.
const CLOUD_CONFIG = path self ./modules/cloud-wins-config.nu
const CLOUD_ENGINE = path self ./modules/cloud-wins-engine.nu
use $CLOUD_CONFIG [cloud-mode-active cloud-state-dir]
use $CLOUD_ENGINE [cloud-engine engine-json]
const ROOT = path self ..
const PROVIDER = path self ./modules/sync-provider.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
use $PROVIDER *
use $SAFETY [operation-lock lock-release state-root atomic-record]
use $CORE [machine-context error-message failure-envelope captured-failure]

def run-local [name: string args: list] {
    let script = ($ROOT | path join "scripts" $name)
    let exe = $nu.current-exe
    ^$exe --no-config-file $script ...$args
    if ($env.LAST_EXIT_CODE | default 1) != 0 { error make { msg: ("Local sync phase failed: " + $name) } }
}

def main [action: string --force --prune --allow-protected --source-only --discard-source] {
    if not ($action in ["push" "pull"]) { error make { msg: "Choose push or pull." } }
    if $action == "push" and ($force or $source_only or $discard_source or $allow_protected or $prune) {
        error make { msg: "Push has no force/bypass flag. Review and acknowledge conflicts explicitly." }
    }
    if $action == "push" and (cloud-mode-active) {
        error make {msg: "cloud-wins is active: dotpush/export is blocked. The mirror is read-only; deactivate explicitly to restore the previous mode."}
    }
    let lock = (operation-lock)
    mut store_lock = null
    let operation_result = (try {
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lock.token
        let config = (load-provider)
        if $action == "pull" and (cloud-mode-active) {
            let helper = (cloud-engine)
            engine-json $helper ["ready" "--target" $config.data_root "--state-dir" (cloud-state-dir $config.data_root)] | ignore
            if $prune or ((machine-context).sync.prune_extras? | default false) { error make {msg: "Pruning is disabled in cloud-wins mode."} }
            print "[cloud-wins] Applying the last approved local workspace, not fetching the server. Use dotcloud plan/apply to refresh it."
        }
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
    } catch {|err|
        let message = (error-message $err "Synchronization failed.")
        let rendered = (try { $err | get --optional rendered } catch { null })
        if ($rendered | describe) == "string" and not ($rendered | is-empty) {
            print --stderr "[sync] Original failure:"
            print --stderr $rendered
        } else { print --stderr ("[sync] " + $message) }
        failure-envelope {msg: $message}
    })
    let operation_failure = (captured-failure $operation_result)

    # Snapshot the error in catch; inspect mutable handles in the outer block.
    # Attempt both releases, including when the remote lock cannot be removed.
    let remote_cleanup_result = (try { release-remote-lock $store_lock; null } catch {|err|
        print --stderr ("[warn] Remote-lock cleanup failed: " + (error-message $err))
        failure-envelope true
    })
    let local_cleanup_result = (try { lock-release $lock; null } catch {|err|
        print --stderr ("[warn] Local-lock cleanup failed: " + (error-message $err))
        failure-envelope true
    })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)
    if $operation_failure != null {
        let message = (error-message $operation_failure "Synchronization failed.")
        try {
            atomic-record ((state-root) | path join "last-transport-error.nuon") {
                version: 1 action: $action message: $message
                at: (date now | format date "%+")
            }
        } catch {
            print --stderr "[warn] Could not save last-transport-error.nuon; the original synchronization error is unchanged."
        }
        error make {msg: $message}
    }
    if $remote_cleanup_error != null {
        error make {msg: "Remote-lock cleanup failed. The original cleanup diagnostic was printed above."}
    }
    if $local_cleanup_error != null {
        error make {msg: "Local-lock cleanup failed. The original cleanup diagnostic was printed above."}
    }
}
