#!/usr/bin/env nu
# Isolated regressions. No Proton account, production HOME, or real chezmoi apply.
const ROOT = path self ..
const IMPL = path self ./cloud-wins-main.nu
const CONFIG = path self ./modules/cloud-wins-config.nu
const ENGINE = path self ./modules/cloud-wins-engine.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
const OUTPUT = path self ./modules/process-output.nu
use $CONFIG [cloud-config-path cloud-state-dir]
use $ENGINE [cloud-build-layout cloud-engine]
use $SAFETY [state-root atomic-record]
use $CORE [machine-config-path error-message failure-envelope captured-failure]
use $OUTPUT [output-text]

def check [condition: bool message: string] {
    if not $condition { error make {msg: ("[cloud-test] " + $message)} }
}
def child [script: path args: list --expect-failure: string = ""] {
    let exe = $nu.current-exe
    let result = (do { ^$exe --no-config-file $script ...$args } | complete)
    let stdout = ($result.stdout | output-text)
    let stderr = ($result.stderr | output-text)
    if not ($expect_failure | is-empty) {
        check ($result.exit_code != 0) "A negative test unexpectedly succeeded."
        check (($stdout + $stderr) | str contains $expect_failure) ("Wrong failure diagnostic: " + $stdout + $stderr)
        return null
    }
    if $result.exit_code != 0 { error make {msg: ($stdout + $stderr)} }
    $stdout
}
def call [args: list] { child $IMPL $args | from json }

