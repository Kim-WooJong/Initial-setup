#!/usr/bin/env nu
# Offline fixtures. This suite NEVER queries a registry or installs a real crate.
const RUNTIME = path self ./modules/nu-runtime.nu
const LAUNCHER = path self ./runtime-launch.nu
const ROOT = path self ..
use $RUNTIME [runtime-version-compare runtime-release runtime-root runtime-cargo-home runtime-build-args runtime-cache runtime-probe runtime-session-valid runtime-ensure runtime-install]

def expect [ok: bool message: string] {
    if not $ok { error make {msg: ("FAILED: " + $message)} }
    print ("[pass] " + $message)
}
def rejects [action: closure label: string] {
    let failed = (try { do $action | ignore; false } catch { true })
    expect $failed $label
}
def index-text [rows: list] { $rows | each {|row| $row | to json --raw } | str join (char nl) }

def tests [sandbox: path] {
    for row in [
        {a: "0.99.9" b: "0.100.0" expected: (-1)}
        {a: "0.114.9" b: "0.114.12" expected: (-1)}
        {a: "0.114.12" b: "0.114.9" expected: 1}
        {a: "0.12.32" b: "0.13.0" expected: (-1)}
        {a: "0.13.0" b: "0.12.99" expected: 1}
        {a: "1.0.0" b: "0.999.0" expected: 1}
        {a: "1.0.0" b: "1.0.0" expected: 0}
    ] { expect ((runtime-version-compare $row.a $row.b) == $row.expected) ("Version comparison " + $row.a + " / " + $row.b) }
    let base = {name: "nu" vers: "0.114.0" yanked: false cksum: ("source" | hash sha256) rust_version: "1.85"}
    let index = (index-text [
        $base
        ($base | upsert vers "0.114.9")
        ($base | upsert vers "0.114.12")
        ($base | upsert vers "9.0.0-rc.1")
        ($base | upsert vers "0.115.0" | upsert yanked true)
        ($base | upsert vers "0.113.0")
    ])
    let release = (runtime-release $index)
    expect ($release.version == "0.114.12") "Newest stable non-yanked crate selected numerically, independent of row order"
    expect ($release.rust_version == "1.85") "MSRV is retained for compiler validation"
    rejects { runtime-release "not-json" } "Invalid registry response cannot become a version"
    rejects { runtime-release (index-text [($base | upsert name "other")]) } "Wrong crate rejected"
    rejects { runtime-release (index-text [($base | upsert cksum "")]) } "Missing registry checksum rejected"
    rejects { runtime-release (index-text [($base | upsert yanked true)]) } "Yanked-only registry rejected"
    rejects { runtime-release (index-text [($base | upsert vers "0.108.0")]) } "Result below runtime baseline rejected"
    let destination = ($sandbox | path join "Cargo [한글] install")
    let args = (runtime-build-args $release $destination "x86_64-pc-windows-msvc")
    expect ($args == ["install" "nu" "--locked" "--version" "0.114.12" "--bin" "nu" "--registry" "crates-io" "--root" ($destination | into string) "--target" "x86_64-pc-windows-msvc"]) "Exact Cargo arguments preserve path boundaries"
    expect ("--force" not-in $args and "--ignore-rust-version" not-in $args and "--git" not-in $args) "No forced replacement, MSRV bypass or moving Git source"
    let selected = (runtime-ensure)
    expect ($selected.exe == $nu.current-exe and not $selected.checked) "Isolated test mode never fetches or installs"
    expect (not ((runtime-root) | path exists)) "Read-only selection creates no runtime store"
    # Exercise read-only selection OUTSIDE the fixture shortcut. The isolated HOME
    # has no cached receipt; this must choose the current supported interpreter.
    with-env {INITIAL_SETUP_TEST_MODE: "0" CARGO_HOME: ($sandbox | path join "offline-cargo") INITIAL_SETUP_NU_SESSION_EXE: "" INITIAL_SETUP_NU_SESSION_PROVIDER: ""} {
        let offline = (runtime-ensure --read-only)
        expect ($offline.exe == $nu.current-exe and not $offline.checked) "Read-only diagnostics do not require a registry lookup"
    }
    with-env {INITIAL_SETUP_NU_SESSION_EXE: ($nu.current-exe | into string) INITIAL_SETUP_NU_SESSION_VERSION: (version).version INITIAL_SETUP_NU_SESSION_PROVIDER: "github"} {
        expect (not (runtime-session-valid)) "Old GitHub session cannot skip Cargo migration"
    }
    with-env {INITIAL_SETUP_NU_SESSION_EXE: ($nu.current-exe | into string) INITIAL_SETUP_NU_SESSION_VERSION: (version).version INITIAL_SETUP_NU_SESSION_PROVIDER: "cargo-v1"} {
        expect (runtime-session-valid) "Matching child invocation reuses its selection"
    }
    let echo = ($sandbox | path join "echo [한글].nu")
    'def --wrapped main [...args: string] { $args | to json --raw }' | save $echo
    let argv = ["space value" "한글" 'literal$(echo no)' 'a;b' "--opaque"]
    let exe = $nu.current-exe
    let result = (do { ^$exe --no-config-file $LAUNCHER $echo ...$argv } | complete)
    expect ($result.exit_code == 0 and ($result.stdout | from json) == $argv) "Real launcher preserves argv"
    let failure = ($sandbox | path join "exit.nu")
    'def main [] { print "child output"; exit 37 }' | save $failure
    let failed = (do { ^$exe --no-config-file $LAUNCHER $failure } | complete)
    expect ($failed.exit_code == 37) "Child exit code is propagated"
    expect ($failed.stdout | str contains "child output") "Child output is streamed rather than treated as a result record"
    for name in ["setup.nu" "scripts/sync-transport.nu" "scripts/auto-sync.nu" "scripts/refresh-commands.nu" "scripts/update-nushell.nu"] {
        let help = (do { ^$exe --no-config-file ($ROOT | path join $name) --help } | complete)
        expect ($help.exit_code == 0) ("Minimal entry parses: " + $name)
    }
    # Fake rustup executes local filesystem fixtures only; no Rust/Cargo required.
    # Windows compiler/process integration needs a real Windows test separately.
    if $nu.os-info.name == "windows" { print "[skip] POSIX fake-compiler fixture; use a Windows Cargo integration run."; return }
    let bin = ((runtime-cargo-home) | path join "bin")
    mkdir $bin
    let fake = ($bin | path join "rustup")
    r#'#!/bin/sh
set -eu
printf "%s\n" "$*" >> "$NU_CARGO_TEST_LOG"
if [ "$1" = "toolchain" ]; then exit 0; fi
shift 2
if [ "$1" = "rustc" ]; then printf "release: 99.0.0\nhost: x86_64-unknown-linux-gnu\n"; exit 0; fi
[ "$1" = "cargo" ] || exit 66
[ "${NU_CARGO_TEST_FAIL:-0}" = 0 ] || exit 37
root=""; version=""
while [ "$#" -gt 0 ]; do
 case "$1" in --root) root="$2"; shift 2;; --version) version="$2"; shift 2;; *) shift;; esac
