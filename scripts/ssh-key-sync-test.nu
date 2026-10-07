#!/usr/bin/env nu
# Age-encrypted SSH key sync: enroll + capture on machine A, restore on a fresh
# machine B sharing the same identity + private source. Requires age/age-keygen;
# skips cleanly otherwise. No real cloud, no user HOME, synthetic keys only.
const SSH = path self ./modules/ssh-key-sync.nu
const PROVIDER = path self ./modules/sync-provider.nu
use $PROVIDER [audit-export workspace-manifest]
use $SSH [ssh-key-add ssh-key-add-all scan-local-private-keys ssh-key-list enrolled-keys capture-ssh-keys prepare-ssh-restore commit-prepared-ssh ssh-keys-verify]

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[ssh-key-sync-test] " + $message)} }
    print ("[pass] " + $message)
}

# Minimal vault + machine config for a given HOME, reusing one shared identity.
def setup-machine [home: path identity: path recipient: string data_root: path] {
    let state = ($home | path join ".config" "dotfiles")
    mkdir $state ($state | path join "age")
    cp $identity ($state | path join "age" "identity.txt")
    {schema_version: 5 tools_root: "/tmp/x" data_root: ($data_root | into string)} | to nuon | save --force ($state | path join "config.nuon")
    {schema_version: 2 identity: (($state | path join "age" "identity.txt") | into string) recipients: [$recipient] entries: []} | to nuon | save --force ($state | path join "vault.nuon")
}

def env-for [home: path] {
    {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($home | into string) HOME: ($home | into string) USERPROFILE: ($home | into string)}
}

