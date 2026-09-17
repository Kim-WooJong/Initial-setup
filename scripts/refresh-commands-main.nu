#!/usr/bin/env nu
# Local command refresh only. No cloud/source writes or synchronization.
const ROOT = path self ..
const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
const CLOUD = path self ./modules/cloud-wins-config.nu
use $CORE [nu-home machine-config-path error-message failure-envelope captured-failure]
use $SAFETY [state-root operation-lock lock-release atomic-record private-directory]
use $CLOUD [load-cloud-config cloud-config-path]

# A checkout move is allowed, including retry after an interrupted refresh.
# Any context edit OTHER than tools_root still requires explicit recovery.
def refreshed-control [context: record] {
    let config = (load-cloud-config)
    if $config == null or not $config.active { return null }
    if ($config.previous_context? | describe) !~ '^record' or ($config.activated_context? | describe) !~ '^record' {
        error make {msg: "Active cloud-wins control state is missing its recovery snapshots."}
    }
    let comparable = ($context | reject tools_root)
    if $comparable != ($config.previous_context | reject tools_root) and $comparable != ($config.activated_context | reject tools_root) {
        error make {msg: "CLOUD_CONTEXT_CHANGED: machine settings other than tools_root changed after activation. Refusing to rewrite recovery snapshots."}
    }
    $config
    | upsert previous_context ($config.previous_context | upsert tools_root ($ROOT | into string))
    | upsert activated_context ($config.activated_context | upsert tools_root ($ROOT | into string))
}

def main [--dry-run] {
    let source = ($ROOT | path join "scripts" "modules" "dotfiles.nu")
    let target = ((nu-home) | path join ".config" "nushell" "modules" "dotfiles.nu")
    let config_file = (machine-config-path)
    let control_file = (cloud-config-path)
    if not ($config_file | path exists) {
        error make {msg: "No machine configuration exists yet. Run setup first; refresh-commands does not bootstrap a new machine."}
    }
    if ($source | path type) != "file" { error make {msg: "This checkout is missing its regular dotfiles.nu command module."} }
    if ($target | path exists) and ($target | path type) != "file" {
        error make {msg: "Installed command-module path is not a regular file. Refusing to replace a directory or link."}
    }
    if ($config_file | path type) != "file" { error make {msg: "Machine configuration must be a regular file."} }
    if ($control_file | path exists) and ($control_file | path type) != "file" {
        error make {msg: "Cloud-wins control state must be a regular file."}
    }
    if $dry_run {
        let updated = (refreshed-control (open --raw $config_file | from nuon))
        print {module: $target tools_root: ($ROOT | into string) recovery_snapshots_updated: ($updated != null) private_source_changed: false}
        return
    }
    let lease = (operation-lock)
    let backup = ((state-root) | path join "command-backups" (random uuid))
    let had_target = ($target | path exists)
    let had_control = ($control_file | path exists)
    let temp = (($target | into string) + ".refresh-" + (random uuid))
    # Backup failure must never restore from an incomplete backup.
    let prepared = (try {
        private-directory $backup
        cp $config_file ($backup | path join "config.nuon")
        if $had_target { cp $target ($backup | path join "dotfiles.nu") }
        if $had_control { cp $control_file ($backup | path join "cloud-wins.nuon") }
        null
    } catch {|err| failure-envelope $err })
    let prepare_failure = (captured-failure $prepared)
    if $prepare_failure != null {
        try { lock-release $lease } catch { print --stderr "[warn] Could not release operation.lock." }
        error make {msg: (error-message $prepare_failure "Command backup failed; no existing files were replaced.")}
    }
    let result = (try {
        let context = (open --raw $config_file | from nuon)
        let updated = (refreshed-control $context)
        mkdir ($target | path dirname)
        cp $source $temp
        if (open --raw $temp | hash sha256) != (open --raw $source | hash sha256) {
            error make {msg: "Command module copy verification failed."}
        }
        # Keep active=true throughout. Snapshot-first permits a safe retry after
        # interruption; deactivate remains fail-closed until refresh completes.
        if $updated != null { atomic-record $control_file $updated }
        atomic-record $config_file ($context | upsert tools_root ($ROOT | into string))
        mv --force $temp $target
        null
    } catch {|err| failure-envelope $err })
    let failure = (captured-failure $result)
    if $failure != null {
        try {
            atomic-record $config_file (open --raw ($backup | path join "config.nuon") | from nuon)
            if $had_control { atomic-record $control_file (open --raw ($backup | path join "cloud-wins.nuon") | from nuon) }
            if $had_target { cp --force ($backup | path join "dotfiles.nu") $target } else if ($target | path exists) { rm $target }
        } catch { print --stderr ("[recovery] Local command backup remains at: " + $backup) }
    }
    try { if ($temp | path exists) { rm $temp } } catch { print --stderr "[warn] Temporary module copy could not be removed." }
    let cleanup = (try { lock-release $lease; null } catch {|err| failure-envelope $err })
    if $failure != null { error make {msg: (error-message $failure "Command refresh failed.")} }
    let cleanup_failure = (captured-failure $cleanup)
    if $cleanup_failure != null { error make {msg: (error-message $cleanup_failure "Commands refreshed but operation.lock cleanup failed.")} }
    print ("[ok] Installed local commands from: " + ($ROOT | into string))
    print ("[backup] " + $backup)
    print "Restart Nushell/VS Code terminals. No private source or synchronization baseline was changed."
}
