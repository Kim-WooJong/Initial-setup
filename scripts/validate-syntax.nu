#!/usr/bin/env nu
const PROCESS_OUTPUT = path self ./modules/process-output.nu
use $PROCESS_OUTPUT [output-text]
# Deliberately standalone: a broken project module cannot prevent this runner
# from reporting errors in the rest of the project. No project imports here.
const ROOT = path self ..
const WORKER = path self ./syntax-check-file.nu

# Literal directory traversal avoids treating [brackets] in a checkout path as
# glob syntax. Do not follow symlinks or recurse into Git's internal directory.
def source-files [directory: path] {
    mut files = []
    for item in (ls --all $directory) {
        if ($item.name | path basename) == ".git" { continue }
        if $item.type == "dir" {
            $files = ($files | append (source-files $item.name))
        } else if $item.type == "file" and ($item.name | str ends-with ".nu") {
            $files = ($files | append $item.name)
        }
    }
    $files
}

# 'use' resolves its argument at parse time. Always emit one quoted literal,
# including paths with spaces, quotes, backslashes, brackets or Unicode.
def nu-string-literal [value: string] {
    let escaped = ($value
        | str replace --all '\' '\\'
        | str replace --all '"' '\"'
        | str replace --all (char nl) '\n'
        | str replace --all (char cr) '\r'
        | str replace --all (char tab) '\t')
    '"' + $escaped + '"'
}

# Run every check in a fresh process so earlier imports cannot mask errors.
def child [args: list] {
    let exe = $nu.current-exe
    try { do { ^$exe --no-config-file ...$args } | complete } catch {|err|
        {exit_code: 1 stdout: "" stderr: $err.msg}
    }
}

def diagnostic-text [result: record] {
    [($result.stderr? | output-text) ($result.stdout? | output-text)]
    | str join (char nl)
    | str trim
}

# --help checks compile script entrypoints without calling main. Importing a
# module can evaluate top-level statements. This is NOT a security sandbox:
# run it only on trusted source trees. --parse-only omits these startup checks.
# --root is mainly for isolated validator regression fixtures.
def main [--parse-only --deny-warnings --report: path --root: path] {
    let source_root = if $root == null { $ROOT } else { $root | path expand }
    if not ($WORKER | path exists) {
        error make {msg: "Missing scripts/syntax-check-file.nu; restore the complete release before validating."}
    }
    if not ($source_root | path exists) or ($source_root | path type) != "dir" {
        error make {msg: "Syntax-check root must be an existing directory."}
    }
    let sources = (source-files $source_root | sort)
    if ($sources | is-empty) { error make {msg: "No Nushell source files found."} }
    let nu_parts = ((version).version | split row ".")
    let modern_case = (($nu_parts.0 | into int) > 0 or ($nu_parts.1 | into int) >= 114)
    let inactive_adapter = if $modern_case {
        "scripts/modules/compat/case-legacy.nu"
    } else {
        "scripts/modules/compat/case-modern.nu"
    }
    mut skipped = []
    mut results = []
    for file in $sources {
        let relative = ($file | path relative-to $source_root | into string | str replace --all '\' '/')
        # A version-specific adapter must be checked with its matching Nu.
        # No other source can opt out of parsing, and skips are in the report.
        if $relative == $inactive_adapter {
            let reason = ("Inactive case adapter for Nushell " + (version).version + "; validate this file with the other compatibility-matrix interpreter.")
            $skipped = ($skipped | append {file: $relative reason: $reason})
            print ("[inactive] " + $relative + " | " + $reason)
            continue
        }
        let module = ($relative | str starts-with "scripts/modules/")
        let args = if $module { [$WORKER $file "--as-module"] } else { [$WORKER $file] }
        let parsed = (child $args)
        # Even when nu-check fails, a --help/import check can expose the original
        # file/line instead of only nu-check's generic 'Failed to parse content'.
        let startup = if $parse_only {
            {exit_code: 0 stdout: "" stderr: ""}
        } else if $module {
            child ["--commands" ("use " + (nu-string-literal ($file | into string)) + " *")]
        } else {
            child [$file "--help"]
        }
        let parser_details = if $parsed.exit_code != 0 { diagnostic-text $parsed } else { "" }
        let startup_details = if $startup.exit_code != 0 { diagnostic-text $startup } else { "" }
        let warnings = ([
            (if $parsed.exit_code == 0 { $parsed.stderr? | output-text | str trim } else { "" })
            (if $startup.exit_code == 0 { $startup.stderr? | output-text | str trim } else { "" })
        ] | where {|text| not ($text | is-empty) } | uniq | str join (char nl))
        let ok = ($parsed.exit_code == 0 and $startup.exit_code == 0)
        let details = ([
            (if $parsed.exit_code != 0 { "[nu-check]\n" + $parser_details } else { "" })
            (if $startup.exit_code != 0 { "[startup/import: original source diagnostic]\n" + $startup_details } else { "" })
        ] | where {|text| not ($text | is-empty) } | str join (char nl))
        $results = ($results | append {
            file: $relative module: $module ok: $ok
            parser_exit_code: $parsed.exit_code
            startup_checked: (not $parse_only)
            startup_exit_code: $startup.exit_code
            parser_diagnostics: $parser_details
            startup_diagnostics: $startup_details
            diagnostics: $details
            warning_diagnostics: $warnings
        })
        if $ok {
            if ($warnings | is-empty) { print ("[ok] " + $relative) } else {
                print ("[WARN] " + $relative)
                print $warnings
            }
        } else {
            print ("[FAIL] " + $relative)
            print $details
        }
    }
    let failures = ($results | where ok == false)
    let summary = {
        format: 3 project: "Initial-setup"
        nushell: (version | get version)
        platform: $nu.os-info.name
        source_root: ($source_root | into string)
        discovered: ($sources | length)
        checked: ($results | length) failed: ($failures | length)
        skipped: $skipped skipped_count: ($skipped | length)
        warnings: ($results | where {|row| not ($row.warning_diagnostics | is-empty) } | length)
        deny_warnings: $deny_warnings
        parse_only: $parse_only results: $results
    }
    if $report != null {
        let destination = ($report | path expand)
        mkdir ($destination | path dirname)
        $summary | to json | save --force $destination
        print ("[report] " + ($destination | into string))
    }
    print ("[syntax] " + ($summary.checked | into string) + " checked; " + ($summary.failed | into string) + " failed; " + ($summary.warnings | into string) + " with warnings; " + ($summary.skipped_count | into string) + " inactive adapter(s).")
    if not ($failures | is-empty) or ($deny_warnings and $summary.warnings > 0) { exit 1 }
}
