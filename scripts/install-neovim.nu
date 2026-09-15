#!/usr/bin/env nu

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def run-program [label: string program: string args: list] {
    print ("[run] " + $label)
    ^$program ...$args
    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print ("[warn] " + $label + " returned exit code " + ($exit_code | into string))
    }

    $exit_code
}

def main [] {
    if not (which nvim | is-empty) {
        print "[ok] Neovim already installed"
        return
    }

    match $nu.os-info.name {
        "windows" => {
            if (which winget | is-empty) {
                print "[warn] winget not found; Neovim installation skipped."
                return
            }

            let args = ["install" "--id" "Neovim.Neovim" "--exact" "--source" "winget" "--accept-package-agreements" "--accept-source-agreements"]
            run-program "Install Neovim with winget" "winget" $args | ignore
        }

        "macos" => {
            if (which brew | is-empty) {
                print "[warn] Homebrew not found; Neovim installation skipped."
                return
            }

            run-program "Install Neovim with Homebrew" "brew" ["install" "neovim"] | ignore
        }

        "linux" => {
            if not (which apt-get | is-empty) {
                run-program "Install Neovim with APT" "sudo" ["apt-get" "install" "-y" "neovim"] | ignore
                return
            }

            if not (which dnf | is-empty) {
                run-program "Install Neovim with DNF" "sudo" ["dnf" "install" "-y" "neovim"] | ignore
                return
            }

            if not (which pacman | is-empty) {
                run-program "Install Neovim with pacman" "sudo" ["pacman" "-S" "--needed" "--noconfirm" "neovim"] | ignore
                return
            }

            if not (which zypper | is-empty) {
                run-program "Install Neovim with zypper" "sudo" ["zypper" "install" "-y" "neovim"] | ignore
                return
            }

            if not (which apk | is-empty) {
                run-program "Install Neovim with apk" "sudo" ["apk" "add" "neovim"] | ignore
                return
            }

            print "[warn] No supported Linux package manager found for Neovim."
        }

        _ => {
            print "[warn] Unsupported OS for automatic Neovim installation."
        }
    }

    if (which nvim | is-empty) {
        print "[info] If installation succeeded, restart the shell so PATH can refresh."
    } else {
        print "[ok] Neovim installed"
    }
}
