#!/usr/bin/env nu
# Continue across INDEPENDENT tests; never continue an unsafe setup/apply.
# No production setup or Proton access. Cargo builds only the local helper cache.
# Reports contain paths/diagnostics; inspect them before sharing.
const ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $SUBPROCESS [run-command]
use $INSTALL_UTILS [probe-tool]

def save-log [file: path content: string] {
    let temp = (($file | path dirname) | path join ((random uuid) + ".tmp"))
    $content | save $temp
    mv --force $temp $file
}

def invoke [script: string args: list directory: path name: string] {
    let exe = ($nu.current-exe | into string)
    let path = ($ROOT | path join "scripts" $script)
    let started = (date now)
    let result = (run-command $exe (["--no-config-file" ($path | into string)] | append $args))
    let out = ($result.stdout? | default "")
    let err = if $result.launched { ($result.stderr? | default "") } else { ($result.launch_error? | default "Child process failed to launch") }
    let log = ($directory | path join ($name + ".log"))
    save-log $log ([$out $err] | where {|x| not ($x | is-empty) } | str join (char nl))
    let ok = $result.ok
    print ((if $ok { "[pass] " } else { "[FAIL] " }) + $name + " -> " + ($log | into string))
    if not $ok and not ($err | is-empty) { print --stderr $err }
    {
        name: $name
        status: (if $ok { "passed" } else { "failed" })
        launched: $result.launched
        exit_code: (if $result.exit_code == null { 1 } else { $result.exit_code })
        elapsed: ((date now) - $started | into string)
        log: ($log | into string)
    }
}

def write-summary [directory: path results: list full: bool offline: bool finished: bool working_tree: bool] {
    let failed = ($results | where status == "failed" | length)
    let incomplete = ($results | where {|r| $r.status in ["blocked" "skipped"] } | length)
    let payload = {
        format: 1 project: "Initial-setup" version: (open --raw ($ROOT | path join "VERSION") | str trim)
        platform: $nu.os-info.name nushell: (version).version executable: ($nu.current-exe | into string)
        full_requested: $full offline_cargo: $offline finished: $finished
        working_tree_mode: $working_tree
        release_manifest_enforced: (not $working_tree)
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

def main [--full --offline --report-dir: path --skip-build --working-tree] {
    let parent = if $report_dir != null { $report_dir | path expand } else {
        $env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand
    }
    let directory = ($parent | path join ("initial-setup-verify-" + (random uuid)))
    mkdir $directory
    print ("[reports] " + ($directory | into string))
    mut results = []
    let preflight_args = if $working_tree {
        ["--manifest" "--require-runtime"]
    } else {
        ["--manifest" "--strict-manifest" "--require-runtime"]
    }
    let preflight = (invoke "diagnose-project.nu" $preflight_args $directory "preflight")
    $results = ($results | append $preflight)
    if $preflight.status != "passed" {
        # A broken archive/old interpreter cannot safely execute the remaining scripts.
        $results = ($results | append {name: "remaining-checks" status: "blocked" reason: "Fix preflight errors before executing project code."})
        write-summary $directory $results $full $offline true $working_tree | ignore
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
        {name: "rclone-explicit-sync" script: "rclone-explicit-sync-policy-test.nu" args: []}
        {name: "installer-health" script: "installer-health-test.nu" args: []}
        {name: "orchestration-policy" script: "orchestration-policy-test.nu" args: []}
        {name: "interactive-tty-policy" script: "interactive-tty-policy-test.nu" args: []}
        {name: "setup-reconciliation" script: "setup-reconcile-test.nu" args: []}
        {name: "sync-recovery-policy" script: "sync-recovery-policy-test.nu" args: []}
        {name: "diagnostics-policy" script: "diagnostics-policy-test.nu" args: []}
        {name: "production-subprocess-policy" script: "production-subprocess-policy-test.nu" args: []}
        {name: "subprocess-core" script: "subprocess-test.nu" args: []}
        {name: "subprocess-diagnostics" script: "process-output-test.nu" args: ["--external"]}
        {name: "locks" script: "lock-test.nu" args: []}
        {name: "managed-editor" script: "edit-managed-test.nu" args: []}
        {name: "vault-init" script: "vault-init-test.nu" args: []}
        {name: "edit-identity" script: "edit-identity-test.nu" args: []}
        {name: "platform-shim" script: "platform-shim-test.nu" args: []}
        {name: "rpool-install" script: "rpool-install-test.nu" args: []}
        {name: "ssh-key-sync" script: "ssh-key-sync-test.nu" args: []}
        {name: "command-refresh" script: "refresh-commands-test.nu" args: []}
        {name: "command-shim" script: "command-shim-test.nu" args: []}
        {name: "checkout-private" script: "checkout-private-test.nu" args: []}
        {name: "prune-obsolete" script: "prune-obsolete-test.nu" args: []}
        {name: "subprocess-chain" script: "subprocess-chain-test.nu" args: []}
        {name: "run-state" script: "run-state-test.nu" args: []}
        {name: "rpool-sync" script: "rpool-sync-test.nu" args: []}
        {name: "rclone-compare" script: "rclone-compare-test.nu" args: []}
        {name: "rpool-two-machine" script: "rpool-two-machine-test.nu" args: []}
        {name: "wireguard-policy" script: "wireguard-policy-test.nu" args: []}
        {name: "rpool-hidden" script: "rpool-hidden-test.nu" args: []}
        {name: "rpool-resolver" script: "rpool-resolver-test.nu" args: []}
        {name: "migration-errors" script: "migration-error-test.nu" args: []}
    ] {
        let row = (invoke $stage.script $stage.args $directory $stage.name)
        $results = ($results | append $row)
        write-summary $directory $results $full $offline false $working_tree | ignore
    }
    if $nu.os-info.name in ["linux" "macos"] {
        let posix = (invoke "posix-bootstrap-test.nu" [] $directory "posix-bootstrap")
        $results = ($results | append $posix)
        write-summary $directory $results $full $offline false $working_tree | ignore
    }
    let cargo_probe = (probe-tool "cargo" ["--version"])
    let rustc_probe = (probe-tool "rustc" ["--version"])
    let cargo_available = ($cargo_probe.healthy and $rustc_probe.healthy)
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
    let summary = (write-summary $directory $results $full $offline true $working_tree)
    print ("[summary] " + ($directory | path join "summary.json"))
    if not $summary.verified_requested_scope { exit 1 }
    print "[pass] Requested checks completed on this interpreter/platform. See scope limitations in summary.json."
}
