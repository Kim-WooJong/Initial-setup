#!/usr/bin/env nu
const TRANSPORT = path self ./sync-transport.nu
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-error]

# protected-conflicts is enforced in sync-down-local.nu even with --force.
def main [--prune --force --allow-protected --source-only --discard-source --discard-local --manual --reload] {
    mut args = ["--no-config-file" $TRANSPORT "pull"]
    if $prune { $args = ($args | append "--prune") }
    if $force { $args = ($args | append "--force") }
    if $allow_protected { $args = ($args | append "--allow-protected") }
    if $source_only { $args = ($args | append "--source-only") }
    if $discard_source { $args = ($args | append "--discard-source") }
    if $discard_local { $args = ($args | append "--discard-local") }
    if $reload { $args = ($args | append "--reload") }
    if $manual {
        $args = ($args | append "--manual")
        exec $nu.current-exe ...$args
    }
    let result = (run-command $nu.current-exe $args --live)
    if not $result.ok {
        if not $result.launched { print-error (command-failure-message "Pull" $result) }
        exit ($result.exit_code? | default 1)
    }
}
