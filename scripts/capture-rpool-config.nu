#!/usr/bin/env nu

const CORE = path self ./modules/core.nu
const RPOOL = path self ./modules/rpool-sync.nu
const CONSOLE = path self ./modules/console.nu
use $CORE [machine-context]
use $RPOOL [capture-rpool-config]
use $CONSOLE [print-info print-ok print-warn]

def main [--source-root: string = ""] {
    let context = (machine-context)
    let root = if ($source_root | str trim | is-empty) { $context.data_root | path expand } else { $source_root | path expand }
    let result = (capture-rpool-config $root)
    let secrets = if ($result.secrets? | default false) { " (with age-encrypted crypt secrets)" } else { "" }
    match ($result.status? | default "") {
        "captured" => { print-ok ("rpool portable config captured" + $secrets + ": " + $result.path) }
        "unchanged" => { print-info ("rpool portable config is unchanged" + $secrets + "; existing synchronized bundle was reused.") }
        "skipped" => { print-warn ($result.reason + "; portable config capture skipped on this optional machine.") }
        _ => { null }
    }
}