def test-body [base: path helper: any] {
    let source = ($base | path join "Proton mirror 한글")
    let target = ($base | path join "local workspace")
    mkdir ($source | path join "home") $target (state-root)
    "home" | save ($source | path join ".chezmoiroot")
    "[user]\n    name = cloud-test\n" | save ($source | path join "home" "dot_gitconfig")
    "keep me" | save ($target | path join "local-only.txt")
    let original = {
        app_version: "0.13.2" schema_version: 5 data_root: ($source | into string) tools_root: ($ROOT | into string)
        machine: {name: "cloud-wins-sandbox" profile: "minimal" install_gui_apps: false}
        sync: {enabled: true auto_push: true auto_pull: true interval_minutes: 1 conflict_policy: "stop" stability_delay_seconds: 0 prune_extras: true}
        features: {rust: false julia: false vscode: false rclone_config: false}
        maintenance: {snapshots_enabled: false snapshot_keep: 2 log_keep_lines: 100}
    }
    atomic-record (machine-config-path) $original
    let preview = (call ["configure" "--source" $source "--target" $target])
    check $preview.dry_run "configure is not preview-first"
    check (not (cloud-config-path | path exists)) "Preview wrote cloud control configuration."
    check ((open --raw (machine-config-path) | from nuon) == $original) "Preview changed machine config."
    child $IMPL ["configure" "--source" $source "--target" $source "--execute"] --expect-failure "overlap" | ignore
    call ["configure" "--source" $source "--target" $target "--execute"] | ignore
    let configured = (open --raw (cloud-config-path) | from nuon)
    check (not $configured.active) "configure activated unexpectedly"
    check ((open --raw (machine-config-path) | from nuon) == $original) "configure changed data_root"
    # Simulate interruption between fail-closed blocker and machine-config write.
    let activated = ($original | upsert data_root ($target | into string) | upsert sync.enabled false | upsert sync.auto_push false | upsert sync.auto_pull false | upsert sync.prune_extras false)
    atomic-record (cloud-config-path) ($configured | upsert active true | upsert previous_context $original | upsert activated_context $activated)
    child ($ROOT | path join "scripts" "sync-transport-main.nu") ["push"] --expect-failure "cloud-wins is active" | ignore
    child ($ROOT | path join "scripts" "auto-sync-worker.nu") [] | ignore
    child ($ROOT | path join "scripts" "backend-control.nu") ["configure" "--kind" "rclone" "--remote" "test:unused"] --expect-failure "Deactivate cloud-wins" | ignore
    call ["deactivate" "--execute" "--confirm" "restore-previous-mode"] | ignore
    check ((open --raw (machine-config-path) | from nuon) == $original) "Interrupted activation recovery changed machine config"
    print "[ok] cloud control: preview, explicit configuration, push/backend/auto guards, interrupted activation recovery"
    if $helper == null {
        print "[SKIP] Rust-backed cloud integration: helper not built. Run verify.nu for the required engine gate."
        return
    }
    let layout = (cloud-build-layout)
    mkdir $layout.root
    atomic-record $layout.receipt {version: 1 source_hash: $layout.source_hash exe: ($helper | into string) sha256: (open --raw $helper | hash sha256)}
    let plan = (call ["plan" "--settle-ms" "0"])
    check ($plan.create == 2) "unexpected source inventory"
    check ($plan.target_only_files_ignored == 1) "target-only file was not retained"
    call ["apply" "--plan" $plan.plan_file] | ignore
    check (not ($target | path join ".chezmoiroot" | path exists)) "apply preview copied data"
    child $IMPL ["apply" "--plan" $plan.plan_file "--execute" "--confirm" "wrong"] --expect-failure "confirm" | ignore
    let applied = (call ["apply" "--plan" $plan.plan_file "--execute" "--confirm" $plan.plan_id])
    check $applied.applied "apply did not report success"
    check ((open --raw ($target | path join "local-only.txt")) == "keep me") "target-only file changed"
    call ["activate" "--settle-ms" "0"] | ignore
    check ((open --raw (machine-config-path) | from nuon) == $original) "activation preview changed config"
    call ["activate" "--settle-ms" "0" "--execute" "--confirm" "activate-local-workspace"] | ignore
    let context = (open --raw (machine-config-path) | from nuon)
    check ($context.data_root == ($target | into string)) "activation did not switch data_root"
    check (not $context.sync.enabled and not $context.sync.auto_push and not $context.sync.auto_pull) "activation did not disable autosync"
    check (not $context.sync.prune_extras) "activation did not disable configured pruning"
    child ($ROOT | path join "scripts" "sync-transport-main.nu") ["push"] --expect-failure "cloud-wins is active" | ignore
    child ($ROOT | path join "scripts" "sync-transport-main.nu") ["pull" "--prune"] --expect-failure "Pruning is disabled" | ignore
    # A full live chezmoi apply is deliberately not run by these fixtures.
    call ["rollback" "--run" $applied.run_id] | ignore
    call ["rollback" "--run" $applied.run_id "--execute" "--confirm" $applied.run_id] | ignore
    check (not ($target | path join ".chezmoiroot" | path exists)) "rollback did not remove its created file"
    check ((open --raw ($source | path join ".chezmoiroot")) == "home") "source content changed"
    call ["deactivate" "--execute" "--confirm" "restore-previous-mode"] | ignore
    check ((open --raw (machine-config-path) | from nuon) == $original) "deactivation did not restore original machine config"
    print "[ok] cloud engine integration: plan, preview, confirmation, apply, activation, rollback, deactivation"
}

def main [--require-engine --keep] {
    let helper = (try { cloud-engine } catch { null })
    if $require_engine and $helper == null { error make {msg: "Build the Rust helper with cloud-wins-build.nu --test before the required integration gate."} }
    let temporary = if $nu.os-info.name == "windows" { $env.TEMP? | default $env.TMP? } else { $env.TMPDIR? | default "/tmp" }
    if $temporary == null or ($temporary | is-empty) { error make {msg: "No temporary directory configured."} }
    let base = ($temporary | path expand | path join ("initial-setup-cloud-test-" + (random uuid)))
    mkdir $base
    let home = ($base | path join "home")
    mkdir $home
    let result = (with-env {
        INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($home | into string)
        HOME: ($home | into string) USERPROFILE: ($home | into string)
        XDG_CONFIG_HOME: ($home | path join ".config") XDG_CACHE_HOME: ($home | path join ".cache")
        APPDATA: ($home | path join "AppData" "Roaming") LOCALAPPDATA: ($home | path join "AppData" "Local")
    } {
        try { test-body $base $helper; null } catch {|err| failure-envelope {msg: (error-message $err "cloud-wins regression failed.")} }
    })
    let failed = (captured-failure $result)
    if $keep or $failed != null { print ("[fixture] " + ($base | into string)) } else { rm --recursive $base }
    if $failed != null { error make {msg: $failed.msg} }
}
