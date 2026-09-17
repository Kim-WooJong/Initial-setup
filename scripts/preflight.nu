#!/usr/bin/env nu

const POLICY_MODULE = path self ./modules/setup-policy.nu
use $POLICY_MODULE [local-config-exists private-config-exists]

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

    if not ($file | path exists) {
        error make { msg: ("Machine config not found: " + ($file | into string)) }
    }

    open $file
}

def main [--diff] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    print "Initial-setup preflight"
    print "────────────────────────────────────────────────────────────"
    print ("Machine       : " + $context.machine.name)
    print ("Profile       : " + $context.machine.profile)
    print ("Private data  : " + ($data_root | into string))
    print ("Local config  : " + (if (local-config-exists) { "detected" } else { "not detected" }))
    print ("Private config: " + (if (private-config-exists $data_root) { "detected" } else { "not detected" }))
    print ""

    if (which chezmoi | is-empty) {
        print "[warn] chezmoi is not installed."
        return
    }

    if not ($data_root | path exists) {
        print "[warn] Private data root is unavailable."
        return
    }

    print "chezmoi status:"
    let status_args = [
        "--source"
        ($data_root | into string)
        "status"
    ]
    ^chezmoi ...$status_args

    if $diff {
        print ""
        print "chezmoi diff:"
        let diff_args = [
            "--source"
            ($data_root | into string)
            "diff"
        ]
        ^chezmoi ...$diff_args
    } else {
        print ""
        print "Use `dotpreflight --diff` to show the full managed-file diff."
    }
}
