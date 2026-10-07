#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

def toolchain-names [] {
    let result = (run-command "rustup" ["toolchain" "list"])
    if not $result.ok { error make {msg: (command-failure-message "rustup toolchain list" $result)} }
    $result.stdout
    | lines
    | each { |line| $line | str trim | split row " " | first }
    | where { |item| not ($item | is-empty) }
    | uniq
}

def installed-components [toolchain: string] {
    let probe = (run-command "rustup" ["component" "list" "--installed" "--toolchain" $toolchain])
    if not $probe.ok { error make {msg: (command-failure-message ("rustup component list " + $toolchain) $probe)} }
    let lines = ($probe.stdout | lines | each { |line| $line | str trim })
    let candidates = ["clippy" "rustfmt" "rust-src" "rust-analyzer" "rust-analysis" "llvm-tools" "rustc-dev" "miri" "rust-docs"]
    mut result = []

    for component in $candidates {
        let present = ($lines | any { |line| $line == $component or ($line | str starts-with ($component + "-")) })
        if $present { $result = ($result | append $component) }
    }

    $result
}

def installed-targets [toolchain: string] {
    let result = (run-command "rustup" ["target" "list" "--installed" "--toolchain" $toolchain])
    if not $result.ok { error make {msg: (command-failure-message ("rustup target list " + $toolchain) $result)} }
    $result.stdout
    | lines
    | each { |line| $line | str trim }
    | where { |item| not ($item | is-empty) }
    | uniq
}

def default-toolchain [toolchains: list] {
    let result = (run-command "rustup" ["toolchain" "list"])
    if not $result.ok { error make {msg: (command-failure-message "rustup toolchain list" $result)} }
    let default_lines = ($result.stdout | lines | where { |line| $line | str contains "(default)" })

    if not ($default_lines | is-empty) {
        return ($default_lines | first | str trim | split row " " | first)
    }

    if not ($toolchains | is-empty) { return ($toolchains | first) }
    ""
}

def main [] {
    let context = (machine-context)

    if not $context.features.rust {
        print "[skip] Rust disabled"
        return
    }

    if (which rustup | is-empty) {
        print "[skip] rustup not found"
        return
    }

    let names = (toolchain-names)
    let default_name = (default-toolchain $names)
    mut toolchains = []

    for name in $names {
        let state = {
            name: $name
            components: (installed-components $name)
            targets: (installed-targets $name)
        }

        $toolchains = ($toolchains | append $state)
    }

    let output_dir = ($context.data_root | path expand | path join "toolchains" "rust")
    mkdir $output_dir

    {
        version: 1
        captured_at: (date now | format date "%Y-%m-%d %H:%M:%S %z")
        default: $default_name
        toolchains: $toolchains
    }
    | to nuon
    | save --force ($output_dir | path join "state.nuon")

    print ("[ok] Rust state captured: " + ($output_dir | into string))
}