done
mkdir -p "$root/bin"
cp "$NU_CARGO_TEST_EXE" "$root/bin/nu"
printf '{"installs":{"nu %s (registry+https://github.com/rust-lang/crates.io-index)":{"bins":["nu"]}}}\n' "$version" > "$root/.crates2.json"
'# | save $fake
    ^chmod +x $fake
    let sample = {version: (version).version checksum: ("fake-source" | hash sha256) rust_version: "1.85"}
    let logfile = ($sandbox | path join "cargo-argv.log")
    with-env {NU_CARGO_TEST_LOG: $logfile NU_CARGO_TEST_EXE: ($nu.current-exe | into string) NU_CARGO_TEST_FAIL: "0"} {
        let built = (runtime-install $sample)
        expect ($built | path exists) "Fake Cargo installation was verified and promoted"
        let root = (runtime-root)
        let before = (open --raw $logfile)
        expect ((runtime-install $sample) == $built) "Exact validated cache reused"
        expect ((open --raw $logfile) == $before) "Cache reuse does not invoke compiler or rustup"
        let pointer = ($root | path join "current.json")
        let pointer_hash = (open --raw $pointer | hash sha256)
        with-env {NU_CARGO_TEST_FAIL: "1"} {
            rejects { runtime-install ($sample | upsert version "99.0.0") } "Cargo build failure stops promotion"
        }
        expect ((open --raw $pointer | hash sha256) == $pointer_hash) "Failed build preserves previous receipt"
        expect ($built | path exists) "Failed build preserves previous runtime"
        let saved = (open --raw $pointer | from json)
        ($saved | upsert directory "../escape") | to json | save --force $pointer
        rejects { runtime-cache $root $sample } "Receipt path traversal rejected before execution"
        $saved | to json | save --force $pointer
        ($saved | upsert binary_sha256 ("bad" | hash sha256)) | to json | save --force $pointer
        rejects { runtime-cache $root $sample } "Changed binary checksum rejected before execution"
    }
}

def main [] {
    let temp = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp"))
    let sandbox = ($temp | path join ("initial-setup-cargo-test-" + (random uuid)))
    mkdir $sandbox
    try {
        with-env {
            INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $sandbox
            HOME: $sandbox USERPROFILE: $sandbox LOCALAPPDATA: ($sandbox | path join "Local")
            INITIAL_SETUP_NU_SESSION_EXE: "" INITIAL_SETUP_NU_SESSION_VERSION: "" INITIAL_SETUP_NU_SESSION_PROVIDER: ""
        } { tests $sandbox }
    } catch {|err|
        print --stderr ("[kept] Runtime fixture: " + $sandbox)
        error make {msg: ($err.msg? | default "Cargo runtime regression failed.")}
    }
    rm --recursive --force $sandbox
    print "[ok] Offline Cargo/runtime regressions passed. A real registry/compiler integration is a separate test."
}
