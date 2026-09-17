#!/usr/bin/env nu

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
    (nu-home)
    | path join ".config" "dotfiles" "sync-state.nuon"
}

def conflict-file [] {
    (nu-home)
    | path join ".config" "dotfiles" "SYNC-CONFLICT.txt"
}

def fingerprint [kind: string] {
    let script = ($TOOLS_ROOT | path join "scripts" "sync-fingerprint.nu")
    let result = (do { ^nu --no-config-file $script --kind $kind } | complete)
    if $result.exit_code != 0 { error make { msg: "Fingerprint unavailable; synchronization baseline was not advanced." } }
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

    {
        version: "2"
        local_hash: $local_hash
        cloud_hash: $cloud_hash
        last_sync: (
            date now
            | format date "%Y-%m-%d %H:%M:%S %z"
        )
        last_writer: (
            $meta.last_writer?
            | default "unknown"
        )
        last_write_time: (
            $meta.updated_at?
            | default "unknown"
        )
        last_action: (
            $meta.last_action?
            | default "unknown"
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
