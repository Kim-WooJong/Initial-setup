#!/usr/bin/env nu
# Explicit rclone-only transport. This intentionally does not replace the
# normal provider configuration or its trusted baseline.

const ROOT = path self ..
const PROVIDER = path self ./modules/sync-provider.nu
const SAFETY = path self ./modules/safety.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $PROVIDER [load-provider]
use $SAFETY [atomic-record]
use $SUBPROCESS [run-command command-failure-message]

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)
    if $test_mode == "1" and not ($override | is-empty) { return ($override | path expand) }
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }
    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }
    error make {msg: "Unable to determine the Nushell home directory."}
}

def dedicated-config-path [] {
    (nu-home) | path join ".config" "dotfiles" "rclone-sync.nuon"
}

def validate-remote [remote: string] {
    let value = ($remote | str trim)
    if ($value | is-empty) {
        error make {msg: "An rclone remote is required. Use --remote 'remote:dedicated/path'."}
    }
    if not ($value =~ '^[a-zA-Z0-9][a-zA-Z0-9_. -]*:.+') or ($value =~ '[\x00-\x1f]') {
        error make {msg: "Use a named rclone remote with a dedicated subdirectory, for example proton:Initial-setup-store."}
    }
    $value
}

def saved-remote [] {
    let file = (dedicated-config-path)
    if not ($file | path exists) { return "" }
    let config = (open --raw $file | from nuon)
    if ($config.version? | default 0) != 1 { error make {msg: "Unsupported rclone-only sync configuration."} }
    validate-remote ($config.remote? | default "")
}

def resolve-remote [explicit: string] {
    let requested = ($explicit | str trim)
    if not ($requested | is-empty) { return (validate-remote $requested) }
    let saved = (saved-remote)
    if not ($saved | is-empty) { return $saved }
    let normal = (load-provider)
    if $normal.kind == "rclone" { return (validate-remote $normal.remote) }
    error make {
        msg: "No rclone-only remote is configured. Supply --remote 'remote:dedicated/path'. Add --save-remote after reviewing the path to reuse it later."
    }
}

def main [
    action: string
    --remote: string = ""
    --save-remote
    --prune
    --force
    --discard-local
] {
    if $action not-in ["push" "pull"] { error make {msg: "Choose push or pull."} }
    if $action == "push" and ($prune or $force or $discard_local) {
        error make {msg: "rclone-only push has no force/prune bypass. Resolve the remote baseline first."}
    }
    if $save_remote and ($remote | str trim | is-empty) {
        error make {msg: "--save-remote requires an explicit --remote value."}
    }

    let target = (resolve-remote $remote)
    let scope = (("rclone-explicit|" + $target) | hash sha256)

    # The child transport inherits these overrides. The normal provider config,
    # normal provider baseline, and normal sync-state file remain untouched.
    $env.INITIAL_SETUP_PROVIDER_OVERRIDE_REMOTE = $target
    $env.INITIAL_SETUP_PROVIDER_STATE_SCOPE = $scope
    $env.INITIAL_SETUP_TRANSPORT_ONLY = "1"
    $env.INITIAL_SETUP_SUPPRESS_GLOBAL_SYNC_STATE = "1"

    let transport = ($ROOT | path join "scripts" "sync-transport.nu")
    mut args = ["--no-config-file" $transport $action]
    if $action == "pull" {
        if $prune { $args = ($args | append "--prune") }
        if $force { $args = ($args | append "--force") }
        if $discard_local { $args = ($args | append "--discard-local") }
    }

    print ("[rclone-only] Remote: " + $target)
    let result = (run-command $nu.current-exe $args --live)
    if not $result.ok {
        error make {msg: (command-failure-message ("rclone-only " + $action) $result)}
    }

    if $save_remote {
        atomic-record (dedicated-config-path) {version: 1 remote: $target}
        print ("[ok] Saved rclone-only remote: " + $target)
    }
}
