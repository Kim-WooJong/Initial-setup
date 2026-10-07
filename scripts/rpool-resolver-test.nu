#!/usr/bin/env nu
const RPOOL = path self ./modules/rpool-sync.nu
const CORE = path self ./modules/core.nu
use $RPOOL [resolve-rpool-executable capture-rpool-config restore-rpool-config rpool-local-hash]
use $CORE [machine-config-path]

def check [ok: bool label: string] {
    if not $ok { error make {msg: $label} }
    print ("[pass] " + $label)
}
def rejected [operation: closure] { try { do $operation | ignore; false } catch { true } }
def tests [base: path] {
    let tools = ($base | path join "workspace" "initial-setup")
    let sibling = ($base | path join "workspace" "rpool")
    let binary = ($base | path join "app with spaces" "rpool")
    let bundle_root = ($base | path join "private")
    mkdir $tools $sibling ($binary | path dirname) ($bundle_root | path join "rpool") ((machine-config-path) | path dirname)
    {tools_root: $tools} | save (machine-config-path)
    '{}' | save ($bundle_root | path join "rpool" "portable-config.json")
    '#!/bin/sh
case "$1 $2" in
"config --help") echo "export import";;
"config export") echo "{}" > "$3";;
"config import") exit 0;;
esac
' | save $binary
    ^/bin/chmod +x $binary
    let bin_dir = ($binary | path dirname)
    cp $binary ($bin_dir | path join "rclone")
    let snippet = ($base | path join "sync-tools.nu")
    const template = path self ../templates/sync-tools.nu.example
    open --raw $template | str replace 'C:\Tools\rpool' $bin_dir | save $snippet
    with-env {RPOOL_BIN: "stale-override" PATH: "/usr/bin:/bin"} {
        let code = ('source ' + ($snippet | to nuon) + '; source ' + ($snippet | to nuon) + '; {override: ($env.RPOOL_BIN? | default ""), paths: $env.PATH} | to json')
        let loaded = (^$nu.current-exe --no-config-file -c $code | from json)
        check ($loaded.override == "") "Configuration snippet removes stale override"
        check (($loaded.paths | where {|p| $p == $bin_dir} | length) == 1) "Reloading snippet does not duplicate PATH"
    }
    with-env {RPOOL_BIN: "" PATH: ($bin_dir + ":/usr/bin:/bin")} {
        check ((resolve-rpool-executable) == $binary) "Shared PATH directory resolves rpool"
        check ((which rclone --all | where type == "external" | first | get path) == ($bin_dir | path join "rclone")) "Same PATH directory resolves rclone"
        check ((capture-rpool-config $bundle_root).status == "unchanged") "PATH-selected executable captures settings"
        check ((restore-rpool-config $bundle_root).status == "restored") "PATH-selected executable restores settings"
        let child = (^$nu.current-exe --no-config-file -c '[(which rpool | first | get path) (which rclone | first | get path)] | to json' | from json)
        check ($child == [$binary ($bin_dir | path join "rclone")]) "No-config child inherits both executable paths with spaces"
    }
    with-env {RPOOL_BIN: $binary PATH: "/usr/bin:/bin"} {
        check ((resolve-rpool-executable) == $binary) "Explicit executable containing spaces resolves"
        check ((capture-rpool-config $bundle_root).status == "unchanged") "Explicit off-PATH executable exports"
        check ((restore-rpool-config $bundle_root).status == "restored") "Same off-PATH executable imports"
        check ((rpool-local-hash) != "UNAVAILABLE") "Fingerprint uses explicit executable"
    }
    with-env {RPOOL_BIN: ($base | path join "missing") PATH: "/usr/bin:/bin"} {
        check (rejected { resolve-rpool-executable }) "Invalid override fails without fallback"
    }
    with-env {RPOOL_BIN: "relative/rpool" PATH: "/usr/bin:/bin"} {
        check (rejected { resolve-rpool-executable }) "Relative override fails"
    }
    cp $binary ($sibling | path join "rpool")
    with-env {RPOOL_BIN: "" PATH: "/usr/bin:/bin"} {
        check ((resolve-rpool-executable) == ($sibling | path join "rpool")) "Sibling executable resolves without PATH or cwd dependence"
    }
    rm ($sibling | path join "rpool")
    mkdir ($sibling | path join "target" "release")
    cp $binary ($sibling | path join "target" "release" "rpool")
    with-env {RPOOL_BIN: "" PATH: "/usr/bin:/bin"} {
        check ((resolve-rpool-executable) == ($sibling | path join "target" "release" "rpool")) "Sibling release build resolves"
    }
    rm ($sibling | path join "target" "release" "rpool")
    with-env {RPOOL_BIN: "" PATH: "/usr/bin:/bin"} {
        check ((capture-rpool-config $bundle_root).status == "skipped") "Absent optional application skips capture"
        check (rejected { restore-rpool-config $bundle_root }) "Incoming bundle requires a usable executable"
        check ((open --raw ($bundle_root | path join "rpool" "portable-config.json")) == '{}') "Missing executable preserves synchronized bundle"
        check ((rpool-local-hash) == "UNAVAILABLE") "Absent optional application has unavailable fingerprint"
        let active = if $nu.os-info.name == "macos" { $base | path join "Library" "Application Support" "rpool" } else { $base | path join ".config" "rpool" }
        mkdir $active
        '{}' | save ($active | path join "gui.json")
        check (rejected { capture-rpool-config $bundle_root }) "Active settings without CLI block capture"
        check (rejected { restore-rpool-config $bundle_root }) "Active settings without CLI block restore"
        check (rejected { rpool-local-hash }) "Active settings without CLI block fingerprint"
        rm ($active | path join "gui.json")
    }
    '#!/bin/sh
echo "old unsupported build"
' | save --force $binary
    with-env {RPOOL_BIN: $binary PATH: "/usr/bin:/bin"} {
        check (rejected { capture-rpool-config $bundle_root }) "Unsupported installed build blocks capture"
        check (rejected { restore-rpool-config $bundle_root }) "Unsupported installed build blocks restore"
        check (rejected { rpool-local-hash }) "Unsupported installed build blocks fingerprint"
    }
}
def main [] {
    if $nu.os-info.name == "windows" { print "POSIX executable fixture; Windows requires native executable fixture."; return }
    let base = (($env.TMPDIR? | default "/tmp") | path join ("rpool-resolver-" + (random uuid)))
    mkdir $base
    try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $base XDG_CONFIG_HOME: ($base | path join ".config")} { tests $base }
    } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
}
