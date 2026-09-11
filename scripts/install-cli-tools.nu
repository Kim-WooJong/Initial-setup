#!/usr/bin/env nu

# ============================================================
# Install common CLI tools from public package manifests.
# ============================================================

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
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

    open $file
}

def run-program [
    label: string
    program: string
    args: list
] {
    print (
        "[run] "
        + $label
    )
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
                "[skip] No Windows mapping: "
                + $name
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
                "[ok] "
                + $name
            )
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
                "[skip] No macOS mapping: "
                + $name
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
                "[ok] "
                + $name
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
    if not (which apt-get | is-empty) {
        return "apt"
    }

    if not (which dnf | is-empty) {
        return "dnf"
    }

    if not (which pacman | is-empty) {
        return "pacman"
    }

    "unsupported"
}

def install-linux-package [
    manager: string
    package: string
    name: string
] {
    if $package == "-" {
        return false
    }

    let args = (
        if $manager == "apt" {
            [
                "apt-get"
                "install"
                "-y"
                $package
            ]
        } else if $manager == "dnf" {
            [
                "dnf"
                "install"
                "-y"
                $package
            ]
        } else {
            [
                "pacman"
                "-S"
                "--needed"
                "--noconfirm"
                $package
            ]
        }
    )

    let exit_code = (run-program ("Install " + $name) "sudo" $args)

    $exit_code == 0
}

def install-linux [
    names: list
] {
    let manager = (
        linux-manager
    )

    if $manager == "unsupported" {
        print "[warn] No supported Linux package manager for manifest."
        return
    }

    let column = (
        if $manager == "apt" {
            2
        } else if $manager == "dnf" {
            3
        } else {
            4
        }
    )

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
                "[skip] No Linux mapping: "
                + $name
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
                "[ok] "
                + $name
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
            "[warn] Could not install "
            + $name
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

    let names = (
        common-packages
    )

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
