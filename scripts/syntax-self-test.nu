#!/usr/bin/env nu
const PROCESS_OUTPUT = path self ./modules/process-output.nu
use $PROCESS_OUTPUT [output-text]
# Standalone regression tests for the syntax validator itself. Invalid source
# lives only in string fixtures written under a temporary directory. No cloud,
# installer, machine configuration or project module is invoked.
const VALIDATOR = path self ./validate-syntax.nu
const CASE_SOURCE = path self ./modules/text-case.nu
const CASE_ADAPTERS = path self ./modules/compat

def expect [condition: bool message: string] {
    if not $condition { error make {msg: ("FAILED: " + $message)} }
    print ("[pass] " + $message)
}

def check-tree [root: path report: path parse_only: bool = false deny_warnings: bool = false] {
    let exe = $nu.current-exe
    let base_args = if $parse_only {
        [$VALIDATOR "--root" $root "--report" $report "--parse-only"]
    } else {
        [$VALIDATOR "--root" $root "--report" $report]
    }
    let args = if $deny_warnings { $base_args | append "--deny-warnings" } else { $base_args }
    do { ^$exe --no-config-file ...$args } | complete
}

def fixtures [sandbox: path] {
    # A real path containing glob metacharacters, spaces and non-ASCII text.
    let root = ($sandbox | path join "checkout [literal] 한국어")
    let modules = ($root | path join "scripts" "modules")
    mkdir $modules ($root | path join ".git")
    let harmless = 'def main [] { error make {msg: "Syntax validation must not execute main."} }'
    $harmless | save ($root | path join "a-good.nu")
    $harmless | save ($root | path join "z-after-errors.nu")
    'export def ping [] { "ok" }' | save ($modules | path join "good.nu")
    'export def quoted-name [] { "ok" }' | save ($modules | path join "quote's 한국어.nu")
    'const M = path self ./scripts/modules/good.nu
use $M [ping]
def main [] { ping }' | save ($root | path join "import-good.nu")
    # Git internals are not project sources and must not inflate the count.
    'def broken [' | save ($root | path join ".git" "ignored.nu")

    let good_report = ($sandbox | path join "good.json")
    let good = (check-tree $root $good_report)
    if $good.exit_code != 0 { print $good.stdout; print $good.stderr }
    expect ($good.exit_code == 0) "Valid scripts/modules pass in a bracketed Unicode checkout path"
    let first = (open $good_report)
    expect ($first.checked == 5 and $first.failed == 0) "All five fixture sources are checked; .git is excluded"
    expect ($first.nushell == (version | get version)) "Report identifies the actual running Nushell"
    expect ($first.results | all {|row| $row.startup_checked }) "Default validation includes startup/import checks"

    'def main [] { let a0 = 1; let r0 = 0; if $a0 != $r0 { return $a0 > $r0 } }' | save ($root | path join "bad-return.nu")
    'use ./module-that-does-not-exist.nu *
def main [] {}' | save ($root | path join "missing-import.nu")
    # Deliberately invalid parse-time evaluation. Keep it inside a fixture:
    # no attempt to read this path may be made by the parser.
    'const BROKEN = (open "never-read-by-parser.txt")
def main [] {}' | save ($root | path join "bad-const.nu")
    let nu_parts = ((version).version | split row ".")
    let modern_keywords = (($nu_parts.0 | into int) > 0 or ($nu_parts.1 | into int) >= 115)
    if $modern_keywords {
        'def run [script: string] { $script }
def main [] {}' | save ($root | path join "keyword-run.nu")
        'alias run = print
def main [] {}' | save ($root | path join "keyword-alias.nu")
        'export def run [] { "bad" }' | save ($modules | path join "keyword-export.nu")
    }
    let extra_errors = if $modern_keywords { 3 } else { 0 }
    let expected_checked = (8 + $extra_errors)
    let expected_failed = (3 + $extra_errors)
    let bad_report = ($sandbox | path join "bad.json")
    let bad = (check-tree $root $bad_report)
    expect ($bad.exit_code != 0) "A tree with syntax/import failures exits nonzero"
    expect ($bad_report | path exists) "A report is still written after a target parser failure"
    let second = (open $bad_report)
    expect ($second.checked == $expected_checked and $second.failed == $expected_failed) "All return/import/const/keyword errors are collected without stopping"
    let later = ($second.results | where file == "z-after-errors.nu" | first)
    expect $later.ok "Validation continues to a valid file after an earlier failure"
    let reported = ($second.results | where file == "bad-return.nu" | first)
    expect ($reported.parser_exit_code != 0) "The invalid return is rejected by nu-check"
    expect ($reported.startup_checked and $reported.startup_exit_code != 0) "Startup diagnostics run even after nu-check failure"
    expect ($reported.startup_diagnostics | str contains "bad-return.nu") "Diagnostics retain the original failing file name"

    let const_failure = ($second.results | where file == "bad-const.nu" | first)
    expect ($const_failure.parser_exit_code != 0 and $const_failure.startup_exit_code != 0) "Non-constant commands in const fail parser and startup checks"
    expect ($const_failure.startup_diagnostics | str contains "const") "Original const diagnostic is preserved"

    let parse_report = ($sandbox | path join "parse-only.json")
    let parse = (check-tree $root $parse_report true)
    expect ($parse.exit_code != 0) "Parse-only does not hide invalid source"
    let third = (open $parse_report)
    expect ($third.checked == $expected_checked and $third.failed == $expected_failed) "Parse-only also inspects every source"
    expect ($third.results | all {|row| not $row.startup_checked }) "Parse-only omits target startup/import evaluation"
    if $modern_keywords {
        let keyword = ($second.results | where file == "keyword-run.nu" | first)
        expect ($keyword.parser_exit_code != 0 and $keyword.startup_exit_code != 0) "Reserved helper fails both parser and original-source checks"
        expect ($keyword.startup_diagnostics | str contains "keyword") "Original keyword failure is retained in the report"
    }

    # Exercise warning collection only on releases where these aliases are
    # deprecated but still exist. Future removal must not break this fixture.
    let has_deprecated_aliases = (($nu_parts.0 | into int) == 0 and ($nu_parts.1 | into int) >= 114 and ($nu_parts.1 | into int) <= 115)
    if $has_deprecated_aliases {
        let warning_root = ($sandbox | path join "warning-fixture")
        mkdir $warning_root
        'def main [] { "ABC" | str downcase }' | save ($warning_root | path join "warning.nu")
        let warning_report = ($sandbox | path join "warning.json")
        let ordinary = (check-tree $warning_root $warning_report)
        expect ($ordinary.exit_code == 0) "Default validation distinguishes warnings from parser errors"
        let warning_data = (open $warning_report)
        expect ($warning_data.warnings == 1) "Successful parser stderr is not silently discarded"
        let strict = (check-tree $warning_root ($sandbox | path join "strict-warning.json") false true)
        expect ($strict.exit_code != 0) "Explicit strict mode rejects warnings"
    }
}


