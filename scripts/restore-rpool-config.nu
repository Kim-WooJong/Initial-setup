#!/usr/bin/env nu

const CORE = path self ./modules/core.nu
const RPOOL = path self ./modules/rpool-sync.nu
const CONSOLE = path self ./modules/console.nu
use $CORE [machine-context]
use $RPOOL [restore-rpool-config]
use $CONSOLE [print-info print-ok]

def main [--source-root: string = "" --dry-run] {
    let context = (machine-context)
    let root = if ($source_root | str trim | is-empty) { $context.data_root | path expand } else { $source_root | path expand }
    let result = (restore-rpool-config $root --dry-run=$dry_run)
    let crypt = ($result.crypt? | default "")
    match ($result.status? | default "") {
        "restored" => { print-ok ("rpool portable configuration restored." + (if ($crypt | is-empty) { "" } else { " " + $crypt })) }
        "validated" => { print-ok ("rpool portable configuration import preflight succeeded." + (if ($crypt | is-empty) { "" } else { " " + $crypt })) }
        "missing" => { print-info "No synchronized rpool portable config exists yet." }
        _ => { null }
    }
}
