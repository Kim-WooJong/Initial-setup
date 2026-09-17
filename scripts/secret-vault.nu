#!/usr/bin/env nu
const VAULT = path self ./modules/vault.nu
const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
use $VAULT *
use $CORE [error-message failure-envelope captured-failure]
use $SAFETY [operation-lock lock-release]
const PROVIDER = path self ./modules/sync-provider.nu
use $PROVIDER [load-provider assert-expected-head provider-head record-provider-state remote-lock release-remote-lock]

# Never print an entire error record: raw/debug/details can be verbose or contain
# unrelated values. Prefer the original rendered location, with a text fallback.
def show-vault-failure [err: any context: string] {
    print --stderr ("[vault] " + $context)
    let rendered = (try { $err | get --optional rendered } catch { null })
    if ($rendered | describe) == "string" and not ($rendered | is-empty) {
        print --stderr $rendered
    } else { print --stderr (error-message $err "Vault operation failed.") }
}

def main [action: string = "status" name: string = "" --force --remove-legacy --recipient: string = "" --check] {
    if not ($action in ["status" "init" "capture" "restore" "migrate-rclone"]) {
        error make {msg: "Use: status, init [--check], capture NAME, restore NAME, migrate-rclone."}
    }
    if $check and $action != "init" { error make {msg: "--check is supported only by dotvault init."} }
    if $action == "status" {
        if not (vault-configured) { print "Vault: not configured (no plaintext capture permitted)."; return }
        let config = (load-vault)
        print ($config.entries | each {|entry|
            {name: $entry.name encrypted_copy: ((ciphertext-path $entry.name) | path exists) auto_capture: ($entry.auto_capture? | default false) auto_restore: ($entry.auto_restore? | default false)}
        })
        print "No secret values are displayed."
        return
    }
    # Read-only init preflight does not acquire any lock or load the provider.
    if $action == "init" and $check { initialize-vault $recipient --check; return }

    let lock = (operation-lock)
    mut store_lock = null
    let operation_result = (try {
        if $action == "init" {
            initialize-vault $recipient
        } else if $action == "restore" {
            restore-secret $name $force
        } else {
            # Only capture/migration write to the private source. These paths
            # retain the provider lock and revision check; init never resets it.
            let provider = (load-provider)
            $store_lock = (remote-lock $provider)
            if $provider.kind == "directory" { assert-expected-head $provider | ignore }
            if $action == "capture" { capture-secret $name } else { migrate-rclone-secret $remove_legacy }
            if $provider.kind == "directory" { record-provider-state $provider (provider-head $provider) }
        }
        null
    } catch {|err|
        show-vault-failure $err ("Original failure during " + $action + ":")
        failure-envelope true
    })
    let operation_failure = (captured-failure $operation_result)

    # Always attempt BOTH releases before reporting failure. No timeout-based
    # unlock, automatic credential deletion, or success-on-error fallback.
    let remote_cleanup_result = (try { release-remote-lock $store_lock; null } catch {|err|
        show-vault-failure $err "Remote-lock cleanup also failed:"
        failure-envelope true
    })
    let local_cleanup_result = (try { lock-release $lock; null } catch {|err|
        show-vault-failure $err "Local-lock cleanup also failed:"
        failure-envelope true
    })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)
    # Diagnostics were emitted at the catch site. Do not manufacture a new error
    # at the footer and relocate the blame away from the original failure.
    if $operation_failure != null or $remote_cleanup_error != null or $local_cleanup_error != null { exit 1 }
}
