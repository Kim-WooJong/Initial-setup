#!/usr/bin/env nu

const ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

def fail [message: string] { print --stderr ("[FAIL] " + $message); exit 1 }

def main [] {
    let fixture = ($ROOT | path join "scripts" "subprocess-fixture.nu")
    let exe = ($nu.current-exe | into string)

    let ok = (run-command $exe ["--no-config-file" $fixture "ok"])
    if not $ok.ok or $ok.exit_code != 0 or not ($ok.stdout | str contains "fixture-ok") { fail "success result contract" }

    let bad = (run-command $exe ["--no-config-file" $fixture "fail"])
    if $bad.ok or $bad.exit_code != 23 { fail "non-zero exit code preservation" }
    if not ($bad.stdout | str contains "fixture-stdout") { fail "stdout preservation" }
    if not ($bad.stderr | str contains "fixture-stderr") { fail "stderr preservation" }
    let message = (command-failure-message "fixture" $bad)
    if not ($message | str contains "fixture-stderr") { fail "diagnostic preservation" }

    let sensitive = (run-command $exe ["--no-config-file" $fixture "fail"] --sensitive)
    if ($sensitive.diagnostic | str contains "fixture-stderr") { fail "sensitive diagnostic redaction" }

    let live = (run-command $exe ["--no-config-file" $fixture "ok"] --live)
    if not $live.ok or $live.exit_code != 0 or not ($live.stdout | str contains "fixture-ok") { fail "live result contract" }

    print "[pass] shared subprocess result contract"
}
