#!/usr/bin/env nu
# Offline transaction failures; all state and fault injection stay in a temp copy.
const ROOT = path self ..
const MIGRATE = path self ./migrate-state-transaction.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command]
const VAULT = path self ./modules/vault.nu
use $VAULT [validate-vault-state canonical-vault]

def check [ok: bool message: string] {
    if not $ok { error make {msg: $message} }
    print ("[pass] " + $message)
}

def invoke [script: path home: path] {
    with-env {
        INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $home
        HOME: $home USERPROFILE: $home INITIAL_SETUP_OPERATION_TOKEN: ""
        INITIAL_SETUP_PROVIDER_STATE_SCOPE: ""
    } { run-command $nu.current-exe ["--no-config-file" $script] }
}

def tests [base: path] {
    let vault = {version: 1 identity: "fixture/identity.txt" recipients: ["age1fixture"] entries: [{name: "rclone" local: "fixture/rclone.conf"}]}
    check ((validate-vault-state $vault).status == "migration-required") "Record-table vault entries are valid legacy state"
    check ((canonical-vault $vault).entries == $vault.entries) "Vault migration preserves entry records"
    validate-vault-state ($vault | upsert entries []) | ignore
    for invalid in ["invalid" {name: "rclone"} [1] [{name: "rclone"}] [{name: "bad/name" local: "fixture"}] [{name: "rclone" local: "fixture" last_plaintext_sha256: "bad"}] [{name: "same" local: "a"} {name: "same" local: "b"}]] {
        let rejected = (try { validate-vault-state ($vault | upsert entries $invalid) | ignore; false } catch { true })
        check $rejected "Malformed vault entries remain rejected"
    }
    let home = ($base | path join "home with spaces")
    let state = ($home | path join ".config" "dotfiles")
    let config = ($state | path join "config.nuon")
    let lock = ($state | path join "locks" "operation.lock")
    mkdir $state
    for case in [
        {content: '{schema_version: 999}' expected: "newer than supported"}
        {content: '{schema_version:' expected: "Unable to parse machine config as NUON"}
    ] {
        $case.content | save --force $config
        let result = (invoke $MIGRATE $home)
        check (not $result.ok) "Invalid config fails migration"
        check ($result.stderr | str contains $case.expected) "Original preflight diagnostic survives"
        check (not ($result.stderr | str contains "cant_convert")) "Error reporting does not mask the cause"
        check ((open --raw $config) == $case.content) "Preflight failure preserves original bytes"
        check (not ($lock | path exists)) "Preflight failure releases operation lock"
    }
    rm $config
    let policy = ($state | path join "vault.nuon")
    '{version:' | save $policy
    let parse_failed = (invoke $MIGRATE $home)
    check (not $parse_failed.ok and ($parse_failed.stderr | str contains "Unable to parse vault policy as NUON")) "Malformed vault diagnostic is preserved"
    check (not ($parse_failed.stderr | str contains "cant_convert")) "Vault parse failure is not masked"
    check (not ($lock | path exists)) "Vault parse failure releases operation lock"
    $vault | to nuon | save --force $policy
    let sync = ($state | path join "sync-state.nuon")
    let old = {version: 2 local_hash: ("local" | hash sha256) cloud_hash: ""}
    $old | to nuon | save $sync
    let before = (open --raw $sync | hash sha256)
    let copy = ($base | path join "fixture")
    mkdir $copy
    cp --recursive ($ROOT | path join "scripts") ($copy | path join "scripts")
    cp ($ROOT | path join "SCHEMA_VERSION") ($copy | path join "SCHEMA_VERSION")
    let injected = ($copy | path join "scripts" "migrate-state-transaction.nu")
    let source = (open --raw $injected)
    let marker = '$committed = ($committed | append $row)'
    check ($source | str contains $marker) "Fault injection targets a completed state commit"
    $source | str replace $marker ($marker + (char nl) + '            error make {msg: "fixture failure after commit"}') | save --force $injected
    let failed = (invoke $injected $home)
    check (not $failed.ok and ($failed.stderr | str contains "fixture failure after commit")) "Post-commit failure keeps original diagnostic"
    check ((open --raw $sync | hash sha256) == $before) "Failed transaction restores exact original state bytes"
    let transactions = (glob ($state | path join "state-migration-backups" "transactions" "*" "transaction.nuon"))
    check (($transactions | length) == 1) "Failed transaction records recovery metadata"
    check ((open ($transactions | first)).status == "rolled-back") "Transaction is recorded as rolled back"
    check (not ($lock | path exists)) "Post-commit failure releases operation lock"
    let success = (invoke $MIGRATE $home)
    check $success.ok "Migration succeeds after rollback and can reacquire lock"
    check ((open $sync).schema_version == 3) "Legacy sync state reaches current schema"
    check ((open $sync).local_hash == $old.local_hash) "Schema migration preserves the existing sync baseline"
    check ((open $policy).schema_version == 2) "Vault with record-table entries migrates successfully"
    check ((open $policy).entries == $vault.entries) "Persisted vault entry configuration is preserved"
}

def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("migration-errors-" + (random uuid)))
    mkdir $base
    try { tests $base } catch {|err|
        print --stderr ("[kept] " + $base)
        error make {msg: $err.msg}
    }
    rm --recursive --force $base
}
