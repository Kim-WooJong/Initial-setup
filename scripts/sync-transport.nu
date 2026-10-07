#!/usr/bin/env nu
# Runtime selection happens BEFORE operation.lock, capture, upload or apply.
const RUNTIME = path self ./modules/nu-runtime.nu
const IMPL = path self ./sync-transport-main.nu
use $RUNTIME [runtime-execute]
def main [action: string --force --prune --allow-protected --source-only --discard-source --discard-local --manual --reload] {
    if $action not-in ["push" "pull"] { error make {msg: "Choose push or pull."} }
    mut args = [$action]
    if $force { $args = ($args | append "--force") }
    if $prune { $args = ($args | append "--prune") }
    if $allow_protected { $args = ($args | append "--allow-protected") }
    if $source_only { $args = ($args | append "--source-only") }
    if $discard_source { $args = ($args | append "--discard-source") }
    if $discard_local { $args = ($args | append "--discard-local") }
    if $manual { $args = ($args | append "--manual") }
    if $reload { $args = ($args | append "--reload") }
    # Sync must not depend on crates.io reachability or on "latest": use the
    # prepared/current supported runtime (see runtime-ensure --prefer-current).
    runtime-execute $IMPL $args --prefer-current
}
