#!/usr/bin/env nu
const PLANNER = path self ./modules/planner.nu
use $PLANNER [build-plan resolve-plan-path]

def main [--plan: string = ""] {
    let file = (resolve-plan-path $plan)
    let original = (open $file)
    let direction = ($original.direction? | default "none")
    let current = (build-plan $direction)
    mut failures = []

    if not ($current.missing_packages | is-empty) { $failures = ($failures | append ("Missing packages remain: " + (($current.missing_packages | get name) | str join ", "))) }
    if not ($current.toolchain_drift | is-empty) { $failures = ($failures | append ("Toolchain drift remains: " + (($current.toolchain_drift | get name) | str join ", "))) }
    if $direction in ["pull" "push"] and (($current.config.diff_count? | default 0) > 0 or not ($current.config.verify_ok? | default false)) { $failures = ($failures | append ("chezmoi target still differs from the destination.")) }
    if not ($current.protected_conflicts | is-empty) { $failures = ($failures | append ("Protected conflicts remain: " + (($current.protected_conflicts | length) | into string))) }

    print "Plan verification"
    print "────────────────────────────────────────────────────────────"
    if ($failures | is-empty) { print "[ok] Desired state verified."; return }
    for item in $failures { print ("[FAIL] " + $item) }
    exit 1
}
