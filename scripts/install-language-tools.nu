#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
const TOOLS_ROOT = path self ..
const UTILS = path self ./modules/install-utils.nu
use $UTILS [probe-tool run-installer winget-package-state user-tool-paths]

# Rust and Julia are optional developer toolchains. Presence alone is not enough:
# the executable must answer its version probe successfully.

def rust-probe [] {
    let paths = (user-tool-paths)
    let exe = if $nu.os-info.name == "windows" { "rustup.exe" } else { "rustup" }
    probe-tool "rustup" ["--version"] [($paths.cargo | path join $exe)]
}

def julia-probe [] {
    let paths = (user-tool-paths)
    let juliaup_exe = if $nu.os-info.name == "windows" { "juliaup.exe" } else { "juliaup" }
    let julia_exe = if $nu.os-info.name == "windows" { "julia.exe" } else { "julia" }
    let up = (probe-tool "juliaup" ["--version"] [($paths.juliaup | path join $juliaup_exe)])
    if $up.healthy { return $up }
    probe-tool "julia" ["--version"] [($paths.juliaup | path join $julia_exe)]
}

def install-rust [] {
    let before = (rust-probe)
    if $before.healthy {
        print ("[ok] Rustup " + $before.version + " -> " + $before.path)
        return true
    }
    if $before.found {
        print ("[warn] Rustup exists but failed its health check: " + $before.path)
        if $before.result != null and not ($before.result.diagnostic | str trim | is-empty) { print --stderr $before.result.diagnostic }
    }

    let installed = if $nu.os-info.name == "windows" {
        if (which winget | is-empty) {
            print "[warn] winget not found; Rustup installation skipped."
            false
        } else {
            let state = (winget-package-state $TOOLS_ROOT "Rustlang.Rustup")
            if $state == "error" {
                print "[warn] Could not determine Rustup WinGet state; refusing a blind reinstall."
                false
            } else {
                let verb = if $state == "yes" { "upgrade" } else { "install" }
                let result = (run-installer ("Rustup WinGet " + $verb) "winget" [$verb "--id" "Rustlang.Rustup" "--exact" "--source" "winget" "--accept-package-agreements" "--accept-source-agreements"])
                $result.ok
            }
        }
    } else {
        if (which curl | is-empty) or (which sh | is-empty) {
            print "[warn] curl and sh are required for Rustup installation."
            false
        } else {
            (run-installer "Install Rustup with official installer" "sh" ["-c" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"]).ok
        }
    }

    if not $installed { return false }
    let after = (rust-probe)
    if $after.healthy {
        print ("[ok] Rustup verified -> " + $after.path)
        true
    } else {
        print "[warn] Rustup installer completed, but `rustup --version` still failed. Restart the shell or repair PATH."
        false
    }
}

def install-julia [] {
    let before = (julia-probe)
    if $before.healthy {
        print ("[ok] Julia toolchain " + $before.version + " -> " + $before.path)
        return true
    }
    if $before.found {
        print ("[warn] Julia/Juliaup exists but failed its health check: " + $before.path)
        if $before.result != null and not ($before.result.diagnostic | str trim | is-empty) { print --stderr $before.result.diagnostic }
    }

    let installed = if $nu.os-info.name == "windows" {
        if (which winget | is-empty) {
            print "[warn] winget not found; Juliaup installation skipped."
            false
        } else {
            let state = (winget-package-state $TOOLS_ROOT "9NJNWW8PVKMN" "msstore")
            if $state == "error" {
                print "[warn] Could not determine Julia MS Store state; refusing a blind reinstall."
                false
            } else {
                let verb = if $state == "yes" { "upgrade" } else { "install" }
                let args = if $verb == "install" {
                    [$verb "--name" "Julia" "--id" "9NJNWW8PVKMN" "--exact" "--source" "msstore" "--accept-package-agreements" "--accept-source-agreements"]
                } else {
                    [$verb "--id" "9NJNWW8PVKMN" "--exact" "--source" "msstore" "--accept-package-agreements" "--accept-source-agreements"]
                }
                (run-installer ("Julia WinGet " + $verb) "winget" $args).ok
            }
        }
    } else {
        if (which curl | is-empty) or (which sh | is-empty) {
            print "[warn] curl and sh are required for Juliaup installation."
            false
        } else {
            (run-installer "Install Juliaup with official installer" "sh" ["-c" "curl -fsSL https://install.julialang.org | sh -s -- --yes"]).ok
        }
    }

    if not $installed { return false }
    let after = (julia-probe)
    if $after.healthy {
        print ("[ok] Julia toolchain verified -> " + $after.path)
        true
    } else {
        print "[warn] Julia installer completed, but Julia/Juliaup still failed its version probe. Restart the shell or repair PATH."
        false
    }
}

def main [] {
    let context = (machine-context)
    print "=== Language toolchains ==="
    print ""
    if ($context.features.rust? | default false) { install-rust | ignore }
    if ($context.features.julia? | default false) { print ""; install-julia | ignore }
}