def tests [base: path] {
    let data_root = ($base | path join "private")
    let home_a = ($base | path join "A")
    let home_b = ($base | path join "B")
    mkdir $data_root
    let identity = ($base | path join "identity.txt")
    ^age-keygen -o $identity err> ($base | path join "k.log")
    let recipient = (^age-keygen -y $identity | str trim)

    setup-machine $home_a $identity $recipient $data_root
    mkdir ($home_a | path join ".ssh")
    let key_a = ($home_a | path join ".ssh" "id_test")
    "-----BEGIN OPENSSH PRIVATE KEY-----\nFIXTURE-A-NOT-A-REAL-KEY\n-----END OPENSSH PRIVATE KEY-----\n" | save $key_a
    "ssh-ed25519 AAAAFIXTUREpub test\n" | save ($key_a + ".pub")

    # Enroll on A.
    with-env (env-for $home_a) { ssh-key-add $data_root "id_test" }
    check ((enrolled-keys $data_root) == ["id_test"]) "Key is enrolled (published .age)"
    let cipher = ($data_root | path join "secrets" "ssh" "id_test.age")
    check ($cipher | path exists) "Encrypted key published to the private source"
    check (((open --raw $cipher | into binary | bytes at 0..<21 | decode utf-8) == "age-encryption.org/v1")) "Published file is an age ciphertext, not plaintext"

    # Bulk enrollment: several keys plus noise files in ~/.ssh.
    "-----BEGIN OPENSSH PRIVATE KEY-----\nFIXTURE-K2\n-----END OPENSSH PRIVATE KEY-----\n" | save ($home_a | path join ".ssh" "id_second")
    "-----BEGIN OPENSSH PRIVATE KEY-----\nFIXTURE-K3\n-----END OPENSSH PRIVATE KEY-----\n" | save ($home_a | path join ".ssh" "work.key")
    "ssh-ed25519 AAAApub\n" | save ($home_a | path join ".ssh" "id_second.pub")
    "Host *\n  AddKeysToAgent yes\n" | save ($home_a | path join ".ssh" "config")
    "fixture known hosts\n" | save ($home_a | path join ".ssh" "known_hosts")
    "PuTTY-User-Key-File-3: ssh-ed25519\nPrivate-Lines: 1\nfixture\n" | save ($home_a | path join ".ssh" "legacy.ppk")
    let scanned = (with-env (env-for $home_a) { scan-local-private-keys })
    check (($scanned | sort) == ["id_second" "id_test" "work.key"]) "Scanner finds only real private keys (skips .pub/config/known_hosts/.ppk)"
    with-env (env-for $home_a) { ssh-key-add-all $data_root }
    check ((enrolled-keys $data_root) == ["id_second" "id_test" "work.key"]) "add-all enrolls every private key, no duplicates"
    check ((($data_root | path join "secrets" "ssh" "work.key.age") | path exists) and (($data_root | path join "secrets" "ssh" "id_second.age") | path exists)) "add-all published all new keys"
    # Idempotent: running again adds nothing.
    with-env (env-for $home_a) { ssh-key-add-all $data_root }
    check (((enrolled-keys $data_root) | length) == 3) "add-all is idempotent"

    # The published secrets/ssh/<name>.age layout must pass the dotpush audit
    # (this is the exact gate that previously rejected the SSH payload).
    "home" | save ($data_root | path join ".chezmoiroot")
    mkdir ($data_root | path join "home")
    audit-export $data_root
    check (((workspace-manifest $data_root) | get path | where {|p| $p | str starts-with "secrets/ssh/" } | sort) == ["secrets/ssh/id_second.age" "secrets/ssh/id_test.age" "secrets/ssh/work.key.age"]) "Enrolled keys appear in the publish manifest under secrets/ssh"
    # A cloud conflict copy next to the keys must not break the audit.
    "{}" | save ($data_root | path join "secrets" "ssh" "id_test (# Edit conflict 2026-10-06 z #).age")
    audit-export $data_root
    check (((workspace-manifest $data_root) | get path | where {|p| $p | str contains "# Edit conflict" } | is-empty)) "A conflict copy under secrets/ssh is ignored by the publish audit"
    rm ($data_root | path join "secrets" "ssh" "id_test (# Edit conflict 2026-10-06 z #).age")

    # Capture is idempotent when unchanged.
    # Capture is idempotent when unchanged.
    let before = (open --raw $cipher | hash sha256)
    with-env (env-for $home_a) { capture-ssh-keys $data_root }
    check ((open --raw $cipher | hash sha256) == $before) "Unchanged key is not re-encrypted"

    # A real change re-encrypts.
    "-----BEGIN OPENSSH PRIVATE KEY-----\nFIXTURE-A-EDITED\n-----END OPENSSH PRIVATE KEY-----\n" | save --force $key_a
    with-env (env-for $home_a) { capture-ssh-keys $data_root }
    check ((open --raw $cipher | hash sha256) != $before) "Edited key is re-encrypted"

    # Fresh machine B restores the key.
    setup-machine $home_b $identity $recipient $data_root
    mkdir ($home_b | path join ".ssh")
    let key_b = ($home_b | path join ".ssh" "id_test")
    with-env (env-for $home_b) {
        let plan = (prepare-ssh-restore $data_root)
        check ($plan.status == "prepared") "B prepares the restore"
        commit-prepared-ssh $plan | ignore
    }
    check ($key_b | path exists) "B restored the private key"
    check ((open --raw $key_b) == (open --raw $key_a)) "Restored key content matches A"
    let mode = (ls -l $key_b | get 0.mode | into string)
    check ($mode | str ends-with "------") "Restored private key is owner-only"

    # Second pull is a no-op.
    with-env (env-for $home_b) {
        let plan2 = (prepare-ssh-restore $data_root)
        check ($plan2.status == "current") "Repeated pull restores nothing (unchanged)"
    }
    with-env (env-for $home_b) {
        let v = (ssh-keys-verify $data_root)
        check ($v.status == "match") "verify reports match on B"
    }

    # Local divergence on B is detected and backed up on next restore.
    "-----BEGIN OPENSSH PRIVATE KEY-----\nB-LOCAL-DIVERGED\n-----END OPENSSH PRIVATE KEY-----\n" | save --force $key_b
    with-env (env-for $home_b) {
        let v = (ssh-keys-verify $data_root)
        check ($v.status == "differ") "verify detects a diverged local key"
    }
    # A new published version (edit A again, capture) should restore onto B with a backup.
    "-----BEGIN OPENSSH PRIVATE KEY-----\nFIXTURE-A-V3\n-----END OPENSSH PRIVATE KEY-----\n" | save --force $key_a
    with-env (env-for $home_a) { capture-ssh-keys $data_root }
    with-env (env-for $home_b) {
        let plan3 = (prepare-ssh-restore $data_root)
        check ($plan3.status == "prepared") "B restores the newer published key"
        let committed = (commit-prepared-ssh $plan3)
        check (($committed.restored | first | get recovery) != null) "Existing local key was backed up before overwrite"
    }
    check ((open --raw $key_b) == (open --raw $key_a)) "B now matches the newest published key"

    # No-vault machine refuses restore (fail closed).
    let home_c = ($base | path join "C")
    mkdir ($home_c | path join ".config" "dotfiles")
    {schema_version: 5 tools_root: "/tmp/x" data_root: ($data_root | into string)} | to nuon | save ($home_c | path join ".config" "dotfiles" "config.nuon")
    let refused = (with-env (env-for $home_c) { try { prepare-ssh-restore $data_root | ignore; false } catch { true } })
    check $refused "A machine without the vault refuses SSH restore (fail closed)"
}

def main [] {
    if $nu.os-info.name == "windows" { print "[skip] POSIX permission test only."; return }
    let missing = (["age" "age-keygen"] | where {|t| which $t | where type == "external" | is-empty })
    if not ($missing | is-empty) { print $"[skip] ssh-key-sync test needs: ($missing | str join ', ')"; return }
    let created = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-sshkey-" + (random uuid)))
    mkdir $created
    let base = ($created | path expand)
    try { tests $base } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
    print "[ok] ssh-key-sync regressions passed."
}
