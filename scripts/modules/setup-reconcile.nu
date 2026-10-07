# Interactive setup only. Background writers retain assert-expected-head.
const PROVIDER = path self ./sync-provider.nu
const SAFETY = path self ./safety.nu
const CONSOLE = path self ./console.nu
use $PROVIDER [assert-same-head copy-workspace workspace-manifest]
use $SAFETY [state-root private-directory atomic-record manifest-hash]
use $CONSOLE [print-heading print-text print-key-value print-choice print-status]

export def setup-head-changed [state: any head: record] {
    if $state == null { return false }
    $state.revision != $head.revision or $state.tree_hash != $head.tree_hash
}

export def choose-changed-source [config: record state: record head: record preview: closure] {
    # stderr remains visible while the return value is collected by the caller.
    # Checking stdin alone would allow a child with captured diagnostics to prompt.
    if not (is-terminal --stdin) or not (is-terminal --stderr) {
        error make {msg: "Private source changed. Run nu setup.nu in an interactive terminal to review and choose which configuration to keep."}
    }
    print --stderr ""
    print-heading "Private source changed since the last synchronization." --stderr
    print-key-value "Baseline revision: " $state.revision --stderr
    print-key-value "Current revision : " $head.revision --stderr
    print-key-value "Private source   : " ($config.data_root | into string) --stderr
    print-text "info" "Choose which managed configuration to keep. Unmanaged files are unaffected." --stderr
    print-text "info" "Continuing creates a local configuration backup and a verified private-source recovery copy." --stderr
    loop {
        print --stderr ""
        print-choice "1" "Review local/private differences, then return to this menu" --stderr
        print-choice "2" "Keep this machine's managed configuration (local -> private)" --stderr
        print-choice "3" "Keep the current private configuration (private -> this machine)" --stderr
        print-text "info" "     Protected Git/SSH targets still require their existing individual review." --stderr
        print-choice "4" "Cancel without applying changes" --stderr
        print-text "prompt" "Select [4] (press Enter to cancel):" --stderr
        let choice = (input | str trim)
        match $choice {
            "1" => { do $preview }
            "2" => { return "push-local" }
            "3" => { return "backup-private" }
            "4" | "" => { return "cancel" }
            _ => { print-text "warn" "Choose 1, 2, 3, or 4." --stderr }
        }
    }
}

# Keep this recovery copy outside rotating snapshots, even when snapshots are disabled.
# Never acknowledge a new baseline here: setup commits it only after success.
export def preserve-reviewed-source [config: record head: record run_id: string] {
    if $config.kind != "directory" { error make {msg: "Setup reconciliation requires a directory provider."} }
    assert-same-head $config $head
    let root = ((state-root) | path join "reconciliation-backups")
    private-directory $root
    let destination = ($root | path join (random uuid))
    private-directory $destination
    print-status "info" "recovery" ("Preserving private source at: " + ($destination | into string))
    let entries = (copy-workspace $config.data_root $destination)
    if (manifest-hash $entries) != $head.tree_hash or (workspace-manifest $destination) != $entries {
        error make {msg: ("Private source changed or recovery verification failed. Setup stopped; incomplete recovery retained at: " + ($destination | into string))}
    }
    assert-same-head $config $head
    atomic-record ($destination | path join "reconciliation.nuon") {
        version: 1 run_id: $run_id data_root: $config.data_root
        revision: $head.revision tree_hash: $head.tree_hash files: $entries
        created_at: (date now | format date "%+")
    }
    $destination
}
