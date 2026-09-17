#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
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

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }
    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }
    error make {msg: "Unable to determine the Nushell home directory."}
}

def winget-package-state [
    mode: string
    package_id: string
    source: string = "winget"
] {
    let script = ($TOOLS_ROOT | path join "scripts" "winget-package-state.nu")
    let args = [$script $mode $package_id "--source" $source]

    ^$nu.current-exe --no-config-file ...$args | ignore
    let exit_code = ($env.LAST_EXIT_CODE | default 2)

    match $exit_code {
        0 => { "yes" }
        10 => { "no" }
        _ => { "error" }
    }
}

def run-program [
    label: string
    program: string
    args: list
] {
    print ("[run] " + $label)
    print ""

    ^$program ...$args

    let exit_code = (
        $env.LAST_EXIT_CODE
        | default 0
    )

    if $exit_code != 0 {
        print ""
        print (
            "[warn] Command returned exit code " + ($exit_code | into string)
        )
    }

    $exit_code
}

def install-with-winget [repair: bool = false] {
    if (which winget | is-empty) {
        return false
    }

    let package_state = (winget-package-state "installed" "Starship.Starship")

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

        let upgrade_code = (run-program "Upgrade Starship with winget" "winget" $upgrade_args)
        return ($upgrade_code == 0)
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

    let exit_code = (run-program "Install Starship with winget" "winget" $args)

    $exit_code == 0
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

    let exit_code = (run-program "Install Starship with Cargo" "cargo" $args)

    $exit_code == 0
}

def install-with-brew [] {
    if (which brew | is-empty) {
        return false
    }

    let args = [
        "install"
        "starship"
    ]

    let exit_code = (run-program "Install Starship with Homebrew" "brew" $args)

    $exit_code == 0
}

def install-with-official-script [] {
    if (which curl | is-empty) or (which sh | is-empty) {
        return false
    }

    let bin_dir = ((nu-home) | path join ".local" "bin")
    mkdir $bin_dir
    let bin_literal = (($bin_dir | into string) | str replace --all '"' '\\"')
    let command = (
        "curl --proto '=https' --tlsv1.2 -sSf https://starship.rs/install.sh "
        + "| sh -s -- -y -b \"" + $bin_literal + "\""
    )

    let args = [
        "-c"
        $command
    ]

    let exit_code = (run-program "Install Starship with official installer" "sh" $args)

    $exit_code == 0
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
