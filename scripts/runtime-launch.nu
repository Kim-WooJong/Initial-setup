#!/usr/bin/env nu
# Bootstrap wrappers use this after preparing a seed Nushell installation.
const RUNTIME = path self ./modules/nu-runtime.nu
use $RUNTIME [runtime-execute runtime-ensure]
def --wrapped main [--prepare --check ...args: string] {
    # Wrapped commands forward unknown flags; handle launcher help before any
    # runtime selection or registry access, while preserving child --help argv.
    if not ($args | is-empty) and (($args | first) in ["--help" "-h"]) {
        print "Usage: nu scripts/runtime-launch.nu [--prepare] [--check] <script> ...args"
        return
    }
    if $prepare { return ((runtime-ensure --read-only=$check).exe | into string) }
    if ($args | is-empty) { error make {msg: "Supply a script path followed by its arguments."} }
    runtime-execute ($args | first) ($args | skip 1)
}
