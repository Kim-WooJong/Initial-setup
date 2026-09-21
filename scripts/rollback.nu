#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
const PROVIDER = path self ./modules/sync-provider.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $CORE [error-message failure-envelope captured-failure]
use $SAFETY [state-root operation-lease release-lease manifest-hash]
use $PROVIDER [load-provider assert-expected-head assert-same-head stable-provider-head record-provider-state remote-lock release-remote-lock install-workspace workspace-manifest new-transfer-dir copy-workspace]
use $SUBPROCESS [run-command command-failure-message]

def snapshot-root [] { (state-root) | path join "snapshots" }

def snapshot-list [] {
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

def run-script [name: string ...args: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)
    let result = (run-command $nu.current-exe (["--no-config-file" $script] | append $args) --live)
    if not $result.ok { error make {msg: (command-failure-message ("Script " + $name) $result)} }
}

def resolve-snapshot [requested: string] {
    let snapshots = (snapshot-list)
    if ($snapshots | is-empty) { error make {msg: "No snapshot is available."} }
    if ($requested | is-empty) { return ($snapshots | first | get name) }
    if ($requested | path basename) != $requested or $requested in ["." ".."] {
        error make {msg: "Snapshot must be selected by name, not by a path."}
    }
    let matches = ($snapshots | where {|row| ($row.name | path basename) == $requested })
    if ($matches | length) != 1 {
        error make {msg: ("Completed snapshot not found: " + $requested)}
    }
    $matches | first | get name
}

def validate-snapshot [selected: path] {
    let meta_file = ($selected | path join "snapshot.nuon")
    if not ($meta_file | path exists) { error make {msg: "Snapshot metadata is missing."} }
    let meta = (open --raw $meta_file | from nuon)
    let version = ($meta.version? | default 1 | into int)
    if not ($version in [1 2 3]) { error make {msg: "Unsupported snapshot version."} }
    if $version == 3 {
        let expected = ($meta.files? | default [])
        if ($expected | describe) !~ '^(list|table)' { error make {msg: "Snapshot v3 manifest is invalid."} }
        let actual = (workspace-manifest $selected)
        if $actual != $expected { error make {msg: "Snapshot payload no longer matches its recorded SHA-256 manifest."} }
        let hash = (manifest-hash $actual)
        if $hash != ($meta.tree_hash? | default "") { error make {msg: "Snapshot tree hash is invalid."} }
    } else {
        print --stderr ("[warn] Snapshot v" + ($version | into string) + " predates content-hash verification; compatibility restore will be used.")
    }
    {meta: $meta version: $version}
}

def prepare-restore-source [provider: record selected: path version: int] {
    if $version != 1 { return {source: $selected cleanup: null} }
    # v1 predates the encrypted vault. Preserve current ciphertext rather than
    # interpreting an absent secrets/ directory as a request to delete it.
    let stage = (new-transfer-dir)
    copy-workspace $selected $stage | ignore
    let current_secrets = ($provider.data_root | path expand | path join "secrets")
    if ($current_secrets | path exists) {
        cp --recursive $current_secrets ($stage | path join "secrets")
    }
    {source: $stage cleanup: $stage}
}

def rollback-impl [provider: record --snapshot: string = "" --source-only] {
    let selected = (resolve-snapshot $snapshot)
    let validated = (validate-snapshot $selected)

    # Preserve a normal user-facing snapshot before changing the private source.
    run-script "create-snapshot.nu" "--label" "pre-rollback" "--quiet"

    let prepared = (prepare-restore-source $provider $selected $validated.version)
    let apply_source = $prepared.source
    let install_result = (try { install-workspace $provider $apply_source; null } catch {|err| failure-envelope $err })
    let install_failure = (captured-failure $install_result)
    if $install_failure != null {
        if $prepared.cleanup != null { try { rm --recursive --force $prepared.cleanup } catch {} }
        error make {msg: (error-message $install_failure "Snapshot workspace restore failed.")}
    }

    if $source_only {
        if $prepared.cleanup != null { try { rm --recursive --force $prepared.cleanup } catch {} }
        print ("[ok] Restored private source snapshot without applying it locally: " + ($selected | path basename))
        return
    }

    run-script "write-sync-meta.nu" "--action" "rollback"
    run-script "sync-down-local.nu" "--source-root" ($apply_source | into string)
    if $prepared.cleanup != null { try { rm --recursive --force $prepared.cleanup } catch {
        print --stderr ("[warn] Compatibility staging remains at: " + ($prepared.cleanup | into string))
    } }
    print ("[ok] Restored snapshot: " + ($selected | path basename))
}

def main [--list --snapshot: string = "" --source-only] {
    if $list {
        let snapshots = (snapshot-list)
        if ($snapshots | is-empty) { print "No snapshots."; return }
        $snapshots | each {|item| $item.name | path basename } | print
        return
    }

    let lease = (operation-lease)
    mut shared = null
    let operation_result = (try {
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lease.lock.token
        let provider = (load-provider)
        $shared = (remote-lock $provider)
        let head = (assert-expected-head $provider)
        rollback-impl $provider --snapshot $snapshot --source-only=$source_only
        if $provider.kind == "directory" {
            let current = (stable-provider-head $provider)
            record-provider-state $provider $current
            if not $source_only { run-script "update-sync-state.nu" }
        } else {
            assert-same-head $provider $head
            print "[info] Remote HEAD is unchanged. Run dotpush only after reviewing the reverted workspace."
        }
        null
    } catch {|err| failure-envelope $err })
    let operation_failure = (captured-failure $operation_result)

    let remote_cleanup_result = (try { release-remote-lock $shared; null } catch {|err| failure-envelope $err })
    let local_cleanup_result = (try { release-lease $lease; null } catch {|err| failure-envelope $err })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)

    if $operation_failure != null {
        mut message = (error-message $operation_failure "Rollback failed.")
        if $remote_cleanup_error != null { $message = ($message + (char nl) + "Remote-lock cleanup also failed: " + (error-message $remote_cleanup_error)) }
        if $local_cleanup_error != null { $message = ($message + (char nl) + "Local-lock cleanup also failed: " + (error-message $local_cleanup_error)) }
        error make {msg: $message}
    }
    if $remote_cleanup_error != null { error make {msg: ("Remote-lock cleanup failed: " + (error-message $remote_cleanup_error))} }
    if $local_cleanup_error != null { error make {msg: ("Local-lock cleanup failed: " + (error-message $local_cleanup_error))} }
}
