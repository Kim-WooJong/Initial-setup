#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $INSTALL_UTILS [run-installer probe-tool winget-package-state privileged-command]

# Neovim is optional. A visible executable is accepted only when `nvim --version`
# succeeds. Installer success is also followed by the same health probe.

def nvim-probe [] { probe-tool "nvim" ["--version"] }

def run-linux [label: string program: string args: list] {
    let elevated = (privileged-command $program $args)
    if not $elevated.ok {
        print ("[warn] " + $elevated.reason)
        return false
    }
    (run-installer $label $elevated.program $elevated.args).ok
}

def install [] {
    match $nu.os-info.name {
        "windows" => {
            if (which winget | is-empty) {
                print "[warn] winget not found; Neovim installation skipped."
                return false
            }
            let state = (winget-package-state $TOOLS_ROOT "Neovim.Neovim")
            if $state == "error" {
                print "[warn] Could not determine Neovim WinGet state; refusing a blind reinstall."
                return false
            }
            let verb = if $state == "yes" { "upgrade" } else { "install" }
            (run-installer ("Neovim WinGet " + $verb) "winget" [$verb "--id" "Neovim.Neovim" "--exact" "--source" "winget" "--accept-package-agreements" "--accept-source-agreements"]).ok
        }
        "macos" => {
            if (which brew | is-empty) { print "[warn] Homebrew not found; Neovim installation skipped."; return false }
            (run-installer "Install Neovim with Homebrew" "brew" ["install" "neovim"]).ok
        }
        "linux" => {
            if not (which apt-get | is-empty) { return (run-linux "Install Neovim with APT" "apt-get" ["install" "-y" "neovim"]) }
            if not (which dnf | is-empty) { return (run-linux "Install Neovim with DNF" "dnf" ["install" "-y" "neovim"]) }
            if not (which pacman | is-empty) { return (run-linux "Install Neovim with pacman" "pacman" ["-S" "--needed" "--noconfirm" "neovim"]) }
            if not (which zypper | is-empty) { return (run-linux "Install Neovim with zypper" "zypper" ["--non-interactive" "install" "neovim"]) }
            if not (which apk | is-empty) { return (run-linux "Install Neovim with apk" "apk" ["add" "--no-cache" "neovim"]) }
            print "[warn] No supported Linux package manager found for Neovim."
            false
        }
        _ => { print "[warn] Unsupported OS for automatic Neovim installation."; false }
    }
}

def main [] {
    let before = (nvim-probe)
    if $before.healthy {
        print ("[ok] Neovim " + $before.version + " -> " + $before.path)
        return
    }
    if $before.found {
        print ("[warn] Neovim exists but failed `nvim --version`: " + $before.path)
        if $before.result != null and not ($before.result.diagnostic | str trim | is-empty) { print --stderr $before.result.diagnostic }
    }

    let attempted = (install)
    if not $attempted { return }
    let after = (nvim-probe)
    if $after.healthy {
        print ("[ok] Neovim verified -> " + $after.path)
    } else {
        print "[warn] Neovim installer completed, but `nvim --version` still failed. Restart the shell or repair PATH."
    }
}
