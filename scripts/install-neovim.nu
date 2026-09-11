#!/usr/bin/env nu

def run-program [
    label: string
    program: string
    args: list
] {
    print ("[run] " + $label)

    ^$program ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print (
            "[warn] "
            + $label
            + " returned exit code "
            + ($exit_code | into string)
        )
    }

    $exit_code
}

def install-windows [] {
    if not (which winget | is-empty) {
        let args = [
            "install"
            "--id"
            "Neovim.Neovim"
            "--exact"
            "--source"
            "winget"
            "--accept-package-agreements"
            "--accept-source-agreements"
        ]

        run-program "Install Neovim" "winget" $args | ignore
        return
    }

    print "[warn] winget not found"
}

def install-macos [] {
    if not (which brew | is-empty) {
        run-program "Install Neovim" "brew" ["install" "neovim"] | ignore
        return
    }

    print "[warn] Homebrew not found"
}

def install-linux [] {
    if not (which apt-get | is-empty) {
        run-program "Install Neovim" "sudo" ["apt-get" "install" "-y" "neovim"] | ignore
        return
    }

    if not (which dnf | is-empty) {
        run-program "Install Neovim" "sudo" ["dnf" "install" "-y" "neovim"] | ignore
        return
    }

    if not (which pacman | is-empty) {
        run-program "Install Neovim" "sudo" ["pacman" "-S" "--needed" "--noconfirm" "neovim"] | ignore
        return
    }

    if not (which zypper | is-empty) {
        run-program "Install Neovim" "sudo" ["zypper" "install" "-y" "neovim"] | ignore
        return
    }

    if not (which apk | is-empty) {
        run-program "Install Neovim" "sudo" ["apk" "add" "neovim"] | ignore
        return
    }

    print "[warn] No supported package manager found"
}

def main [] {
    if not (which nvim | is-empty) {
        print "[ok] Neovim already installed"
        return
    }

    match $nu.os-info.name {
        "windows" => {
            install-windows
        }

        "macos" => {
            install-macos
        }

        "linux" => {
            install-linux
        }

        _ => {
            print "[warn] Unsupported OS"
        }
    }

    if (which nvim | is-empty) {
        print "[warn] Neovim was installed but may require a new shell before PATH is refreshed."
    } else {
        print "[ok] Neovim installed"
    }
}