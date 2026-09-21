#!/usr/bin/env nu

const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

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

def run-rustup [label: string args: list] {
    print ("[rustup] " + $label)
    let result = (run-command "rustup" $args --live)
    if not $result.ok {
        let code = if $result.exit_code == null { "not launched" } else { $result.exit_code | into string }
        print ("[warn] Rustup failed (" + $code + "): " + $label)
        if not ($result.diagnostic | str trim | is-empty) { print --stderr $result.diagnostic }
    }
    if $result.ok { 0 } else if $result.exit_code == null { 1 } else { $result.exit_code }
}

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

        if $present {
            $result = ($result | append $component)
        }
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

def default-toolchain [] {
    let result = (run-command "rustup" ["toolchain" "list"])
    if not $result.ok { error make {msg: (command-failure-message "rustup toolchain list" $result)} }
    let rows = ($result.stdout | lines | where { |line| $line | str contains "(default)" })

    if ($rows | is-empty) {
        return ""
    }

    $rows | first | str trim | split row " " | first
}

def main [--source-root: string = ""] {
    let context = (machine-context)

    if not $context.features.rust {
        print "[skip] Rust disabled"
        return
    }

    if (which rustup | is-empty) {
        print "[warn] rustup not found; Rust state restore skipped."
        return
    }

    let source_root = if ($source_root | str trim | is-empty) { $context.data_root | path expand } else { $source_root | path expand }
    let file = ($source_root | path join "toolchains" "rust" "state.nuon")

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
