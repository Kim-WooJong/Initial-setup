#!/usr/bin/env nu
const RUNS = path self ./modules/run-state.nu
use $RUNS [runs-root create-run load-run mark-stage stage-status finish-run]
def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[run-state-test] " + $message)} }
    print ("[pass] " + $message)
}
def tests [] {
    for id in ["../outside" ".." "/tmp/escape" 'C:\escape' "with space" "a/b" ""] {
        let failed = (try { load-run $id | ignore; false } catch {|err| $err.msg | str contains "RUN_ID_INVALID" })
        check $failed ("Path-like run identifier rejected: " + $id)
    }
    let id = (create-run "0.14.1" "auto" "ask" "minimal" "test-data" true)
    check ((load-run $id).run_id == $id) "Created state can be read"
    mark-stage $id "fixture" "running"
    mark-stage $id "fixture" "success" "fixture complete"
    check ((stage-status $id "fixture") == "success") "Checkpoint replacement persists the latest state"
    finish-run $id "success"
    check ((load-run $id).status == "success") "Final state persists"
    let names = (ls --all ((runs-root) | path join $id) | get name | path basename)
    check (($names | sort) == (["events.log" "state.nuon"] | sort)) "No partial checkpoint remains"
}
def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-run-state-" + (random uuid)))
    mkdir $base
    try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $base HOME: $base USERPROFILE: $base} { tests }
    } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
}
