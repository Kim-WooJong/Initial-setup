#!/usr/bin/env nu
# Byte fixtures are literals, not produced by the decoder under test.
# Default: pure diagnostics only; no locks, files, credentials or remote traffic.
# --external additionally emits deliberate invalid UTF-8 from a child process.
const OUTPUT = path self ./modules/process-output.nu
const SAFETY = path self ./modules/safety.nu
const RCLONE = path self ./modules/rclone-install.nu
use $OUTPUT [output-text]
use $SAFETY [lock-result-message]
use $RCLONE [perform-rclone-install]

def expect [ok: bool label: string] {
    if not $ok { error make {msg: ("FAILED: " + $label)} }
    print ("[pass] " + $label)
}

def fixtures [] {
    expect ((null | output-text) == "") "Missing/null stream becomes text"
    expect ((0x[] | output-text) == "") "Empty binary becomes empty text"
    expect ((" a\r\nb\n " | output-text) == " a\r\nb\n ") "Existing text and whitespace are unchanged"
    expect ((0x[61 62 63] | output-text) == "abc") "ASCII binary decodes"
    expect ((0x[ed 95 9c ea b8 80] | output-text) == "한글") "UTF-8 Korean decodes"
    expect ((0x[ef bb bf 61 62 63] | output-text) == "abc") "UTF-8 BOM is removed"
    expect ((0x[ef bb bf] | output-text) == "") "BOM-only UTF-8 is empty"
    expect ((0x[ef bf bd] | output-text) == "�") "A genuine UTF-8 replacement character is not a decoding failure"
    let expected = "INITIAL_SETUP_LOCK_IO: 접근 거부 fixture-owner-token"
    let korean = 0x[49 4e 49 54 49 41 4c 5f 53 45 54 55 50 5f 4c 4f 43 4b 5f 49 4f 3a 20 c1 a2 b1 d9 20 b0 c5 ba ce 20 66 69 78 74 75 72 65 2d 6f 77 6e 65 72 2d 74 6f 6b 65 6e]
    let little = 0x[ff fe 49 00 4e 00 49 00 54 00 49 00 41 00 4c 00 5f 00 53 00 45 00 54 00 55 00 50 00 5f 00 4c 00 4f 00 43 00 4b 00 5f 00 49 00 4f 00 3a 00 20 00 11 c8 fc ad 20 00 70 ac 80 bd 20 00 66 00 69 00 78 00 74 00 75 00 72 00 65 00 2d 00 6f 00 77 00 6e 00 65 00 72 00 2d 00 74 00 6f 00 6b 00 65 00 6e 00]
    let big = 0x[fe ff 00 49 00 4e 00 49 00 54 00 49 00 41 00 4c 00 5f 00 53 00 45 00 54 00 55 00 50 00 5f 00 4c 00 4f 00 43 00 4b 00 5f 00 49 00 4f 00 3a 00 20 c8 11 ad fc 00 20 ac 70 bd 80 00 20 00 66 00 69 00 78 00 74 00 75 00 72 00 65 00 2d 00 6f 00 77 00 6e 00 65 00 72 00 2d 00 74 00 6f 00 6b 00 65 00 6e]
    expect (($little | output-text) == $expected) "UTF-16LE BOM diagnostic decodes"
    expect (($big | output-text) == $expected) "UTF-16BE BOM diagnostic decodes"
    expect (($little | output-text --encoding invalid-hint) == $expected) "BOM wins over a legacy encoding hint"
    expect (($korean | output-text --encoding euc-kr) == $expected) "Explicit Korean legacy decoding"
    let hinted = (with-env {INITIAL_SETUP_DIAGNOSTIC_ENCODING: "euc-kr"} { $korean | output-text })
    expect ($hinted == $expected) "A session-local encoding hint is honored"
    expect ((0x[ed 95 9c ea b8 80] | output-text --encoding euc-kr) == "한글") "Valid UTF-8 wins over a legacy hint"
    let unknown = ($korean | output-text)
    expect ($unknown | str starts-with "[Non-UTF-8 diagnostic:") "Unknown encoding is visibly marked, not guessed"
    expect ($unknown | str contains "INITIAL_SETUP_LOCK_IO:") "Fallback retains ASCII error codes"
    expect ($unknown | str contains "fixture-owner-token") "Fallback retains an ASCII UUID-shaped token for redaction"
    let bad_hint = ($korean | output-text --encoding not-a-real-encoding)
    expect ($bad_hint | str contains "[Non-UTF-8 diagnostic:") "Invalid encoding hint cannot crash the diagnostic path"
    let malformed = (0x[ff 61 00 62 0a] | output-text)
    expect ($malformed | str ends-with "�ab\n") "Last-resort output keeps ASCII and removes embedded NULs"
    for value in [["unexpected" "list"] {unexpected: "record"} 42] {
        let normalized = ($value | output-text)
        expect (($normalized | describe) == "string") "Unexpected types never reach str trim as non-text"
        expect ($normalized | str starts-with "[Non-text diagnostic omitted:") "Unexpected structured data is not dumped"
    }

    let path = "diagnostic-only.lock"
    let token = "fixture-owner-token"
    expect ((lock-result-message $path {exit_code: 0 stderr: 0x[ff]} $token) == "") "Successful helper exit stays successful"
    expect ((lock-result-message $path {exit_code: 74} $token) | str starts-with "LOCK_CREATE_FAILED:") "Missing stderr preserves failure classification"
    expect ((lock-result-message $path {exit_code: 74 stderr: null} $token) | str starts-with "LOCK_CREATE_FAILED:") "Null stderr preserves failure classification"
    for stream in [
        $expected
        ($expected | encode utf-8)
        $little
        $big
        $korean
        0x[ff 49 4f 20 65 72 72 6f 72]
    ] {
        let message = (lock-result-message $path {exit_code: 74 stderr: $stream} $token)
        expect ($message | str starts-with "LOCK_CREATE_FAILED:") "Nonzero exit never turns into a successful lock"
        expect (not ($message | str contains $token)) "Token remains redacted for every supported diagnostic representation"
    }
    let raw_busy = ("INITIAL_SETUP_LOCK_EXISTS: fixture-owner-token" | encode utf-8)
    let busy = (lock-result-message $path {exit_code: 17 stderr: $raw_busy} $token)
    expect ($busy | str starts-with "LOCK_EXISTS:") "Binary collision marker with exit 17 remains a collision"
    expect (not ($busy | str contains $token)) "Binary collision token is redacted"
    expect ($busy | str contains "<redacted-lock-token>") "Redaction marker remains visible"
    let non_collision = (lock-result-message $path {exit_code: 17 stderr: 0x[ff 61 62]} $token)
    expect ($non_collision | str starts-with "LOCK_CREATE_FAILED:") "Exit 17 alone does not prove an existing lock"
    let wrong_code = (lock-result-message $path {exit_code: 74 stderr: $raw_busy} $token)
    expect ($wrong_code | str starts-with "LOCK_CREATE_FAILED:") "Collision marker alone does not override an I/O exit code"
    let fake_plan = {manager: "fixture" supported: true reason: "" steps: [{label: "Fixture installer"}]}
    let failed_executor = { |_step| {exit_code: 74 stderr: $korean} }
    let missing_probe = {|| {found: false ready: false path: "" version: ""} }
    let install_error = (try {
        perform-rclone-install $fake_plan $failed_executor $missing_probe | ignore
        null
    } catch {|err| $err })
    expect ($install_error != null) "Mock installer rejects a nonzero child exit"
    expect ($install_error.msg | str contains "Fixture installer failed (exit 74)") "Mock installer keeps its intended error rather than a binary concatenation error"
    expect ($install_error.msg | str contains "INITIAL_SETUP_LOCK_IO:") "Mock installer preserves its ASCII cause"
    let utf16_broken = (0x[ff fe 49 00 4e 00 49 00 54 00 49 00 41 00 4c 00 5f 00 53 00 45 00 54 00 55 00 50 00 5f 00 4c 00 4f 00 43 00 4b 00 5f 00 49 00 4f 00 3a 00 20 00 11 c8 fc ad 20 00 70 ac 80 bd 20 00 66 00 69 00 78 00 74 00 75 00 72 00 65 00 2d 00 6f 00 77 00 6e 00 65 00 72 00 2d 00 74 00 6f 00 6b 00 65 00 6e 00 01])
    let broken_message = (lock-result-message $path {exit_code: 74 stderr: $utf16_broken} $token)
    expect (not ($broken_message | str contains $token)) "Truncated UTF-16 diagnostic still redacts its token"
    expect ($broken_message | str starts-with "LOCK_CREATE_FAILED:") "Truncated UTF-16 cannot suppress a helper failure"
}

