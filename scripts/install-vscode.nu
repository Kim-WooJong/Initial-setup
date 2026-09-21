#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $INSTALL_UTILS [run-installer probe-tool winget-package-state privileged-command]

# VS Code is optional. Treat PATH presence as a candidate, not as proof of health.

def code-probe [] { probe-tool "code" ["--version"] }

def run-linux [label: string program: string args: list] {
    let elevated = (privileged-command $program $args)
    if not $elevated.ok { print ("[warn] " + $elevated.reason); return false }
    (run-installer $label $elevated.program $elevated.args).ok
}

def install [] {
    match $nu.os-info.name {
        "windows" => {
            if (which winget | is-empty) { print "[warn] winget not found; VS Code installation skipped."; return false }
            let state = (winget-package-state $TOOLS_ROOT "Microsoft.VisualStudioCode")
            if $state == "error" { print "[warn] Could not determine VS Code WinGet state; refusing a blind reinstall."; return false }
            let verb = if $state == "yes" { "upgrade" } else { "install" }
            (run-installer ("VS Code WinGet " + $verb) "winget" [$verb "--id" "Microsoft.VisualStudioCode" "--exact" "--source" "winget" "--accept-package-agreements" "--accept-source-agreements"]).ok
        }
        "macos" => {
            if (which brew | is-empty) { print "[warn] Homebrew not found; VS Code installation skipped."; return false }
            (run-installer "Install VS Code with Homebrew" "brew" ["install" "--cask" "visual-studio-code"]).ok
        }
        "linux" => {
            # Distribution repositories do not consistently provide Microsoft's
            # VS Code package. Prefer existing package channels only; do not add
            # repositories implicitly during setup.
            if not (which snap | is-empty) { return (run-linux "Install VS Code with snap" "snap" ["install" "code" "--classic"]) }
            if not (which flatpak | is-empty) {
                return (run-installer "Install VS Code with Flatpak" "flatpak" ["install" "-y" "flathub" "com.visualstudio.code"]).ok
            }
            print "[warn] No supported existing VS Code package channel found on Linux; installation skipped."
            false
        }
        _ => { print "[warn] Unsupported OS for automatic VS Code installation."; false }
    }
}

def main [] {
    if (($env.INITIAL_SETUP_SKIP_VSCODE? | default "") == "1") { print "[skip] VS Code installation disabled by bootstrap option."; return }
    let before = (code-probe)
    if $before.healthy { print ("[ok] VS Code " + $before.version + " -> " + $before.path); return }
    if $before.found {
        print ("[warn] VS Code CLI exists but failed `code --version`: " + $before.path)
        if $before.result != null and not ($before.result.diagnostic | str trim | is-empty) { print --stderr $before.result.diagnostic }
    }
    let attempted = (install)
    if not $attempted { return }
    let after = (code-probe)
    if $after.healthy { print ("[ok] VS Code verified -> " + $after.path) } else { print "[warn] VS Code installer completed, but `code --version` still failed. Restart the shell or repair PATH." }
}
