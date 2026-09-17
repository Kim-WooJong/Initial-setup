#!/usr/bin/env nu
# Only diagnostics/help are executed. No production setup, updates, or credentials.
const ROOT = path self ..
def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[entrypoint-test] " + $message)} }
    print ("[pass] " + $message)
}
def child [path: path args: list] {
    let exe = $nu.current-exe
    do { ^$exe --no-config-file $path ...$args } | complete
}
def tests [base: path] {
    let result = (do {
        cd $base
        child ($ROOT | path join "setup.nu") ["--diagnose"]
    })
    check ($result.exit_code == 0) ("Absolute entry works from an unrelated cwd: " + $result.stderr)
    let report = ($result.stdout | from json)
    check ($report.project_root == ($ROOT | into string) and $report.cwd != $report.project_root) "Diagnostics distinguish cwd from checkout root"
    check ($report.diagnostic_only and not $report.setup_blocked and ($report.failures | is-empty)) "Diagnostics distinguish diagnostic scope from setup policy"
    check (not ($base | path join ".config" | path exists)) "Diagnostics do not write machine configuration"
    for name in ["setup.nu" "verify.nu" "scripts/diagnose-project.nu" "scripts/setup-entry.nu"] {
        let help = (child ($ROOT | path join $name) ["--help"])
        check ($help.exit_code == 0) ("Entrypoint help parses: " + $name)
    }
    let broken = ($base | path join "partial checkout [한글]")
    mkdir ($broken | path join "scripts")
    cp ($ROOT | path join "setup.nu") ($broken | path join "setup.nu")
    cp ($ROOT | path join "scripts" "diagnose-project.nu") ($broken | path join "scripts" "diagnose-project.nu")
    let failure = (child ($broken | path join "setup.nu") ["--diagnose"])
    check ($failure.exit_code != 0) "Partial extraction is rejected"
    check ($failure.stdout | str contains "INCOMPLETE_RELEASE") "Partial extraction has a specific diagnostic before module imports"
    let normal = (child ($broken | path join "setup.nu") [])
    check ($normal.exit_code != 0 and ($normal.stdout | str contains "INCOMPLETE_RELEASE")) "Normal entry rejects incomplete releases before runtime updates"
    if $nu.os-info.name != "windows" {
        if (which bash | is-empty) { error make {msg: "Bash is required for the POSIX bootstrap fixture."} }
        let fixture = (do { ^bash ($ROOT | path join "scripts" "posix" "prepare-nu-cargo-test.sh") } | complete)
        check ($fixture.exit_code == 0) ("POSIX bootstrap mock suite: " + $fixture.stderr)
    }
}
def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-entry-" + (random uuid)))
    mkdir $base
    try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $base HOME: $base USERPROFILE: $base} { tests $base }
    } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
}
