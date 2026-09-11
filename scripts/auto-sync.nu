#!/usr/bin/env nu

# ============================================================
# auto-sync.nu
#
# Conflict-safe bidirectional synchronization.
#
# last baseline     current state           action
# ------------------------------------------------------------
# unchanged local + unchanged cloud      -> nothing
# changed local   + unchanged cloud      -> sync-up
# unchanged local + changed cloud        -> sync-down
# changed local   + changed cloud        -> conflict, stop
#
# A short stability delay is used before automatic writes.
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

def machine-context [] {
    let file = (
        $nu.home-path
        | path join ".config" "dotfiles" "config.nuon"
    )

    if not ($file | path exists) {
        return null
    }

    open $file
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

def write-conflict [
    reason: string
    baseline_local: string
    current_local: string
    baseline_cloud: string
    current_cloud: string
] {
    let file = (
        conflict-file
    )

    mkdir (
        $file
        | path dirname
    )

    let timestamp = (
        date now
        | format date "%Y-%m-%d %H:%M:%S %z"
    )

    [
        "DOTFILES SYNC CONFLICT"
        ""
        ("Time: " + $timestamp)
        ("Reason: " + $reason)
        ""
        ("Baseline local: " + $baseline_local)
        ("Current local:  " + $current_local)
        ""
        ("Baseline cloud: " + $baseline_cloud)
        ("Current cloud:  " + $current_cloud)
        ""
        "Automatic synchronization has been stopped for this cycle."
        ""
        "Choose one side explicitly:"
        "  dotpush   -> local configuration wins"
        "  dotpull   -> cloud configuration wins"
        ""
    ]
    | str join (char nl)
    | save --force $file

    print "[conflict] Both local and cloud configuration changed."
    print (
        "[conflict] Details: "
        + ($file | into string)
    )
}

def run-script [name: string] {
    let script = (
        $TOOLS_ROOT
        | path join "scripts" $name
    )

    ^nu $script

    $env.LAST_EXIT_CODE
    | default 0
}

def main [] {
    let context = (
        machine-context
    )

    if $context == null {
        return
    }

    let data_root = (
        $context.data_root
        | path expand
    )

    if not ($data_root | path exists) {
        return
    }

    let state_path = (
        state-file
    )

    if not ($state_path | path exists) {
        print "[skip] Sync baseline is missing."
        print "[info] Run nu setup.nu once to initialize automatic sync."
        return
    }

    let state = (
        open $state_path
    )

    let current_local = (
        fingerprint "local"
    )

    let current_cloud = (
        fingerprint "cloud"
    )

    let local_changed = (
        $current_local
        != $state.local_hash
    )

    let cloud_changed = (
        $current_cloud
        != $state.cloud_hash
    )

    if not $local_changed and not $cloud_changed {
        return
    }

    if $local_changed and $cloud_changed {
        write-conflict
            "Local and cloud changed since the last successful sync."
            $state.local_hash
            $current_local
            $state.cloud_hash
            $current_cloud

        return
    }

    if $local_changed {
        sleep 3sec

        let cloud_after_delay = (
            fingerprint "cloud"
        )

        if $cloud_after_delay != $current_cloud {
            write-conflict
                "Cloud changed while a local update was waiting to publish."
                $state.local_hash
                $current_local
                $state.cloud_hash
                $cloud_after_delay

            return
        }

        print "[auto] Local configuration changed."
        print "[auto] Publishing local configuration to private cloud source."

        let exit_code = (
            run-script "sync-up.nu"
        )

        if $exit_code != 0 {
            print "[warn] Automatic sync-up failed."
        }

        return
    }

    if $cloud_changed {
        sleep 2sec

        let cloud_after_delay = (
            fingerprint "cloud"
        )

        if $cloud_after_delay != $current_cloud {
            print "[skip] Cloud source is still changing."
            print "[info] The next automatic sync cycle will retry."
            return
        }

        let local_after_delay = (
            fingerprint "local"
        )

        if $local_after_delay != $current_local {
            write-conflict
                "Local changed while a cloud update was waiting to apply."
                $state.local_hash
                $local_after_delay
                $state.cloud_hash
                $current_cloud

            return
        }

        print "[auto] Private cloud configuration changed."
        print "[auto] Applying the latest configuration."

        let exit_code = (
            run-script "sync-down.nu"
        )

        if $exit_code != 0 {
            print "[warn] Automatic sync-down failed."
        }
    }
}
