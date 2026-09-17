#!/usr/bin/env nu
const MODULE = path self ./modules/planner.nu
use $MODULE [build-plan save-plan]

def show [plan: record] {
    print "Initial-setup Plan"
    print "────────────────────────────────────────────────────────────"
    print ("Machine   : " + $plan.machine)
    print ("Profile   : " + $plan.profile)
    print ("Direction : " + $plan.direction)
    print ("Provider  : " + $plan.transport.kind + " / reachable=" + ($plan.transport.available | into string))
    print ("Revision  : " + $plan.transport.revision)
    print ("Vault     : " + ($plan.encrypted_vault_configured | into string))
    print ("Packages  : " + (($plan.missing_packages | length) | into string) + " missing")
    for item in $plan.missing_packages { print ("  + " + $item.name + " (" + $item.command + ")") }
    print ("Config    : " + ($plan.config.count | into string) + " changed target(s)")
    for line in $plan.config.lines { print ("  " + $line) }
    print ("Protected : " + (($plan.protected_conflicts | length) | into string) + " conflict(s)")
    for item in $plan.protected_conflicts { print ("  ! " + $item.target) }
    print ("Toolchain : " + (($plan.toolchain_drift | length) | into string) + " drift/missing")
    for item in $plan.toolchain_drift { print ("  ~ " + $item.name + " desired=" + $item.desired + " actual=" + (if ($item.actual | is-empty) { "missing" } else { $item.actual })) }
}

def main [--direction: string = "none" --no-save] {
    let plan = (build-plan $direction)
    show $plan
    if not $no_save {
        let file = (save-plan $plan)
        print ""
        print ("[save] Plan -> " + ($file | into string))
    }
}
