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

def run-rustup [label: string args: list] {
    print ("[rustup] " + $label)
    ^rustup ...$args
    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print ("[warn] Rustup returned exit code " + ($exit_code | into string) + ": " + $label)
    }

    $exit_code
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

        if $present {
            $result = ($result | append $component)
        }
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

def default-toolchain [] {
    let rows = (^rustup toolchain list | lines | where { |line| $line | str contains "(default)" })

    if ($rows | is-empty) {
        return ""
    }

    $rows | first | str trim | split row " " | first
}

def main [] {
    let context = (machine-context)

    if not $context.features.rust {
        print "[skip] Rust disabled"
        return
    }

    if (which rustup | is-empty) {
        print "[warn] rustup not found; Rust state restore skipped."
        return
    }

    let file = ($context.data_root | path expand | path join "toolchains" "rust" "state.nuon")

    if not ($file | path exists) {
        print "[skip] No captured Rust state"
        return
    }

    let state = (open $file)
    mut current_toolchains = (toolchain-names)

    for toolchain in $state.toolchains {
        if not ($toolchain.name in $current_toolchains) {
            let install_exit = (run-rustup ("Install toolchain " + $toolchain.name) ["toolchain" "install" $toolchain.name "--profile" "minimal"])

            if $install_exit == 0 {
                $current_toolchains = ($current_toolchains | append $toolchain.name | uniq)
            }
        } else {
            print ("[skip] Rust toolchain already installed: " + $toolchain.name)
        }

        if not ($toolchain.name in $current_toolchains) {
            print ("[warn] Toolchain unavailable; skipping components/targets: " + $toolchain.name)
            continue
        }

        mut current_components = (installed-components $toolchain.name)

        for component in $toolchain.components {
            if $component in $current_components {
                print ("[skip] Component already installed: " + $component + " @ " + $toolchain.name)
                continue
            }

            let component_exit = (run-rustup ("Add " + $component + " to " + $toolchain.name) ["component" "add" $component "--toolchain" $toolchain.name])

            if $component_exit == 0 {
                $current_components = ($current_components | append $component | uniq)
            }
        }

        mut current_targets = (installed-targets $toolchain.name)

        for target in $toolchain.targets {
            if $target in $current_targets {
                print ("[skip] Target already installed: " + $target + " @ " + $toolchain.name)
                continue
            }

            let target_exit = (run-rustup ("Add target " + $target + " to " + $toolchain.name) ["target" "add" $target "--toolchain" $toolchain.name])

            if $target_exit == 0 {
                $current_targets = ($current_targets | append $target | uniq)
            }
        }
    }

    let desired_default = ($state.default? | default "")
    let current_default = (default-toolchain)

    if not ($desired_default | is-empty) {
        if $desired_default == $current_default {
            print ("[skip] Default Rust toolchain already set: " + $desired_default)
        } else {
            run-rustup ("Set default toolchain " + $desired_default) ["default" $desired_default] | ignore
        }
    }

    print "[ok] Rust toolchain state restore completed"
}
