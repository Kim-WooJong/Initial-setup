#!/usr/bin/env nu
# Compatibility alias. Use the version-independent root verify.nu for new runs.
const ENTRY = path self ../verify.nu
def main [--full --offline] {
    mut args = []
    if $full { $args = ($args | append "--full") }
    if $offline { $args = ($args | append "--offline") }
    let exe = $nu.current-exe
    ^$exe --no-config-file $ENTRY ...$args
    exit ($env.LAST_EXIT_CODE | default 1)
}
