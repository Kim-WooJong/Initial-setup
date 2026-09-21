#!/usr/bin/env nu
# Compile from a private local cache, not inside a cloud-synchronized checkout.
const ROOT = path self ..
const ENGINE = path self ./modules/cloud-wins-engine.nu
const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $ENGINE [cloud-build-layout]
use $SAFETY [private-directory atomic-record operation-lease release-lease]
use $CORE [error-message failure-envelope captured-failure]
use $SUBPROCESS [run-command command-failure-message]

def checked-cargo [args: list] {
    let result = (run-command "cargo" $args --live)
    if not $result.ok {
        error make {msg: ((command-failure-message "Cargo" $result) + (char nl) + "No successful build receipt was written.")}
    }
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
        let rust = (run-command "rustc" ["-vV"])
        if not $rust.ok { error make {msg: (command-failure-message "Query rustc host" $rust)} }
        let host_rows = ($rust.stdout | lines | where {|line| $line | str starts-with "host: "})
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
        let version = (run-command ($exe | into string) ["--version"])
        let expected_version = (open --raw ($ROOT | path join "VERSION") | str trim)
        if not $version.ok or ($version.stdout | str trim) != ("cloudwins " + $expected_version) {
            let detail = if $version.ok { "Unexpected version output: " + ($version.stdout | str trim) } else { command-failure-message "Built cloudwins --version" $version }
            error make {msg: ("Built helper did not report the expected version." + (char nl) + $detail)}
        }
        atomic-record $layout.receipt {
            version: 1 source_hash: $layout.source_hash exe: ($exe | into string)
            sha256: (open --raw $exe | hash sha256)
            cargo_lock_sha256: (open --raw "Cargo.lock" | hash sha256)
            host: $host tests_executed: $test built_at: (date now | format date "%+")
        }
        print {built: true exe: $exe tests_executed: $test receipt: $layout.receipt}
        null
    } catch {|err| failure-envelope $err })
    let failed = (captured-failure $result)
    let cleanup = (try { release-lease $lease; null } catch {|err| failure-envelope $err })
    let cleanup_failure = (captured-failure $cleanup)
    if $failed != null {
        mut message = (error-message $failed "cloudwins build failed.")
        if $cleanup_failure != null { $message = ($message + (char nl) + "Build operation-lock cleanup also failed: " + (error-message $cleanup_failure)) }
        error make {msg: $message}
    }
    if $cleanup_failure != null { error make {msg: ("Build operation-lock cleanup failed: " + (error-message $cleanup_failure))} }
}
