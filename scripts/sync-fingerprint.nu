#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context vscode-user-dir]
const SUBPROCESS = path self ./modules/subprocess.nu
const RPOOL_MODULE = path self ./modules/rpool-sync.nu
const WIREGUARD_MODULE = path self ./modules/wireguard-sync.nu
use $SUBPROCESS [run-command]
use $RPOOL_MODULE [rpool-sync-status rpool-local-hash]
use $WIREGUARD_MODULE [wireguard-local-hash]

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

    ($label + "|" + $relative + "|" + $content_hash)
}

def is-shell-history [file: path] {
    ($file | path basename) =~ '^history\.(txt|sqlite3)(-wal|-shm|-journal)?$'
}

def target-entries [
    label: string
    target: any
] {
    if $target == null {
        return [
            ($label + "|MISSING")
        ]
    }

    let target_text = ($target | into string)

    if ($target_text | is-empty) {
        return [
            ($label + "|MISSING")
        ]
    }

    if not ($target_text | path exists) {
        return [
            ($label + "|MISSING")
        ]
    }

    let expanded = ($target_text | path expand)

    if $expanded == null {
        return [
            ($label + "|MISSING")
        ]
    }

    let object_type = (
        try {
            $expanded | path type
        } catch {
            null
        }
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
            ($label + "|FILE|" + $content_hash)
        ]
    }

    if $object_type == "dir" {
        let root_text = (
            normalize-path $expanded
        )

        let pattern = ($root_text + "/**/*" | into glob)

        # Nushell rewrites its command history on every prompt. History is
        # not managed configuration, so it must not register as a local edit.
        let files = (
            glob -D $pattern
            | where {|file| not ($label == "nushell" and (is-shell-history $file)) }
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

def rclone-config-path [] {
    if (which rclone | is-empty) {
        return null
    }

    let result = (run-command "rclone" ["config" "file"])
    if not $result.ok { return null }
    let rows = ($result.stdout | lines | each {|line| $line | str trim } | where {|line| not ($line | is-empty) })
    if ($rows | is-empty) { return null }
    $rows | last
}

def append-target [
    entries: list
    label: string
    path: any
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

    if ($features.rclone_config? | default false) {
        let rclone_path = (rclone-config-path)

        if $rclone_path == null {
            $entries = ($entries | append "rclone-config|UNAVAILABLE")
        } else {
            $entries = (append-target $entries "rclone-config" $rclone_path)
        }
    }

    let rpool_status = (rpool-sync-status ($context.data_root | path expand))
    if $rpool_status.installed or $rpool_status.bundle_exists {
        $entries = ($entries | append ("rpool-config|" + (rpool-local-hash)))
    }

    let wireguard_hash = (wireguard-local-hash)
    if $wireguard_hash != "DISABLED" {
        $entries = ($entries | append ("wireguard-config|" + $wireguard_hash))
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

            let code_result = (run-command "code" $args)
            let extension_text = if $code_result.ok {
                $code_result.stdout
                | lines
                | where { |item| not ($item | is-empty) }
                | sort
                | uniq
                | str join (char nl)
            } else {
                "UNAVAILABLE:" + ($code_result.exit_code? | default 1 | into string)
            }

            let extension_hash = (
                $extension_text
                | hash sha256
            )

            $entries = (
                $entries
                | append ("vscode-extensions|" + $extension_hash)
            )
        }
    }

    $entries
}

const PROVIDER_MODULE = path self ./modules/sync-provider.nu
use $PROVIDER_MODULE [load-provider provider-head]

def main [
    --kind: string
] {
    if $kind == "cloud" {
        let head = (provider-head (load-provider))
        print $head.tree_hash
        return
    }
    let entries = (
        if $kind == "local" {
            local-entries
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
