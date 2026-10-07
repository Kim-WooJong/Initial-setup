#!/usr/bin/env nu
# Local command refresh only. No cloud/source writes or synchronization.
const ROOT = path self ..
const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
const CLOUD = path self ./modules/cloud-wins-config.nu
const MACHINE_CONFIG = path self ./modules/machine-config.nu
const COMMAND_RUNTIME = path self ./modules/command-runtime.nu
use $CORE [nu-home machine-config-path error-message failure-envelope captured-failure]
use $SAFETY [state-root operation-lock lock-release private-directory]
use $CLOUD [load-cloud-config cloud-config-path write-cloud-config]
use $MACHINE_CONFIG [write-machine-config]
use $COMMAND_RUNTIME [generate-command-shim]

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
    let target_dir = ((nu-home) | path join ".config" "nushell" "modules")
    let config_file = (machine-config-path)
    let control_file = (cloud-config-path)

    # Only the generated shim is installed (generation fails on a broken
    # checkout). Previously copied runtime modules are left in place unused.
    let shim = (generate-command-shim $ROOT)
    mut modules = []
    for name in ["dotfiles.nu"] {
        let target = ($target_dir | path join $name)
        if ($target | path exists) and ($target | path type) != "file" {
            error make {msg: ("Installed command-module path is not a regular file: " + ($target | into string))}
        }
        $modules = ($modules | append {
            name: $name
            content: $shim
            target: $target
            temp: (($target | into string) + ".refresh-" + (random uuid))
            had_target: ($target | path exists)
        })
    }

    if not ($config_file | path exists) {
        error make {msg: "No machine configuration exists yet. Run setup first; refresh-commands does not bootstrap a new machine."}
    }
    if ($config_file | path type) != "file" { error make {msg: "Machine configuration must be a regular file."} }
    if ($control_file | path exists) and ($control_file | path type) != "file" {
        error make {msg: "Cloud-wins control state must be a regular file."}
    }

    if $dry_run {
        let updated = (refreshed-control (open --raw $config_file | from nuon))
        print {
            modules: ($modules | each {|item| $item.target })
            tools_root: ($ROOT | into string)
            recovery_snapshots_updated: ($updated != null)
            private_source_changed: false
        }
        return
    }

    let lease = (operation-lock)
    let backup = ((state-root) | path join "command-backups" (random uuid))
    let had_control = ($control_file | path exists)

    let prepared = (try {
        private-directory $backup
        cp $config_file ($backup | path join "config.nuon")
        for item in $modules {
            if $item.had_target {
                let saved = ($backup | path join $item.name)
                mkdir ($saved | path dirname)
                cp $item.target $saved
            }
        }
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
        mkdir $target_dir

        # Prepare and verify every dependency before replacing any installed file.
        for item in $modules {
            mkdir ($item.temp | path dirname)
            $item.content | save --raw $item.temp
            if (open --raw $item.temp | hash sha256) != ($item.content | hash sha256) {
                error make {msg: ("Command module copy verification failed: " + $item.name)}
            }
        }

        # Keep active=true throughout. Snapshot-first permits a safe retry after
        # interruption; deactivate remains fail-closed until refresh completes.
        if $updated != null { write-cloud-config $updated | ignore }
        write-machine-config ($context | upsert tools_root ($ROOT | into string)) | ignore

        for item in $modules {
            mkdir ($item.target | path dirname)
            mv --force $item.temp $item.target
        }
        null
    } catch {|err| failure-envelope $err })
    let failure = (captured-failure $result)

    if $failure != null {
        try {
            write-machine-config (open --raw ($backup | path join "config.nuon") | from nuon) | ignore
            if $had_control { write-cloud-config (open --raw ($backup | path join "cloud-wins.nuon") | from nuon) | ignore }
            for item in $modules {
                let saved = ($backup | path join $item.name)
                if $item.had_target {
                    mkdir ($item.target | path dirname)
                    cp --force $saved $item.target
                } else if ($item.target | path exists) {
                    rm $item.target
                }
            }
        } catch { print --stderr ("[recovery] Local command backup remains at: " + $backup) }
    }

    for item in $modules {
        try { if ($item.temp | path exists) { rm $item.temp } } catch { print --stderr ("[warn] Temporary module copy could not be removed: " + $item.name) }
    }

    let cleanup = (try { lock-release $lease; null } catch {|err| failure-envelope $err })
    if $failure != null { error make {msg: (error-message $failure "Command refresh failed.")} }
    let cleanup_failure = (captured-failure $cleanup)
    if $cleanup_failure != null { error make {msg: (error-message $cleanup_failure "Commands refreshed but operation.lock cleanup failed.")} }

    print ("[ok] Installed the command shim for checkout: " + ($ROOT | into string))
    print "Commands now run from this checkout; later updates apply without refresh unless a command/flag list changes."
    print ("[backup] " + $backup)
    print "Restart Nushell/VS Code terminals. No private source or synchronization baseline was changed."
}
