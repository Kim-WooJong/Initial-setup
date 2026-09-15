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

    for toolchain in $state.toolchains {
        run-rustup ("Install toolchain " + $toolchain.name) ["toolchain" "install" $toolchain.name] | ignore

        for component in $toolchain.components {
            run-rustup ("Add " + $component + " to " + $toolchain.name) ["component" "add" $component "--toolchain" $toolchain.name] | ignore
        }

        for target in $toolchain.targets {
            run-rustup ("Add target " + $target + " to " + $toolchain.name) ["target" "add" $target "--toolchain" $toolchain.name] | ignore
        }
    }

    let default_name = ($state.default? | default "")

    if not ($default_name | is-empty) {
        run-rustup ("Set default toolchain " + $default_name) ["default" $default_name] | ignore
    }

    print "[ok] Rust toolchain state restore completed"
}
