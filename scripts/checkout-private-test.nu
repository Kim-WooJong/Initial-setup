#!/usr/bin/env nu
# <checkout>/private holds user settings by default. Release inventories,
# dotupgrade verification, junk cleanup and syntax validation must ignore it.
# Runs on a temporary copy of this checkout; no real settings are used.
const ROOT = path self ..
const UPGRADE = path self ./modules/upgrade.nu
const DATA = path self ./modules/data-root.nu
use $UPGRADE [write-release-manifest verify-release]
use $DATA [default-data-root CHECKOUT_PRIVATE_DIR]

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[checkout-private-test] " + $message)} }
    print ("[pass] " + $message)
}

def tests [base: path] {
    let checkout = ($base | path join "Initial-setup")
    mkdir $checkout
    for entry in (ls --all $ROOT | where {|e| ($e.name | path basename) not-in [".git" "target" $CHECKOUT_PRIVATE_DIR] }) {
        cp --recursive $entry.name $checkout
    }
    check ((default-data-root $checkout) == ($checkout | path join "private")) "Default data root is <checkout>/private"
    check ((open --raw ($checkout | path join ".gitignore")) | str contains "/private/") "private/ is git-ignored"

    write-release-manifest $checkout | ignore
    let private = ($checkout | path join "private")
    mkdir ($private | path join "home" "dot_config" "nushell") ($private | path join "secrets") ($private | path join "rpool" "config")
    "def broken [ {" | save ($private | path join "home" "dot_config" "nushell" "config.nu")
    "fixture ciphertext" | save ($private | path join "secrets" "rclone.age")
    "settings" | save ($private | path join "home" ".DS_Store")
    "{}" | save ($private | path join "rpool" "config" "portable-config.json")

    let verified = (try { verify-release $checkout "" | ignore; true } catch { false })
    check $verified "dotupgrade release verification ignores private/"
    let manifest = (open --raw ($checkout | path join "RELEASE-MANIFEST.json") | from json)
    check ($manifest.files | all {|row| not ($row.path | str starts-with "private/") }) "Release manifest never lists private/"
    write-release-manifest $checkout | ignore
    let regenerated = (open --raw ($checkout | path join "RELEASE-MANIFEST.json") | from json)
    check ($regenerated.files | all {|row| not ($row.path | str starts-with "private/") }) "Regenerated manifest with private/ present excludes it"

    let junk = (do { ^$nu.current-exe --no-config-file ($checkout | path join "scripts" "cleanup-release-junk.nu") --check } | complete)
    check ($junk.exit_code == 0 and not ($junk.stdout | str contains "private")) "Release junk cleanup does not report files in private/"
    check (($private | path join "home" ".DS_Store") | path exists) "Release junk cleanup leaves private/ untouched"

    # An older version saved the checkout's parent as data_root: it is ignored
    # and every command uses <checkout>/private (production rule enforced).
    let home = ($base | path join "home-sandbox")
    mkdir ($home | path join ".config" "dotfiles")
    let config = ($home | path join ".config" "dotfiles" "config.nuon")
    {schema_version: 5 tools_root: ($checkout | into string) data_root: ($base | into string)} | to nuon | save $config
    let fixed = (with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_ENFORCE_PRIVATE: "1" INITIAL_SETUP_HOME_OVERRIDE: $home HOME: $home USERPROFILE: $home} {
        do { ^$nu.current-exe --no-config-file -c ("use " + ($checkout | path join "scripts" "modules" "core.nu" | to nuon) + " [machine-context]; (machine-context).data_root") } | complete
    })
    check (($fixed.stdout | str trim) == ($checkout | path join "private" | into string)) "Saved legacy data_root is replaced by <checkout>/private"
    let dry = (with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $home HOME: $home USERPROFILE: $home} {
        do { ^$nu.current-exe --no-config-file ($checkout | path join "setup.nu") --dry-run --mode auto --profile minimal --config-policy push-local --no-auto-sync } | complete
    })
    let dry_text = ($dry.stdout + $dry.stderr | ansi strip)
    check ($dry.exit_code == 0 and ($dry_text | str contains ($checkout | path join "private" | into string))) "Setup without --data-dir uses <checkout>/private"
    check ((open $config).data_root == ($base | into string)) "Setup dry-run writes nothing"

    let syntax = (do { ^$nu.current-exe --no-config-file ($checkout | path join "scripts" "validate-syntax.nu") --parse-only } | complete)
    check ($syntax.exit_code == 0 and not ($syntax.stdout | str contains "private/")) "Syntax validation skips private/ user Nushell files"
}

def main [] {
    let created = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-private-" + (random uuid)))
    mkdir $created
    let base = ($created | path expand)
    try { tests $base } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
    print "[ok] Checkout private directory exclusions passed."
}
