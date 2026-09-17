#!/usr/bin/env nu

# ============================================================
# Install common CLI tools from public package manifests.
# ============================================================

const TOOLS_ROOT = path self ..
const RCLONE_INSTALL_MODULE = path self ./modules/rclone-install.nu
use $RCLONE_INSTALL_MODULE [ensure-rclone]

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
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

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

def run-program [
    label: string
    program: string
    args: list
] {
    print (
        "[run] " + $label
    )
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

def useful-lines [file: path] {
    open --raw $file
    | lines
    | each { |line|
        $line
        | str trim
    }
    | where { |line|
        not ($line | is-empty) and not ($line | str starts-with "#")
    }
}

def mappings [file: path] {
    useful-lines $file
    | each { |line|
        $line
        | split row "|"
    }
}

def common-packages [] {
    let file = (
        $TOOLS_ROOT
        | path join "packages" "common.txt"
    )

    useful-lines $file
}

def find-row [
    rows: list
    name: string
] {
    let matches = (
        $rows
        | where { |row|
            ($row | get 0) == $name
        }
    )

    if ($matches | is-empty) {
        null
    } else {
        $matches
        | first
    }
}

def install-windows [
    names: list
] {
    if (which winget | is-empty) {
        print "[warn] winget not found; package manifest skipped."
        return
    }

    let file = (
        $TOOLS_ROOT
        | path join "packages" "windows.txt"
    )

    let rows = (
        mappings $file
    )

    for name in $names {
        let row = (
            find-row $rows $name
        )

        if $row == null {
            print (
                "[skip] No Windows mapping: " + $name
            )
            continue
        }

        let command = (
            $row
            | get 1
        )

        let package_id = (
            $row
            | get 2
        )

        if not (which $command | is-empty) {
            print (
                "[ok] " + $name
            )
            continue
        }

        let package_state = (winget-package-state "installed" $package_id)

        if $package_state == "yes" {
            print ("[ok] " + $name + " package already installed; skipping reinstall")
            print ("[info] " + $command + " is not visible in PATH in this process")
            continue
        }

        if $package_state == "error" {
            print ("[warn] Could not determine WinGet state for " + $package_id + "; leaving package unchanged")
            continue
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

        run-program ("Install " + $name) "winget" $args | ignore
    }
}

def install-macos [
    names: list
] {
    if (which brew | is-empty) {
        print "[warn] Homebrew not found; package manifest skipped."
        return
    }

    let file = (
        $TOOLS_ROOT
        | path join "packages" "macos.txt"
    )

    let rows = (
        mappings $file
    )

    for name in $names {
        let row = (
            find-row $rows $name
        )

        if $row == null {
            print (
                "[skip] No macOS mapping: " + $name
            )
            continue
        }

        let command = (
            $row
            | get 1
        )

        let package = (
            $row
            | get 2
        )

        if not (which $command | is-empty) {
            print (
                "[ok] " + $name
            )
            continue
        }

        let args = [
            "install"
            $package
        ]

        run-program ("Install " + $name) "brew" $args | ignore
    }
}

def linux-manager [] {
    for row in [
        {command: "apt-get" name: "apt" column: 2}
        {command: "dnf" name: "dnf" column: 3}
        {command: "pacman" name: "pacman" column: 4}
        {command: "zypper" name: "zypper" column: 5}
        {command: "apk" name: "apk" column: 6}
    ] {
        if not (which $row.command | is-empty) { return $row }
    }
    {command: "" name: "unsupported" column: (-1)}
}

def linux-is-root [] {
    if (which id | is-empty) { return false }
    let result = (do { ^id -u } | complete)
    $result.exit_code == 0 and ($result.stdout | str trim) == "0"
}

def privileged-command [program: string args: list] {
    if (linux-is-root) { return {program: $program args: $args} }
    if (which sudo | is-empty) {
        error make {msg: ("Root privileges are required to install Linux package with " + $program + ", but sudo is unavailable.")}
    }
    {program: "sudo" args: ([$program] | append $args)}
}

def install-linux-package [
    manager: string
    package: string
    name: string
] {
    if $package == "-" { return false }

    let args = (match $manager {
        "apt" => { ["install" "-y" $package] }
        "dnf" => { ["install" "-y" $package] }
        "pacman" => { ["-S" "--needed" "--noconfirm" $package] }
        "zypper" => { ["--non-interactive" "install" $package] }
        "apk" => { ["add" "--no-cache" $package] }
        _ => { return false }
    })
    let program = (match $manager {
        "apt" => "apt-get"
        "dnf" => "dnf"
        "pacman" => "pacman"
        "zypper" => "zypper"
        "apk" => "apk"
        _ => ""
    })
    let elevated = (privileged-command $program $args)
    let exit_code = (run-program ("Install " + $name) $elevated.program $elevated.args)
    $exit_code == 0
}

def install-linux [
    names: list
] {
    let manager_info = (linux-manager)
    let manager = $manager_info.name

    if $manager == "unsupported" {
        print "[warn] No supported Linux package manager for manifest."
        return
    }

    let column = $manager_info.column

    let file = (
        $TOOLS_ROOT
        | path join "packages" "linux.txt"
    )

    let rows = (
        mappings $file
    )

    for name in $names {
        let row = (
            find-row $rows $name
        )

        if $row == null {
            print (
                "[skip] No Linux mapping: " + $name
            )
            continue
        }

        let command = (
            $row
            | get 1
        )

        let package = (
            $row
            | get $column
        )

        if not (which $command | is-empty) {
            print (
                "[ok] " + $name
            )
            continue
        }

        let installed = (install-linux-package $manager $package $name)

        if $installed {
            continue
        }

        if $name == "git-delta" and not (which cargo | is-empty) {
            let args = [
                "install"
                "git-delta"
                "--locked"
            ]

            run-program "Install git-delta with Cargo fallback" "cargo" $args | ignore

            continue
        }

        if $name == "lazygit" and not (which go | is-empty) {
            let args = [
                "install"
                "github.com/jesseduffield/lazygit@latest"
            ]

            run-program "Install lazygit with Go fallback" "go" $args | ignore

            continue
        }

        print (
            "[warn] Could not install " + $name
        )
    }

    if (which fd | is-empty) and not (which fdfind | is-empty) {
        print "[info] This distro provides fd as 'fdfind'."
    }

    if (which bat | is-empty) and not (which batcat | is-empty) {
        print "[info] This distro provides bat as 'batcat'."
    }
}

def main [] {
    let context = (
        machine-context
    )

    if not $context.features.cli_tools {
        print "[skip] CLI package manifests disabled"
        return
    }

    # The setup entrypoint already ensured it; standalone manifest installation
    # uses the same strict dependency path rather than warning-and-continuing.
    ensure-rclone | ignore
    let names = (common-packages | where {|name| $name != "rclone" })

    print "=== Package manifest ==="
    print ""

    match $nu.os-info.name {
        "windows" => {
            install-windows $names
        }

        "macos" => {
            install-macos $names
        }

        "linux" => {
            install-linux $names
        }

        _ => {
            print "[warn] Unsupported OS for package manifest."
        }
    }
}
