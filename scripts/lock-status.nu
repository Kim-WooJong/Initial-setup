#!/usr/bin/env nu
# Read-only by default. --probe exclusively creates a uniquely named test file,
# verifies the token, and releases ONLY that test lock. It never clears a lock.
const SAFETY = path self ./modules/safety.nu
const PROVIDER = path self ./modules/sync-provider.nu
const CORE = path self ./modules/core.nu
use $SAFETY [state-root lock-acquire lock-release]
use $PROVIDER [load-provider provider-local-lock-path legacy-directory-lock-path]
use $CORE [error-message failure-envelope captured-failure]

def inspect-lock [file: path] {
    let target = ($file | path expand --no-symlink)
    let kind = (try { $target | path type } catch { null })
    if $kind == null {
        return {path: $target state: "not-found-or-inaccessible" kind: null modified: null sha256: "" note: "No readable entry was found. An inaccessible path is not proof of absence."}
    }
    if $kind != "file" {
        return {path: $target state: "invalid-lock-path" kind: $kind modified: null sha256: "" note: "Not a regular file. No removal or replacement was attempted."}
    }
    let row = (try { ls --all $target | first } catch { {} })
    let digest = (try { open --raw $target | hash sha256 } catch { "" })
    {
        path: $target state: "exists-owner-unknown" kind: $kind
        modified: ($row.modified? | default null) sha256: $digest
        note: "Token-only lock format: PID, host and liveness are not recorded. Old age does NOT prove that a lock is stale."
    }
}

def probe-lock [file: path] {
    let directory = ($file | path dirname)
    let test_file = ($directory | path join (".initial-setup-lock-probe-" + (random uuid) + ".lock"))
    let probe_result = (try {
        let owned = (lock-acquire $test_file)
        lock-release $owned
        if ($test_file | path exists) { error make {msg: "Probe lock was not released."} }
        null
    } catch {|err| failure-envelope $err })
    let failure = (captured-failure $probe_result)
    {
        directory: $directory ok: ($failure == null)
        diagnostic: (if $failure == null { "Exclusive create, token verification and release succeeded. This does NOT prove that an existing operation lock is stale." } else { error-message $failure "Lock probe failed." })
        probe_path: $test_file
    }
}

def main [--file: path --data-dir: path --probe --json] {
    if $file != null and $data_dir != null { error make {msg: "Choose --file or --data-dir, not both."} }
    mut targets = []
    mut notes = []
    if $file != null {
        $targets = [$file]
    } else {
        $targets = [((state-root) | path join "locks" "operation.lock")]
        if $data_dir != null {
            let directory_provider = {version: 1 kind: "directory" remote: "" data_root: ($data_dir | path expand | into string)}
            let obsolete_local = (provider-local-lock-path $directory_provider)
            if ($obsolete_local | path exists) {
                $notes = ($notes | append ("Obsolete pre-v0.12.24 local provider lock exists but is ignored: " + ($obsolete_local | into string)))
            }
            let legacy = (legacy-directory-lock-path $directory_provider)
            if $legacy != null and ($legacy | path exists) {
                $notes = ($notes | append ("Legacy cloud lock exists but is ignored and never probed automatically: " + ($legacy | into string)))
            }
        } else {
            let config_file = ((state-root) | path join "config.nuon")
            if ($config_file | path exists) {
                let provider_result = (try { {value: (load-provider) message: ""} } catch {|err| {value: null message: (error-message $err "Provider configuration could not be loaded.")} })
                if $provider_result.value != null {
                    let provider = $provider_result.value
                    if $provider.kind == "directory" {
                        let obsolete_local = (provider-local-lock-path $provider)
                        if ($obsolete_local | path exists) {
                            $notes = ($notes | append ("Obsolete pre-v0.12.24 local provider lock exists but is ignored: " + ($obsolete_local | into string)))
                        }
                        let legacy = (legacy-directory-lock-path $provider)
                        if $legacy != null and ($legacy | path exists) {
                            $notes = ($notes | append ("Legacy cloud lock exists but is ignored and never probed automatically: " + ($legacy | into string)))
                        }
                    }
                    if $provider.kind == "local" { $targets = ($targets | append ($provider.remote | path join ".initial-setup-write.lock")) }
                    if $provider.kind == "rclone" { $notes = ($notes | append "rclone has no shared filesystem lock to inspect. No remote API was called.") }
                } else { $notes = ($notes | append ("Provider configuration could not be read: " + $provider_result.message)) }
            } else {
                $notes = ($notes | append "No machine config yet. Add --data-dir <your-private-data-root> to report legacy/obsolete provider locks, or --file <exact-error-path>.")
            }
        }
    }
    let inspected = ($targets | uniq | each {|target| inspect-lock $target })
    let probes = if $probe { $targets | uniq | each {|target| probe-lock $target } } else { [] }
    let report = {
        version: 1 checks: $inspected probes: $probes notes: $notes
        recovery: "No locks were removed. Local directory-provider locks coordinate only this machine. Shared-filesystem locks still require checking all machines. Legacy cloud lock entries are informational only and are never probed or deleted automatically."
    }
    if $json { $report | to json } else { $report }
}
