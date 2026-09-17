#!/usr/bin/env nu
# Old terminals can refresh the installed command module without parsing it first.
const RUNTIME = path self ./modules/nu-runtime.nu
const IMPL = path self ./refresh-commands-main.nu
use $RUNTIME [runtime-execute]
def main [--dry-run] {
    let args = if $dry_run { ["--dry-run"] } else { [] }
    runtime-execute $IMPL $args --read-only=$dry_run
}
