#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
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

def state-file [] {
    (nu-home)
    | path join ".config" "dotfiles" "sync-state.nuon"
}

def conflict-file [] {
    (nu-home)
    | path join ".config" "dotfiles" "SYNC-CONFLICT.txt"
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    if not ($file | path exists) {
        return null
    }

    open $file
}

def log [
    level: string
    message: string
] {
    let script = ($TOOLS_ROOT | path join "scripts" "log-event.nu")
    let args = [
        $script
        "--level"
        $level
        "--message"
        $message
    ]

    ^nu ...$args | ignore
}

def fingerprint [kind: string] {
    let script = ($TOOLS_ROOT | path join "scripts" "sync-fingerprint.nu")
    let args = [
        $script
        "--kind"
        $kind
    ]

    ^nu ...$args | str trim
}

def run-script [name: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)

    ^nu $script

    $env.LAST_EXIT_CODE | default 0
}

def wait-stable [seconds: int] {
    let delay = ($seconds | into duration --unit sec)
    sleep $delay
}

def write-conflict [
    context: record
    reason: string
    baseline_local: string
    current_local: string
    baseline_cloud: string
    current_cloud: string
] {
    let file = (conflict-file)
    mkdir ($file | path dirname)

    let timestamp = (date now | format date "%Y-%m-%d %H:%M:%S %z")

    [
        "DOTFILES SYNC CONFLICT"
        ""
        ("Machine: " + $context.machine.name)
        ("Time: " + $timestamp)
        ("Reason: " + $reason)
        ""
        ("Baseline local: " + $baseline_local)
        ("Current local:  " + $current_local)
        ""
        ("Baseline cloud: " + $baseline_cloud)
        ("Current cloud:  " + $current_cloud)
        ""
        "Automatic overwrite was stopped."
        ""
        "Resolve explicitly:"
        "  dotpush   -> local configuration wins"
        "  dotpull   -> cloud configuration wins"
        ""
    ]
    | str join (char nl)
    | save --force $file

    log "CONFLICT" $reason
    print "[conflict] Local and cloud configuration both changed."
    print ("[conflict] " + ($file | into string))
}

def resolve-both-changed [
    context: record
    state: record
    current_local: string
    current_cloud: string
] {
    let policy = $context.sync.conflict_policy

    if $policy == "prefer_local" {
        log "WARN" "Both sides changed; prefer_local policy selected."

        if not $context.sync.auto_push {
            print "[skip] auto_push is disabled"
            return
        }

        run-script "sync-up.nu" | ignore
        return
    }

    if $policy == "prefer_cloud" {
        log "WARN" "Both sides changed; prefer_cloud policy selected."

        if not $context.sync.auto_pull {
            print "[skip] auto_pull is disabled"
            return
        }

        run-script "sync-down.nu" | ignore
        return
    }

    write-conflict $context "Local and cloud changed since the last successful sync." $state.local_hash $current_local $state.cloud_hash $current_cloud
}

def main [] {
    let context = (machine-context)

    if $context == null {
        return
    }

    if not $context.sync.enabled {
        return
    }

    let data_root = ($context.data_root | path expand)

    if not ($data_root | path exists) {
        log "WARN" "Private data root is unavailable."
        return
    }

    let state_path = (state-file)

    if not ($state_path | path exists) {
        log "WARN" "Sync baseline is missing."
        print "[skip] Sync baseline is missing."
        return
    }

    let state = (open $state_path)
    let current_local = (fingerprint "local")
    let current_cloud = (fingerprint "cloud")
    let local_changed = ($current_local != $state.local_hash)
    let cloud_changed = ($current_cloud != $state.cloud_hash)

    if not $local_changed and not $cloud_changed {
        return
    }

    if $local_changed and $cloud_changed {
        resolve-both-changed $context $state $current_local $current_cloud
        return
    }

    let delay = $context.sync.stability_delay_seconds

    if $local_changed {
        if not $context.sync.auto_push {
            log "INFO" "Local change detected but auto_push is disabled."
            return
        }

        wait-stable $delay

        let cloud_after_delay = (fingerprint "cloud")

        if $cloud_after_delay != $current_cloud {
            write-conflict $context "Cloud changed while a local update was waiting to publish." $state.local_hash $current_local $state.cloud_hash $cloud_after_delay
            return
        }

        log "INFO" "Local configuration changed; starting automatic push."

        let exit_code = (run-script "sync-up.nu")

        if $exit_code != 0 {
            log "ERROR" "Automatic sync-up failed."
            print "[warn] Automatic sync-up failed."
        } else {
            log "INFO" "Automatic sync-up completed."
        }

        return
    }

    if $cloud_changed {
        if not $context.sync.auto_pull {
            log "INFO" "Cloud change detected but auto_pull is disabled."
            return
        }

        wait-stable $delay

        let cloud_after_delay = (fingerprint "cloud")

        if $cloud_after_delay != $current_cloud {
            log "INFO" "Cloud source is still changing; retry next cycle."
            return
        }

        let local_after_delay = (fingerprint "local")

        if $local_after_delay != $current_local {
            write-conflict $context "Local changed while a cloud update was waiting to apply." $state.local_hash $local_after_delay $state.cloud_hash $current_cloud
            return
        }

        log "INFO" "Cloud configuration changed; starting automatic pull."

        let exit_code = (run-script "sync-down.nu")

        if $exit_code != 0 {
            log "ERROR" "Automatic sync-down failed."
            print "[warn] Automatic sync-down failed."
        } else {
            log "INFO" "Automatic sync-down completed."
        }
    }
}
