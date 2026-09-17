#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

# ============================================================
# Install VS Code where a predictable package-manager path exists.
# VS Code is optional; failure does not stop setup.
# ============================================================


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


def linux-is-root [] {
    if (which id | is-empty) { return false }
    let result = (do { ^id -u } | complete)
    $result.exit_code == 0 and (($result.stdout | str trim) == "0")
}

def linux-run-root [label: string program: string args: list] {
    if (linux-is-root) { return (run-program $label $program $args) }
    if (which sudo | is-empty) {
        print ("[warn] " + $label + " requires root privileges and sudo is unavailable.")
        return 1
    }
    run-program $label "sudo" ([$program] | append $args)
}

def main [] {
    if (($env.INITIAL_SETUP_SKIP_VSCODE? | default "") == "1") {
        print "[skip] VS Code installation disabled by bootstrap option."
        return
    }

    if not (which code | is-empty) {
        print "[ok] VS Code already installed"
        return
    }

    match $nu.os-info.name {
        "windows" => {
            if (which winget | is-empty) {
                print "[warn] winget not found; skipping VS Code installation."
                return
            }

            let package_state = (winget-package-state "installed" "Microsoft.VisualStudioCode")

            if $package_state == "yes" {
                print "[ok] VS Code WinGet package already installed; skipping reinstall"
                print "[info] code is not visible in PATH in this process"
                return
            }

            if $package_state == "error" {
                print "[warn] Could not determine VS Code WinGet state; leaving package unchanged"
                return
            }

            let args = [
                "install"
                "--id"
                "Microsoft.VisualStudioCode"
                "--exact"
                "--source"
                "winget"
                "--accept-package-agreements"
                "--accept-source-agreements"
            ]

            let exit_code = (
                run-program "Install VS Code with winget" "winget" $args
            )

            if $exit_code != 0 {
                print "[warn] Continuing without VS Code."
            }
        }

        "macos" => {
            if (which brew | is-empty) {
                print "[warn] Homebrew not found; skipping VS Code installation."
                return
            }

            let args = [
                "install"
                "--cask"
                "visual-studio-code"
            ]

            let exit_code = (
                run-program "Install VS Code with Homebrew" "brew" $args
            )

            if $exit_code != 0 {
                print "[warn] Continuing without VS Code."
            }
        }

        "linux" => {
            if not (which snap | is-empty) {
                let args = [
                    "install"
                    "code"
                    "--classic"
                ]

                let exit_code = (
                    linux-run-root "Install VS Code with snap" "snap" $args
                )

                if $exit_code == 0 {
                    return
                }
            }

            print "[info] Automatic VS Code installation is skipped on this Linux distribution."
            print "[info] VS Code Remote users may not need the desktop application on this host."
        }

        _ => {
            print "[warn] Unsupported OS for automatic VS Code installation."
        }
    }
}
