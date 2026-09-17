#!/usr/bin/env nu
# Focused regression: no cloud API, no real credentials or user's HOME.
# Uses actual age tools when installed; otherwise tests the missing-tool path.
const ROOT = path self ..
const CLI = path self ./secret-vault.nu
const VAULT = path self ./modules/vault.nu
const OUTPUT = path self ./modules/process-output.nu
use $VAULT [vault-command-text]
use $OUTPUT [output-text]

def expect [ok: bool label: string] {
    if not $ok { error make {msg: ("FAILED: " + $label)} }
    print ("[pass] " + $label)
}

def invoke [args: list] {
    let exe = $nu.current-exe
    do { ^$exe --no-config-file $CLI ...$args } | complete
}

def text-regressions [] {
    expect ((vault-command-text "  age1fixture\n" "fixture") == "age1fixture") "Public text is trimmed"
    expect ((vault-command-text ("age1fixture\n" | encode utf-8) "fixture") == "age1fixture") "Valid UTF-8 bytes are decoded strictly"
    let bad = (try { vault-command-text 0x[ff 61] "fixture" | ignore; false } catch { true })
    expect $bad "Malformed UTF-8 cannot become a public key or path"
    let non_text = (try { vault-command-text {secret: "must-not-render"} "fixture" | ignore; false } catch { true })
    expect $non_text "Records are not serialized into vault command data"
}

def fixtures [sandbox: path have_age: bool] {
    let home = ($sandbox | path join "home")
    let state = ($home | path join ".config" "dotfiles")
    let private = ($sandbox | path join "private")
    let policy = ($state | path join "vault.nuon")
    let identity = ($state | path join "age" "identity.txt")
    let operation_lock = ($state | path join "locks" "operation.lock")
    mkdir $state ($private | path join "rclone")
    {schema_version: 5 tools_root: ($ROOT | into string) data_root: ($private | into string)} | to nuon | save ($state | path join "config.nuon")
    # A broken provider and legacy plaintext must not block LOCAL init.
    let provider_file = ($state | path join "sync-provider.nuon")
    "this deliberately is not a provider record" | save $provider_file
    let legacy = ($private | path join "rclone" "rclone.conf")
    "dummy credential fixture, not a real secret" | save $legacy
    let legacy_hash = (open --raw $legacy | hash sha256)
    let provider_hash = (open --raw $provider_file | hash sha256)

    let unknown = (invoke ["invalid-vault-test-action"])
    expect ($unknown.exit_code != 0) "Unknown action is rejected before taking a lock"
    expect (not ($operation_lock | path exists)) "Invalid action does not strand a lock"

    let check = (invoke ["init" "--check"])
    expect (not ($operation_lock | path exists)) "Read-only check does not acquire operation.lock"
    expect (not ($policy | path exists) and not (($state | path join "age") | path exists)) "Read-only check does not create policy or identity directory"
    if not $have_age {
        expect ($check.exit_code != 0) "Missing age tools cause preflight to fail"
        expect (($check.stderr | output-text) | str contains "VAULT_DEPENDENCY_MISSING") "Missing tools are diagnosed rather than a provider error"
        let actual = (invoke ["init"])
        expect ($actual.exit_code != 0) "Init exits nonzero with missing tools"
        expect (($actual.stderr | output-text) | str contains "VAULT_DEPENDENCY_MISSING") "The original dependency diagnostic survives CLI cleanup"
        expect (not ($operation_lock | path exists)) "Failed init releases its own operation lock"
        expect (not ($policy | path exists) and not (($state | path join "age") | path exists)) "Missing tools do not leave a partially initialized vault"
        print "[skip] Real key creation and retry tests need age AND age-keygen. They were not run."
    } else {
        if $check.exit_code != 0 { print --stderr ($check.stderr | output-text) }
        expect ($check.exit_code == 0) "Preflight succeeds with real age tools despite broken provider config"
        let init = (invoke ["init"])
        if $init.exit_code != 0 { print --stderr ($init.stderr | output-text) }
        expect ($init.exit_code == 0) "Init succeeds independently of provider and plaintext export guards"
        expect (($policy | path type) == "file" and ($identity | path type) == "file") "Key and policy are regular files"
        expect (not ($operation_lock | path exists)) "Successful init releases its own operation lock"
        let key_hash = (open --raw $identity | hash sha256)
        let policy_hash = (open --raw $policy | hash sha256)
        let repeated = (invoke ["init"])
        expect ($repeated.exit_code != 0 and (($repeated.stderr | output-text) | str contains "VAULT_ALREADY_EXISTS")) "Repeated init requires explicit policy editing"
        expect ((open --raw $identity | hash sha256) == $key_hash and (open --raw $policy | hash sha256) == $policy_hash) "Repeated init replaces neither key nor policy"
        expect (not ($operation_lock | path exists)) "Repeated-init error does not strand a lock"
        # Only this isolated fixture's policy is removed, to model interrupted
        # initialization AFTER key generation but BEFORE policy commit.
        rm $policy
        let retry = (invoke ["init"])
        if $retry.exit_code != 0 { print --stderr ($retry.stderr | output-text) }
        expect ($retry.exit_code == 0) "Retry can reuse an existing identity after interrupted initialization"
        expect ((open --raw $identity | hash sha256) == $key_hash) "Retry does not regenerate the identity"
        let loaded = (open --raw $policy | from nuon)
        expect (($loaded.recipients | length) == 1) "Policy records one public recipient"
        expect (not ($operation_lock | path exists)) "Retry releases operation.lock"
        if $nu.os-info.name != "windows" {
            let p = (do { ^stat -c %a $policy } | complete)
            if $p.exit_code == 0 { expect (($p.stdout | output-text | str trim) == "600") "Policy keeps owner-only mode after staged rename" }
        }
    }
    expect ((open --raw $legacy | hash sha256) == $legacy_hash) "Init never migrates or removes legacy credentials"
    expect ((open --raw $provider_file | hash sha256) == $provider_hash) "Init does not rewrite provider configuration"
    expect (not (($state | path join "provider-state.nuon") | path exists)) "Init does not approve a provider baseline"
}

def main [--require-age --keep] {
    text-regressions
    let have_age = (not (which age | is-empty) and not (which age-keygen | is-empty))
    if $require_age and not $have_age { error make {msg: "age and age-keygen are required for the real initialization tests."} }
    let temp = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand)
    let sandbox = ($temp | path join ("initial-setup-vault-init-" + (random uuid)))
    let home = ($sandbox | path join "home")
    mkdir $home
    try {
        with-env {
            INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($home | into string)
            INITIAL_SETUP_OPERATION_TOKEN: ""
            HOME: ($home | into string) USERPROFILE: ($home | into string)
            APPDATA: ($home | path join "AppData" "Roaming") LOCALAPPDATA: ($home | path join "AppData" "Local")
            XDG_CONFIG_HOME: ($home | path join ".config") XDG_DATA_HOME: ($home | path join ".local" "share")
            XDG_STATE_HOME: ($home | path join ".local" "state") XDG_CACHE_HOME: ($home | path join ".cache")
            RCLONE_CONFIG: ($sandbox | path join "unused-rclone.conf")
        } { fixtures $sandbox $have_age }
        if $keep { print ("[kept] " + ($sandbox | into string)) } else { rm --recursive --force $sandbox }
    } catch {|err|
        # Contains only generated fixture keys/dummy paths, never user credentials.
        print --stderr ("[kept] Failed fixture directory: " + ($sandbox | into string))
        error make $err
    }
    print "[ok] All available vault-init tests passed; any skipped cases are listed above."
}
