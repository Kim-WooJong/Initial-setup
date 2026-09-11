#!/usr/bin/env nu

# ============================================================
# sync-fingerprint.nu
#
# Compute a deterministic SHA-256 fingerprint for either:
#   local - actual managed configuration on this machine
#   cloud - private chezmoi/cloud source
#
# The fingerprint is compared only against an earlier
# fingerprint of the same side.
# ============================================================

def machine-context [] {
    let file = (
        $nu.home-path
        | path join ".config" "dotfiles" "config.nuon"
    )

    if not ($file | path exists) {
        error make {
            msg: (
                "Machine config not found: "
                + ($file | into string)
            )
        }
    }

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
            $nu.home-path
            | path join "Library" "Application Support" "Code" "User"
        }

        "linux" => {
            $nu.home-path
            | path join ".config" "Code" "User"
        }

        _ => {
            null
        }
    }
}

def local-entries [] {
    let config_root = (
        $nu.home-path
        | path join ".config"
    )

    let targets = [
        {
            label: "nvim"
            path: (
                $config_root
                | path join "nvim"
            )
        }
        {
            label: "nushell"
            path: (
                $config_root
                | path join "nushell"
            )
        }
        {
            label: "wezterm"
            path: (
                $config_root
                | path join "wezterm"
            )
        }
        {
            label: "starship"
            path: (
                $config_root
                | path join "starship.toml"
            )
        }
        {
            label: "git-home"
            path: (
                $nu.home-path
                | path join ".gitconfig"
            )
        }
        {
            label: "git-xdg"
            path: (
                $config_root
                | path join "git" "config"
            )
        }
        {
            label: "ssh-config"
            path: (
                $nu.home-path
                | path join ".ssh" "config"
            )
        }
        {
            label: "cargo"
            path: (
                $nu.home-path
                | path join ".cargo" "config.toml"
            )
        }
        {
            label: "julia"
            path: (
                $nu.home-path
                | path join ".julia" "config" "startup.jl"
            )
        }
    ]

    mut entries = []

    for target in $targets {
        let target_values = (
            target-entries
                $target.label
                $target.path
        )

        for value in $target_values {
            $entries = (
                $entries
                | append $value
            )
        }
    }

    let vscode_dir = (
        vscode-user-dir
    )

    if $vscode_dir == null {
        $entries = (
            $entries
            | append "vscode-config|UNAVAILABLE"
        )
    } else {
        for item in [
            {
                label: "vscode-settings"
                path: (
                    $vscode_dir
                    | path join "settings.json"
                )
            }
            {
                label: "vscode-keybindings"
                path: (
                    $vscode_dir
                    | path join "keybindings.json"
                )
            }
            {
                label: "vscode-snippets"
                path: (
                    $vscode_dir
                    | path join "snippets"
                )
            }
        ] {
            let target_values = (
                target-entries
                    $item.label
                    $item.path
            )

            for value in $target_values {
                $entries = (
                    $entries
                    | append $value
                )
            }
        }
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

    let targets = [
        {
            label: "cloud-home"
            path: (
                $data_root
                | path join "home"
            )
        }
        {
            label: "cloud-vscode"
            path: (
                $data_root
                | path join "vscode"
            )
        }
    ]

    mut entries = []

    for target in $targets {
        let target_values = (
            target-entries
                $target.label
                $target.path
        )

        for value in $target_values {
            $entries = (
                $entries
                | append $value
            )
        }
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
