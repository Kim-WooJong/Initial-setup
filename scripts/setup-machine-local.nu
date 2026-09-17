#!/usr/bin/env nu

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

def main [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "local.nu")

    if ($file | path exists) {
        print ("[keep] Machine-local setup: " + ($file | into string))
        return
    }

    mkdir ($file | path dirname)

    [
        "# Generated once by Initial-setup."
        "#"
        "# MACHINE-LOCAL NUSHELL SETUP"
        "# This file is intentionally NOT synchronized."
        "# Initial-setup creates it only when missing and never overwrites it."
        "# It is excluded from chezmoi/private-cloud sync, sync fingerprints,"
        "# snapshots, rollback, and the public Initial-setup repository."
        "#"
        "# Put computer-specific Nushell setup below this line."
        "#"
        "# Examples:"
        '# $env.MY_MACHINE_ONLY = "value"'
        "# alias local-tool = some-command"
        ""
    ]
    | str join (char nl)
    | save $file

    print ("[create] Machine-local setup: " + ($file | into string))
}
