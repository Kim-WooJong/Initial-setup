#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context useful-lines]
const TOOLS_ROOT = path self ..
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $INSTALL_UTILS [run-installer probe-tool winget-package-state privileged-command]

# Common CLI packages are optional individually. Each command is considered
# ready only after a real version probe succeeds.

def mappings [file: path] { useful-lines $file | each {|line| $line | split row "|" } }
def common-packages [] { useful-lines ($TOOLS_ROOT | path join "packages" "common.txt") }
def find-row [rows: list name: string] { let x = ($rows | where {|row| ($row | get 0) == $name }); if ($x | is-empty) { null } else { $x | first } }

def version-probe [command: string] {
    let args = if $command == "rclone" { ["version"] } else { ["--version"] }
    probe-tool $command $args
}

def logical-probe [name: string command: string] {
    let primary = (version-probe $command)

    if $name == "age" {
        let keygen = (version-probe "age-keygen")
        if $primary.healthy and $keygen.healthy { return $primary }
        if $primary.found {
            return {
                found: true
                healthy: false
                path: $primary.path
                version: ""
                result: (if $keygen.result != null { $keygen.result } else { $primary.result })
            }
        }
        if $keygen.found {
            return {found: true healthy: false path: $keygen.path version: "" result: $keygen.result}
        }
        return $primary
    }

    if $primary.healthy { return $primary }
    if $nu.os-info.name == "linux" and $name == "fd" { return (version-probe "fdfind") }
    if $nu.os-info.name == "linux" and $name == "bat" { return (version-probe "batcat") }
    $primary
}

def verify-after [name: string command: string] {
    let result = (logical-probe $name $command)
    if $result.healthy {
        print ("[ok] " + $name + " -> " + $result.path)
        true
    } else {
        print ("[warn] Installer finished, but " + $name + " failed its version probe. Restart the shell or repair PATH.")
        false
    }
}

def install-windows [names: list] {
    if (which winget | is-empty) { print "[warn] winget not found; package manifest skipped."; return }
    let rows = (mappings ($TOOLS_ROOT | path join "packages" "windows.txt"))
    for name in $names {
        let row = (find-row $rows $name)
        if $row == null { print ("[skip] No Windows mapping: " + $name); continue }
        let command = ($row | get 1)
        let package_id = ($row | get 2)
        let before = (logical-probe $name $command)
        if $before.healthy { print ("[ok] " + $name + " " + $before.version); continue }
        if $before.found { print ("[warn] " + $command + " exists but failed its health probe: " + $before.path) }
        let state = (winget-package-state $TOOLS_ROOT $package_id)
        if $state == "error" { print ("[warn] Could not determine WinGet state for " + $package_id + "; refusing a blind reinstall"); continue }
        let verb = if $state == "yes" { "upgrade" } else { "install" }
        let result = (run-installer ("Install/repair " + $name) "winget" [$verb "--id" $package_id "--exact" "--source" "winget" "--accept-package-agreements" "--accept-source-agreements"])
        if $result.ok { verify-after $name $command | ignore }
    }
}

def install-macos [names: list] {
    if (which brew | is-empty) { print "[warn] Homebrew not found; package manifest skipped."; return }
    let rows = (mappings ($TOOLS_ROOT | path join "packages" "macos.txt"))
    for name in $names {
        let row = (find-row $rows $name)
        if $row == null { print ("[skip] No macOS mapping: " + $name); continue }
        let command = ($row | get 1)
        let package = ($row | get 2)
        let before = (logical-probe $name $command)
        if $before.healthy { print ("[ok] " + $name + " " + $before.version); continue }
        let result = (run-installer ("Install/repair " + $name) "brew" ["install" $package])
        if $result.ok { verify-after $name $command | ignore }
    }
}

