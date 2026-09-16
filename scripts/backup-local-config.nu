#!/usr/bin/env nu

# ============================================================
# Backup and restore live machine-local configuration.
#
# This is intentionally separate from `dotsnapshot`, which
# snapshots the private synchronized source. Dedicated secret
# files and SSH private keys are not copied by this script.
# Ordinary config files are backed up verbatim, so users should
# not embed secrets directly in those files.
# ============================================================

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def backup-root [] {
    (nu-home) | path join ".config" "dotfiles" "local-backups"
}


def backup-keep [] {
    let config_file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    if not ($config_file | path exists) {
        return 20
    }

    let context = (open $config_file)
    $context.maintenance.snapshot_keep? | default 20
}

def prune-backups [] {
    let root = (backup-root)
    let keep = (backup-keep)

    if $keep <= 0 or not ($root | path exists) {
        return
    }

    let backups = (
        ls $root
        | where type == dir
        | sort-by name
        | reverse
    )

    if ($backups | length) <= $keep {
        return
    }

    for item in ($backups | skip $keep) {
        rm -r $item.name
    }
}

def sanitize-label [label: string] {
    $label
    | str replace --all ' ' '-'
    | str replace --all '/' '-'
    | str replace --all '\\' '-'
    | str replace --all ':' '-'
}

def vscode-user-dir [] {
    match $nu.os-info.name {
        "windows" => {
            let appdata = ($env.APPDATA? | default "")
            if ($appdata | is-empty) { null } else { $appdata | path join "Code" "User" }
        }
        "macos" => { (nu-home) | path join "Library" "Application Support" "Code" "User" }
        "linux" => { (nu-home) | path join ".config" "Code" "User" }
        _ => { null }
    }
}

def backup-targets [] {
    let home = (nu-home)
    mut targets = [
        { name: "nvim", source: ($home | path join ".config" "nvim"), stored: "nvim" }
        { name: "nushell", source: ($home | path join ".config" "nushell"), stored: "nushell" }
        { name: "gitconfig", source: ($home | path join ".gitconfig"), stored: "gitconfig" }
        { name: "git-xdg", source: ($home | path join ".config" "git" "config"), stored: "git-xdg-config" }
        { name: "git-local", source: ($home | path join ".gitconfig.local"), stored: "gitconfig-local" }
        { name: "ssh-config", source: ($home | path join ".ssh" "config"), stored: "ssh-config" }
        { name: "ssh-config-local", source: ($home | path join ".ssh" "config.local"), stored: "ssh-config-local" }
        { name: "wezterm", source: ($home | path join ".config" "wezterm"), stored: "wezterm" }
        { name: "wezterm-legacy", source: ($home | path join ".wezterm.lua"), stored: "wezterm-legacy.lua" }
        { name: "starship", source: ($home | path join ".config" "starship.toml"), stored: "starship.toml" }
        { name: "cargo-config", source: ($home | path join ".cargo" "config.toml"), stored: "cargo-config.toml" }
        { name: "julia-startup", source: ($home | path join ".julia" "config" "startup.jl"), stored: "julia-startup.jl" }
        { name: "julia-environments", source: ($home | path join ".julia" "environments"), stored: "julia-environments" }
    ]

    let vscode = (vscode-user-dir)
    if $vscode != null {
        $targets = ($targets | append { name: "vscode-settings", source: ($vscode | path join "settings.json"), stored: "vscode-settings.json" })
        $targets = ($targets | append { name: "vscode-keybindings", source: ($vscode | path join "keybindings.json"), stored: "vscode-keybindings.json" })
        $targets = ($targets | append { name: "vscode-snippets", source: ($vscode | path join "snippets"), stored: "vscode-snippets" })
    }

    $targets
}

def copy-target [source: path destination: path] {
    mkdir ($destination | path dirname)

    if (($source | path type) == "dir") {
        cp -r $source $destination
    } else {
        cp $source $destination
    }
}

