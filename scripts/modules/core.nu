# Shared Initial-setup helpers.

export def nu-home [] {
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
