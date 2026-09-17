#!/usr/bin/env nu
const CLOUD_CONFIG = path self ./modules/cloud-wins-config.nu
use $CLOUD_CONFIG [cloud-mode-active load-cloud-config]
const PROVIDER = path self ./modules/sync-provider.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
use $PROVIDER *
use $SAFETY [atomic-record operation-lock lock-release]
use $CORE [error-message]

def main [action: string = "status" --kind: string = "directory" --remote: string = "" --expected: string = "" --force] {
    if $action == "status" {
        let config = (load-provider)
        let head = (stable-provider-head $config)
        let state = (load-provider-state $config)
        let local_provider_lock = if $config.kind == "directory" { provider-local-lock-path $config } else { null }
        let legacy_lock = if $config.kind == "directory" { legacy-directory-lock-path $config } else { null }
        let export_check = (try {
            if (cloud-mode-active) { error make {msg: "cloud-wins is active: publishing is disabled."} }
            audit-export $config.data_root
            {allowed: true blocker: ""}
        } catch {|err| {allowed: false blocker: (error-message $err "Export audit failed.")} })
        print {
            cloud_wins: (load-cloud-config)
            provider: $config.kind remote: $config.remote current_revision: $head.revision
            baseline_revision: ($state.revision? | default "uninitialized")
            current_tree_hash: $head.tree_hash
            baseline_tree_hash: ($state.tree_hash? | default "uninitialized")
            remote_changed: ($state == null or ($state.revision? | default "") != $head.revision or ($state.tree_hash? | default "") != $head.tree_hash)
            data_root: $config.data_root
            export_allowed: $export_check.allowed
            export_blocker: $export_check.blocker
            workspace_hash: (if $config.kind == "directory" { $head.tree_hash } else { workspace-hash $config.data_root })
            cooperative_store_lock: ($config.kind == "local")
            provider_lock_scope: (match $config.kind {
                "directory" => "operation-lock-only"
                "local" => "shared-filesystem"
                _ => "none"
            })
            provider_lock_path: ""
            legacy_cloud_lock_present: ($legacy_lock != null and ($legacy_lock | path exists))
            atomic_remote_compare_and_swap: false
        }
        if $config.kind == "directory" and not (cloud-mode-active) {
            print "The cloud client controls upload/download. Same-machine serialization uses operation.lock only; cross-machine conflicts use the saved revision/tree fingerprint."
            if $legacy_lock != null and ($legacy_lock | path exists) {
                print ("[legacy] Ignored old cloud lock entry: " + ($legacy_lock | into string))
                print "         v0.12.21 does not probe or delete it automatically."
            }
        }
        if $config.kind == "rclone" { print "Optimistic checks are not a distributed transaction. Concurrent revisions are retained; no automatic revision deletion occurs." }
        return
    }
    if (cloud-mode-active) { error make {msg: "Deactivate cloud-wins before changing/initializing/acknowledging the provider."} }
    let lock = (operation-lock)
    try {
        match $action {
            "configure" => {
                if not ($kind in ["directory" "local" "rclone"]) { error make { msg: "Choose directory, local, or rclone." } }
                if $kind != "directory" and ($remote | is-empty) { error make { msg: "A dedicated --remote is required." } }
                let file = (provider-config-path)
                let existed = ($file | path exists)
                if $existed and not $force { error make { msg: "Provider already configured. Use --force only after reviewing the existing configuration." } }
                let previous = if $existed { open --raw $file | from nuon } else { null }
                atomic-record $file {version: 1 kind: $kind remote: $remote}
                try { load-provider | ignore } catch {|err|
                    if $previous == null { rm --force $file } else { atomic-record $file $previous }
                    error make { msg: (error-message $err "Provider configuration failed.") }
                }
                print "[ok] Provider configured. No data was moved. Run dotbackend init, then dotpull or dotpush."
            }
            "init" => { provider-init (load-provider); print "[ok] Revision store is available. No existing files were deleted." }
            "acknowledge" => {
                if ($expected | is-empty) { error make { msg: "Supply the exact current_revision from dotbackend status using --expected. This explicitly permits a later local-over-remote push." } }
                let config = (load-provider)
                let head = (stable-provider-head $config)
                if $head.revision != $expected { error make { msg: "Remote revision no longer matches the reviewed revision." } }
                assert-same-head $config $head
                record-provider-state $config $head
                print "[acknowledged] Reviewed revision recorded. No files were copied or merged."
            }
            _ => { error make { msg: "Use status, configure, init, or acknowledge." } }
        }
        lock-release $lock
    } catch {|err|
        lock-release $lock
        error make { msg: (error-message $err "Provider configuration failed.") }
    }
}
