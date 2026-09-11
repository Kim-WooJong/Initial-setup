#!/usr/bin/env nu

def nu-home [] {
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
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

    open $file
}

def normalize-path [value: path] {
    $value
    | path expand
    | into string
    | str replace --all '\' '/'
}

def file-entry [
    label: string
    root: path
    file: path
] {
    let relative = (
        $file
        | path relative-to $root
        | into string
        | str replace --all '\' '/'
    )

    let content_hash = (
        open --raw $file
        | hash sha256
    )

    $label
    + "|"
    + $relative
    + "|"
    + $content_hash
}

def target-entries [
    label: string
    target: path
] {
    let expanded = (
        $target
        | path expand
    )

    let object_type = (
        $expanded
        | path type
    )

    if $object_type == null {
        return [
            ($label + "|MISSING")
        ]
    }

    if $object_type == "file" {
        let content_hash = (
            open --raw $expanded
            | hash sha256
        )

        return [
            (
                $label
                + "|FILE|"
                + $content_hash
            )
        ]
    }

    if $object_type == "dir" {
        let root_text = (
            normalize-path $expanded
        )

        let pattern = (
            $root_text
            + "/**/*"
        )

        let files = (
            glob -D $pattern
            | sort
        )

        if ($files | is-empty) {
            return [
                ($label + "|EMPTY")
            ]
        }

        return (
            $files
            | each { |file|
                file-entry $label $expanded $file
            }
        )
    }

    [
        ($label + "|OTHER")
    ]
}

def vscode-user-dir [] {
    match $nu.os-info.name {
        "windows" => {
            let appdata = (
                $env.APPDATA?
                | default ""
            )

            if ($appdata | is-empty) {
                return null
            }

            $appdata
            | path join "Code" "User"
        }

        "macos" => {
            (nu-home)
            | path join "Library" "Application Support" "Code" "User"
        }

        "linux" => {
            (nu-home)
            | path join ".config" "Code" "User"
        }

        _ => {
            null
        }
    }
}

def append-target [
    entries: list
    label: string
    path: path
] {
    mut result = $entries

    let values = (target-entries $label $path)

    for value in $values {
        $result = (
            $result
            | append $value
        )
    }

    $result
}

def local-entries [] {
    let context = (
        machine-context
    )

    let features = (
        $context.features
    )

    let config_root = (
        (nu-home)
        | path join ".config"
    )

    mut entries = []

    let nvim_path = ($config_root | path join "nvim")
    $entries = (append-target $entries "nvim" $nvim_path)

    let nushell_path = ($config_root | path join "nushell")
    $entries = (append-target $entries "nushell" $nushell_path)

    if $features.wezterm {
        let wezterm_path = ($config_root | path join "wezterm")
        $entries = (append-target $entries "wezterm" $wezterm_path)
    }

    if $features.starship {
        let starship_path = ($config_root | path join "starship.toml")
        $entries = (append-target $entries "starship" $starship_path)
    }

    if $features.git_config {
        let git_home_path = ((nu-home) | path join ".gitconfig")
        $entries = (append-target $entries "git-home" $git_home_path)

        let git_xdg_path = ($config_root | path join "git" "config")
        $entries = (append-target $entries "git-xdg" $git_xdg_path)
    }

    if $features.ssh_config {
        let ssh_config_path = ((nu-home) | path join ".ssh" "config")
        $entries = (append-target $entries "ssh-config" $ssh_config_path)
    }

    if $features.rust {
        let cargo_path = ((nu-home) | path join ".cargo" "config.toml")
        $entries = (append-target $entries "cargo" $cargo_path)
    }

    if $features.julia {
        let julia_path = ((nu-home) | path join ".julia" "config" "startup.jl")
        $entries = (append-target $entries "julia" $julia_path)
    }

    if $features.vscode {
        let vscode_dir = (
            vscode-user-dir
        )

        if $vscode_dir == null {
            $entries = (
                $entries
                | append "vscode-config|UNAVAILABLE"
            )
        } else {
            let vscode_settings_path = ($vscode_dir | path join "settings.json")
            $entries = (append-target $entries "vscode-settings" $vscode_settings_path)

            let vscode_keybindings_path = ($vscode_dir | path join "keybindings.json")
            $entries = (append-target $entries "vscode-keybindings" $vscode_keybindings_path)

            let vscode_snippets_path = ($vscode_dir | path join "snippets")
            $entries = (append-target $entries "vscode-snippets" $vscode_snippets_path)
        }

        if (which code | is-empty) {
            $entries = (
                $entries
                | append "vscode-extensions|UNAVAILABLE"
            )
        } else {
            let args = [
                "--list-extensions"
            ]

            let extension_text = (
                ^code ...$args
                | lines
                | where { |item|
                    not ($item | is-empty)
                }
                | sort
                | uniq
                | str join (char nl)
            )

            let extension_hash = (
                $extension_text
                | hash sha256
            )

            $entries = (
                $entries
                | append (
                    "vscode-extensions|"
                    + $extension_hash
                )
            )
        }
    }

    $entries
}

def cloud-entries [] {
    let context = (
        machine-context
    )

    let data_root = (
        $context.data_root
        | path expand
    )

    mut entries = []

    let cloud_home_path = ($data_root | path join "home")
    $entries = (append-target $entries "cloud-home" $cloud_home_path)

    if $context.features.vscode {
        let cloud_vscode_path = ($data_root | path join "vscode")
        $entries = (append-target $entries "cloud-vscode" $cloud_vscode_path)
    }

    $entries
}

def main [
    --kind: string
] {
    let entries = (
        if $kind == "local" {
            local-entries
        } else if $kind == "cloud" {
            cloud-entries
        } else {
            error make {
                msg: "Use --kind local or --kind cloud."
            }
        }
    )

    let canonical = (
        $entries
        | sort
        | str join (char nl)
    )

    $canonical
    | hash sha256
}
