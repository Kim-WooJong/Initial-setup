#!/usr/bin/env nu

# ============================================================
# Install VS Code where a predictable package-manager path exists.
# VS Code is optional; failure does not stop setup.
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

def main [] {
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
                    "snap"
                    "install"
                    "code"
                    "--classic"
                ]

                let exit_code = (
                    run-program "Install VS Code with snap" "sudo" $args
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
