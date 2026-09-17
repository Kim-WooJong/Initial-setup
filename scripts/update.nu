#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

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

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    open $file
}


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

def run-external [
    label: string
    program: string
    args: list
] {
    if (which $program | is-empty) {
        print ("[skip] " + $program + " not found")
        return false
    }

    print ("[run] " + $label)

    ^$program ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print (
            "[warn] " + $label + " returned exit code " + ($exit_code | into string)
        )
        return false
    }

    true
}

def run-script [
    name: string
    ...args: string
] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)

    ^$nu.current-exe --no-config-file $script ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print ("[warn] Script failed: " + $name)
        return false
    }

    true
}

def useful-lines [file: path] {
    open --raw $file
    | lines
    | each { |line| $line | str trim }
    | where { |line| not ($line | is-empty) and not ($line | str starts-with "#") }
}


def linux-is-root [] {
    if (which id | is-empty) {
        return false
    }

    let result = (do { ^id -u } | complete)
    $result.exit_code == 0 and (($result.stdout | str trim) == "0")
}

def privileged-linux [label: string program: string args: list] {
    if (linux-is-root) {
        return (run-external $label $program $args)
    }

    if (which sudo | is-empty) {
        print ("[warn] sudo is required to " + ($label | str downcase) + "; skipping.")
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
                print ("[warn] Could not determine installed state for " + $package_id + "; leaving it unchanged")
                continue
            }

            if $installed_state == "no" {
                print ("[skip] " + $package_id + " is not installed")
                continue
            }

            let upgrade_state = (winget-package-state "upgrade-available" $package_id)

            if $upgrade_state == "error" {
                print ("[warn] Could not determine upgrade state for " + $package_id + "; leaving it unchanged")
                continue
            }

            if $upgrade_state == "no" {
                print ("[ok] " + $package_id + " already up to date; skipping reinstall")
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
        print "[warn] No supported Linux package manager found; CLI package update skipped."
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
        print "[safe-update] Repository files are not updated by a blind git pull."
        print "Run dotupgrade --ref <tag> --commit <trusted-full-commit> --yes for a Git checkout."
        print "For an extracted release, run dotupgrade --from <folder> --manifest-sha256 <trusted-digest> --yes."
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
                print "[warn] Unsupported OS for package updates"
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
