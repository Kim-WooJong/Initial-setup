#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def run-script [name: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)
    ^nu $script
    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print ("[warn] Script failed: " + $name)
    }
}

def main [] {
    run-script "capture-rust-state.nu"
    run-script "capture-julia-environments.nu"
}
