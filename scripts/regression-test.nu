#!/usr/bin/env nu
const PROCESS_OUTPUT = path self ./modules/process-output.nu
use $PROCESS_OUTPUT [output-text]
const TEXT_CASE = path self ./modules/text-case.nu
use $TEXT_CASE [text-lower text-upper case-backend]
# Focused v0.12.11 regressions. No downloads, package installation or live cloud.
const ROOT = path self ..
const TOOLS = path self ./modules/toolchains.nu
const SAFETY = path self ./modules/safety.nu
const PROVIDER = path self ./modules/sync-provider.nu
const CORE = path self ./modules/core.nu
use $TOOLS [parse-tool-version parse-rust-channel parse-julia-channel version-gte]
use $SAFETY [state-root atomic-record operation-lock lock-release]
use $PROVIDER [provider-config-path load-provider workspace-hash remote-lock release-remote-lock]
use $CORE [error-message failure-envelope captured-failure]

def expect [condition: bool message: string] {
    if not $condition { error make {msg: ("FAILED: " + $message)} }
    print ("[pass] " + $message)
}

def child [file: string args: list] {
    let exe = $nu.current-exe
    let script = ($ROOT | path join "scripts" $file)
    do { ^$exe --no-config-file $script ...$args } | complete
}

def language-regressions [] {
    # These are strings on purpose: the rejected fixture is never imported.
    let invalid = 'mut choice = "pull"; let action = {|| $choice }; do $action'
    let valid = 'mut choice = "pull"; let resolved = $choice; let action = {|| $resolved }; do $action'
    expect (not ($invalid | nu-check)) "Mutable-capture fixture is rejected by the running parser"
    expect ($valid | nu-check) "Immutable snapshot fixture is accepted by the running parser"

    # A return keyword takes one value: comparisons must be parenthesized.
    let bad_return = 'def f [a: int b: int] { return $a > $b }'
    let good_return = 'def f [a: int b: int] { return ($a > $b) }'
    expect (not ($bad_return | nu-check)) "Unparenthesized return comparison is rejected"
    expect ($good_return | nu-check) "Parenthesized return comparison is accepted"
    for fixture in [
        {actual: "1.0.0" required: "0.109.1" expected: true}
        {actual: "0.115.1" required: "1.0.0" expected: false}
        {actual: "0.115.1" required: "0.109.1" expected: true}
        {actual: "0.108.9" required: "0.109.1" expected: false}
        {actual: "0.109.2" required: "0.109.1" expected: true}
        {actual: "0.109.0" required: "0.109.1" expected: false}
        {actual: "0.109.1" required: "0.109.1" expected: true}
        {actual: "" required: "0.109.1" expected: false}
    ] {
        expect ((version-gte $fixture.actual $fixture.required) == $fixture.expected) ("Minimum-version comparison: " + $fixture.actual + " / " + $fixture.required)
    }
    # The active adapter uses native case conversion for this interpreter.
    expect (("AbC" | text-lower) == "abc") "Lowercase conversion on the supported baseline"
    expect (("AbC" | text-upper) == "ABC") "Uppercase conversion on the supported baseline"
    expect (("C:/Users/Änne/한글" | text-lower) == "c:/users/änne/한글") "Unicode path lowercase is preserved"
    expect (("Straße/한글" | text-upper) == "STRASSE/한글") "Unicode uppercase expansion is preserved"
    expect (("" | text-lower) == "" and ("" | text-upper) == "") "Empty strings remain empty"
    let parts = ((version).version | split row ".")
    let modern = (($parts.0 | into int) > 0 or ($parts.1 | into int) >= 114)
    expect ((case-backend) == (if $modern { "modern" } else { "legacy" })) "Case adapter matches the running interpreter"
    let safe_name = 'def run-plan-script [script: string ...args: string] { $script }; run-plan-script "fixture.nu"'
    expect ($safe_name | nu-check) "Plan helper has a non-keyword name"
    if (($parts.0 | into int) > 0 or ($parts.1 | into int) >= 115) {
        let reserved_name = 'def run [script: string] { $script }'
        expect (not ($reserved_name | nu-check)) "Modern Nushell rejects a helper named run"
    }

    # catch is a closure; inspect the mutable handle in the enclosing block.
    mut handle = "not-acquired"
    let failure = (try {
        $handle = "acquired"
        error make {msg: "injected-stage-error"}
        null
    } catch {|err| $err })
    expect ($failure != null) "A failing stage returns its error for outer cleanup"
    expect ($handle == "acquired") "The latest mutable handle survives the stage failure"
    $handle = "released"
    expect ($handle == "released") "Outer cleanup can mutate state without a closure capture"

    for fixture in [
        {program: "rustc" output: "rustc 1.89.0 (fixture 2025-01-01)" expected: "1.89.0"}
        {program: "rustc" output: "rustc 1.90.0-nightly (fixture)" expected: "1.90.0-nightly"}
        {program: "julia" output: "julia version 1.11.7" expected: "1.11.7"}
        {program: "julia" output: "julia version 1.12.0-rc1" expected: "1.12.0-rc1"}
        {program: "rustc" output: "" expected: ""}
        {program: "julia" output: "  \n" expected: ""}
        {program: "rustc" output: "rustc" expected: ""}
        {program: "julia" output: "julia version unavailable" expected: ""}
    ] {
        expect ((parse-tool-version $fixture.program $fixture.output) == $fixture.expected) ("Version parser: " + $fixture.program + " / " + $fixture.expected)
    }
    for fixture in [
        {output: "stable-x86_64-pc-windows-msvc (default)" expected: "stable"}
        {output: "1.89.0-aarch64-apple-darwin (default)" expected: "1.89.0"}
        {output: "nightly-2025-08-01-x86_64-unknown-linux-gnu (default)" expected: "nightly-2025-08-01"}
        {output: "nightly-x86_64-unknown-linux-gnu (default)" expected: "nightly"}
        {output: "" expected: ""}
    ] {
        expect ((parse-rust-channel $fixture.output) == $fixture.expected) ("Rust channel parser: " + $fixture.expected)
    }
    expect ((parse-julia-channel " Default  Channel  Version\n * release 1.11.7+0.x64.linux.gnu\n   lts 1.10.10\n") == "release") "Julia default marker is not discarded"
    expect ((parse-julia-channel " * 1.12.0-rc1 1.12.0-rc1+0.x64.w64.mingw32\n") == "1.12.0-rc1") "Julia channel punctuation is preserved"
    expect ((parse-julia-channel "") == "") "Empty Julia status is handled"
}

