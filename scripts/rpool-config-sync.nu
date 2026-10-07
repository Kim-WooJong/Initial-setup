#!/usr/bin/env nu

const CORE = path self ./modules/core.nu
const RPOOL = path self ./modules/rpool-sync.nu
use $CORE [machine-context]
use $RPOOL [print-rpool-status capture-rpool-config restore-rpool-config]

def main [--capture --restore --dry-run] {
    if $capture and $restore { error make {msg: "Use either --capture or --restore, not both."} }
    if $capture and $dry_run { error make {msg: "--dry-run applies only to restore/import."} }
    let root = ((machine-context).data_root | path expand)
    if $capture { capture-rpool-config $root | ignore; return }
    if $restore { restore-rpool-config $root --dry-run=$dry_run | ignore; return }
    if $dry_run { restore-rpool-config $root --dry-run | ignore; return }
    print-rpool-status $root
}
