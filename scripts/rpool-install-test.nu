#!/usr/bin/env nu
# Regressions for rpool-install. Pure helpers (asset selection, checksum parsing)
# run offline; the real GitHub download runs only when the network and tar are
# available, and installs to a throwaway HOME. No user HOME is touched.
const M = path self ./modules/rpool-install.nu
use $M [select-asset asset-filename version-from-tag sha-for assert-archive-checksum install-rpool rpool-install-check install-dir]

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[rpool-install-test] " + $message)} }
    print ("[pass] " + $message)
}
def rejected [c: closure] { try { do $c; false } catch { true } }

def pure-tests [] {
    check ((select-asset "macos" "aarch64") == {platform: "macos-arm64" ext: "tar.gz" exe: "rpool" gui: "rpool-gui"}) "macOS arm64 asset"
    check ((select-asset "macos" "x86_64").platform == "macos-x86_64") "macOS x86_64 asset"
    check ((select-asset "linux" "x86_64").platform == "linux-x86_64") "Linux x86_64 asset"
    let win = (select-asset "windows" "x86_64")
    check ($win.platform == "windows-x86_64" and $win.ext == "zip" and $win.exe == "rpool.exe" and $win.gui == "rpool-gui.exe") "Windows x86_64 asset (zip, .exe)"
    check (rejected {|| select-asset "linux" "aarch64" }) "Unsupported: Linux ARM errors"
    check (rejected {|| select-asset "windows" "aarch64" }) "Unsupported: Windows ARM errors"
    check (rejected {|| select-asset "freebsd" "x86_64" }) "Unsupported: unknown OS errors"

    check ((asset-filename "v2.14.0" "macos-arm64" "tar.gz") == "rpool-v2.14.0-macos-arm64.tar.gz") "Asset filename format"
    check ((version-from-tag "v2.14.0") == "2.14.0") "Version from tag strips v"

    let sums = "aaaa  rpool-v1-linux-x86_64.tar.gz\n63de0ea32eab05aa4446bb7cb67aebb9bb7b73e9226d908c224c8f40dad7bfcc  rpool-v2.14.0-macos-arm64.tar.gz\n"
    check ((sha-for $sums "rpool-v2.14.0-macos-arm64.tar.gz") == "63de0ea32eab05aa4446bb7cb67aebb9bb7b73e9226d908c224c8f40dad7bfcc") "sha-for picks the matching asset"
    check (rejected {|| sha-for $sums "rpool-v2.14.0-windows-x86_64.zip" }) "sha-for errors when the asset is absent"
}

def checksum-tests [base: path] {
    let archive = ($base | path join "fake.tar.gz")
    "payload" | save $archive
    let real = (open --raw $archive | hash sha256)
    let good = ($real + "  fake.tar.gz\n")
    check ((assert-archive-checksum $archive $good "fake.tar.gz") == $real) "Matching checksum passes"
    let bad = ("0000000000000000000000000000000000000000000000000000000000000000  fake.tar.gz\n")
    check (rejected {|| assert-archive-checksum $archive $bad "fake.tar.gz" }) "Tampered/mismatched checksum aborts"
}

def network-tests [base: path] {
    let reachable = (try { http get --headers ["User-Agent" "x"] "https://api.github.com/repos/Kim-WooJong/RPool/releases/latest" | get tag_name | is-not-empty } catch { false })
    if not $reachable { print "[skip] GitHub not reachable; skipping live install."; return }
    if (which tar | is-empty) { print "[skip] tar unavailable."; return }
    let home = ($base | path join "home")
    mkdir $home
    with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $home HOME: $home USERPROFILE: $home} {
        let r = (install-rpool "v2.14.0")
        check ($r.status == "installed" and $r.version == "2.14.0") "Live install of v2.14.0 succeeds"
        let exe = (install-dir | path join "rpool")
        check (($exe | path exists) and (($exe | path type) == "file")) "rpool binary is a regular file in the resolver path"
        let mode = (ls -l $exe | get 0.mode | into string)
        check ($mode | str contains "x") "Installed rpool is executable"
        check ((install-rpool "v2.14.0").status == "up-to-date") "Re-install of the same version is idempotent"
        let chk = (rpool-install-check "v2.14.0")
        check ($chk.up_to_date and $chk.installed_version == "2.14.0") "--check reports up to date"
    }
}

def main [] {
    pure-tests
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-rpoolinstall-" + (random uuid)) | path expand)
    mkdir $base
    try {
        checksum-tests $base
        if $nu.os-info.name != "windows" { network-tests $base }
    } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
    print "[ok] rpool-install regressions passed."
}
