#!/usr/bin/env nu
# Compatibility alias. Use the version-independent root verify.nu for new runs.
const ENTRY = path self ../verify.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command print-result]
def main [--full --offline] {
    mut args = []
    if $full { $args = ($args | append "--full") }
    if $offline { $args = ($args | append "--offline") }
    let exe = ($nu.current-exe | into string)
    let result = (run-command $exe (["--no-config-file" ($ENTRY | into string)] | append $args) --live)
    if not $result.ok { print-result "verify compatibility alias" $result }
    exit ($result.exit_code? | default 1)
}
