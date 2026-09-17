#!/usr/bin/env nu
const ROOT = path self ..
const IMPL = path self ./refresh-commands-main.nu
const CONTROL = path self ./cloud-wins-main.nu
const CORE = path self ./modules/core.nu
const CLOUD = path self ./modules/cloud-wins-config.nu
const SAFETY = path self ./modules/safety.nu
use $CORE [machine-config-path]
use $CLOUD [cloud-config-path]
use $SAFETY [atomic-record]
def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[refresh-test] " + $message)} }
    print ("[pass] " + $message)
}
def child [path: path args: list --failure: string = ""] {
    let exe = $nu.current-exe
    let result = (do { ^$exe --no-config-file $path ...$args } | complete)
    if ($failure | is-empty) {
        if $result.exit_code != 0 { error make {msg: ($result.stdout + $result.stderr)} }
    } else {
        check ($result.exit_code != 0 and (($result.stdout + $result.stderr) | str contains $failure)) "Unexpected context edits fail closed"
    }
}
def tests [base: path] {
    let source = ($base | path join "cloud")
    let target = ($base | path join "local")
    mkdir $source $target
    let previous = {data_root: $source tools_root: ($base | path join "old checkout") sync: {enabled: true auto_push: true auto_pull: true prune_extras: false}}
    let active = ($previous | upsert data_root $target | upsert sync.enabled false | upsert sync.auto_push false | upsert sync.auto_pull false)
    let config = {version: 1 source: $source target: $target active: true previous_context: $previous activated_context: $active}
    atomic-record (machine-config-path) $active
    atomic-record (cloud-config-path) $config
    child $IMPL ["--dry-run"]
    check ((open --raw (machine-config-path) | from nuon) == $active) "Preview does not change machine config"
    check ((open --raw (cloud-config-path) | from nuon) == $config) "Preview does not change recovery snapshots"
    child $IMPL []
    let next = (open --raw (cloud-config-path) | from nuon)
    check ($next.active and $next.previous_context.tools_root == ($ROOT | into string) and $next.activated_context.tools_root == ($ROOT | into string)) "Active recovery snapshots follow the new checkout"
    let refreshed = (open --raw (machine-config-path) | from nuon)
    check ($refreshed == ($active | upsert tools_root ($ROOT | into string))) "Refresh only changes tools_root"
    # Simulate interruption after cloud snapshots changed but before machine write.
    atomic-record (machine-config-path) $active
    child $IMPL []
    check ((open --raw (machine-config-path) | from nuon) == $refreshed) "Interrupted refresh is safely retryable"
    child $CONTROL ["deactivate" "--execute" "--confirm" "restore-previous-mode"]
    check ((open --raw (machine-config-path) | from nuon) == ($previous | upsert tools_root ($ROOT | into string))) "Deactivation restores old policy without restoring a stale checkout"
    atomic-record (machine-config-path) ($active | upsert data_root ($base | path join "unapproved"))
    atomic-record (cloud-config-path) $config
    let before = (open --raw (machine-config-path) | from nuon)
    child $IMPL [] --failure "CLOUD_CONTEXT_CHANGED"
    check ((open --raw (machine-config-path) | from nuon) == $before) "Refused refresh preserves unrelated machine edits"
    check ((open --raw (cloud-config-path) | from nuon) == $config) "Refused refresh preserves recovery state"
}
def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-refresh-" + (random uuid)))
    mkdir $base
    try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $base HOME: $base USERPROFILE: $base} { tests $base }
    } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
}
