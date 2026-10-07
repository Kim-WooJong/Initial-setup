const CORE = path self ./core.nu
use $CORE [nu-home]
# Configuration source selection helpers.

const CONSOLE = path self ./console.nu
use $CONSOLE [print-heading print-text print-key-value print-choice]

def local-config-markers [] {
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

def private-config-markers [data_root: path] {
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
    print-heading "Choose synchronization direction"
    print-heading "────────────────────────────────────────────────────────────"
    print-choice "1" "Save this machine -> private drive"
    print-text "info" "     Current local managed files become authoritative."
    print ""
    print-choice "2" "Apply private drive -> this machine"
    print-text "info" "     Private managed files become authoritative."
    print ""
    print-choice "3" "Backup this machine, then apply private drive"
    print-text "info" "     Create a restorable local backup before pulling."
    print ""
    print-choice "4" "Cancel"
    print ""

    mut selected = ""

    while ($selected | is-empty) {
        print-text "prompt" "Select [1] (press Enter for default):"
        let choice = (input | str trim)
        let answer = (if ($choice | is-empty) { "1" } else { $choice })

        match $answer {
            "1" => { $selected = "push-local" }
            "2" => { $selected = "pull-private" }
            "3" => { $selected = "backup-private" }
            "4" => { $selected = "cancel" }
            _ => { print-text "warn" "Choose 1, 2, 3, or 4." }
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
    print-heading "Configuration synchronization policy"
    print-heading "────────────────────────────────────────────────────────────"
    print-key-value "Local configuration   : " (if $local_exists { "detected" } else { "not detected" })
    print-key-value "Private configuration : " (if $private_exists { "detected" } else { "not detected" })
    print ""
    print-choice "1" "Review differences, then choose direction"
    print-text "info" "     Show chezmoi status/diff first. Initial-setup will then ask push or pull."
    print ""
    print-choice "2" "Save local changes to private drive"
    print-text "info" "     This machine is authoritative; publish managed local files to private storage."
    print ""
    print-choice "3" "Apply private configuration to this machine"
    print-text "info" "     Private synchronized files are authoritative; replace managed local files."
    print ""
    print-choice "4" "Backup local, then apply private configuration"
    print-text "info" "     Save a restorable local backup before replacing managed files."
    print ""
    print-choice "5" "Preview only"
    print-text "info" "     Show the setup plan and chezmoi differences, then exit without applying."
    print ""
    print-choice "6" "Cancel"
    print ""

    let recommendation = (
        match $default_choice {
            "1" => "review"
            "2" => "push-local"
            "3" => "pull-private"
            _ => "review"
        }
    )

    print-key-value "Recommended for the detected state: " $recommendation
    print ""

    mut selected = ""

    while ($selected | is-empty) {
        print-text "prompt" ("Select [" + $default_choice + "] (press Enter for default):")
        let answer = (input | str trim)
        let choice = (if ($answer | is-empty) { $default_choice } else { $answer })

        match $choice {
            "1" => { $selected = "review" }
            "2" => { $selected = "push-local" }
            "3" => { $selected = "pull-private" }
            "4" => { $selected = "backup-private" }
            "5" => { $selected = "preview" }
            "6" => { $selected = "cancel" }
            _ => { print-text "warn" "Choose 1, 2, 3, 4, 5, or 6." }
        }
    }

    $selected
}
