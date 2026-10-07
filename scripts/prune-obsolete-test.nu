#!/usr/bin/env nu
# Overlay-copy workflow: obsolete release files are pruned, while private/,
# .git/ and local build output are never touched. Uses a temporary copy.
const ROOT = path self ..
const UPGRADE = path self ./modules/upgrade.nu
use $UPGRADE [write-release-manifest verify-release]

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[prune-obsolete-test] " + $message)} }
    print ("[pass] " + $message)
}

def prune [checkout: path args: list] {
    do { ^$nu.current-exe --no-config-file ($checkout | path join "scripts" "prune-obsolete.nu") ...$args } | complete
}

def tests [base: path] {
    let checkout = ($base | path join "Initial-setup")
    mkdir $checkout
    for entry in (ls --all $ROOT | where {|e| ($e.name | path basename) not-in [".git" "private"] }) {
        cp --recursive $entry.name $checkout
    }
    if (($checkout | path join "tools" "cloudwins" "target") | path exists) { rm --recursive --force ($checkout | path join "tools" "cloudwins" "target") }
    write-release-manifest $checkout | ignore

    let r = (prune $checkout ["--json"])
    check ($r.exit_code == 0 and (($r.stdout | from json).obsolete | is-empty)) "A clean release copy has nothing to prune"

    # Leftovers of an older release plus user/local data that must stay.
    mkdir ($checkout | path join "docs" "old-topic" "deep") ($checkout | path join "private" "home") ($checkout | path join ".git") ($checkout | path join "tools" "cloudwins" "target" "release")
    "old" | save ($checkout | path join "scripts" "removed-in-new-release.nu")
    "old" | save ($checkout | path join "docs" "old-topic" "deep" "page.md")
    "settings" | save ($checkout | path join "private" "home" "dot_gitconfig")
    "ref: refs/heads/main" | save ($checkout | path join ".git" "HEAD")
    "binary" | save ($checkout | path join "tools" "cloudwins" "target" "release" "cloudwins")

    let preview = (prune $checkout ["--json"])
    let report = ($preview.stdout | from json)
    check ($preview.exit_code == 0 and $report.obsolete == ["docs/old-topic/deep/page.md" "scripts/removed-in-new-release.nu"]) "Preview lists exactly the obsolete release files"
    check (($checkout | path join "scripts" "removed-in-new-release.nu") | path exists) "Preview deletes nothing"
    check (($report.missing | is-empty) and ($report.modified | is-empty)) "Complete copy reports no missing/modified files"

    let r = (prune $checkout ["--execute"])
    check ($r.exit_code == 0) "Prune --execute succeeds"
    check (not (($checkout | path join "scripts" "removed-in-new-release.nu") | path exists)) "Obsolete script is deleted"
    check (not (($checkout | path join "docs" "old-topic") | path exists)) "Folders emptied by pruning are removed"
    check ((open --raw ($checkout | path join "private" "home" "dot_gitconfig")) == "settings") "private/ is never touched"
    check (($checkout | path join ".git" "HEAD") | path exists) ".git/ is never touched"
    check (($checkout | path join "tools" "cloudwins" "target" "release" "cloudwins") | path exists) "Local build output is never touched"
    rm --recursive --force ($checkout | path join ".git") ($checkout | path join "tools" "cloudwins" "target")
    check ((try { verify-release $checkout "" | get version } catch { "" }) != "") "After pruning, the folder verifies as the exact release"

    rm ($checkout | path join "scripts" "verify-sync.nu")
    "tampered" | save --force ($checkout | path join "README.md")
    let partial = ((prune $checkout ["--json"]).stdout | from json)
    check ($partial.missing == ["scripts/verify-sync.nu"] and $partial.modified == ["README.md"]) "Incomplete or altered copies are reported"

    "0.0.1" | save --force ($checkout | path join "VERSION")
    let mixed = (prune $checkout ["--execute"])
    check ($mixed.exit_code != 0) "VERSION/manifest mismatch refuses to prune"
}

def main [] {
    let created = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-prune-" + (random uuid)))
    mkdir $created
    let base = ($created | path expand)
    try { tests $base } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
    print "[ok] Prune-obsolete regressions passed."
}
