#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $INSTALL_UTILS [run-installer probe-tool winget-package-state privileged-command]

# WezTerm is optional. Existing PATH entries must pass `wezterm --version`.

def wezterm-probe [] { probe-tool "wezterm" ["--version"] }

def linux-has-gui [] {
    let display = ($env.DISPLAY? | default "")
    let wayland = ($env.WAYLAND_DISPLAY? | default "")
    not (($display | is-empty) and ($wayland | is-empty))
}

def run-linux [label: string program: string args: list] {
    let elevated = (privileged-command $program $args)
    if not $elevated.ok { print ("[warn] " + $elevated.reason); return false }
    (run-installer $label $elevated.program $elevated.args).ok
}

def install-windows [] {
    if not (which winget | is-empty) {
        let state = (winget-package-state $TOOLS_ROOT "wez.wezterm")
        if $state != "error" {
            let verb = if $state == "yes" { "upgrade" } else { "install" }
            if (run-installer ("WezTerm WinGet " + $verb) "winget" [$verb "--id" "wez.wezterm" "--exact" "--source" "winget" "--accept-package-agreements" "--accept-source-agreements"]).ok { return true }
        } else { print "[warn] Could not determine WezTerm WinGet state." }
    }
    if not (which scoop | is-empty) and (run-installer "Install WezTerm with Scoop" "scoop" ["install" "wezterm"]).ok { return true }
    if not (which choco | is-empty) and (run-installer "Install WezTerm with Chocolatey" "choco" ["install" "wezterm" "-y"]).ok { return true }
    false
}

def install [] {
    match $nu.os-info.name {
        "windows" => { install-windows }
        "macos" => {
            if (which brew | is-empty) { print "[warn] Homebrew not found; WezTerm installation skipped."; false } else { (run-installer "Install WezTerm with Homebrew" "brew" ["install" "--cask" "wezterm"]).ok }
        }
        "linux" => {
            if not (linux-has-gui) { print "[skip] Headless Linux detected; WezTerm is not required."; return false }
            if not (which pacman | is-empty) and (run-linux "Install WezTerm with pacman" "pacman" ["-S" "--needed" "--noconfirm" "wezterm"]) { return true }
            if not (which flatpak | is-empty) and (run-installer "Install WezTerm with Flatpak" "flatpak" ["install" "-y" "flathub" "org.wezfurlong.wezterm"]).ok { return true }
            print "[warn] No supported WezTerm package channel found on this Linux host."
            false
        }
        _ => { print "[warn] Unsupported OS for automatic WezTerm installation."; false }
    }
}

def main [] {
    let before = (wezterm-probe)
    if $before.healthy { print ("[ok] WezTerm " + $before.version + " -> " + $before.path); return }
    if $before.found {
        print ("[warn] WezTerm exists but failed `wezterm --version`: " + $before.path)
        if $before.result != null and not ($before.result.diagnostic | str trim | is-empty) { print --stderr $before.result.diagnostic }
    }
    let attempted = (install)
    if not $attempted { return }
    let after = (wezterm-probe)
    if $after.healthy { print ("[ok] WezTerm verified -> " + $after.path) } else { print "[warn] WezTerm installer completed, but `wezterm --version` still failed. Restart the shell or repair PATH." }
}
