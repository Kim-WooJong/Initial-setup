#!/usr/bin/env nu
const VAULT = path self ./modules/vault.nu
const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
use $VAULT *
use $CORE [error-message failure-envelope captured-failure]
use $SAFETY [operation-lock lock-release]
const PROVIDER = path self ./modules/sync-provider.nu
use $PROVIDER [load-provider assert-expected-head provider-head record-provider-state remote-lock release-remote-lock]

def main [action: string = "status" name: string = "" --force --remove-legacy --recipient: string = ""] {
    if $action == "status" {
        if not (vault-configured) { print "Vault: not configured (no plaintext capture permitted)."; return }
        let config = (load-vault)
        print ($config.entries | each {|entry|
            { name: $entry.name encrypted_copy: ((ciphertext-path $entry.name) | path exists) auto_capture: ($entry.auto_capture? | default false) auto_restore: ($entry.auto_restore? | default false) }
        })
        print "No secret values are displayed."
        return
    }
    let lock = (operation-lock)
    mut store_lock = null
    let operation_result = (try {
        let provider = (load-provider)
        if $action in ["capture" "migrate-rclone"] {
            $store_lock = (remote-lock $provider)
            if $provider.kind == "directory" { assert-expected-head $provider | ignore }
        }
        match $action {
            "init" => { initialize-vault $recipient }
            "capture" => { capture-secret $name }
            "restore" => { restore-secret $name $force }
            "migrate-rclone" => { migrate-rclone-secret $remove_legacy }
            _ => { error make { msg: "Use: status, init, capture NAME, restore NAME, migrate-rclone." } }
        }
        if $action in ["capture" "migrate-rclone"] and $provider.kind == "directory" {
            record-provider-state $provider (provider-head $provider)
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
    if $operation_failure != null { error make { msg: (error-message $operation_failure "Vault operation failed.") } }
    if $remote_cleanup_error != null { error make {msg: (error-message $remote_cleanup_error "Remote-lock cleanup failed.")} }
    if $local_cleanup_error != null { error make {msg: (error-message $local_cleanup_error "Local-lock cleanup failed.")} }
}
