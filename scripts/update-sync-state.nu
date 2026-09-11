#!/usr/bin/env nu

# ============================================================
# update-sync-state.nu
#
# Save the current synchronized local/cloud baseline.
# Called only after a successful setup, push, or pull.
# ============================================================

const TOOLS_ROOT = path self ..

def state-file [] {
    $nu.home-path
    | path join ".config" "dotfiles" "sync-state.nuon"
}

def conflict-file [] {
    $nu.home-path
    | path join ".config" "dotfiles" "SYNC-CONFLICT.txt"
}

def fingerprint [kind: string] {
    let script = (
        $TOOLS_ROOT
        | path join "scripts" "sync-fingerprint.nu"
    )

    let args = [
        $script
        "--kind"
        $kind
    ]

    ^nu ...$args
    | str trim
}

def main [] {
    let local_hash = (
        fingerprint "local"
    )

    let cloud_hash = (
        fingerprint "cloud"
    )

    let state_path = (
        state-file
    )

    mkdir (
        $state_path
        | path dirname
    )

    {
        version: "1"
        local_hash: $local_hash
        cloud_hash: $cloud_hash
        last_sync: (
            date now
            | format date "%Y-%m-%d %H:%M:%S %z"
        )
    }
    | to nuon
    | save --force $state_path

    let conflict_path = (
        conflict-file
    )

    if ($conflict_path | path exists) {
        rm $conflict_path
    }

    print "[ok] Sync baseline updated"
}
