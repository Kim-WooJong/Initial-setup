#!/usr/bin/env nu
# Offline lock regressions. No package manager, credentials, remote API or real
# operation.lock is used. On Windows this uses the real PowerShell helper.
const SAFETY = path self ./modules/safety.nu
use $SAFETY [lock-acquire lock-release lock-result-message]

def expect [ok: bool label: string] {
    if not $ok { error make {msg: ("FAILED: " + $label)} }
    print ("[pass] " + $label)
}

def expect-error [action: closure text: string] {
    let failure = (try { do $action | ignore; null } catch {|err| $err })
    expect ($failure != null) ("Rejected: " + $text)
    expect (($failure.msg? | default "") | str contains $text) ("Diagnostic: " + $text)
}

def fixtures [sandbox: path] {
    let path = ($sandbox | path join "spaces [literal] 한글" "fixture.lock")
    expect ((lock-result-message $path {exit_code: 0 stderr: ""} "token") == "") "Successful helper has no error"
    let busy = (lock-result-message $path {exit_code: 17 stderr: "INITIAL_SETUP_LOCK_EXISTS: fixture"} "token")
    expect ($busy | str starts-with "LOCK_EXISTS:") "Existing-file helper outcome is distinct"
    expect ($busy | str contains "active OR left") "Existing-file diagnostic does not assert process liveness"
    # v0.12.17: list/join formatting must preserve the full multiline diagnostic.
    expect (($busy | lines | length) == 5) "Collision message retains header, advice and helper diagnostic lines"
    expect ($busy | str ends-with "\nHelper diagnostic:\nINITIAL_SETUP_LOCK_EXISTS: fixture") "Collision helper diagnostic keeps its separator"
    let quiet_failure = (lock-result-message $path {exit_code: 74 stderr: ""} "token")
    expect (($quiet_failure | lines | length) == 3) "Empty stderr produces no extra diagnostic section"
    expect ($quiet_failure | str contains " (helper exit 74).\nThis is NOT proof") "Failure header and advice keep their newline boundary"
    let source_lines = (open --raw $SAFETY | lines)
    let leading_plus = ($source_lines | any {|line| $line | str trim | str starts-with "+ " })
    expect (not $leading_plus) "Lock module obeys the repository's operator-leading line guard"
    for result in [
        {exit_code: 1 stderr: "fixture: running scripts is disabled"}
        {exit_code: 74 stderr: "fixture: access denied"}
        {exit_code: 127 stderr: "fixture: helper not found"}
        {exit_code: 17 stderr: "unrecognized nonzero status"}
    ] {
        let message = (lock-result-message $path $result "token")
        expect ($message | str starts-with "LOCK_CREATE_FAILED:") "Non-collision failure is not reported as an active lock"
        expect ($message | str contains $result.stderr) "Original helper error is retained"
    }
    let secret_marker = "fixture-token-not-a-secret"
    let redacted = (lock-result-message $path {exit_code: 74 stderr: $secret_marker} $secret_marker)
    expect (not ($redacted | str contains $secret_marker)) "Token is redacted from diagnostics"

    let first = (lock-acquire $path)
    expect ((open --raw $path) == $first.token) "Exclusive creation retains the existing raw-token format"
    let before = (open --raw $path | hash sha256)
    expect-error {|| lock-acquire $path } "LOCK_EXISTS:"
    expect ((open --raw $path | hash sha256) == $before) "Second writer never truncates the first token"
    lock-release {path: $first.path token: "different-owner"}
    expect ($path | path exists) "Wrong-token release cannot remove the lock"
    lock-release $first
    expect (not ($path | path exists)) "Owner release removes the lock"
    let next = (lock-acquire $path)
    lock-release $next
    expect (not ($path | path exists)) "Released lock can be reacquired"

    let legacy = ($sandbox | path join "legacy.lock")
    "legacy-owner-token" | save $legacy
    expect-error {|| lock-acquire $legacy } "LOCK_EXISTS:"
    expect ((open --raw $legacy) == "legacy-owner-token") "Legacy lock is never auto-deleted"
    let empty = ($sandbox | path join "empty.lock")
    "" | save $empty
    expect-error {|| lock-acquire $empty } "LOCK_EXISTS:"
    expect ($empty | path exists) "Empty/partial lock still blocks; no unsafe age-based recovery"

    let invalid = ($sandbox | path join "directory.lock")
    mkdir $invalid
    expect-error {|| lock-acquire $invalid } "LOCK_CREATE_FAILED:"
    let parent_file = ($sandbox | path join "not-a-directory")
    "fixture" | save $parent_file
    expect-error {|| lock-acquire ($parent_file | path join "child.lock") } "LOCK_CREATE_FAILED:"
}

def main [] {
    let sandbox = (mktemp --directory)
    let failure = (try { fixtures $sandbox; null } catch {|err| $err })
    # This is our unique temporary directory, never the user's state directory.
    rm --recursive --force $sandbox
    if $failure != null { error make {msg: $failure.msg} }
    print "[ok] Lock diagnostic and lifecycle regressions passed."
}