def create-backup [label: string quiet: bool] {
    let root = (backup-root)
    mkdir $root

    let timestamp = (date now | format date "%Y%m%d-%H%M%S")
    let safe_label = (sanitize-label $label)
    let backup_dir = ($root | path join ($timestamp + "-" + $safe_label))
    let files_dir = ($backup_dir | path join "files")
    mkdir $files_dir

    mut items = []

    for target in (backup-targets) {
        let source = ($target.source | path expand)

        if not ($source | path exists) {
            continue
        }

        let stored = ($files_dir | path join $target.stored)
        copy-target $source $stored

        $items = ($items | append {
            name: $target.name
            source: ($source | into string)
            stored: ("files/" + $target.stored)
            type: ($source | path type)
        })

        if not $quiet {
            print ("[backup] " + ($source | into string))
        }
    }

    {
        version: 1
        created_at: (date now | format date "%Y-%m-%d %H:%M:%S %z")
        label: $label
        machine: ($env.COMPUTERNAME? | default ($env.HOSTNAME? | default "unknown-machine"))
        items: $items
    }
    | to nuon
    | save ($backup_dir | path join "manifest.nuon")

    prune-backups

    if not $quiet {
        print ""
        print ("[ok] Local configuration backup: " + ($backup_dir | into string))
        print "[info] SSH private keys and dedicated secret files were not included."
        print "[info] rclone.conf is excluded because it commonly contains credentials."
        print "[info] Ordinary config files are copied verbatim; do not embed secrets in them."
    }

    $backup_dir
}

def list-backups [] {
    let root = (backup-root)

    if not ($root | path exists) {
        print "No local configuration backups."
        return
    }

    let backups = (
        ls $root
        | where type == dir
        | sort-by name
        | reverse
    )

    if ($backups | is-empty) {
        print "No local configuration backups."
        return
    }

    print "Local configuration backups"
    print "────────────────────────────────────────────────────────────"

    for item in $backups {
        let manifest = ($item.name | path join "manifest.nuon")
        if ($manifest | path exists) {
            let meta = (open $manifest)
            print (($item.name | path basename) + "  " + ($meta.created_at? | default "") + "  " + ($meta.label? | default ""))
        } else {
            print ($item.name | path basename)
        }
    }
}

def resolve-backup [requested: string] {
    let root = (backup-root)

    if not ($root | path exists) {
        error make { msg: "No local configuration backups exist." }
    }

    if not ($requested | is-empty) {
        let direct = ($requested | path expand)
        if ($direct | path exists) { return $direct }

        let under_root = ($root | path join $requested)
        if ($under_root | path exists) { return $under_root }

        error make { msg: ("Local backup not found: " + $requested) }
    }

    let backups = (
        ls $root
        | where type == dir
        | sort-by name
        | reverse
    )

    if ($backups | is-empty) {
        error make { msg: "No local configuration backups exist." }
    }

    $backups | first | get name
}

def restore-backup [requested: string force: bool] {
    let backup_dir = (resolve-backup $requested)
    let manifest_file = ($backup_dir | path join "manifest.nuon")

    if not ($manifest_file | path exists) {
        error make { msg: ("Backup manifest is missing: " + ($manifest_file | into string)) }
    }

    let manifest = (open $manifest_file)

    print ("Backup : " + ($backup_dir | into string))
    print ("Created: " + ($manifest.created_at? | default "unknown"))
    print ""

    if not $force {
        print "Restore preview:"
        for item in ($manifest.items? | default []) {
            print ("  " + $item.name + " -> " + $item.source)
        }
        print ""
        print "No files were changed. Re-run with --force to restore this backup."
        return
    }

    for item in ($manifest.items? | default []) {
        let stored = ($backup_dir | path join $item.stored)
        let destination = ($item.source | path expand)

        if not ($stored | path exists) {
            print ("[skip] Backup payload missing: " + ($stored | into string))
            continue
        }

        if ($destination | path exists) {
            if (($destination | path type) == "dir") {
                rm -r $destination
            } else {
                rm $destination
            }
        }

        mkdir ($destination | path dirname)
        copy-target $stored $destination
        print ("[restore] " + ($destination | into string))
    }

    print ""
    print "[ok] Local configuration restored."
}

def main [
    --label: string = "pre-apply"
    --quiet
    --list
    --restore: string = ""
    --restore-latest
    --force
] {
    if $list {
        list-backups
        return
    }

    if $restore_latest or not ($restore | is-empty) {
        restore-backup $restore $force
        return
    }

    if $force {
        error make { msg: "--force is only valid with --restore or --restore-latest." }
    }

    create-backup $label $quiet | ignore
}
