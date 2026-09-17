#!/usr/bin/env nu
# Continue across INDEPENDENT tests; never continue an unsafe setup/apply.
# No production setup or Proton access. Cargo builds only the local helper cache.
# Reports contain paths/diagnostics; inspect them before sharing.
const ROOT = path self ..

def text [value: any] {
    if ($value | describe) == "string" { return $value }
    if ($value | describe) == "binary" {
        try { $value | decode utf-8 } catch { "[Non-UTF-8 diagnostic omitted]" }
    } else { "" }
}

def invoke [script: string args: list directory: path name: string] {
    let exe = $nu.current-exe
    let path = ($ROOT | path join "scripts" $script)
    let started = (date now)
    let result = (try { do { ^$exe --no-config-file $path ...$args } | complete } catch {|err|
        {exit_code: 1 stdout: "" stderr: ($err.msg? | default "Child process failed")}
    })
    let out = (text $result.stdout)
    let err = (text $result.stderr)
    let log = ($directory | path join ($name + ".log"))
    ([$out $err] | str join (char nl)) | save $log
    let ok = ($result.exit_code == 0)
    print ((if $ok { "[pass] " } else { "[FAIL] " }) + $name + " -> " + ($log | into string))
    if not $ok and not ($err | is-empty) { print --stderr $err }
    {name: $name status: (if $ok { "passed" } else { "failed" }) exit_code: $result.exit_code elapsed: ((date now) - $started | into string) log: ($log | into string)}
}

def write-summary [directory: path results: list full: bool offline: bool finished: bool] {
    let failed = ($results | where status == "failed" | length)
    let incomplete = ($results | where {|r| $r.status in ["blocked" "skipped"] } | length)
    let payload = {
        format: 1 project: "Initial-setup" version: (open --raw ($ROOT | path join "VERSION") | str trim)
        platform: $nu.os-info.name nushell: (version).version executable: ($nu.current-exe | into string)
        full_requested: $full offline_cargo: $offline finished: $finished
        optional_external_security: (not $full)
        dependency_note: "Default scope permits security fixtures to skip absent age/rclone. --full requires both. A skipped Rust build is never a successful verification."
        passed: ($results | where status == "passed" | length) failed: $failed incomplete: $incomplete
        verified_requested_scope: ($finished and $failed == 0 and $incomplete == 0)
        coverage: "Native platform only. No production chezmoi apply, Proton server test, Windows/macOS emulation, or implicit multi-version compatibility claim."
        results: $results
    }
    let file = ($directory | path join "summary.json")
    let temp = ($directory | path join ("summary-" + (random uuid) + ".tmp"))
    $payload | to json | save $temp
    mv --force $temp $file
    $payload
}

def main [--full --offline --report-dir: path --skip-build] {
    let parent = if $report_dir != null { $report_dir | path expand } else {
        $env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand
    }
    let directory = ($parent | path join ("initial-setup-verify-" + (random uuid)))
    mkdir $directory
    print ("[reports] " + ($directory | into string))
    mut results = []
    let preflight = (invoke "diagnose-project.nu" ["--manifest" "--strict-manifest" "--require-runtime"] $directory "preflight")
    $results = ($results | append $preflight)
    if $preflight.status != "passed" {
        # A broken archive/old interpreter cannot safely execute the remaining scripts.
        $results = ($results | append {name: "remaining-checks" status: "blocked" reason: "Fix preflight errors before executing project code."})
        write-summary $directory $results $full $offline true | ignore
        exit 1
    }
    let syntax = (invoke "validate-syntax.nu" ["--deny-warnings" "--report" ($directory | path join "syntax.json")] $directory "syntax")
    $results = ($results | append $syntax)
    # Still run independent fixtures: one bad module must not hide unrelated errors.
    for stage in [
        {name: "structure" script: "validate-project.nu" args: []}
        {name: "wiki-docs" script: "wiki-docs-test.nu" args: []}
        {name: "entrypoints" script: "entrypoint-test.nu" args: []}
        {name: "syntax-fixtures" script: "syntax-self-test.nu" args: []}
        {name: "runtime-fixtures" script: "nu-runtime-test.nu" args: []}
        {name: "regressions" script: "regression-test.nu" args: []}
        {name: "rclone-fixtures" script: "rclone-install-test.nu" args: []}
        {name: "subprocess-diagnostics" script: "process-output-test.nu" args: ["--external"]}
        {name: "locks" script: "lock-test.nu" args: []}
        {name: "managed-editor" script: "edit-managed-test.nu" args: []}
        {name: "vault-init" script: "vault-init-test.nu" args: []}
        {name: "command-refresh" script: "refresh-commands-test.nu" args: []}
        {name: "subprocess-chain" script: "subprocess-chain-test.nu" args: []}
        {name: "run-state" script: "run-state-test.nu" args: []}
    ] {
        let row = (invoke $stage.script $stage.args $directory $stage.name)
        $results = ($results | append $row)
        write-summary $directory $results $full $offline false | ignore
    }
    if $nu.os-info.name in ["linux" "macos"] {
        let posix = (invoke "posix-bootstrap-test.nu" [] $directory "posix-bootstrap")
        $results = ($results | append $posix)
        write-summary $directory $results $full $offline false | ignore
    }
    let cargo_available = (not (which cargo | is-empty) and not (which rustc | is-empty))
    if $skip_build or not $cargo_available {
        $results = ($results | append {name: "rust-build-tests" status: "skipped" reason: (if $skip_build { "--skip-build requested" } else { "Rust/Cargo not found" })})
        $results = ($results | append {name: "cloud-engine-integration" status: "blocked" reason: "No successful build/test stage in this verification run."})
        $results = ($results | append (invoke "cloud-wins-test.nu" [] $directory "cloud-control"))
    } else {
        let args = if $offline { ["--test" "--offline"] } else { ["--test"] }
        let built = (invoke "cloud-wins-build.nu" $args $directory "rust-build-tests")
        $results = ($results | append $built)
        if $built.status == "passed" {
            $results = ($results | append (invoke "cloud-wins-test.nu" ["--require-engine"] $directory "cloud-engine-integration"))
        } else {
            $results = ($results | append {name: "cloud-engine-integration" status: "blocked" reason: "Cargo stage failed; no engine success assumed."})
        }
    }
    $results = ($results | append (invoke "self-test.nu" ["--sandbox" "--setup-only"] $directory "setup-sandbox"))
    let security_args = if $full { ["--require-age" "--require-rclone"] } else { [] }
    let security = (invoke "security-self-test.nu" $security_args $directory "security")
    $results = ($results | append $security)
    let summary = (write-summary $directory $results $full $offline true)
    print ("[summary] " + ($directory | path join "summary.json"))
    if not $summary.verified_requested_scope { exit 1 }
    print "[pass] Requested checks completed on this interpreter/platform. See scope limitations in summary.json."
}
