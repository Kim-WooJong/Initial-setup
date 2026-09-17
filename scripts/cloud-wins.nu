#!/usr/bin/env nu
# Select the established project runtime before importing business modules.
const RUNTIME = path self ./modules/nu-runtime.nu
const IMPL = path self ./cloud-wins-main.nu
use $RUNTIME [runtime-execute]

def --wrapped main [action: string = "help" ...args: string] {
    if $action == "help" or "--help" in $args {
        print "dotcloud configure --source <mirror> --target <local-workspace> [--execute]"
        print "dotcloud probe | plan | verify | status"
        print "dotcloud apply --plan <file> [--execute --confirm <plan-id>]"
        print "dotcloud activate [--execute --confirm activate-local-workspace]"
        print "dotcloud rollback --run <id> [--execute --confirm <run-id>]"
        print "dotcloud deactivate [--execute --confirm restore-previous-mode]"
        print "Build/test helper first: nu --no-config-file scripts/cloud-wins-build.nu --test"
        return
    }
    let mutation = ($action in ["apply" "rollback" "configure" "activate" "deactivate"] and "--execute" in $args)
    # Recovery/status use a previously validated cached runtime, never a registry
    # lookup. This is synchronous execution, not a background service.
    let recovery = ($action in ["status" "rollback" "deactivate"])
    runtime-execute $IMPL ([$action] | append $args) --read-only=(not $mutation) --background=$recovery
}
