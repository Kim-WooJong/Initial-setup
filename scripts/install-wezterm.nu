#!/usr/bin/env nu

# ============================================================
# install-wezterm.nu
#
# WezTerm is optional.
#
# External installers write directly to the terminal. This
# avoids encoding/binary stdout issues from Windows programs
# such as winget.
#
# A failed WezTerm installation does not stop setup.
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

def wezterm-visible [] {
    not (which wezterm | is-empty)
}

def install-with-winget [] {
    if (which winget | is-empty) {
        return false
    }

    let args = [
        "install"
        "--id"
        "wez.wezterm"
        "--exact"
        "--source"
        "winget"
        "--accept-package-agreements"
        "--accept-source-agreements"
    ]

    let exit_code = (run-program "Install WezTerm with winget" "winget" $args)

    $exit_code == 0
}

def install-with-scoop [] {
    if (which scoop | is-empty) {
        return false
    }

    let args = [
        "install"
        "wezterm"
    ]

    let exit_code = (run-program "Install WezTerm with Scoop" "scoop" $args)

    $exit_code == 0
}

def install-with-choco [] {
    if (which choco | is-empty) {
        return false
    }

    let args = [
        "install"
        "wezterm"
        "-y"
    ]

    let exit_code = (run-program "Install WezTerm with Chocolatey" "choco" $args)

    $exit_code == 0
}

def install-with-brew [] {
    if (which brew | is-empty) {
        return false
    }

    let args = [
        "install"
        "--cask"
        "wezterm"
    ]

    let exit_code = (run-program "Install WezTerm with Homebrew" "brew" $args)

    $exit_code == 0
}

def linux-has-gui [] {
    let display = (
        $env.DISPLAY?
        | default ""
    )

    let wayland = (
        $env.WAYLAND_DISPLAY?
        | default ""
    )

    not (($display | is-empty) and ($wayland | is-empty))
}

def install-linux [] {
    if not (linux-has-gui) {
        print "[skip] Headless Linux detected."
        print "[info] WezTerm is not required on this machine."
        return true
    }

    if not (which pacman | is-empty) and not (which sudo | is-empty) {
        let args = [
            "pacman"
            "-S"
            "--needed"
            "--noconfirm"
            "wezterm"
        ]

        let exit_code = (run-program "Install WezTerm with pacman" "sudo" $args)

        if $exit_code == 0 {
            return true
        }
    }

    if not (which flatpak | is-empty) {
        let args = [
            "install"
            "-y"
            "flathub"
            "org.wezfurlong.wezterm"
        ]

        let exit_code = (run-program "Install WezTerm with Flatpak" "flatpak" $args)

        if $exit_code == 0 {
            return true
        }
    }

    false
}

def main [] {
    if (wezterm-visible) {
        print "[ok] WezTerm already installed"
        return
    }

    print "=== WezTerm installation ==="
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
                    print "[info] Trying Scoop fallback..."

                    let scoop_ok = (
                        install-with-scoop
                    )

                    if $scoop_ok {
                        true
                    } else {
                        print ""
                        print "[info] Scoop installation failed or is unavailable."
                        print "[info] Trying Chocolatey fallback..."

                        install-with-choco
                    }
                }
            }

            "macos" => {
                install-with-brew
            }

            "linux" => {
                install-linux
            }

            _ => {
                false
            }
        }
    )

    print ""

    if $installed {
        print "[ok] WezTerm installation completed"
        print "[info] A shell restart may be required before WezTerm appears in PATH."
    } else {
        print "[warn] WezTerm could not be installed automatically."
        print "[warn] Continuing setup without WezTerm."
    }
}
