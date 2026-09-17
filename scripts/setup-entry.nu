#!/usr/bin/env nu
# Compatibility entry point. No business modules are parsed before runtime setup.
const RUNTIME = path self ./modules/nu-runtime.nu
const IMPL = path self ../setup-main.nu
const VALIDATOR = path self ./validate-project.nu
use $RUNTIME [runtime-execute]
def main [
    --mode: string = "auto"
    --data-dir: string = ""
    --profile: string = ""
    --config-policy: string = "ask"
    --no-auto-sync
    --dry-run
    --resume
    --run-id: string = ""
    --validate
] {
    mut args = ["--mode" $mode "--data-dir" $data_dir "--profile" $profile "--config-policy" $config_policy "--run-id" $run_id]
    if $no_auto_sync { $args = ($args | append "--no-auto-sync") }
    if $dry_run { $args = ($args | append "--dry-run") }
    if $resume { $args = ($args | append "--resume") }
    if $validate { $args = ($args | append "--validate") }
    let preview = ($dry_run or $config_policy == "preview")
    let preflight = if $preview and not $validate { "" } else { $VALIDATOR }
    runtime-execute $IMPL $args --read-only=$preview --preflight $preflight
}
