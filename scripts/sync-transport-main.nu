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
const SUBPROCESS = path self ./modules/subprocess.nu
const LOCAL_GUARD = path self ./modules/sync-local-guard.nu
const CONSOLE = path self ./modules/console.nu
use $PROVIDER *
use $SAFETY [operation-lock lock-release state-root atomic-record]
use $CORE [machine-context error-message failure-envelope captured-failure]
use $SUBPROCESS [run-command command-failure-message]
use $LOCAL_GUARD [guard-pull-local assert-local-unchanged]
use $CONSOLE [print-info print-ok print-warn]

def run-local [name: string args: list] {
    let script = ($ROOT | path join "scripts" $name)
    let result = (run-command $nu.current-exe (["--no-config-file" $script] | append $args) --live)
    if not $result.ok {
        error make {msg: (command-failure-message ("Local sync phase " + $name) $result)}
    }
}

def main [action: string --force --prune --allow-protected --source-only --discard-source --discard-local] {
    if not ($action in ["push" "pull"]) { error make { msg: "Choose push or pull." } }
    if $action == "push" and ($force or $source_only or $discard_source or $discard_local or $allow_protected or $prune) {
        error make { msg: "Push has no force/bypass flag. Review and acknowledge conflicts explicitly." }
    }
    let transport_only = (($env.INITIAL_SETUP_TRANSPORT_ONLY? | default "" | str trim) == "1")
    let suppress_global_state = (($env.INITIAL_SETUP_SUPPRESS_GLOBAL_SYNC_STATE? | default "" | str trim) == "1")
    if $action == "push" and (cloud-mode-active) and not $transport_only {
        error make {msg: "cloud-wins is active: dotpush/export is blocked. The mirror is read-only; deactivate explicitly to restore the previous mode."}
    }
    let lock = (operation-lock)
    mut store_lock = null
    mut transfer_dir: any = null
    let operation_result = (try {
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lock.token
        let config = (load-provider)
        if $action == "pull" and (cloud-mode-active) and not $transport_only {
            let helper = (cloud-engine)
            engine-json $helper ["ready" "--target" $config.data_root "--state-dir" (cloud-state-dir $config.data_root)] | ignore
            if $prune or ((machine-context).sync.prune_extras? | default false) { error make {msg: "Pruning is disabled in cloud-wins mode."} }
            print-info "Cloud-wins is applying the last approved local workspace, not fetching the server. Use dotcloud plan/apply to refresh it."
        }
        provider-probe $config
        $store_lock = (remote-lock $config)
        if $action == "push" {
            let expected = (assert-expected-head $config)
            audit-export $config.data_root
            # Normal push captures live configuration into the private source.
            # Explicit rclone-only transport intentionally publishes the current
            # private source snapshot without mutating the normal provider source.
            if $transport_only {
                print-info "rclone-only: publishing the current private source snapshot without re-capturing live files."
            } else {
                run-local "sync-up-local.nu" []
            }
            if $config.kind != "directory" { assert-same-head $config $expected }
            let head = (publish-revision $config $expected)
            record-provider-state $config $head
            if not $suppress_global_state { run-local "update-sync-state.nu" [] }
            if $config.kind == "directory" {
                print-ok "Local cloud-mirror files updated. Server upload completion is controlled by the cloud client."
            } else { print-ok ("Verified published revision: " + $head.revision) }
        } else {
            let head = (stable-provider-head $config)
            mut apply_source = ($config.data_root | path expand)
            mut fetched_workspace: any = null

            if $transport_only {
                # Explicit rclone-only pull never replaces the normal provider's
                # private source. Apply from a verified temporary revision instead.
                let stage = (new-transfer-dir)
                $transfer_dir = $stage
                $apply_source = (fetch-revision $config $head $stage)
                assert-same-head $config $head
            } else if $config.kind == "directory" {
                # Never apply directly from a cloud-client-mutated directory.
                # Capture one verified local snapshot and apply from that immutable
                # snapshot while the provider HEAD is monitored independently.
                if not $source_only {
                    let stage = (new-transfer-dir)
                    $transfer_dir = $stage
                    $apply_source = (fetch-revision $config $head $stage)
                    assert-same-head $config $head
                }
            } else {
                let state = (load-provider-state $config)
                let workspace = (workspace-hash $config.data_root)
                let known = ($state.source_hash? | default "")
                let has_files = (workspace-manifest $config.data_root | is-not-empty)
                if $has_files and $workspace != $known and $workspace != $head.tree_hash and not $discard_source {
                    error make { msg: "Unpublished workspace changes would be replaced. Review them; --discard-source explicitly permits a backed-up replacement." }
                }
                let stage = (new-transfer-dir)
                $transfer_dir = $stage
                let fetched = (fetch-revision $config $head $stage)
                assert-same-head $config $head
                $fetched_workspace = $fetched
                $apply_source = $fetched
            }

            if $source_only and $fetched_workspace != null {
                install-workspace $config $fetched_workspace
            }

            if not $source_only {
                # Manual pull must not silently roll back edits made after the
                # last successful synchronization. Compare the live-machine
                # fingerprint with sync-state before replacing anything.
                let local_guard = (guard-pull-local $apply_source --discard-local=$discard_local)

                run-local "backup-local-config.nu" ["--label" "before-verified-pull" "--quiet"]
                assert-local-unchanged $local_guard.local_hash

                # Only after the live-machine guard passes may a revision-store
                # pull replace the normal private workspace. A blocked pull leaves
                # both live configuration and the private workspace untouched.
                if $fetched_workspace != null {
                    install-workspace $config $fetched_workspace
                }
                assert-local-unchanged $local_guard.local_hash

                mut args = []
                if $force { $args = ($args | append "--force") }
                if $prune { $args = ($args | append "--prune") }
                if $allow_protected { $args = ($args | append "--allow-protected") }
                if $config.kind == "directory" or $transport_only or $fetched_workspace != null {
                    $args = ($args | append ["--source-root" ($apply_source | into string)])
                }
                run-local "sync-down-local.nu" $args
            }

            # The baseline advances only if the observed provider revision is still
            # the same after all local application/restoration work completed.
            assert-same-head $config $head
            record-provider-state $config $head
            if not $source_only and (not $suppress_global_state or $transport_only) {
                # Explicit rclone-only transport carries a provider-state scope, so
                # update-sync-state writes an isolated local/cloud baseline instead
                # of touching the normal provider's sync-state.nuon.
                run-local "update-sync-state.nu" []
            }

            if $transfer_dir != null and ($transfer_dir | path exists) {
                let cleanup_path = $transfer_dir
                try { rm --recursive --force $cleanup_path; $transfer_dir = null } catch {
                    print-warn ("Verified transfer staging remains at: " + ($cleanup_path | into string))
                }
            }
            print-ok (if $source_only { "Fetched source only; live configuration was not applied." } else { "Private configuration applied; baseline recorded." })
        }
        null
    } catch {|err|
        let message = (error-message $err "Synchronization failed.")
        let rendered = (try { $err | get --optional rendered } catch { null })
        if ($rendered | describe) == "string" and not ($rendered | is-empty) {
            print --stderr "[sync] Original failure:"
            print --stderr $rendered
        } else { print --stderr ("[sync] " + $message) }
        failure-envelope $err
    })
    let operation_failure = (captured-failure $operation_result)

    # Snapshot the error in catch; inspect mutable handles in the outer block.
    # Attempt both releases, including when the remote lock cannot be removed.
    let remote_cleanup_result = (try { release-remote-lock $store_lock; null } catch {|err|
        print-warn ("Remote-lock cleanup failed: " + (error-message $err))
        failure-envelope $err
    })
    let local_cleanup_result = (try { lock-release $lock; null } catch {|err|
        print-warn ("Local-lock cleanup failed: " + (error-message $err))
        failure-envelope $err
    })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)
    if $operation_failure != null {
        mut message = (error-message $operation_failure "Synchronization failed.")
        if $transfer_dir != null and ($transfer_dir | path exists) {
            $message = ($message + (char nl) + "Verified transfer staging retained for recovery: " + ($transfer_dir | into string))
        }
        if $remote_cleanup_error != null {
            $message = ($message + (char nl) + "Remote-lock cleanup also failed: " + (error-message $remote_cleanup_error))
        }
        if $local_cleanup_error != null {
            $message = ($message + (char nl) + "Local-lock cleanup also failed: " + (error-message $local_cleanup_error))
        }
        try {
            atomic-record ((state-root) | path join "last-transport-error.nuon") {
                version: 2 action: $action message: $message
                transfer_dir: (if $transfer_dir == null { "" } else { $transfer_dir | into string })
                at: (date now | format date "%+")
            }
        } catch {
            print-warn "Could not save last-transport-error.nuon; the original synchronization error is unchanged."
        }
        error make {msg: $message}
    }
    if $remote_cleanup_error != null {
        error make {msg: ("Remote-lock cleanup failed: " + (error-message $remote_cleanup_error))}
    }
    if $local_cleanup_error != null {
        error make {msg: ("Local-lock cleanup failed: " + (error-message $local_cleanup_error))}
    }
}
