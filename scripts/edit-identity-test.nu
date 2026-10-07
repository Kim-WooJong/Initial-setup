#!/usr/bin/env nu
# Regressions for `dotvault edit-identity` using a fake editor. No real cloud,
# no user HOME. Requires age/age-keygen; skips cleanly when they are missing.
const ROOT = path self ..
const SCRIPT = path self ./edit-identity.nu
const VAULT = path self ./modules/vault.nu
const CORE = path self ./modules/core.nu
use $CORE [machine-config-path]

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[edit-identity-test] " + $message)} }
    print ("[pass] " + $message)
}

# A fake editor: copies $EDIT_CONTENT_FILE over the last argument it is given.
def fake-editor-script [] {
    '#!/bin/sh
for a in "$@"; do t="$a"; done
[ "$t" = "--" ] && exit 0
if [ -n "$EDIT_CONTENT_FILE" ]; then cp "$EDIT_CONTENT_FILE" "$t"; fi
exit ${EDIT_EXIT:-0}
'
}

def invoke [home: path bindir: path content: path --exit: int = 0] {
    with-env {
        INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $home
        HOME: $home USERPROFILE: $home
        PATH: ([$bindir ($env.PATH | path expand)] | flatten | str join (char esep))
        EDIT_CONTENT_FILE: ($content | into string) EDIT_EXIT: ($exit | into string)
    } {
        do { ^$nu.current-exe --no-config-file $SCRIPT --editor fake-editor } | complete
    }
}

def tests [base: path] {
    let home = ($base | path join "home")
    let bindir = ($base | path join "bin")
    mkdir ($home | path join ".config" "dotfiles") $bindir
    let fake = ($bindir | path join "fake-editor")
    fake-editor-script | save $fake
    chmod +x $fake

    # Two distinct real identities.
    let id_a = ($base | path join "idA.txt")
    let id_b = ($base | path join "idB.txt")
    ^age-keygen -o $id_a err> (($base | path join "ka.log"))
    ^age-keygen -o $id_b err> (($base | path join "kb.log"))
    let pub_a = (^age-keygen -y $id_a | str trim)
    let pub_b = (^age-keygen -y $id_b | str trim)
    check (($pub_a | str starts-with "age1") and $pub_a != $pub_b) "Fixture identities generated"

    let identity_path = ($home | path join ".config" "dotfiles" "age" "identity.txt")

    # 1. No vault, no identity file: creates it, derives the key, reports no vault.
    let r1 = (invoke $home $bindir $id_a)
    if $r1.exit_code != 0 { print $r1.stderr }
    check ($r1.exit_code == 0) "edit-identity succeeds with no prior vault"
    check ($identity_path | path exists) "Identity file was created"
    check (($r1.stdout | str contains $pub_a)) "Derived public key is shown"
    check (($r1.stdout + $r1.stderr | str contains "dotvault init")) "User is told to init the vault"
    let mode = (ls -l $identity_path | get 0.mode | into string)
    check ($mode | str ends-with "------") "Identity file is owner-only (no group/other bits)"
    let secret_a = (open --raw $id_a | lines | where {|l| $l | str starts-with "AGE-SECRET-KEY-" } | first)
    check (not (($r1.stdout + $r1.stderr) | str contains $secret_a)) "The actual secret key value is never printed"

    # The file currently holds id_a (from case 1). Alternate the content each
    # time so edit-identity always sees a real change (not a no-op).
    # 2. Vault recipient == the newly edited identity -> match.
    let state = ($home | path join ".config" "dotfiles")
    {schema_version: 5 tools_root: ($ROOT | into string) data_root: ($base | path join "private" | into string)} | to nuon | save --force ($state | path join "config.nuon")
    {schema_version: 2 identity: ($identity_path | into string) recipients: [$pub_b] entries: []} | to nuon | save --force ($state | path join "vault.nuon")
    let r2 = (invoke $home $bindir $id_b)
    check ($r2.exit_code == 0 and ($r2.stdout | str contains "matches the vault recipient")) "Matching identity is reported as a match"
    check ((^age-keygen -y $identity_path | str trim) == $pub_b) "The edited identity content was saved"

    # 3. Editor writes a different identity than the recipient -> mismatch warning.
    let r3 = (invoke $home $bindir $id_a)
    check ($r3.exit_code == 0 and (($r3.stdout + $r3.stderr) | str contains "does NOT match")) "A non-recipient identity is flagged as a mismatch"

    # 4. Editor writes garbage -> not a usable identity.
    let junk = ($base | path join "junk.txt")
    "not an age key" | save $junk
    let r4 = (invoke $home $bindir $junk)
    check ($r4.exit_code == 0 and (($r4.stdout + $r4.stderr) | str contains "not a usable age identity")) "Invalid identity content is rejected with guidance"

    # 5. Editor exits non-zero -> command fails but permissions stay restricted.
    let r5 = (invoke $home $bindir $id_b --exit 1)
    check ($r5.exit_code != 0) "A failing editor makes the command fail"
    let mode5 = (ls -l $identity_path | get 0.mode | into string)
    check ($mode5 | str ends-with "------") "Identity stays owner-only after a failed editor"
}

def main [] {
    if $nu.os-info.name == "windows" { print "[skip] POSIX fake-editor test only."; return }
    let missing = (["age" "age-keygen"] | where {|t| which $t | where type == "external" | is-empty })
    if not ($missing | is-empty) { print $"[skip] edit-identity test needs: ($missing | str join ', ')"; return }
    let created = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-editid-" + (random uuid)))
    mkdir $created
    let base = ($created | path expand)
    try { tests $base } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
    print "[ok] edit-identity regressions passed."
}
