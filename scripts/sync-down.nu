#!/usr/bin/env nu
const TRANSPORT = path self ./sync-transport.nu
# protected-conflicts is enforced in sync-down-local.nu even with --force.
def main [--prune --force --allow-protected --source-only --discard-source] {
    mut args = ["pull"]
    if $prune { $args = ($args | append "--prune") }
    if $force { $args = ($args | append "--force") }
    if $allow_protected { $args = ($args | append "--allow-protected") }
    if $source_only { $args = ($args | append "--source-only") }
    if $discard_source { $args = ($args | append "--discard-source") }
    let exe = $nu.current-exe
    ^$exe --no-config-file $TRANSPORT ...$args
    if ($env.LAST_EXIT_CODE | default 1) != 0 { error make { msg: "Pull stopped; inspect the reported conflict or transport error." } }
}