# Exercise the REAL module's constant expression, not a runtime copy of its
# logic. Synthetic versions are test data only; no production override exists.
# Stub the selected adapter and deliberately break the other adapter to prove
# that it is not parsed. This is a selector test, NOT a cross-version test of
# the actual native commands; the interpreter matrix is still required.
def case-selector-fixtures [sandbox: path] {
    let source = (open --raw $CASE_SOURCE)
    expect ($source | str contains "(version).version") "Case module exposes the actual version expression to the fixture"
    let root = ($sandbox | path join "case selector [literal] 한국어")
    let adapters = ($root | path join "compat")
    mkdir $adapters
    let runner = ($root | path join "check.nu")
    'const CASE = path self ./text-case.nu
use $CASE [text-lower text-upper case-backend]
def main [] { [(case-backend) ("AbC" | text-lower) ("AbC" | text-upper)] | to json --raw }' | save $runner
    let stub = 'export def text-lower []: string -> string { "fixture-lower" }
export def text-upper []: string -> string { "fixture-upper" }'
    let exe = $nu.current-exe
    for fixture in [
        {version: "0.109.1" expected: "legacy"}
        {version: "0.109.12" expected: "legacy"}
        {version: "0.110.0" expected: "legacy"}
        {version: "0.111.0" expected: "legacy"}
        {version: "0.112.2" expected: "legacy"}
        {version: "0.113.1" expected: "legacy"}
        {version: "0.113.0-rc.1" expected: "legacy"}
        {version: "0.114.0" expected: "modern"}
        {version: "0.114.0-rc.1" expected: "modern"}
        {version: "0.114.1" expected: "modern"}
        {version: "0.115.1" expected: "modern"}
        {version: "0.115.1-nightly.2+fixture" expected: "modern"}
        {version: "0.116.0" expected: "modern"}
        {version: "0.1000.0" expected: "modern"}
        {version: "1.0.0" expected: "modern"}
    ] {
        let literal = ('"' + $fixture.version + '"')
        $source | str replace "(version).version" $literal | save --force ($root | path join "text-case.nu")
        let active = if $fixture.expected == "modern" { "case-modern.nu" } else { "case-legacy.nu" }
        let inactive = if $fixture.expected == "modern" { "case-legacy.nu" } else { "case-modern.nu" }
        $stub | save --force ($adapters | path join $active)
        'export def must-not-parse [' | save --force ($adapters | path join $inactive)
        let result = (do { ^$exe --no-config-file $runner } | complete)
        if $result.exit_code != 0 { print $result.stdout; print $result.stderr }
        expect ($result.exit_code == 0) ("Case const/import succeeds for synthetic " + $fixture.version)
        let values = ($result.stdout | from json)
        expect ($values == [$fixture.expected "fixture-lower" "fixture-upper"]) ("Correct branch only: " + $fixture.version)
        expect ($result.stderr | output-text | str trim | is-empty) ("No selector warning: " + $fixture.version)
    }

    # Real version and real native implementations in a fresh child process.
    # Unlike the synthetic tests this checks the active commands on THIS binary.
    $source | save --force ($root | path join "text-case.nu")
    for name in ["case-legacy.nu" "case-modern.nu"] {
        open --raw ($CASE_ADAPTERS | path join $name) | save --force ($adapters | path join $name)
    }
    let actual = (do { ^$exe --no-config-file $runner } | complete)
    if $actual.exit_code != 0 { print $actual.stdout; print $actual.stderr }
    expect ($actual.exit_code == 0) "Actual case module imports using the running interpreter"
    let values = ($actual.stdout | from json)
    let parts = ((version).version | split row ".")
    let modern = (($parts.0 | into int) > 0 or ($parts.1 | into int) >= 114)
    let expected = if $modern { "modern" } else { "legacy" }
    expect ($values == [$expected "abc" "ABC"]) "Active native case functions return the expected values"
    expect ($actual.stderr | output-text | str trim | is-empty) "Actual active adapter emits no warning"
}

def main [--keep] {
    let base = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand)
    let sandbox = ($base | path join ("initial-setup-syntax-" + (random uuid)))
    mkdir $sandbox
    try {
        fixtures $sandbox
        case-selector-fixtures $sandbox
    } catch {|err|
        print ("[kept] Syntax-test fixtures and diagnostics: " + ($sandbox | into string))
        error make {msg: $err.msg}
    }
    if $keep { print ("[kept] " + ($sandbox | into string)) } else { rm --recursive --force $sandbox }
    print "[ok] Syntax-validator regression tests passed."
}
