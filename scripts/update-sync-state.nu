#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
const SUBPROCESS = path self ./modules/subprocess.nu
const SYNC_STATE = path self ./modules/sync-state.nu
use $SUBPROCESS [run-command command-failure-message]
use $SYNC_STATE [sync-state-file write-sync-state]

const TOOLS_ROOT = path self ..

def conflict-file [] {
    (nu-home)
    | path join ".config" "dotfiles" "SYNC-CONFLICT.txt"
}

def fingerprint [kind: string] {
    let script = ($TOOLS_ROOT | path join "scripts" "sync-fingerprint.nu")
    let result = (run-command $nu.current-exe ["--no-config-file" $script "--kind" $kind])
    if not $result.ok { error make { msg: ((command-failure-message ("Fingerprint " + $kind) $result) + (char nl) + "Synchronization baseline was not advanced.") } }
    let value = ($result.stdout | str trim)
    if not ($value =~ '^[a-f0-9]{64}$') and not ($kind == "cloud" and ($value | is-empty)) {
        error make { msg: "Invalid fingerprint result." }
    }
    $value
}

def main [] {
    let context = (
        machine-context
    )

    let local_hash = (
        fingerprint "local"
    )

    let cloud_hash = (
        fingerprint "cloud"
    )

    let meta_file = (
        $context.data_root
        | path expand
        | path join ".dotfiles-sync-meta.nuon"
    )

    let meta = (
        if ($meta_file | path exists) {
            open $meta_file
        } else {
            {
                last_writer: "unknown"
                last_action: "unknown"
                updated_at: "unknown"
            }
        }
    )

    let state_path = (
        sync-state-file
    )

    write-sync-state $state_path {
        schema_version: 3
        local_hash: $local_hash
        cloud_hash: $cloud_hash
        last_sync: (date now | format date "%Y-%m-%d %H:%M:%S %z")
        last_writer: ($meta.last_writer? | default "unknown")
        last_write_time: ($meta.updated_at? | default "unknown")
        last_action: ($meta.last_action? | default "unknown")
    } | ignore

    let conflict_path = (
        conflict-file
    )

    if ($conflict_path | path exists) {
        rm $conflict_path
    }

    print "[ok] Sync baseline updated"
}