def failure-path-regressions [sandbox: path] {
    let workspace = ($sandbox | path join "workspace")
    mkdir ($workspace | path join "home")
    "unchanged" | save ($workspace | path join "home" "dot_fixture")
    atomic-record ((state-root) | path join "config.nuon") {
        app_version: "regression-test" schema_version: 5
        tools_root: ($ROOT | into string) data_root: ($workspace | into string)
        machine: {name: "sandbox" profile: "minimal" install_gui_apps: false}
        features: {rust: false julia: false vscode: false rclone_config: false}
        maintenance: {snapshots_enabled: false snapshot_keep: 20 log_keep_lines: 100}
        sync: {enabled: false auto_push: false auto_pull: false prune_extras: false}
    }
    atomic-record (provider-config-path) {version: 1 kind: "directory" remote: ""}
    let before = (workspace-hash $workspace)
    let push = (child "sync-transport.nu" ["push"])
    expect ($push.exit_code != 0) "Missing baseline rejects push without running a local capture"
    expect ((($push.stderr | output-text) + ($push.stdout | output-text)) | str contains "No trusted baseline") "Push reaches the intended runtime guard (not a parser failure)"
    expect ((workspace-hash $workspace) == $before) "Failed push leaves workspace content unchanged"
    let local_lock = (operation-lock)
    let shared = (remote-lock (load-provider))
    release-remote-lock $shared
    lock-release $local_lock
    print "[pass] Operation and local provider locks can be reacquired after push failure"

    let vault = (child "secret-vault.nu" ["invalid-regression-action"])
    expect ($vault.exit_code != 0) "Invalid vault action fails"
    expect ((($vault.stderr | output-text) + ($vault.stdout | output-text)) | str contains "Use: status") "Vault reaches its runtime action guard"
    let after_vault = (operation-lock)
    lock-release $after_vault
    print "[pass] Vault failure does not strand the operation lock"

    let upgrade = (child "safe-upgrade.nu" ["--rollback" "invalid-id"])
    expect ($upgrade.exit_code != 0) "Invalid update rollback ID fails"
    expect ((($upgrade.stderr | output-text) + ($upgrade.stdout | output-text)) | str contains "Invalid upgrade ID") "Updater reaches its runtime ID guard"
    let after_upgrade = (operation-lock)
    lock-release $after_upgrade
    print "[pass] Updater failure does not strand the operation lock"

    let backup1 = (child "backup-local-config.nu" ["--label" "same-label" "--quiet"])
    let backup2 = (child "backup-local-config.nu" ["--label" "same-label" "--quiet"])
    expect ($backup1.exit_code == 0 and $backup2.exit_code == 0) "Repeated same-label local backups both succeed"
    let backup_root = ((state-root) | path join "local-backups")
    let backups = (ls $backup_root | where type == dir)
    expect (($backups | length) == 2) "Two backup invocations never reuse the same directory"

    # A missing payload must be discovered before any live destination changes.
    let damaged = ($backups | first | get name)
    let metadata = (open ($damaged | path join "manifest.nuon"))
    let saved_config = ($metadata.items | where name == "machine-config" | first)
    rm ($damaged | path join $saved_config.stored)
    let live_config = ((state-root) | path join "config.nuon")
    let config_hash = (open --raw $live_config | hash sha256)
    let restore = (child "backup-local-config.nu" ["--restore" ($damaged | into string) "--force"])
    expect ($restore.exit_code != 0) "Incomplete local backup is rejected before restore"
    expect ((($restore.stderr | output-text) + ($restore.stdout | output-text)) | str contains "Backup payload missing") "Restore reaches payload preflight"
    expect ((open --raw $live_config | hash sha256) == $config_hash) "Payload-preflight failure leaves live configuration untouched"
}


