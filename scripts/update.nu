#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context useful-lines]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-status print-command]
const TEXT_CASE = path self ./modules/text-case.nu
use $TEXT_CASE [text-lower]

def winget-package-state [
    mode: string
    package_id: string
    source: string = "winget"
] {
    let script = ($TOOLS_ROOT | path join "scripts" "winget-package-state.nu")
    let args = [$script $mode $package_id "--source" $source]

    let result = (run-command ($nu.current-exe | into string) (["--no-config-file"] | append $args))

    match ($result.exit_code? | default 2) {
        0 => { "yes" }
        10 => { "no" }
        _ => { "error" }
    }
}

def run-external [
    label: string
    program: string
    args: list
] {
    if (which $program | is-empty) {
        print-status "warn" "skip" ($program + " not found")
        return false
    }

    print-status "info" "run" $label

    let result = (run-command $program $args --live)
    if not $result.ok {
        print-status "warn" "warn" (command-failure-message $label $result) --stderr
        return false
    }
    true
}

def run-script [
    name: string
    ...args: string
] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)

    let result = (run-command ($nu.current-exe | into string) (["--no-config-file" ($script | into string)] | append $args) --live)
    if not $result.ok {
        print-status "warn" "warn" (command-failure-message ("Script " + $name) $result) --stderr
        return false
    }
    true
}

def linux-is-root [] {
    if (which id | is-empty) {
        return false
    }

    let result = (run-command "id" ["-u"])
    $result.ok and (($result.stdout | str trim) == "0")
}

def privileged-linux [label: string program: string args: list] {
    if (linux-is-root) {
        return (run-external $label $program $args)
    }

    if (which sudo | is-empty) {
        print-status "warn" "warn" ("sudo is required to " + ($label | text-lower) + "; skipping.")
        return false
    }

    run-external $label "sudo" ([$program] | append $args)
}

def update-windows [] {
    let manifest = ($TOOLS_ROOT | path join "packages" "windows.txt")

    if ($manifest | path exists) and not (which winget | is-empty) {
        let ids = (
            useful-lines $manifest
            | each { |line| $line | split row "|" | get 2 }
        )

        let core_ids = [
            "Git.Git"
            "Neovim.Neovim"
            "twpayne.chezmoi"
            "Starship.Starship"
            "wez.wezterm"
            "Microsoft.VisualStudioCode"
        ]

        let all_ids = ($ids | append $core_ids | uniq)

        for package_id in $all_ids {
            let installed_state = (winget-package-state "installed" $package_id)

            if $installed_state == "error" {
                print-status "warn" "warn" ("Could not determine installed state for " + $package_id + "; leaving it unchanged")
                continue
            }

            if $installed_state == "no" {
                print-status "warn" "skip" ($package_id + " is not installed")
                continue
            }

            let upgrade_state = (winget-package-state "upgrade-available" $package_id)

            if $upgrade_state == "error" {
                print-status "warn" "warn" ("Could not determine upgrade state for " + $package_id + "; leaving it unchanged")
                continue
            }

            if $upgrade_state == "no" {
                print-status "ok" "ok" ($package_id + " already up to date; skipping reinstall")
                continue
            }

            let args = [
                "upgrade"
                "--id"
                $package_id
                "--exact"
                "--source"
                "winget"
                "--accept-package-agreements"
                "--accept-source-agreements"
                "--disable-interactivity"
            ]

            run-external ("Upgrade " + $package_id) "winget" $args | ignore
        }
    }
}

def update-macos [] {
    if not (which brew | is-empty) {
        run-external "Homebrew update" "brew" ["update"] | ignore
        run-external "Homebrew upgrade" "brew" ["upgrade"] | ignore
    }
}

