#!/usr/bin/env nu
# platform.nu must exist on every OS because the synchronized config.nu sources
# it; a config synced from another OS must not make Nushell fail to start.
const SHIMS = path self ./setup-platform-shims.nu
use $SHIMS [write-platform-env]

def expect [ok: bool message: string] {
    if not $ok { error make {msg: ("[platform-shim-test] " + $message)} }
    print ("[pass] " + $message)
}

def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-platform-" + (random uuid)))
    mkdir $base
    try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $base HOME: $base USERPROFILE: $base} {
            let f = ($base | path join ".config" "dotfiles" "platform.nu")
            expect (not ($f | path exists)) "platform.nu absent before setup"
            write-platform-env
            expect (($f | path exists) and (($f | path type) == "file")) "write-platform-env creates platform.nu"
            # The file must be a parseable Nushell env source (empty/no-op is fine).
            let check = (do { ^$nu.current-exe --no-config-file -c ("source-env " + ($f | to nuon)) } | complete)
            expect ($check.exit_code == 0) "platform.nu is a valid source-env target (Nushell starts)"
        }
    } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
    print "[ok] platform shim regressions passed."
}
