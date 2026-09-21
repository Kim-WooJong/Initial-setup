#!/usr/bin/env nu

const ROOT = path self ..

def expect [ok: bool label: string] {
    if not $ok { error make {msg: ("FAILED: " + $label)} }
    print ("[pass] " + $label)
}

def read-source [relative: string] {
    open --raw ($ROOT | path join $relative)
}

def main [] {
    let governed = [
        "scripts/doctor.nu"
        "scripts/audit.nu"
        "scripts/preflight.nu"
        "verify.nu"
        "scripts/verify-all.nu"
        "scripts/validate-project.nu"
        "scripts/repo-status.nu"
        "scripts/report.nu"
        "scripts/self-test.nu"
        "scripts/release.nu"
        "scripts/version-info.nu"
        "scripts/posix-bootstrap-test.nu"
    ]

    for file in $governed {
        let text = (read-source $file)
        expect (not ($text | str contains "$env.LAST_EXIT_CODE")) ($file + " does not depend on LAST_EXIT_CODE")
        expect (not ($text | str contains "do { ^")) ($file + " does not bypass the shared subprocess capture path")
    }

    let doctor = (read-source "scripts/doctor.nu")
    expect ($doctor | str contains "tool-diagnostic") "doctor performs executable health checks"
    expect ($doctor | str contains "command-failure-message") "doctor preserves child diagnostics"

    let audit = (read-source "scripts/audit.nu")
    expect ($audit | str contains "tool-diagnostic") "audit uses executable health checks"
    expect ($audit | str contains "summarize-diagnostics") "audit derives its exit policy from structured checks"

    let preflight = (read-source "scripts/preflight.nu")
    expect ($preflight | str contains "chezmoi diff") "preflight retains explicit user diff review"
    expect ($preflight | str contains "command-failure-message") "preflight preserves chezmoi failure diagnostics"

    let verify = (read-source "verify.nu")
    expect ($verify | str contains "run-command") "verification entry uses the shared subprocess contract"
    expect ($verify | str contains "--working-tree") "verification entry supports development-tree validation without weakening release validation"

    let verify_all = (read-source "scripts/verify-all.nu")
    expect ($verify_all | str contains "probe-tool \"cargo\"") "verification health-checks Cargo before build tests"
    expect ($verify_all | str contains "probe-tool \"rustc\"") "verification health-checks rustc before build tests"
    expect ($verify_all | str contains "release_manifest_enforced") "verification summary records whether release manifest enforcement was active"

    let module = (read-source "scripts/modules/diagnostics.nu")
    for token in ["diagnostic-check" "tool-diagnostic" "command-diagnostic" "summarize-diagnostics"] {
        expect ($module | str contains $token) ("shared diagnostics module exports/contains " + $token)
    }

    print "[ok] Diagnostic and verification policy regressions passed."
}
