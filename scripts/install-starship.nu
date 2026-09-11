#!/usr/bin/env nu

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
            "[warn] Command returned exit code "
            + ($exit_code | into string)
        )
    }

    $exit_code
}

def starship-visible [] {
    not (which starship | is-empty)
}

def install-with-winget [] {
    if (which winget | is-empty) {
        return false
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

    let command = (
        "curl -sS https://starship.rs/install.sh "
        + "| sh -s -- -y"
    )

    let args = [
        "-c"
        $command
    ]

    let exit_code = (run-program "Install Starship with official installer" "sh" $args)

    $exit_code == 0
}

def main [] {
    if (starship-visible) {
        print "[ok] Starship already installed"
        return
    }

    print "=== Starship installation ==="
    print ""

    let installed = (
        match $nu.os-info.name {
            "windows" => {
                let winget_ok = (
                    install-with-winget
                )

                if $winget_ok {
                    true
                } else {
                    print ""
                    print "[info] winget installation failed or is unavailable."
                    print "[info] Trying Cargo fallback..."

                    install-with-cargo
                }
            }

            "macos" => {
                let brew_ok = (
                    install-with-brew
                )

                if $brew_ok {
                    true
                } else {
                    print ""
                    print "[info] Homebrew installation failed or is unavailable."
                    print "[info] Trying the official installer..."

                    let official_ok = (
                        install-with-official-script
                    )

                    if $official_ok {
                        true
                    } else {
                        print ""
                        print "[info] Trying Cargo fallback..."

                        install-with-cargo
                    }
                }
            }

            "linux" => {
                let cargo_ok = (
                    install-with-cargo
                )

                if $cargo_ok {
                    true
                } else {
                    print ""
                    print "[info] Cargo installation failed or is unavailable."
                    print "[info] Trying the official installer..."

                    install-with-official-script
                }
            }

            _ => {
                false
            }
        }
    )

    print ""

    if $installed {
        print "[ok] Starship installation completed"
        print "[info] A shell restart may be required before Starship appears in PATH."
    } else {
        print "[warn] Starship could not be installed automatically."
        print "[warn] Continuing setup without Starship."
    }
}
