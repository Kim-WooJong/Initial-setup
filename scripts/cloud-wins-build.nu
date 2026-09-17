#!/usr/bin/env nu
# Compile from a private local cache, not inside a cloud-synchronized checkout.
const OUTPUT = path self ./modules/process-output.nu
use $OUTPUT [output-text]
const ROOT = path self ..
const ENGINE = path self ./modules/cloud-wins-engine.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
use $ENGINE [cloud-build-layout]
use $SAFETY [private-directory atomic-record operation-lease release-lease]
use $CORE [error-message failure-envelope captured-failure]

def checked-cargo [args: list] {
    ^cargo ...$args
    if ($env.LAST_EXIT_CODE | default 1) != 0 { error make {msg: "Cargo failed; no successful build receipt was written."} }
}
def main [--test --offline] {
    if (which cargo | is-empty) or (which rustc | is-empty) {
        error make {msg: "Rust/Cargo >=1.89 is required for the optional cloud-wins engine."}
    }
    let layout = (cloud-build-layout)
    let lease = (operation-lease)
    let result = (try {
        private-directory $layout.root
        private-directory $layout.build_source
        for row in $layout.inputs {
            let destination = ($layout.build_source | path join $row.path)
            mkdir ($destination | path dirname)
            cp --force ($layout.source | path join $row.path) $destination
            if (open --raw $destination | hash sha256) != $row.sha256 {
                error make {msg: ("BUILD_SOURCE_CHANGED: copied input differs from the reviewed source hash: " + $row.path)}
            }
        }
        # Honor the local compiler, but choose its host explicitly, not a user's
        # CARGO_BUILD_TARGET. This command does not change Rustup defaults.
        let rust = (do { ^rustc -vV } | complete)
        if $rust.exit_code != 0 { error make {msg: "Cannot query rustc host."} }
        let host_rows = ($rust.stdout | output-text | lines | where {|line| $line | str starts-with "host: "})
        if ($host_rows | length) != 1 { error make {msg: "Cannot identify rustc host triple."} }
        let host = ($host_rows | first | str replace "host: " "" | str trim)
        let manifest = ($layout.build_source | path join "Cargo.toml")
        cd $layout.build_source
        let offline_args = if $offline { ["--offline"] } else { [] }
        # First build resolves dependencies here; subsequent builds reuse this
        # locally retained lock. No claim of a cross-machine pinned release lock.
        if not ("Cargo.lock" | path exists) {
            checked-cargo (["generate-lockfile" "--manifest-path" $manifest] | append $offline_args)
        }
        let common = ["--manifest-path" $manifest "--target-dir" $layout.target_dir "--target" $host "--locked"]
        checked-cargo (["check"] | append $common | append $offline_args)
        if $test { checked-cargo (["test"] | append $common | append $offline_args) }
        checked-cargo (["build" "--release"] | append $common | append $offline_args)
        let name = if $nu.os-info.name == "windows" { "cloudwins.exe" } else { "cloudwins" }
        let exe = ($layout.target_dir | path join $host "release" $name)
        let version = (do { ^$exe --version } | complete)
        let expected_version = (open --raw ($ROOT | path join "VERSION") | str trim)
        if $version.exit_code != 0 or ($version.stdout | output-text | str trim) != ("cloudwins " + $expected_version) {
            error make {msg: "Built helper did not report the expected version."}
        }
        atomic-record $layout.receipt {
            version: 1 source_hash: $layout.source_hash exe: ($exe | into string)
            sha256: (open --raw $exe | hash sha256)
            cargo_lock_sha256: (open --raw "Cargo.lock" | hash sha256)
            host: $host tests_executed: $test built_at: (date now | format date "%+")
        }
        print {built: true exe: $exe tests_executed: $test receipt: $layout.receipt}
        null
    } catch {|err| failure-envelope {msg: (error-message $err "cloudwins build failed.")} })
    let failed = (captured-failure $result)
    let cleanup = (try { release-lease $lease; null } catch {|err| failure-envelope {msg: (error-message $err "Could not release build lease.")} })
    let cleanup_failure = (captured-failure $cleanup)
    if $failed != null {
        if $cleanup_failure != null { print --stderr $cleanup_failure.msg }
        error make {msg: $failed.msg}
    }
    if $cleanup_failure != null { error make {msg: $cleanup_failure.msg} }
}