def update-linux [] {
    let manifest = ($TOOLS_ROOT | path join "packages" "linux.txt")

    if not ($manifest | path exists) {
        return
    }

    let rows = (
        useful-lines $manifest
        | each { |line| $line | split row "|" }
    )

    let manager = if not (which apt-get | is-empty) {
        {name: "apt" column: 2}
    } else if not (which dnf | is-empty) {
        {name: "dnf" column: 3}
    } else if not (which pacman | is-empty) {
        {name: "pacman" column: 4}
    } else if not (which zypper | is-empty) {
        {name: "zypper" column: 5}
    } else if not (which apk | is-empty) {
        {name: "apk" column: 6}
    } else {
        null
    }

    if $manager == null {
        print-status "warn" "warn" "No supported Linux package manager found; CLI package update skipped."
        return
    }

    let column = $manager.column
    let packages = (
        $rows
        | each { |row| $row | get --optional $column }
        | where { |item| $item != null and $item != "-" and not ($item | is-empty) }
        | uniq
    )

    match $manager.name {
        "apt" => {
            privileged-linux "APT update" "apt-get" ["update"] | ignore
            if not ($packages | is-empty) {
                privileged-linux "Upgrade managed APT tools" "apt-get" (["install" "--only-upgrade" "-y"] | append $packages) | ignore
            }
        }
        "dnf" => {
            if not ($packages | is-empty) {
                privileged-linux "Upgrade managed DNF tools" "dnf" (["upgrade" "-y"] | append $packages) | ignore
            }
        }
        "pacman" => {
            if not ($packages | is-empty) {
                privileged-linux "Refresh managed pacman tools" "pacman" (["-S" "--needed" "--noconfirm"] | append $packages) | ignore
            }
        }
        "zypper" => {
            privileged-linux "Refresh zypper metadata" "zypper" ["--non-interactive" "refresh"] | ignore
            if not ($packages | is-empty) {
                privileged-linux "Upgrade managed zypper tools" "zypper" (["--non-interactive" "update"] | append $packages) | ignore
            }
        }
        "apk" => {
            privileged-linux "Refresh apk metadata" "apk" ["update"] | ignore
            if not ($packages | is-empty) {
                privileged-linux "Upgrade managed apk tools" "apk" (["upgrade"] | append $packages) | ignore
            }
        }
    }
}

def update-toolchains [] {
    if not (which rustup | is-empty) {
        run-external "Rustup update" "rustup" ["update"] | ignore
    }

    if not (which juliaup | is-empty) {
        run-external "Juliaup update" "juliaup" ["update"] | ignore
    }
}

def update-neovim-plugins [] {
    let lock = ((nu-home) | path join ".config" "nvim" "lazy-lock.json")

    if (which nvim | is-empty) or not ($lock | path exists) {
        return
    }

    let args = [
        "--headless"
        "+Lazy! sync"
        "+qa"
    ]

    run-external "Neovim Lazy plugin sync" "nvim" $args | ignore
}

def main [
    --repo
    --tools
    --config
    --all
] {
    let selected = ($repo or $tools or $config)
    let do_all = ($all or not $selected)
    let context = (machine-context)

    if $context.maintenance.snapshots_enabled {
        run-script "create-snapshot.nu" "--label" "pre-update" "--quiet" | ignore
    }

    if $do_all or $repo {
        print-status "info" "safe-update" "Repository files are not updated by a blind git pull."
        print-command "dotupgrade --ref <tag> --commit <trusted-full-commit> --yes"
        print-command "dotupgrade --from <folder> --manifest-sha256 <trusted-digest> --yes"
    }

    if $do_all or $tools {
        match $nu.os-info.name {
            "windows" => {
                update-windows
            }

            "macos" => {
                update-macos
            }

            "linux" => {
                update-linux
            }

            _ => {
                print-status "warn" "warn" "Unsupported OS for package updates"
            }
        }

        update-toolchains
        update-neovim-plugins
        run-script "install-neovim.nu" | ignore
        run-script "install-cli-tools.nu" | ignore
        run-script "capture-work-environment.nu" | ignore
    }

    if $do_all or $config {
        run-script "sync-down.nu" | ignore
        run-script "setup-platform-shims.nu" | ignore
        run-script "setup-local-overrides.nu" | ignore
        run-script "setup-secrets.nu" | ignore
    }

    run-script "doctor.nu" | ignore
}
