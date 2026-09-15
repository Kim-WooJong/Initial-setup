#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
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
            "[warn] "
            + $label
            + " returned exit code "
            + ($exit_code | into string)
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

    ^nu $script ...$args

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
            let args = [
                "upgrade"
                "--id"
                $package_id
                "--exact"
                "--accept-package-agreements"
                "--accept-source-agreements"
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

    if not (which apt-get | is-empty) {
        run-external "APT update" "sudo" ["apt-get" "update"] | ignore

        let packages = (
            $rows
            | each { |row| $row | get 2 }
            | where { |item| $item != "-" }
            | uniq
        )

        if not ($packages | is-empty) {
            let args = (["apt-get" "install" "--only-upgrade" "-y"] | append $packages)
            run-external "Upgrade managed APT tools" "sudo" $args | ignore
        }

        return
    }

    if not (which dnf | is-empty) {
        let packages = (
            $rows
            | each { |row| $row | get 3 }
            | where { |item| $item != "-" }
            | uniq
        )

        if not ($packages | is-empty) {
            let args = (["dnf" "upgrade" "-y"] | append $packages)
            run-external "Upgrade managed DNF tools" "sudo" $args | ignore
        }

        return
    }

    if not (which pacman | is-empty) {
        let packages = (
            $rows
            | each { |row| $row | get 4 }
            | where { |item| $item != "-" }
            | uniq
        )

        if not ($packages | is-empty) {
            let args = (["pacman" "-S" "--needed" "--noconfirm"] | append $packages)
            run-external "Refresh managed pacman tools" "sudo" $args | ignore
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
        let git_dir = ($context.tools_root | path expand | path join ".git")

        if ($git_dir | path exists) and not (which git | is-empty) {
            let args = [
                "-C"
                ($context.tools_root | path expand | into string)
                "pull"
                "--ff-only"
            ]

            run-external "Update Initial-setup repository" "git" $args | ignore
        } else {
            print "[skip] Initial-setup is not a Git checkout"
        }
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
