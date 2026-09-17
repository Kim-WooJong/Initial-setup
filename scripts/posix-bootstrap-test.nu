#!/usr/bin/env nu
const ROOT = path self ..

def main [] {
    if not ($nu.os-info.name in ["linux" "macos"]) {
        print "[skip] POSIX bootstrap tests are not applicable on this OS."
        return
    }
    if (which bash | is-empty) {
        error make {msg: "bash is required for the POSIX bootstrap tests."}
    }

    for relative in [
        "scripts/posix/bootstrap-smoke-test.sh"
        "scripts/posix/prepare-nu-release-test.sh"
        "scripts/posix/prepare-nu-cargo-test.sh"
    ] {
        let script = ($ROOT | path join $relative)
        print ("[test] " + $relative)
        ^bash $script
        if ($env.LAST_EXIT_CODE | default 1) != 0 {
            error make {msg: ("POSIX bootstrap test failed: " + $relative)}
        }
    }
}
