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

const SAFETY = path self ./modules/safety.nu
const CORE = path self ./modules/core.nu
use $SAFETY [operation-lease release-lease private-directory atomic-record tree-manifest manifest-hash verify-tree]
use $CORE [error-message failure-envelope captured-failure]

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

def backup-directories [] {
    let root = (backup-root)
    if not ($root | path exists) { return [] }
    ls $root
    | where type == dir
    | where {|row|
        let name = ($row.name | path basename)
        let is_recovery = ($name | str starts-with ".restore-recovery-")
        let is_partial = ($name | str starts-with ".partial-")
        let complete = (($row.name | path join "manifest.nuon") | path exists)
        (not $is_recovery) and (not $is_partial) and $complete
    }
    | sort-by name
    | reverse
}

def remove-path [target: path] {
    if not ($target | path exists) { return }
    if ($target | path type) == "dir" { rm --recursive --force $target } else { rm --force $target }
}

def prune-backups [] {
    let root = (backup-root)
    let keep = (backup-keep)

    if $keep <= 0 or not ($root | path exists) {
        return
    }

    let backups = (backup-directories)

    if ($backups | length) <= $keep {
        return
    }

    for item in ($backups | skip $keep) {
        rm -r $item.name
    }
}

def sanitize-label [label: string] {
    let safe = ($label | str replace --all --regex '[^A-Za-z0-9._-]' '-')
    if ($safe | is-empty) { "backup" } else { $safe | str substring 0..63 }
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
        { name: "machine-config", source: ($home | path join ".config" "dotfiles" "config.nuon"), stored: "machine-config.nuon" }
        { name: "machine-local", source: ($home | path join ".config" "dotfiles" "local.nu"), stored: "machine-local.nu" }
        { name: "sync-state", source: ($home | path join ".config" "dotfiles" "sync-state.nuon"), stored: "sync-state.nuon" }
        { name: "sync-conflict", source: ($home | path join ".config" "dotfiles" "SYNC-CONFLICT.txt"), stored: "SYNC-CONFLICT.txt" }
        { name: "git-identities", source: ($home | path join ".config" "dotfiles" "git-identities.nuon"), stored: "git-identities.nuon" }
        { name: "conflict-policy", source: ($home | path join ".config" "dotfiles" "conflict-policy.nuon"), stored: "conflict-policy.nuon" }
        { name: "provider-config", source: ($home | path join ".config" "dotfiles" "sync-provider.nuon"), stored: "sync-provider.nuon" }
        { name: "provider-state", source: ($home | path join ".config" "dotfiles" "provider-state.nuon"), stored: "provider-state.nuon" }
        { name: "rclone-sync-config", source: ($home | path join ".config" "dotfiles" "rclone-sync.nuon"), stored: "rclone-sync.nuon" }
        { name: "scoped-provider-states", source: ($home | path join ".config" "dotfiles" "provider-states"), stored: "provider-states" }
        { name: "machine-overlay", source: ($home | path join ".config" "dotfiles" "machine-overlay.nuon"), stored: "machine-overlay.nuon" }
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

def backup-integrity [stored: path] {
    if ($stored | path type) == "dir" {
        let files = (tree-manifest $stored)
        return {files: $files tree_hash: (manifest-hash $files)}
    }
    {sha256: (open --raw $stored | hash sha256)}
}

def create-backup [label: string quiet: bool] {
    let root = (backup-root)
    private-directory $root

    let timestamp = (date now | format date "%Y%m%d-%H%M%S-%f")
    let safe_label = (sanitize-label $label)
    let suffix = (random uuid | str substring 0..7)
    let name = ($timestamp + "-" + $safe_label + "-" + $suffix)
    let backup_dir = ($root | path join $name)
    let staging = ($root | path join (".partial-" + (random uuid)))
    let files_dir = ($staging | path join "files")
    private-directory $staging
    mkdir $files_dir

    let outcome = (try {
        mut items = []

        for target in (backup-targets) {
            let source = ($target.source | path expand)

            if not ($source | path exists) {
                $items = ($items | append {
                    name: $target.name
                    source: ($source | into string)
                    stored: ("files/" + $target.stored)
                    type: "missing"
                    present: false
                })
                continue
            }

            let stored = ($files_dir | path join $target.stored)
            copy-target $source $stored

            let item = {
                name: $target.name
                source: ($source | into string)
                stored: ("files/" + $target.stored)
                type: ($source | path type)
                present: true
            }
            $items = ($items | append ($item | merge (backup-integrity $stored)))

            if not $quiet {
                print ("[backup] " + ($source | into string))
            }
        }

        atomic-record ($staging | path join "manifest.nuon") {
            version: 3
            created_at: (date now | format date "%Y-%m-%d %H:%M:%S %z")
            label: $label
            machine: ($env.COMPUTERNAME? | default ($env.HOSTNAME? | default "unknown-machine"))
            items: $items
        }

        if ($backup_dir | path exists) {
            error make {msg: "Local backup destination unexpectedly already exists."}
        }
        mv $staging $backup_dir
        null
    } catch {|err| failure-envelope $err })

    let failure = (captured-failure $outcome)
    if $failure != null {
        try { if ($staging | path exists) { rm --recursive --force $staging } } catch {
            print --stderr ("[warn] Incomplete local-backup staging remains at: " + ($staging | into string))
        }
        error make {msg: (error-message $failure "Local backup creation failed.")}
    }

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

    let backups = (backup-directories)

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

    let backups = (backup-directories)

    if not ($requested | is-empty) {
        if ($requested | path basename) != $requested or $requested in ["." ".."] {
            error make {msg: "Backup must be selected by its backup name, not by an arbitrary path."}
        }
        let matches = ($backups | where {|row| ($row.name | path basename) == $requested })
        if ($matches | length) == 1 { return ($matches | first | get name) }
        error make { msg: ("Completed local backup not found: " + $requested) }
    }

    if ($backups | is-empty) {
        error make { msg: "No local configuration backups exist." }
    }

    $backups | first | get name
}

def capture-restore-recovery [manifest: record] {
    let root = (backup-root)
    let dir = ($root | path join (".restore-recovery-" + (random uuid)))
    let files = ($dir | path join "files")
    private-directory $dir
    mkdir $files
    mut items = []
    for row in ($manifest.items? | default []) {
        let destination = ($row.source | path expand)
        let present = ($destination | path exists)
        let stored = ("files/" + (($items | length) | into string) + ".payload")
        if $present { copy-target $destination ($dir | path join $stored) }
        $items = ($items | append {source: ($destination | into string) present: $present stored: $stored})
    }
    atomic-record ($dir | path join "recovery.nuon") {
        version: 1
        created_at: (date now | format date "%+")
        items: $items
    }
    {dir: $dir items: $items}
}

def restore-from-recovery [recovery: record] {
    for row in $recovery.items {
        let destination = ($row.source | path expand)
        remove-path $destination
        if $row.present {
            let stored = ($recovery.dir | path join $row.stored)
            if not ($stored | path exists) {
                error make {msg: ("Recovery payload missing: " + ($stored | into string))}
            }
            mkdir ($destination | path dirname)
            copy-target $stored $destination
        }
    }
}

def restore-backup [requested: string force: bool] {
    let backup_dir = (resolve-backup $requested)
    let manifest_file = ($backup_dir | path join "manifest.nuon")

    if not ($manifest_file | path exists) {
        error make { msg: ("Backup manifest is missing: " + ($manifest_file | into string)) }
    }

    let manifest = (open $manifest_file)

    # Inspect the complete payload before deleting/replacing any live file.
    # A partial backup must fail closed, not print a successful partial restore.
    let manifest_version = ($manifest.version? | default 1 | into int)
    if not ($manifest_version in [1 2 3]) {
        error make {msg: "Unsupported local-backup manifest version."}
    }
    let allowed = (backup-targets)
    mut seen_names = []
    for item in ($manifest.items? | default []) {
        if $item.name in $seen_names { error make {msg: "Duplicate item in local-backup manifest."} }
        $seen_names = ($seen_names | append $item.name)
        let matches = ($allowed | where name == $item.name)
        if ($matches | length) != 1 { error make {msg: ("Unknown local-backup target: " + ($item.name | into string))} }
        let expected = ($matches | first)
        if ($item.source | path expand) != ($expected.source | path expand) or ($item.stored | into string) != ("files/" + $expected.stored) {
            error make {msg: ("Local-backup manifest target was modified: " + ($item.name | into string))}
        }
        let relative = ($item.stored | into string)
        let segments = ($relative | split row "/")
        if not ($relative | str starts-with "files/") or ($relative | str contains '\') or ($segments | any {|segment| $segment in ["" "." ".."] }) {
            error make {msg: "Invalid relative payload path in local-backup manifest."}
        }
        let stored = ($backup_dir | path join $relative)
        if ($item.present? | default true) and not ($stored | path exists) {
            error make {msg: ("Backup payload missing; no live files were changed: " + ($stored | into string))}
        }
        if $manifest_version == 3 and ($item.present? | default true) {
            if $item.type == "dir" {
                let expected_files = ($item.files? | default [])
                if ($expected_files | describe) !~ '^(list|table)' {
                    error make {msg: ("Backup directory manifest is invalid: " + ($item.name | into string))}
                }
                verify-tree $stored $expected_files | ignore
                if (manifest-hash $expected_files) != ($item.tree_hash? | default "") {
                    error make {msg: ("Backup directory tree hash is invalid: " + ($item.name | into string))}
                }
            } else {
                let expected_hash = ($item.sha256? | default "")
                if not ($expected_hash =~ '^[a-f0-9]{64}$') or (open --raw $stored | hash sha256) != $expected_hash {
                    error make {msg: ("Backup file checksum mismatch: " + ($item.name | into string))}
                }
            }
        }
    }

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

    let recovery = (capture-restore-recovery $manifest)
    print ("[recovery] Pre-restore state: " + ($recovery.dir | into string))
    let apply_result = (try {
        for item in ($manifest.items? | default []) {
            let stored = ($backup_dir | path join $item.stored)
            let destination = ($item.source | path expand)
            let was_present = ($item.present? | default true)

            if not $was_present {
                if ($destination | path exists) {
                    remove-path $destination
                    print ("[remove] " + ($destination | into string) + " (absent before transaction)")
                }
                continue
            }

            if not ($stored | path exists) {
                error make {msg: ("Backup payload disappeared during restore: " + ($stored | into string))}
            }

            remove-path $destination
            mkdir ($destination | path dirname)
            copy-target $stored $destination
            print ("[restore] " + ($destination | into string))
        }
        null
    } catch {|err| failure-envelope $err })
    let apply_failure = (captured-failure $apply_result)
    if $apply_failure != null {
        let rollback_result = (try { restore-from-recovery $recovery; null } catch {|err| failure-envelope $err })
        let rollback_failure = (captured-failure $rollback_result)
        mut message = (error-message $apply_failure "Local restore failed.")
        if $rollback_failure == null {
            try { rm --recursive --force $recovery.dir } catch {}
            $message = ($message + (char nl) + "All touched local configuration paths were restored to their pre-restore state.")
        } else {
            $message = ($message + (char nl) + "Automatic rollback also failed: " + (error-message $rollback_failure) + (char nl) + "Recovery data retained at: " + ($recovery.dir | into string))
        }
        error make {msg: $message}
    }
    try { rm --recursive --force $recovery.dir } catch {
        print --stderr ("[warn] Restore succeeded, but recovery staging remains at: " + ($recovery.dir | into string))
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

    let lease = (operation-lease)
    let outcome = (try {
        if $restore_latest or not ($restore | is-empty) {
            restore-backup $restore $force
        } else {
            if $force { error make { msg: "--force is only valid with --restore or --restore-latest." } }
            create-backup $label $quiet | ignore
        }
        null
    } catch {|err| failure-envelope $err })
    let failure = (captured-failure $outcome)
    let cleanup = (try { release-lease $lease; null } catch {|err| failure-envelope $err })
    let cleanup_failure = (captured-failure $cleanup)
    if $failure != null {
        mut message = (error-message $failure "Local backup/restore failed.")
        if $cleanup_failure != null { $message = ($message + (char nl) + "Operation-lock cleanup also failed: " + (error-message $cleanup_failure)) }
        error make {msg: $message}
    }
    if $cleanup_failure != null { error make {msg: ("Operation-lock cleanup failed: " + (error-message $cleanup_failure))} }
}
