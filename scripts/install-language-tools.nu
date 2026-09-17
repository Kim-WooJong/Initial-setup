#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

# ============================================================
# Install Rust (rustup) and Julia (Juliaup).
# Both are optional; failures do not abort the full setup.
# ============================================================


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
    print ""

    ^$program ...$args

    let exit_code = (
        $env.LAST_EXIT_CODE
        | default 0
    )

    if $exit_code != 0 {
        print (
            "[warn] Command returned exit code " + ($exit_code | into string)
        )
    }

    $exit_code
}

def install-rust-windows [] {
    if not (which rustup | is-empty) {
        print "[ok] Rustup already installed"
        return
    }

    if (which winget | is-empty) {
        print "[warn] winget not found; Rustup installation skipped."
        return
    }

    let package_state = (winget-package-state "installed" "Rustlang.Rustup")

    if $package_state == "yes" {
        print "[ok] Rustup WinGet package already installed; skipping reinstall"
        print "[info] rustup is not visible in PATH in this process"
        return
    }

    if $package_state == "error" {
        print "[warn] Could not determine Rustup WinGet state; leaving package unchanged"
        return
    }

    let args = [
        "install"
        "--id"
        "Rustlang.Rustup"
        "--exact"
        "--source"
        "winget"
        "--accept-package-agreements"
        "--accept-source-agreements"
    ]

    let exit_code = (
        run-program "Install Rustup with winget" "winget" $args
    )

    if $exit_code != 0 {
        print "[warn] Rustup could not be installed automatically."
    }
}

def install-rust-unix [] {
    if not (which rustup | is-empty) {
        print "[ok] Rustup already installed"
        return
    }

    if (which sh | is-empty) or (which curl | is-empty) {
        print "[warn] curl and sh are required for Rustup installation."
        return
    }

    let command = (
        "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs " + "| sh -s -- -y"
    )

    let args = [
        "-c"
        $command
    ]

    let exit_code = (
        run-program "Install Rustup with official installer" "sh" $args
    )

    if $exit_code != 0 {
        print "[warn] Rustup could not be installed automatically."
    }
}

def install-julia-windows [] {
    if not (which juliaup | is-empty) or not (which julia | is-empty) {
        print "[ok] Julia or Juliaup already installed"
        return
    }

    if (which winget | is-empty) {
        print "[warn] winget not found; Juliaup installation skipped."
        return
    }

    let package_state = (winget-package-state "installed" "9NJNWW8PVKMN" "msstore")

    if $package_state == "yes" {
        print "[ok] Julia WinGet/MS Store package already installed; skipping reinstall"
        print "[info] julia/juliaup is not visible in PATH in this process"
        return
    }

    if $package_state == "error" {
        print "[warn] Could not determine Julia WinGet/MS Store state; leaving package unchanged"
        return
    }

    let args = [
        "install"
        "--name"
        "Julia"
        "--id"
        "9NJNWW8PVKMN"
        "--exact"
        "--source"
        "msstore"
        "--accept-package-agreements"
        "--accept-source-agreements"
    ]

    let exit_code = (
        run-program "Install Juliaup from Microsoft Store" "winget" $args
    )

    if $exit_code != 0 {
        print "[warn] Juliaup could not be installed automatically."
    }
}

def install-julia-unix [] {
    if not (which juliaup | is-empty) or not (which julia | is-empty) {
        print "[ok] Julia or Juliaup already installed"
        return
    }

    if (which sh | is-empty) or (which curl | is-empty) {
        print "[warn] curl and sh are required for Juliaup installation."
        return
    }

    let command = (
        "curl -fsSL https://install.julialang.org " + "| sh -s -- --yes"
    )

    let args = [
        "-c"
        $command
    ]

    let exit_code = (
        run-program "Install Juliaup with official installer" "sh" $args
    )

    if $exit_code != 0 {
        print "[warn] Juliaup could not be installed automatically."
    }
}

def machine-context [] {
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

    open $file
}

def main [] {
    let context = (
        machine-context
    )

    print "=== Language toolchains ==="
    print ""

    match $nu.os-info.name {
        "windows" => {
            if $context.features.rust {
                install-rust-windows
            }

            if $context.features.julia {
                print ""
                install-julia-windows
            }
        }

        "macos" => {
            if $context.features.rust {
                install-rust-unix
            }

            if $context.features.julia {
                print ""
                install-julia-unix
            }
        }

        "linux" => {
            if $context.features.rust {
                install-rust-unix
            }

            if $context.features.julia {
                print ""
                install-julia-unix
            }
        }

        _ => {
            print "[warn] Unsupported OS for automatic Rust/Julia installation."
        }
    }
}
