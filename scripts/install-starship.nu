#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home]
const TOOLS_ROOT = path self ..
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $INSTALL_UTILS [run-installer probe-tool winget-package-state linux-is-root privileged-command]
use modules/starship.nu [probe-starship-candidates resolve-starship]

# ============================================================
# install-starship.nu
#
# Starship is optional.
#
# External installers write directly to the terminal. This
# avoids encoding/binary stdout issues from Windows programs
# such as winget.
#
# A failed Starship installation does not stop setup.
# ============================================================

def install-with-winget [repair: bool = false] {
    if (which winget | is-empty) {
        return false
    }

    let package_state = (winget-package-state $TOOLS_ROOT "Starship.Starship")

    if $package_state == "yes" {
        if not $repair {
            print "[ok] Starship WinGet package already installed"
            return true
        }

        print "[info] Starship package is installed but `starship init nu` is unhealthy."
        print "[info] Trying a WinGet upgrade before falling back to Cargo..."

        let upgrade_args = [
            "upgrade"
            "--id"
            "Starship.Starship"
            "--exact"
            "--source"
            "winget"
            "--accept-package-agreements"
            "--accept-source-agreements"
        ]

        let upgrade = (run-installer "Upgrade Starship with winget" "winget" $upgrade_args)
        return $upgrade.ok
    }

    if $package_state == "error" {
        print "[warn] Could not determine Starship WinGet state; trying an explicit install"
    }

    let args = [
        "install"
        "--id"
        "Starship.Starship"
        "--exact"
        "--source"
        "winget"
        "--accept-package-agreements"
        "--accept-source-agreements"
    ]

    (run-installer "Install Starship with winget" "winget" $args).ok
}

def install-with-cargo [] {
    if (which cargo | is-empty) {
        return false
    }

    let args = [
        "install"
        "starship"
        "--locked"
    ]

    (run-installer "Install Starship with Cargo" "cargo" $args).ok
}

def install-with-brew [] {
    if (which brew | is-empty) {
        return false
    }

    let args = [
        "install"
        "starship"
    ]

    (run-installer "Install Starship with Homebrew" "brew" $args).ok
}

def install-with-official-script [] {
    if (which curl | is-empty) or (which sh | is-empty) {
        return false
    }

    let bin_dir = ((nu-home) | path join ".local" "bin")
    mkdir $bin_dir
    let bin_literal = (($bin_dir | into string) | str replace --all '"' '\\"')
    let command = (
        "curl --proto '=https' --tlsv1.2 -sSf https://starship.rs/install.sh " + "| sh -s -- -y -b \"" + $bin_literal + "\""
    )

    let args = [
        "-c"
        $command
    ]

    (run-installer "Install Starship with official installer" "sh" $args).ok
}

def print-unhealthy-candidates [] {
    let probes = (probe-starship-candidates)

    for probe in $probes {
        if not $probe.healthy {
            print ("[warn] Starship candidate failed health check: " + ($probe.path | into string))
            if not ($probe.version | str trim | is-empty) {
                print ("       version: " + ($probe.version | str trim))
            }
            if $probe.init_exit_code != null {
                print ("       `starship init nu` exit code: " + ($probe.init_exit_code | into string))
            }
            let stderr = ($probe.stderr | str trim)
            if not ($stderr | is-empty) {
                print "       stderr:"
                print $stderr
            }
        }
    }
}

def healthy-after-attempt [] {
    (resolve-starship) != null
}

def main [] {
    let existing = (resolve-starship)
    if $existing != null {
        print ("[ok] Starship already installed and healthy: " + ($existing.version | str trim))
        print ("[ok] Starship executable -> " + ($existing.path | into string))
        return
    }

    let visible_before = (probe-starship-candidates)
    let repair = (not ($visible_before | is-empty))

    if $repair {
        print "[warn] Starship is visible but failed the Nushell initialization health check."
        print-unhealthy-candidates
        print ""
    }

    print "=== Starship installation / repair ==="
    print ""

    let installed = (
        match $nu.os-info.name {
            "windows" => {
                let winget_ok = (install-with-winget $repair)

                if $winget_ok and (healthy-after-attempt) {
                    true
                } else {
                    if $winget_ok {
                        print "[warn] WinGet completed, but no healthy Starship candidate was found yet."
                    } else {
                        print "[info] WinGet repair/install failed or is unavailable."
                    }
                    print "[info] Trying Cargo fallback..."
                    let cargo_ok = (install-with-cargo)
                    $cargo_ok and (healthy-after-attempt)
                }
            }

            "macos" => {
                let brew_ok = (install-with-brew)

                if $brew_ok and (healthy-after-attempt) {
                    true
                } else {
                    print "[info] Homebrew did not produce a healthy Starship candidate."
                    print "[info] Trying the official installer..."
                    let official_ok = (install-with-official-script)

                    if $official_ok and (healthy-after-attempt) {
                        true
                    } else {
                        print "[info] Trying Cargo fallback..."
                        let cargo_ok = (install-with-cargo)
                        $cargo_ok and (healthy-after-attempt)
                    }
                }
            }

            "linux" => {
                let official_ok = (install-with-official-script)

                if $official_ok and (healthy-after-attempt) {
                    true
                } else {
                    print "[info] Official installer did not produce a healthy Starship candidate."
                    print "[info] Trying Cargo fallback..."
                    let cargo_ok = (install-with-cargo)
                    $cargo_ok and (healthy-after-attempt)
                }
            }

            _ => { false }
        }
    )

    print ""

    if $installed {
        let selected = (resolve-starship)
        print ("[ok] Healthy Starship ready: " + ($selected.version | str trim))
        print ("[ok] Starship executable -> " + ($selected.path | into string))
    } else {
        print "[warn] Starship could not be made healthy automatically."
        print-unhealthy-candidates
        print "[warn] Starship is optional; setup will continue and the prompt integration stage will not abort the setup."
    }
}
