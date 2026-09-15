#!/usr/bin/env nu

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    open $file
}

def toolchain-names [] {
    ^rustup toolchain list
    | lines
    | each { |line| $line | str trim | split row " " | first }
    | where { |item| not ($item | is-empty) }
    | uniq
}

def installed-components [toolchain: string] {
    let lines = (^rustup component list --installed --toolchain $toolchain | lines | each { |line| $line | str trim })
    let candidates = ["clippy" "rustfmt" "rust-src" "rust-analyzer" "rust-analysis" "llvm-tools" "rustc-dev" "miri" "rust-docs"]
    mut result = []

    for component in $candidates {
        let present = ($lines | any { |line| $line == $component or ($line | str starts-with ($component + "-")) })
        if $present { $result = ($result | append $component) }
    }

    $result
}

def installed-targets [toolchain: string] {
    ^rustup target list --installed --toolchain $toolchain
    | lines
    | each { |line| $line | str trim }
    | where { |item| not ($item | is-empty) }
    | uniq
}

def default-toolchain [toolchains: list] {
    let default_lines = (^rustup toolchain list | lines | where { |line| $line | str contains "(default)" })

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
