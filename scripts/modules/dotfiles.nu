# ============================================================
# Initial-setup Nushell convenience commands.
# ============================================================

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
    let config_file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    if not ($config_file | path exists) {
        error make {
            msg: ("Dotfiles machine config not found: " + ($config_file | into string))
        }
    }

    open $config_file
}

def data-root [] {
    let config = (machine-context)
    $config.data_root | path expand
}

def tools-root [] {
    let config = (machine-context)
    $config.tools_root | path expand
}

def tool-script [name: string] {
    tools-root | path join "scripts" $name
}

def fingerprint [kind: string] {
    let script = (tool-script "sync-fingerprint.nu")
    let args = [
        $script
        "--kind"
        $kind
    ]

    ^nu ...$args | str trim
}

def edit-file [target: path] {
    mkdir ($target | path dirname)

    if not ($target | path exists) {
        "" | save $target
    }

    ^nvim $target
}

def edit-managed-target [target: path] {
    let root = (data-root)

    let source_args = [
        "--source"
        ($root | into string)
        "source-path"
        ($target | into string)
    ]

    let source = (^chezmoi ...$source_args | str trim | path expand)

    if not ($source | path exists) {
        error make {
            msg: ("Managed source does not exist: " + ($source | into string))
        }
    }

    ^nvim $source

    let editor_exit = ($env.LAST_EXIT_CODE | default 0)

    if $editor_exit != 0 {
        error make {
            msg: "Neovim exited with an error."
        }
    }

    let apply_args = [
        "--source"
        ($root | into string)
        "apply"
        ($target | into string)
    ]

    ^chezmoi ...$apply_args

    let apply_exit = ($env.LAST_EXIT_CODE | default 0)

    if $apply_exit != 0 {
        error make {
            msg: ("chezmoi apply failed: " + ($target | into string))
        }
    }

    ^nu (tool-script "sync-up.nu")
}

export def dotstatus [] {
    let context = (machine-context)
    let state_file = ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict_file = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")

    print "Automatic Sync"
    print "────────────────────────────────"
    print ("Machine       : " + $context.machine.name)
    print ("Profile       : " + $context.machine.profile)
    print ("Enabled       : " + ($context.sync.enabled | into string))
    print ("Interval      : " + ($context.sync.interval_minutes | into string) + " minute(s)")
    print ("Auto push     : " + ($context.sync.auto_push | into string))
    print ("Auto pull     : " + ($context.sync.auto_pull | into string))
    print ("Conflict mode : " + $context.sync.conflict_policy)

    if ($state_file | path exists) {
        let state = (open $state_file)
        let local_now = (fingerprint "local")
        let cloud_now = (fingerprint "cloud")
        let local_status = (if $local_now == $state.local_hash { "clean" } else { "changed" })
        let cloud_status = (if $cloud_now == $state.cloud_hash { "clean" } else { "changed" })

        print ("Last sync     : " + ($state.last_sync? | default "unknown"))
        print ("Last writer   : " + ($state.last_writer? | default "unknown"))
        print ("Writer time   : " + ($state.last_write_time? | default "unknown"))
        print ("Last action   : " + ($state.last_action? | default "unknown"))
        print ("Local         : " + $local_status)
        print ("Cloud         : " + $cloud_status)
    } else {
        print "Last sync     : not initialized"
        print "Last writer   : unknown"
        print "Local         : unknown"
        print "Cloud         : unknown"
    }

    if ($conflict_file | path exists) {
        print "Conflict      : YES"
        print ("Details       : " + ($conflict_file | into string))
    } else {
        print "Conflict      : none"
    }

    print ""
    print ("Private data  : " + (data-root | into string))
    print ""
    print "chezmoi status:"

    let args = [
        "--source"
        (data-root | into string)
        "status"
    ]

    ^chezmoi ...$args
}

export def dotdiff [] {
    let root = (data-root)

    let args = [
        "--source"
        ($root | into string)
        "diff"
    ]

    ^chezmoi ...$args
}

export def dotpush [] {
    ^nu (tool-script "sync-up.nu")
}

export def dotpull [] {
    ^nu (tool-script "sync-down.nu")
}

export def dotsync [] {
    ^nu (tool-script "auto-sync.nu")
}

export def dotsnapshot [
    --label: string = "manual"
] {
    let args = [
        (tool-script "create-snapshot.nu")
        "--label"
        $label
    ]

    ^nu ...$args
}

export def dotrollback [
    --list
    --snapshot: string = ""
] {
    let script = (tool-script "rollback.nu")

    if $list {
        ^nu $script --list
        return
    }

    if ($snapshot | is-empty) {
        ^nu $script
    } else {
        ^nu $script --snapshot $snapshot
    }
}

export def dotdoctor [
    --fix
] {
    let script = (tool-script "doctor.nu")

    if $fix {
        ^nu $script --fix
    } else {
        ^nu $script
    }
}

export def dotupdate [
    --repo
    --tools
    --config
    --all
] {
    let script = (tool-script "update.nu")
    mut args = [$script]

    if $repo {
        $args = ($args | append "--repo")
    }

    if $tools {
        $args = ($args | append "--tools")
    }

    if $config {
        $args = ($args | append "--config")
    }

    if $all {
        $args = ($args | append "--all")
    }

    ^nu ...$args
}

export def dotreport [
    --save
] {
    let script = (tool-script "report.nu")

    if $save {
        ^nu $script --save
    } else {
        ^nu $script
    }
}

export def dotlog [
    --lines: int = 50
    --clear
] {
    let file = ((nu-home) | path join ".config" "dotfiles" "logs" "sync.log")

    if $clear {
        if ($file | path exists) {
            "" | save --force $file
        }

        print "[ok] Sync log cleared"
        return
    }

    if not ($file | path exists) {
        print "No sync log."
        return
    }

    let content = (open --raw $file | lines)
    let count = ($content | length)
    let start = (if $count > $lines { $count - $lines } else { 0 })

    $content
    | skip $start
    | str join (char nl)
    | print
}

export def dotconfig [] {
    edit-file ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    print ""
    print "[info] Run `nu setup.nu` after changing profile, scheduler interval, or feature switches."
}

export def dotsecrets [] {
    edit-file ($nu.data-dir | path join "vendor" "autoload" "dotfiles-secrets.nu")
}

export def dotgitlocal [] {
    edit-file ((nu-home) | path join ".gitconfig.local")
}

export def dotsshlocal [] {
    edit-file ((nu-home) | path join ".ssh" "config.local")
}

export def dotnvim [] {
    edit-managed-target ((nu-home) | path join ".config" "nvim")
}

export def dotnu [] {
    edit-managed-target ((nu-home) | path join ".config" "nushell" "config.nu")
}

export def dotenv [] {
    edit-managed-target ((nu-home) | path join ".config" "nushell" "env.nu")
}

export def dotwezterm [] {
    edit-managed-target ((nu-home) | path join ".config" "wezterm" "wezterm.lua")
}

export def dotstarship [] {
    edit-managed-target ((nu-home) | path join ".config" "starship.toml")
}

export def newproj [
    kind: string
    name: string
    --path: string = ""
] {
    let args = [
        (tool-script "new-project.nu")
        $kind
        $name
        "--path"
        $path
    ]

    ^nu ...$args
}

export def dotdata [] {
    ^nvim (data-root)
}

export def dottools [] {
    ^nvim (tools-root)
}
