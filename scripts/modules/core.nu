# Shared Initial-setup helpers.

export def nu-home [] {
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

export def machine-config-path [] {
    (nu-home) | path join ".config" "dotfiles" "config.nuon"
}

export def machine-context [] {
    let file = (machine-config-path)

    if not ($file | path exists) {
        error make {
            msg: ("Machine config not found: " + ($file | into string))
        }
    }

    open $file
}

export def detect-machine-name [] {
    let computer_name = ($env.COMPUTERNAME? | default "" | str trim)

    if not ($computer_name | is-empty) {
        return $computer_name
    }

    let host_name = ($env.HOSTNAME? | default "" | str trim)

    if not ($host_name | is-empty) {
        return $host_name
    }

    if not (which hostname | is-empty) {
        let external_name = (^hostname | str trim)

        if not ($external_name | is-empty) {
            return $external_name
        }
    }

    "unknown-machine"
}


# Normalize caught values without assuming every failure is a record with `.msg`.
# Some `try` blocks can surface strings/lists/records from normal pipeline output;
# these helpers make explicit failure envelopes distinguishable from success output.
export def error-message [value: any fallback: string = "Operation failed."] {
    let kind = ($value | describe)
    if $kind == "string" {
        if not ($value | str trim | is-empty) { return $value }
    }
    if ($kind | str starts-with "record") {
        for key in ["msg" "rendered"] {
            let candidate = ($value | get --optional $key)
            if ($candidate | describe) == "string" {
                if not ($candidate | str trim | is-empty) { return $candidate }
            }
        }
    }
    $fallback
}

export def failure-envelope [value: any] {
    {
        __initial_setup_failure: true
        error: $value
    }
}

export def captured-failure [value: any] {
    let kind = ($value | describe)
    let values = if ($kind | str starts-with "list") or ($kind | str starts-with "table") { $value } else { [$value] }

    for item in $values {
        let item_kind = ($item | describe)
        if ($item_kind | str starts-with "record") {
            let marker = ($item | get --optional __initial_setup_failure)
            if $marker == true {
                return ($item | get --optional error)
            }
        }
    }

    null
}