def external-fixture [] {
    # Deliberately write a 0xFF byte to stderr to exercise `complete` rather than
    # handing the formatter a manually constructed result record.
    let result = if $nu.os-info.name == "windows" {
        let script = '$b = [byte[]](255, 73, 78, 73, 84, 73, 65, 76, 95, 83, 69, 84, 85, 80, 95, 76, 79, 67, 75, 95, 73, 79, 58, 32, 102, 105, 120, 116, 117, 114, 101, 45, 111, 119, 110, 101, 114, 45, 116, 111, 107, 101, 110, 10); $s = [Console]::OpenStandardError(); $s.Write($b, 0, $b.Length); $s.Flush(); exit 74'
        do { ^powershell.exe -NoProfile -NonInteractive -Command $script } | complete
    } else {
        do { ^sh -c 'printf "\377INITIAL_SETUP_LOCK_IO: fixture-owner-token\n" >&2; exit 74' } | complete
    }
    expect ($result.exit_code == 74) "Raw child preserves its nonzero exit code"
    expect (($result.stderr | describe) == "binary") "complete returns actual binary stderr from the raw child"
    let msg = (lock-result-message "diagnostic-only.lock" $result "fixture-owner-token")
    expect ($msg | str starts-with "LOCK_CREATE_FAILED:") "Real binary stderr reaches the intended helper diagnostic"
    expect ($msg | str contains "INITIAL_SETUP_LOCK_IO:") "Real binary stderr retains its ASCII cause"
    expect (not ($msg | str contains "fixture-owner-token")) "Real binary stderr cannot leak the token"
}

def main [--external] {
    # Do not let the user's optional locale hint affect deterministic fixtures.
    with-env {INITIAL_SETUP_DIAGNOSTIC_ENCODING: ""} {
        fixtures
        if $external { external-fixture }
    }
    print "[ok] Process diagnostic regressions passed. No real operation lock or private configuration was used."
}
