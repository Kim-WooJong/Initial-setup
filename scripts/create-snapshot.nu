#!/usr/bin/env nu

const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
const PROVIDER = path self ./modules/sync-provider.nu
use $CORE [machine-context error-message failure-envelope captured-failure]
use $SAFETY [state-root private-directory atomic-record manifest-hash operation-lease release-lease]
use $PROVIDER [copy-workspace workspace-manifest]

def sanitize-label [label: string] {
    $label
    | str replace --all ' ' '-'
    | str replace --all '/' '-'
    | str replace --all '\\' '-'
    | str replace --all ':' '-'
}

def snapshot-root [] { (state-root) | path join "snapshots" }

def completed-snapshots [] {
    let root = (snapshot-root)
    if not ($root | path exists) { return [] }
    ls $root
    | where type == dir
    | where {|row|
        let name = ($row.name | path basename)
        not ($name | str starts-with ".partial-") and (($row.name | path join "snapshot.nuon") | path exists)
    }
    | sort-by name
    | reverse
}

def create-snapshot [label: string quiet: bool] {
    let context = (machine-context)
    if not $context.maintenance.snapshots_enabled {
        if not $quiet { print "[skip] Snapshots are disabled." }
        return null
    }

    let data_root = ($context.data_root | path expand)
    if not ($data_root | path exists) {
        if not $quiet { print "[skip] Private data root is unavailable." }
        return null
    }

    let root = (snapshot-root)
    private-directory $root
    let timestamp = (date now | format date "%Y%m%d-%H%M%S")
    let safe_label = (sanitize-label $label)
    let id = (random uuid)
    let snapshot_dir = ($root | path join ($timestamp + "-" + $safe_label + "-" + $id))
    let staging = ($root | path join (".partial-" + $id))
    private-directory $staging

    let outcome = (try {
        let entries = (copy-workspace $data_root $staging)
        let metadata = {
            version: 3
            created_at: (date now | format date "%+")
            label: $label
            machine: $context.machine.name
            data_root: ($data_root | into string)
            files: $entries
            tree_hash: (manifest-hash $entries)
        }
        atomic-record ($staging | path join "snapshot.nuon") $metadata
        let verified = (workspace-manifest $staging)
        if $verified != $entries or (manifest-hash $verified) != $metadata.tree_hash {
            error make {msg: "Snapshot staging verification failed; no completed snapshot was committed."}
        }
        if ($snapshot_dir | path exists) { error make {msg: "Snapshot destination unexpectedly already exists."} }
        mv $staging $snapshot_dir
        {value: $snapshot_dir}
    } catch {|err| failure-envelope $err })
    let failure = (captured-failure $outcome)
    if $failure != null {
        try { if ($staging | path exists) { rm --recursive --force $staging } } catch {
            print --stderr ("[warn] Incomplete snapshot staging remains at: " + ($staging | into string))
        }
        error make {msg: (error-message $failure "Snapshot creation failed.")}
    }

    let keep = $context.maintenance.snapshot_keep
    if $keep > 0 {
        let snapshots = (completed-snapshots)
        if ($snapshots | length) > $keep {
            for item in ($snapshots | skip $keep) {
                try { rm --recursive --force $item.name } catch {
                    print --stderr ("[warn] Could not prune old snapshot: " + ($item.name | into string))
                }
            }
        }
    }

    let committed = $outcome.value
    if not $quiet { print ("[snapshot] " + ($committed | into string)) }
    $committed
}

def main [--label: string = "manual" --quiet] {
    let lease = (operation-lease)
    let outcome = (try { {value: (create-snapshot $label $quiet)} } catch {|err| failure-envelope $err })
    let failure = (captured-failure $outcome)
    let cleanup = (try { release-lease $lease; null } catch {|err| failure-envelope $err })
    let cleanup_failure = (captured-failure $cleanup)
    if $failure != null {
        mut message = (error-message $failure "Snapshot creation failed.")
        if $cleanup_failure != null { $message = ($message + (char nl) + "Operation-lock cleanup also failed: " + (error-message $cleanup_failure)) }
        error make {msg: $message}
    }
    if $cleanup_failure != null { error make {msg: ("Operation-lock cleanup failed: " + (error-message $cleanup_failure))} }
    $outcome.value
}
