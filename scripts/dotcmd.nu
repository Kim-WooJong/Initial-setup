#!/usr/bin/env nu
# Checkout-side command runner for the installed command shim.
#
# The shim in ~/.config/nushell/modules/dotfiles.nu forwards every command as
#   dotcmd.nu <shim_version> <signatures_hash> <command name> ...raw args
# This runner loads this checkout's dotfiles.nu, converts the raw arguments by
# the real signature, and runs the command, so checkout updates take effect
# without re-running setup. `dotcmd.nu __signatures` prints the signatures used
# to generate the shim.
const DOTFILES = path self ./modules/dotfiles.nu
const COMMAND_RUNTIME = path self ./modules/command-runtime.nu
use $DOTFILES *
use $COMMAND_RUNTIME [COMMAND_SHIM_VERSION command-signatures command-signatures-hash]

def current-signatures [] {
    let names = (scope modules | where name == "dotfiles" | first | get commands.name)
    command-signatures (scope commands | where name in $names)
}

def fail [message: string] {
    print --stderr $"(ansi red)($message)(ansi reset)"
    exit 2
}

def coerce [value: string shape: string label: string] {
    match $shape {
        "int" => {
            let parsed = (try { $value | into int } catch { fail $"($label) expects an integer, got: ($value)" })
            $parsed | to nuon
        }
        _ => { $value | to nuon }
    }
}

# Rebuild a Nushell call from raw tokens. Values are emitted as NUON literals,
# so arbitrary text can never be interpreted as code.
def build-call [sig: record args: list<string>] {
    let flags = ($sig.params | where kind in ["named" "switch"])
    let positionals = ($sig.params | where kind == "positional")
    mut out = [($sig.name)]
    mut next_positional = 0
    mut i = 0
    mut only_positional = false
    while $i < ($args | length) {
        let token = ($args | get $i)
        $i += 1
        if not $only_positional and $token == "--" { $only_positional = true; continue }
        let long = if $only_positional { [] } else { $token | parse --regex '^--(?<name>[A-Za-z][A-Za-z0-9_-]*)(?:=(?<value>.*))?$' }
        let short = if $only_positional { [] } else { $token | parse --regex '^-(?<name>[A-Za-z])$' }
        if not ($long | is-empty) or not ($short | is-empty) {
            let found = if not ($long | is-empty) {
                $flags | where name == ($long | first | get name)
            } else {
                $flags | where short == ($short | first | get name)
            }
            if ($found | is-empty) {
                if $token in ["--help" "-h"] { $out = ($out | append "--help"); continue }
                fail $"Unknown flag for ($sig.name): ($token). See `($sig.name) --help`."
            }
            let flag = ($found | first)
            let inline = if ($long | is-empty) { null } else { $long | first | get value? }
            if $flag.kind == "switch" {
                if $inline != null and not ($inline | is-empty) { fail $"Switch --($flag.name) does not take a value." }
                $out = ($out | append ("--" + $flag.name))
                continue
            }
            let value = if $inline != null and not ($inline | is-empty) { $inline } else {
                if $i >= ($args | length) { fail $"Flag --($flag.name) needs a value." }
                let v = ($args | get $i)
                $i += 1
                $v
            }
            $out = ($out | append ("--" + $flag.name) | append (coerce $value $flag.shape $"--($flag.name)"))
            continue
        }
        if $next_positional >= ($positionals | length) { fail $"Too many arguments for ($sig.name): ($token)" }
        let param = ($positionals | get $next_positional)
        $next_positional += 1
        $out = ($out | append (coerce $token $param.shape $param.name))
    }
    $out | str join " "
}

def --wrapped main [...argv: string] {
    let sigs = (current-signatures)
    if ($argv | first | default "") == "__signatures" {
        print ($sigs | to nuon)
        return
    }
    if ($argv | first | default "") in ["--help" "-h"] {
        print "Internal runner for the installed Initial-setup command shim. Use dotctl/dotpush/dotpull etc. from Nushell."
        return
    }
    if ($argv | length) < 3 { fail "Internal command runner: invoke Initial-setup commands through the installed shim." }
    let shim_version = ($argv | get 0)
    let shim_hash = ($argv | get 1)
    let name = ($argv | get 2)
    let args = ($argv | skip 3)
    let refresh = ("nu --no-config-file " + (($DOTFILES | path dirname | path dirname | path join "refresh-commands.nu") | to nuon) + ", then restart Nushell")

    if $shim_version != $COMMAND_SHIM_VERSION or $shim_hash != (command-signatures-hash $sigs) {
        print --stderr $"(ansi yellow)[warn](ansi reset) Installed Initial-setup commands are older than this checkout \(new/changed commands or flags\). Run: ($refresh)."
    }
    let found = ($sigs | where name == $name)
    if ($found | is-empty) { fail $"`($name)` is not provided by this checkout. Run: ($refresh)." }
    let call = (build-call ($found | first) $args)
    exec $nu.current-exe --no-config-file -c $"use ($DOTFILES | to nuon) *\n($call)"
}
