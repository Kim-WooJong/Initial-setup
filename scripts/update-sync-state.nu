#!/usr/bin/env nu

const SUBPROCESS = path self ./modules/subprocess.nu
const SAFETY = path self ./modules/safety.nu
use $SUBPROCESS [run-command command-failure-message]
use $SAFETY [atomic-record]

const TOOLS_ROOT = path self ..

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def machine-context [] {
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

    open $file
}

def state-file [] {
    let scope = ($env.INITIAL_SETUP_PROVIDER_STATE_SCOPE? | default "" | str trim)
    if ($scope | is-empty) {
        return ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    }
    if not ($scope =~ '^[a-f0-9]{64}$') { error make {msg: "Invalid sync-state scope."} }
    (nu-home) | path join ".config" "dotfiles" "sync-states" ("sync-state-" + $scope + ".nuon")
}

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
        state-file
    )

    mkdir (
        $state_path
        | path dirname
    )

    atomic-record $state_path {
        version: "2"
        local_hash: $local_hash
        cloud_hash: $cloud_hash
        last_sync: (date now | format date "%Y-%m-%d %H:%M:%S %z")
        last_writer: ($meta.last_writer? | default "unknown")
        last_write_time: ($meta.updated_at? | default "unknown")
        last_action: ($meta.last_action? | default "unknown")
    }

    let conflict_path = (
        conflict-file
    )

    if ($conflict_path | path exists) {
        rm $conflict_path
    }

    print "[ok] Sync baseline updated"
}
