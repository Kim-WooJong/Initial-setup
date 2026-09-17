#!/usr/bin/env nu
const TOOLS_ROOT = path self ..
const PLANNER = path self ./modules/planner.nu
use $PLANNER [resolve-plan-path]
const PROVIDER = path self ./modules/sync-provider.nu
use $PROVIDER [load-provider provider-head provider-id]
const RCLONE = path self ./modules/rclone-install.nu
use $RCLONE [refresh-rclone-path ensure-rclone]

def run-plan-script [script: string ...args: string] {
    let exe = $nu.current-exe
    ^$exe --no-config-file ($TOOLS_ROOT | path join "scripts" $script) ...$args
    if ($env.LAST_EXIT_CODE | default 0) != 0 { error make { msg: ("Plan action failed: " + $script) } }
}

def main [--plan: string = "" --yes] {
    let file = (resolve-plan-path $plan)
    let plan_data = (open $file)
    let current_version = (open --raw ($TOOLS_ROOT | path join "VERSION") | str trim)
    if ($plan_data.app_version? | default "") != $current_version {
        error make { msg: ("Plan was created by Initial-setup " + ($plan_data.app_version? | default "unknown") + "; create a new plan for " + $current_version + ".") }
    }
    if ($plan_data.direction? | default "none") == "pull" and not (($plan_data.protected_conflicts? | default []) | is-empty) {
        error make { msg: "Protected configuration conflicts exist. Run dotresolve before applying a pull plan." }
    }
    if ($plan_data.direction? | default "none") != "none" {
        let transport = ($plan_data.transport? | default {})
        if not ($transport.available? | default false) { error make {msg: "Plan has no verified provider state. Create a new reachable plan."} }
        if ($plan_data.direction? | default "none") == "push" and (($transport.baseline_missing? | default true) or ($transport.remote_changed? | default true)) {
            error make {msg: "Push plan lacks a reconciled baseline. Resolve provider state before any package/tool changes."}
        }
        let provider = (load-provider)
        let current = (provider-head $provider)
        if (provider-id $provider) != $transport.provider_id or $current.revision != $transport.revision or $current.tree_hash != $transport.tree_hash {
            error make {msg: "Provider or remote changed after planning. No plan actions were started; run dotplan again."}
        }
    }
    print ("Applying plan: " + ($file | into string))
    print ("Direction    : " + ($plan_data.direction? | default "none"))
    print ("Packages     : " + (($plan_data.missing_packages? | default [] | length) | into string) + " missing")
    print ("Toolchain    : " + (($plan_data.toolchain_drift? | default [] | length) | into string) + " drift/missing")
    print ("Protected    : " + (($plan_data.protected_conflicts? | default [] | length) | into string) + " conflict(s)")

    if not $yes {
        let answer = (input "Apply this plan? [y/N]: " | str trim)
        if not ($answer in ["y" "Y" "yes" "YES"]) { print "Cancelled."; return }
    }

    # Do not install during planning, provider validation, or a declined plan.
    run-plan-script "install-rclone.nu"
    refresh-rclone-path
    ensure-rclone --check | ignore
    if not (($plan_data.missing_packages? | default []) | is-empty) { run-plan-script "install-cli-tools.nu" }
    let actionable_toolchain_drift = (($plan_data.toolchain_drift? | default []) | where { |item| $item.name in ["rust" "julia"] })
    if not ($actionable_toolchain_drift | is-empty) {
        run-plan-script "install-language-tools.nu"
        run-plan-script "toolchain-state.nu" "--apply"
    }

    match ($plan_data.direction? | default "none") {
        "pull" => { run-plan-script "backup-local-config.nu" "--label" "before-dotapply"; run-plan-script "sync-down.nu" "--force" }
        "push" => { run-plan-script "sync-up.nu" }
        _ => { print "[skip] Configuration direction is none." }
    }

    run-plan-script "verify-plan.nu" "--plan" ($file | into string)
}
