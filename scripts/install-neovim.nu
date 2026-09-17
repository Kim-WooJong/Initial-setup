#!/usr/bin/env nu

const TOOLS_ROOT = path self ..


def winget-package-state [
    mode: string
    package_id: string
    source: string = "winget"
] {
    let script = ($TOOLS_ROOT | path join "scripts" "winget-package-state.nu")
    let args = [$script $mode $package_id "--source" $source]

    ^nu ...$args | ignore
    let exit_code = ($env.LAST_EXIT_CODE | default 2)

    match $exit_code {
        0 => { "yes" }
        10 => { "no" }
        _ => { "error" }
    }
}

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
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

            let package_state = (winget-package-state "installed" "Neovim.Neovim")

            if $package_state == "yes" {
                print "[ok] Neovim WinGet package already installed; skipping reinstall"
                print "[info] nvim is not visible in PATH in this process"
                return
            }

            if $package_state == "error" {
                print "[warn] Could not determine Neovim WinGet state; leaving package unchanged"
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
