#!/usr/bin/env nu
# Bootstrap wrappers use this after preparing a seed Nushell installation.
const RUNTIME = path self ./modules/nu-runtime.nu
use $RUNTIME [runtime-execute runtime-ensure]
def --wrapped main [--prepare --check ...args: string] {
    if $prepare { return ((runtime-ensure --read-only=$check).exe | into string) }
    if ($args | is-empty) { error make {msg: "Supply a script path followed by its arguments."} }
    runtime-execute ($args | first) ($args | skip 1)
}
