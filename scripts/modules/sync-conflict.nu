# Recovery helpers for explicit synchronization conflict resolution.
# Manual dotpush may intentionally choose local configuration over a changed
# directory provider, but only after preserving the reviewed provider payload.
const PROVIDER = path self ./sync-provider.nu
const SAFETY = path self ./safety.nu
use $PROVIDER [assert-same-head copy-workspace workspace-manifest]
use $SAFETY [state-root private-directory atomic-record manifest-hash]

export def preserve-provider-recovery [config: record head: record reason: string] {
    if $config.kind != "directory" {
        error make {msg: "Provider recovery copies are only required for directory providers."}
    }

    assert-same-head $config $head

    let root = ((state-root) | path join "sync-recovery")
    private-directory $root
    let id = (random uuid)
    let destination = ($root | path join $id)
    private-directory $destination

    let entries = (copy-workspace $config.data_root $destination)
    let tree_hash = (manifest-hash $entries)
    if $tree_hash != $head.tree_hash or (workspace-manifest $destination) != $entries {
        error make {msg: ("Provider recovery verification failed. Incomplete recovery retained at: " + ($destination | into string))}
    }

    assert-same-head $config $head
    atomic-record ($destination | path join "recovery.nuon") {
        version: 1
        reason: $reason
        data_root: $config.data_root
        revision: $head.revision
        tree_hash: $head.tree_hash
        files: $entries
        created_at: (date now | format date "%+")
    }

    $destination
}
