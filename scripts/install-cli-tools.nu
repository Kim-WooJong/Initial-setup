#!/usr/bin/env nu

# ============================================================
# Install common CLI tools used by the synchronized environment.
#
# Tools:
#   rg, fd, fzf, bat, zoxide, direnv
#
# These are optional. A package failure never aborts setup.
# ============================================================

def run-program [label: string program: string args: list] {
    print ("[run] " + $label)
    print ""

    ^$program ...$args

    let exit_code = (
        $env.LAST_EXIT_CODE
        | default 0
    )

    if $exit_code != 0 {
        print (
            "[warn] Command returned exit code "
            + ($exit_code | into string)
        )
    }

    $exit_code
}

def install-winget [command: string package_id: string] {
    if not (which $command | is-empty) {
        print ("[ok] " + $command)
        return
    }

    let args = [
        "install"
        "--id"
        $package_id
        "--exact"
        "--source"
        "winget"
        "--accept-package-agreements"
        "--accept-source-agreements"
    ]

    let exit_code = (
        run-program ("Install " + $package_id) "winget" $args
    )

    if $exit_code != 0 {
        print ("[warn] Could not install " + $package_id)
    }
}

def install-brew [command: string package: string] {
    if not (which $command | is-empty) {
        print ("[ok] " + $command)
        return
    }

    let args = [
        "install"
        $package
    ]

    let exit_code = (
        run-program ("Install " + $package) "brew" $args
    )

    if $exit_code != 0 {
        print ("[warn] Could not install " + $package)
    }
}

def install-linux-package [
    command: string
    apt_name: string
    dnf_name: string
    pacman_name: string
] {
    if not (which $command | is-empty) {
        print ("[ok] " + $command)
        return
    }

    if not (which apt-get | is-empty) {
        let args = [
            "apt-get"
            "install"
            "-y"
            $apt_name
        ]

        let exit_code = (
            run-program ("Install " + $apt_name) "sudo" $args
        )

        if $exit_code != 0 {
            print ("[warn] Could not install " + $apt_name)
        }

        return
    }

    if not (which dnf | is-empty) {
        let args = [
            "dnf"
            "install"
            "-y"
            $dnf_name
        ]

        let exit_code = (
            run-program ("Install " + $dnf_name) "sudo" $args
        )

        if $exit_code != 0 {
            print ("[warn] Could not install " + $dnf_name)
        }

        return
    }

    if not (which pacman | is-empty) {
        let args = [
            "pacman"
            "-S"
            "--needed"
            "--noconfirm"
            $pacman_name
        ]

        let exit_code = (
            run-program ("Install " + $pacman_name) "sudo" $args
        )

        if $exit_code != 0 {
            print ("[warn] Could not install " + $pacman_name)
        }

        return
    }

    print ("[warn] No supported package manager for " + $command)
}

def main [] {
    print "=== Common CLI tools ==="
    print ""

    match $nu.os-info.name {
        "windows" => {
            if (which winget | is-empty) {
                print "[warn] winget not found; CLI tool installation skipped."
                return
            }

            install-winget "rg" "BurntSushi.ripgrep.MSVC"
            install-winget "fd" "sharkdp.fd"
            install-winget "fzf" "junegunn.fzf"
            install-winget "bat" "sharkdp.bat"
            install-winget "zoxide" "ajeetdsouza.zoxide"
            install-winget "direnv" "direnv.direnv"
        }

        "macos" => {
            if (which brew | is-empty) {
                print "[warn] Homebrew not found; CLI tool installation skipped."
                return
            }

            install-brew "rg" "ripgrep"
            install-brew "fd" "fd"
            install-brew "fzf" "fzf"
            install-brew "bat" "bat"
            install-brew "zoxide" "zoxide"
            install-brew "direnv" "direnv"
        }

        "linux" => {
            install-linux-package "rg" "ripgrep" "ripgrep" "ripgrep"
            install-linux-package "fd" "fd-find" "fd-find" "fd"
            install-linux-package "fzf" "fzf" "fzf" "fzf"
            install-linux-package "bat" "bat" "bat" "bat"
            install-linux-package "zoxide" "zoxide" "zoxide" "zoxide"
            install-linux-package "direnv" "direnv" "direnv" "direnv"

            if (which fd | is-empty) and not (which fdfind | is-empty) {
                print "[info] Debian/Ubuntu provides fd as 'fdfind'."
            }

            if (which bat | is-empty) and not (which batcat | is-empty) {
                print "[info] Debian/Ubuntu provides bat as 'batcat'."
            }
        }

        _ => {
            print "[warn] Unsupported OS for CLI tool installation."
        }
    }
}
