#!/usr/bin/env nu
const ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $SUBPROCESS [run-command command-failure-message]
use $INSTALL_UTILS [probe-tool]

def main [] {
    if not ($nu.os-info.name in ["linux" "macos"]) {
        print "[skip] POSIX bootstrap tests are not applicable on this OS."
        return
    }
    let bash_probe = (probe-tool "bash" ["--version"])
    if not $bash_probe.healthy {
        error make {msg: "bash is required and must be healthy for the POSIX bootstrap tests."}
    }

    for relative in [
        "scripts/posix/bootstrap-smoke-test.sh"
        "scripts/posix/prepare-nu-release-test.sh"
        "scripts/posix/prepare-nu-cargo-test.sh"
    ] {
        let script = ($ROOT | path join $relative)
        print ("[test] " + $relative)
        let result = (run-command $bash_probe.path [($script | into string)] --live)
        if not $result.ok {
            error make {msg: (command-failure-message ("POSIX bootstrap test: " + $relative) $result)}
        }
    }
}
