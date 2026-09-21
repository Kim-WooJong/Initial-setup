#!/usr/bin/env nu
const TRANSPORT = path self ./sync-transport.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

# protected-conflicts is enforced in sync-down-local.nu even with --force.
def main [--prune --force --allow-protected --source-only --discard-source --discard-local] {
    mut args = ["--no-config-file" $TRANSPORT "pull"]
    if $prune { $args = ($args | append "--prune") }
    if $force { $args = ($args | append "--force") }
    if $allow_protected { $args = ($args | append "--allow-protected") }
    if $source_only { $args = ($args | append "--source-only") }
    if $discard_source { $args = ($args | append "--discard-source") }
    if $discard_local { $args = ($args | append "--discard-local") }
    let result = (run-command $nu.current-exe $args --live)
    if not $result.ok {
        error make { msg: (command-failure-message "Pull" $result) }
    }
}
