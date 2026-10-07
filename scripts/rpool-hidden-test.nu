#!/usr/bin/env nu
const PROVIDER = path self ./modules/sync-provider.nu
const SAFETY = path self ./modules/safety.nu
use $PROVIDER [audit-export workspace-manifest workspace-hash copy-workspace install-workspace]
use $SAFETY [verify-tree]

def expect [ok: bool message: string] {
    if not $ok { error make {msg: $message} }
    print ("PASS: " + $message)
}

def suite [base: path] {
    let source = ($base | path join source)
    let snapshot = ($base | path join snapshot)
    mkdir ($source | path join rpool .git objects)
    mkdir ($source | path join rpool nested .cache)
    "{}" | save ($source | path join rpool portable-config.json)
    "home" | save ($source | path join .chezmoiroot)
    "{}" | save ($source | path join .dotfiles-sync-meta.nuon)
    let before = (workspace-hash $source)
    "local metadata" | save ($source | path join rpool .gitignore)
    "ignored" | save ($source | path join rpool .git objects fixture)
    "ignored" | save ($source | path join rpool nested .cache fixture)
    expect ((workspace-hash $source) == $before) "Hidden descendants do not affect hash"
    audit-export $source
    let entries = (copy-workspace $source $snapshot)
    expect (not ($snapshot | path join rpool .gitignore | path exists)) "Hidden files are not copied"
    expect (($entries | get path | length) == 3) "Managed config and protocol files remain"
    "unexpected" | save ($source | path join rpool extra.txt)
    let rejected = (try { audit-export $source; false } catch { true })
    expect $rejected "Visible unexpected rpool files remain rejected"
    rm ($source | path join rpool extra.txt)
    # A cloud-sync conflict copy of a managed file must be ignored (not rejected,
    # not transported): one stray copy must not block every sync.
    mkdir ($source | path join rpool config)
    let conflict = "portable-config (# Edit conflict 2026-10-06 abc #).json"
    "{}" | save ($source | path join rpool config $conflict)
    audit-export $source
    let entries_c = (copy-workspace $source ($base | path join snapc))
    expect (not (($base | path join snapc rpool config $conflict) | path exists)) "Cloud conflict copies are not transported"
    expect (($entries_c | get path | where {|p| $p | str contains "# Edit conflict" } | is-empty)) "Conflict copies are absent from the manifest"
    rm --recursive --force ($source | path join rpool config)
    "injected" | save ($snapshot | path join rpool .injected)
    let rejected_snapshot = (try { verify-tree $snapshot $entries; false } catch { true })
    expect $rejected_snapshot "Transport verification rejects hidden injection"
    rm ($snapshot | path join rpool .injected)
    mkdir ($snapshot | path join rpool docs)
    "# Guide" | save ($snapshot | path join rpool docs GUIDE.MD)
    "# Old" | save ($source | path join rpool old.md)
    ("AGE-SECRET-" + "KEY-fixture") | save ($snapshot | path join rpool bad.md)
    let rejected_key = (try { audit-export $snapshot; false } catch { true })
    expect $rejected_key "Markdown private-key markers remain rejected"
    rm ($snapshot | path join rpool bad.md)
    audit-export $snapshot
    '{"updated":true}' | save --force ($snapshot | path join rpool portable-config.json)
    install-workspace {data_root: $source} $snapshot | ignore
    expect ((open --raw ($source | path join rpool docs GUIDE.MD)) == "# Guide") "Nested Markdown is installed"
    expect (not ($source | path join rpool old.md | path exists)) "Stale Markdown is removed"
    expect ((open --raw ($source | path join rpool .gitignore)) == "local metadata") "Pull preserves local hidden files"
    expect ($source | path join rpool .git objects fixture | path exists) "Pull preserves local hidden directories"
    expect ((open --raw ($source | path join rpool portable-config.json)) == '{"updated":true}') "Pull replaces managed config"
    rm ($snapshot | path join rpool portable-config.json)
    rm ($snapshot | path join rpool docs GUIDE.MD)
    install-workspace {data_root: $source} $snapshot | ignore
    expect (not ($source | path join rpool docs GUIDE.MD | path exists)) "Removed Markdown is reconciled"
    expect (not ($source | path join rpool portable-config.json | path exists)) "Pull removes absent managed config"
    expect ($source | path join rpool .gitignore | path exists) "Managed deletion preserves hidden metadata"
}

def main [] {
    let base = (mktemp -d)
    let result = (try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($base | path join isolated-home)} {
            suite $base
        }
        null
    } catch {|err| $err})
    rm --recursive --force $base
    if $result != null { error make {msg: $result.msg} }
}
