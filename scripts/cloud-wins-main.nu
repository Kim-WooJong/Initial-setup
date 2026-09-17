#!/usr/bin/env nu
const ROOT = path self ..
const CONFIG = path self ./modules/cloud-wins-config.nu
const ENGINE = path self ./modules/cloud-wins-engine.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
const PROVIDER = path self ./modules/sync-provider.nu
use $CONFIG [cloud-config-path load-cloud-config cloud-mode-active cloud-roots cloud-state-dir assert-cloud-workspace]
use $ENGINE [cloud-engine engine-json]
use $SAFETY [operation-lease release-lease state-root atomic-record private-directory disjoint-paths]
use $CORE [machine-context machine-config-path error-message failure-envelope captured-failure]
use $PROVIDER [load-provider audit-export]

def print-help [] {
    print "dotcloud configure --source <mirror> --target <existing-local-workspace> [--execute]"
    print "dotcloud probe | plan | verify | status"
    print "dotcloud apply --plan <plan-file> [--execute --confirm <plan-id>]"
    print "dotcloud activate [--execute --confirm activate-local-workspace]"
    print "dotpull    # applies the approved workspace; protected-file checks remain"
    print "dotcloud rollback --run <run-id> [--execute --confirm <run-id>]"
    print "dotcloud deactivate [--execute --confirm restore-previous-mode]"
    print "Build first: nu --no-config-file scripts/cloud-wins-build.nu --test"
    print "No server freshness claim. No automatic upload. No target-only deletion."
}
def selected-roots [source: string target: string] {
    let config = (load-cloud-config)
    let src = if not ($source | is-empty) { $source } else { $config.source? | default "" }
    let dst = if not ($target | is-empty) { $target } else { $config.target? | default "" }
    let selected = (cloud-roots $src $dst)
    disjoint-paths $ROOT $selected.source
    disjoint-paths $ROOT $selected.target
    if $config != null and $config.active {
        if ($selected.source | path expand) != ($config.source | path expand) or ($selected.target | path expand) != ($config.target | path expand) {
            error make {msg: "Do not change roots while cloud-wins is active. Deactivate and review a new configuration first."}
        }
    }
    $selected
}
def configure [source: string target: string execute: bool] {
    if (cloud-mode-active) { error make {msg: "cloud-wins is already active; deactivate before reconfiguration."} }
    let r = (selected-roots $source $target)
    if not $execute {
        return {dry_run: true source: $r.source target: $r.target state_dir: $r.state_dir changes_machine_config: false}
    }
    # Cloud mode is opt-in; this step does NOT change data_root or scheduler policy.
    private-directory (state-root)
    let file = (cloud-config-path)
    if ($file | path exists) {
        let backup = ((state-root) | path join "cloud-control-backups" ((random uuid) + ".nuon"))
        private-directory ($backup | path dirname)
        cp $file $backup
    }
    atomic-record $file {version: 1 source: $r.source target: $r.target active: false}
    {configured: true active: false state_dir: $r.state_dir next: "dotcloud plan"}
}
def activate [execute: bool confirm: string settle_ms: int] {
    let config = (load-cloud-config)
    if $config == null { error make {msg: "Configure cloud-wins first."} }
    if $config.active { error make {msg: "cloud-wins is already active; use status/deactivate."} }
    let r = (selected-roots "" "")
    let context = (machine-context)
    let provider = (load-provider)
    if $provider.kind != "directory" { error make {msg: "Activation is only supported for the directory provider. Existing local/rclone providers are not changed."} }
    if ($context.data_root | path expand) != ($r.source | path expand) {
        error make {msg: "Activation requires the current machine data_root to be the configured mirror source."}
    }
    let exe = (cloud-engine)
    engine-json $exe ["verify" "--source" $r.source "--target" $r.target "--state-dir" $r.state_dir "--settle-ms" ($settle_ms | into string)] | ignore
    let selector = ($r.target | path join ".chezmoiroot")
    if not ($selector | path exists) or (open --raw $selector | str trim) != "home" or not ($r.target | path join "home" | path exists) {
        error make {msg: "Target is not an Initial-setup private source (.chezmoiroot must select home)."}
    }
    audit-export $r.target
    let updated = ($context | upsert data_root $r.target | upsert sync.enabled false | upsert sync.auto_push false | upsert sync.auto_pull false | upsert sync.prune_extras false)
    if not $execute { return {dry_run: true data_root_before: $context.data_root data_root_after: $r.target auto_sync_after: false} }
    if $confirm != "activate-local-workspace" { error make {msg: "Use --execute --confirm activate-local-workspace after reviewing the verified workspace."} }
    let backup = ((state-root) | path join "cloud-control-backups" ((random uuid) + ".nuon"))
    private-directory ($backup | path dirname)
    cp (machine-config-path) $backup
    # Fail closed: save the active blocker FIRST. A crash between these writes
    # blocks push/setup and is recoverable with deactivate, not an implicit push.
    atomic-record (cloud-config-path) ($config | upsert active true | upsert previous_context $context | upsert activated_context $updated | upsert machine_backup ($backup | into string))
    atomic-record (machine-config-path) $updated
    {active: true data_root: $r.target source_read_only: $r.source auto_sync: false next: "dotpull (review protected conflicts; no implicit force)"}
}
def deactivate [execute: bool confirm: string] {
    let config = (load-cloud-config)
    if $config == null or not $config.active { error make {msg: "cloud-wins is not active."} }
    let context = (machine-context)
    if $context != $config.activated_context and $context != $config.previous_context {
        error make {msg: "Machine config changed after activation. Refusing to overwrite those edits; compare the retained machine backup first."}
    }
    if not $execute { return {dry_run: true restores_data_root: $config.previous_context.data_root restores_previous_sync_policy: true} }
    if $confirm != "restore-previous-mode" { error make {msg: "Use --execute --confirm restore-previous-mode. This restores the previous bidirectional/automatic policy."} }
    # Restore machine state FIRST; until the second write succeeds, the active
    # blocker still prevents automatic/push writes into the mirror.
    atomic-record (machine-config-path) $config.previous_context
    atomic-record (cloud-config-path) {version: 1 source: $config.source target: $config.target active: false}
    {active: false restored_data_root: $config.previous_context.data_root note: "Previous sync policy restored. Review dotbackend status before publishing."}
}
def perform [options: record] {
    let action = $options.action
    if $action == "configure" { return (configure $options.source $options.target $options.execute) }
    if $action == "activate" { return (activate $options.execute $options.confirm $options.settle_ms) }
    if $action == "deactivate" { return (deactivate $options.execute $options.confirm) }
    if $action == "status" {
        let config = (load-cloud-config)
        let target = if not ($options.target | is-empty) { $options.target } else { $config.target? | default "" }
        if ($target | is-empty) { return {control: $config engine: "unconfigured"} }
        let state = (cloud-state-dir $target)
        let exe = (try { cloud-engine } catch { null })
        if $exe == null { return {control: $config engine: "not-built-or-receipt-invalid" state_dir: $state} }
        return {control: $config engine: (engine-json $exe ["status" "--target" $target "--state-dir" $state])}
    }
    let exe = (cloud-engine)
    if $action == "apply" {
        if ($options.plan | is-empty) { error make {msg: "apply requires --plan."} }
        let plan = (open --raw $options.plan | from json)
        let r = (selected-roots ($plan.source | into string) ($plan.target | into string))
        if ($plan.state_dir | path expand) != ($r.state_dir | path expand) { error make {msg: "Plan is outside this workspace's local state directory."} }
        # In integrated mode, the configured roots are authoritative even before activation.
        let config = (load-cloud-config)
        if $config != null and (($config.source | path expand) != ($r.source | path expand) or ($config.target | path expand) != ($r.target | path expand)) {
            error make {msg: "Plan does not match the configured roots. Reconfigure explicitly first."}
        }
        if $options.execute { private-directory $r.state_dir }
        mut args = ["apply" "--plan" $options.plan]
        if $options.execute { $args = ($args | append ["--execute" "--confirm" $options.confirm]) }
        return (engine-json $exe $args)
    }
    if $action == "rollback" {
        # Do not inspect the source here: cloud-unavailable rollback is supported.
        let config = (load-cloud-config)
        let target = if not ($options.target | is-empty) { $options.target } else { $config.target? | default "" }
        if ($target | is-empty) or ($options.run | is-empty) { error make {msg: "rollback requires a configured/explicit target and --run."} }
        if $config != null and $config.active and ($target | path expand) != ($config.target | path expand) { error make {msg: "Active workspace target mismatch."} }
        let state = (cloud-state-dir $target)
        disjoint-paths $ROOT $target
        disjoint-paths (state-root) $target
        mut args = ["rollback" "--target" $target "--state-dir" $state "--run" $options.run]
        if $options.execute { $args = ($args | append ["--execute" "--confirm" $options.confirm]) }
        return (engine-json $exe $args)
    }
    if $action not-in ["probe" "plan" "verify"] { error make {msg: "Unknown cloud-wins action; run dotcloud help."} }
    let r = (selected-roots $options.source $options.target)
    if $action == "plan" { private-directory $r.state_dir }
    engine-json $exe [$action "--source" $r.source "--target" $r.target "--state-dir" $r.state_dir "--settle-ms" ($options.settle_ms | into string)]
}