def error-handling-regressions [] {
    let plain = "plain failure"
    expect ((error-message $plain "fallback") == "plain failure") "Plain-string failures keep their diagnostic"

    let wrapped = (failure-envelope {msg: "wrapped failure"})
    let mixed = ["normal pipeline output" {value: 42} $wrapped]
    let extracted = (captured-failure $mixed)
    expect ($extracted != null) "Tagged failure is extracted from mixed pipeline output"
    expect ((error-message $extracted "fallback") == "wrapped failure") "Tagged failure preserves the original message"

    let success_only = ["normal pipeline output" {value: 42} null]
    expect ((captured-failure $success_only) == null) "Normal pipeline output is never mistaken for a failure"
}

def main [--keep] {
    language-regressions
    error-handling-regressions
    let base = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand)
    let sandbox = ($base | path join ("initial-setup-regression-" + (random uuid)))
    let home = ($sandbox | path join "home")
    let appdata = ($home | path join "AppData" "Roaming")
    let localappdata = ($home | path join "AppData" "Local")
    mkdir $home $appdata $localappdata
    try {
        with-env {
            INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($home | into string)
            INITIAL_SETUP_OPERATION_TOKEN: ""
            HOME: ($home | into string) USERPROFILE: ($home | into string)
            APPDATA: ($appdata | into string) LOCALAPPDATA: ($localappdata | into string)
            XDG_CONFIG_HOME: ($home | path join ".config") XDG_DATA_HOME: ($home | path join ".local" "share")
            XDG_STATE_HOME: ($home | path join ".local" "state") XDG_CACHE_HOME: ($home | path join ".cache")
        } { failure-path-regressions $sandbox }
        if $keep { print ("[kept] " + ($sandbox | into string)) } else { rm --recursive --force $sandbox }
    } catch {|err|
        # Keep diagnostic fixtures on failure; they contain dummy values only.
        print ("[kept] Failed regression sandbox: " + ($sandbox | into string))
        error make {msg: $err.msg}
    }
    print "[ok] Language, version parsing and failure-path regressions passed."
}
