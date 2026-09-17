#!/usr/bin/env nu
# No live capture/sync: test the real convenience command against dummy scripts.
const DOTFILES = path self ./modules/dotfiles.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
use $DOTFILES [dotcapture]
use $SAFETY [atomic-record]
use $CORE [machine-config-path]
def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[subprocess-chain] " + $message)} }
    print ("[pass] " + $message)
}
def tests [base: path] {
    let tools = ($base | path join "dummy tools [한글]")
    mkdir ($tools | path join "scripts")
    atomic-record (machine-config-path) {tools_root: $tools}
    let capture = ($tools | path join "scripts" "capture-tool-state.nu")
    let sync = ($tools | path join "scripts" "sync-up.nu")
    'def main [] { exit 31 }' | save $capture
    'def main [] { "called" | save ($env.INITIAL_SETUP_HOME_OVERRIDE | path join "sync-was-called") }' | save $sync
    let failed = (try { dotcapture; false } catch {|err| $err.msg | str contains "CAPTURE_FAILED" })
    check $failed "Capture failure is returned to the caller"
    check (not ($base | path join "sync-was-called" | path exists)) "A failed capture cannot start synchronization"
    'def main [] {}' | save --force $capture
    'def main [] { exit 32 }' | save --force $sync
    let sync_failed = (try { dotcapture; false } catch {|err| $err.msg | str contains "CAPTURE_SYNC_FAILED" })
    check $sync_failed "Synchronization failure is not reported as capture success"
}
def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-chain-" + (random uuid)))
    mkdir $base
    try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $base HOME: $base USERPROFILE: $base} { tests $base }
    } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
}