def main [
    action: string = "help"
    --source: string = ""
    --target: string = ""
    --plan: string = ""
    --run: string = ""
    --settle-ms: int = 1500
    --execute
    --confirm: string = ""
] {
    if $action == "help" { print-help; return }
    if $settle_ms < 0 or $settle_ms > 60000 { error make {msg: "settle-ms must be between 0 and 60000."} }
    let options = {action: $action source: $source target: $target plan: $plan run: $run settle_ms: $settle_ms execute: $execute confirm: $confirm}
    # All engine invocations share the same operation lease as manual/auto sync.
    # No force unlock and no lock-age heuristic are introduced.
    let lease = (operation-lease)
    let outcome = (try { {value: (perform $options)} } catch {|err| failure-envelope {msg: (error-message $err "cloud-wins failed.")} })
    let failed = (captured-failure $outcome)
    let cleanup = (try { release-lease $lease; null } catch {|err| failure-envelope {msg: (error-message $err "Could not release cloud operation lease.")} })
    let cleanup_failure = (captured-failure $cleanup)
    if $failed != null {
        if $cleanup_failure != null { print --stderr $cleanup_failure.msg }
        error make {msg: $failed.msg}
    }
    if $cleanup_failure != null { error make {msg: $cleanup_failure.msg} }
    $outcome.value | to json
}