def linux-manager [] {
    for row in [
        {command: "apt-get" name: "apt" column: 2}
        {command: "dnf" name: "dnf" column: 3}
        {command: "pacman" name: "pacman" column: 4}
        {command: "zypper" name: "zypper" column: 5}
        {command: "apk" name: "apk" column: 6}
    ] { if not (which $row.command | is-empty) { return $row } }
    {command: "" name: "unsupported" column: (-1)}
}

def install-linux-package [manager_info: record package: string name: string] {
    if $package == "-" { return false }
    let manager = $manager_info.name
    let args = (match $manager {
        "apt" => ["install" "-y" $package]
        "dnf" => ["install" "-y" $package]
        "pacman" => ["-S" "--needed" "--noconfirm" $package]
        "zypper" => ["--non-interactive" "install" $package]
        "apk" => ["add" "--no-cache" $package]
        _ => []
    })
    if ($args | is-empty) { return false }
    let elevated = (privileged-command $manager_info.command $args)
    if not $elevated.ok { print ("[warn] " + $elevated.reason); return false }
    (run-installer ("Install " + $name) $elevated.program $elevated.args).ok
}

def install-linux [names: list] {
    let manager_info = (linux-manager)
    if $manager_info.name == "unsupported" { print "[warn] No supported Linux package manager for manifest."; return }
    let rows = (mappings ($TOOLS_ROOT | path join "packages" "linux.txt"))
    for name in $names {
        let row = (find-row $rows $name)
        if $row == null { print ("[skip] No Linux mapping: " + $name); continue }
        let command = ($row | get 1)
        let package = ($row | get $manager_info.column)
        let before = (logical-probe $name $command)
        if $before.healthy { print ("[ok] " + $name + " " + $before.version); continue }
        if $before.found { print ("[warn] " + $command + " exists but failed its health probe: " + $before.path) }
        mut installed = (install-linux-package $manager_info $package $name)
        if not $installed and $name == "git-delta" and not (which cargo | is-empty) { $installed = (run-installer "Install git-delta with Cargo fallback" "cargo" ["install" "git-delta" "--locked"]).ok }
        if not $installed and $name == "lazygit" and not (which go | is-empty) { $installed = (run-installer "Install lazygit with Go fallback" "go" ["install" "github.com/jesseduffield/lazygit@latest"]).ok }
        if $installed { verify-after $name $command | ignore } else { print ("[warn] Could not install " + $name) }
    }
}

def main [--required: string = ""] {
    let required_name = ($required | str trim)
    let mapping_file = (match $nu.os-info.name {
        "windows" => { $TOOLS_ROOT | path join "packages" "windows.txt" }
        "macos" => { $TOOLS_ROOT | path join "packages" "macos.txt" }
        "linux" => { $TOOLS_ROOT | path join "packages" "linux.txt" }
        _ => { null }
    })

    let required_command = if not ($required_name | is-empty) {
        if $mapping_file == null {
            error make {msg: ("Required package '" + $required_name + "' is not supported on this OS.")}
        }
        let row = (find-row (mappings $mapping_file) $required_name)
        if $row == null {
            error make {msg: ("Required package mapping is missing: " + $required_name)}
        }
        $row | get 1
    } else {
        ""
    }

    let names = if not ($required_name | is-empty) {
        [$required_name]
    } else {
        let context = (machine-context)
        if not ($context.features.cli_tools? | default true) { print "[skip] CLI tool installation disabled"; return }
        common-packages
    }

    match $nu.os-info.name {
        "windows" => { install-windows $names }
        "macos" => { install-macos $names }
        "linux" => { install-linux $names }
        _ => { print "[warn] Unsupported OS for common CLI package installation." }
    }

    if not ($required_name | is-empty) {
        let final = (logical-probe $required_name $required_command)
        if not $final.healthy {
            error make {
                msg: (
                    "Required package '" + $required_name + "' is not usable after installation. " +
                    "Repair the package manager/PATH and rerun setup."
                )
            }
        }
    }
}
