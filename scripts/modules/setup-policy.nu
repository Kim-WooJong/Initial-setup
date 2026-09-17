# Configuration source selection helpers.

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

export def local-config-markers [] {
    let home_path = (nu-home)

    mut markers = [
        ($home_path | path join ".config" "nvim" "init.lua")
        ($home_path | path join ".config" "nushell" "config.nu")
        ($home_path | path join ".config" "nushell" "env.nu")
        ($home_path | path join ".gitconfig")
        ($home_path | path join ".config" "git" "config")
        ($home_path | path join ".ssh" "config")
        ($home_path | path join ".config" "wezterm" "wezterm.lua")
        ($home_path | path join ".wezterm.lua")
        ($home_path | path join ".config" "starship.toml")
        ($home_path | path join ".cargo" "config.toml")
        ($home_path | path join ".julia" "config" "startup.jl")
    ]

    match $nu.os-info.name {
        "windows" => {
            let appdata = ($env.APPDATA? | default "")
            if not ($appdata | is-empty) {
                $markers = ($markers | append ($appdata | path join "Code" "User" "settings.json"))
            }
        }
        "macos" => {
            $markers = ($markers | append ($home_path | path join "Library" "Application Support" "Code" "User" "settings.json"))
        }
        "linux" => {
            $markers = ($markers | append ($home_path | path join ".config" "Code" "User" "settings.json"))
        }
        _ => {}
    }

    $markers
}

export def private-config-markers [data_root: path] {
    [
        ($data_root | path join "home" "dot_config" "nvim" "init.lua")
        ($data_root | path join "home" "dot_config" "nushell" "config.nu")
        ($data_root | path join "home" "dot_config" "nushell" "env.nu")
        ($data_root | path join "home" "dot_gitconfig")
        ($data_root | path join "home" "dot_config" "git" "config")
        ($data_root | path join "home" "private_dot_ssh" "config")
        ($data_root | path join "home" "dot_config" "wezterm" "wezterm.lua")
        ($data_root | path join "home" "dot_config" "starship.toml")
        ($data_root | path join "vscode" "settings.json")
        ($data_root | path join "toolchains" "rust" "state.nuon")
        ($data_root | path join "rclone" "rclone.conf")
    ]
}

export def local-config-exists [] {
    local-config-markers | any { |item| $item | path exists }
}

export def private-config-exists [data_root: path] {
    private-config-markers $data_root | any { |item| $item | path exists }
}

export def config-policy-names [] {
    [
        "ask"
        "push-local"
        "pull-private"
        "review"
        "backup-private"
        "preview"
        "cancel"
        # Backward-compatible aliases from v0.11.0/v0.11.1.
        "keep-local"
        "keep-private"
    ]
}

export def normalize-config-policy [policy: string] {
    match $policy {
        "keep-local" => { "push-local" }
        "keep-private" => { "pull-private" }
        _ => { $policy }
    }
}

export def choose-reviewed-policy [] {
    print ""
    print "Choose synchronization direction"
    print "────────────────────────────────────────────────────────────"
    print "  1) Save this machine -> private drive"
    print "     Current local managed files become authoritative."
    print ""
    print "  2) Apply private drive -> this machine"
    print "     Private managed files become authoritative."
    print ""
    print "  3) Backup this machine, then apply private drive"
    print "     Create a restorable local backup before pulling."
    print ""
    print "  4) Cancel"
    print ""

    mut selected = ""

    while ($selected | is-empty) {
        let choice = (input "Select [1]: " | str trim)
        let answer = (if ($choice | is-empty) { "1" } else { $choice })

        match $answer {
            "1" => { $selected = "push-local" }
            "2" => { $selected = "pull-private" }
            "3" => { $selected = "backup-private" }
            "4" => { $selected = "cancel" }
            _ => { print "Choose 1, 2, 3, or 4." }
        }
    }

    $selected
}

export def choose-config-policy [data_root: path] {
    let local_exists = (local-config-exists)
    let private_exists = (private-config-exists $data_root)

    let default_choice = (
        if $local_exists and $private_exists {
            "1"
        } else if $private_exists {
            "3"
        } else {
            "2"
        }
    )

    print ""
    print "Configuration synchronization policy"
    print "────────────────────────────────────────────────────────────"
    print ("Local configuration   : " + (if $local_exists { "detected" } else { "not detected" }))
    print ("Private configuration : " + (if $private_exists { "detected" } else { "not detected" }))
    print ""
    print "  1) Review differences, then choose direction"
    print "     Show chezmoi status/diff first. Initial-setup will then ask push or pull."
    print ""
    print "  2) Save local changes to private drive"
    print "     This machine is authoritative; publish managed local files to private storage."
    print ""
    print "  3) Apply private configuration to this machine"
    print "     Private synchronized files are authoritative; replace managed local files."
    print ""
    print "  4) Backup local, then apply private configuration"
    print "     Save a restorable local backup before replacing managed files."
    print ""
    print "  5) Preview only"
    print "     Show the setup plan and chezmoi differences, then exit without applying."
    print ""
    print "  6) Cancel"
    print ""

    let recommendation = (
        match $default_choice {
            "1" => "review"
            "2" => "push-local"
            "3" => "pull-private"
            _ => "review"
        }
    )

    print ("Recommended for the detected state: " + $recommendation)
    print ""

    mut selected = ""

    while ($selected | is-empty) {
        let answer = (input ("Select [" + $default_choice + "]: ") | str trim)
        let choice = (if ($answer | is-empty) { $default_choice } else { $answer })

        match $choice {
            "1" => { $selected = "review" }
            "2" => { $selected = "push-local" }
            "3" => { $selected = "pull-private" }
            "4" => { $selected = "backup-private" }
            "5" => { $selected = "preview" }
            "6" => { $selected = "cancel" }
            _ => { print "Choose 1, 2, 3, 4, 5, or 6." }
        }
    }

    $selected
}
