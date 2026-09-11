# ============================================================
# Dotfiles management commands installed into Nushell.
# ============================================================

def machine-context [] {
    let config_file = (
        $nu.home-path
        | path join ".config" "dotfiles" "config.nuon"
    )

    if not ($config_file | path exists) {
        error make {
            msg: $"Dotfiles machine config not found: ($config_file)"
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
    tools-root
    | path join "scripts" $name
}

def edit-managed-target [target: path] {
    let root = (data-root)

    let args = [
        "--source"
        ($root | into string)
        "source-path"
        ($target | into string)
    ]

    let source = (
        ^chezmoi ...$args
        | str trim
        | path expand
    )

    if not ($source | path exists) {
        error make {
            msg: $"Managed source does not exist: ($source)"
        }
    }

    ^nvim $source

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: "Neovim exited with an error; configuration was not applied."
        }
    }

    let apply_args = [
        "--source"
        ($root | into string)
        "apply"
        ($target | into string)
    ]

    ^chezmoi ...$apply_args

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: $"chezmoi apply failed: ($target)"
        }
    }

    ^nu (tool-script "sync-up.nu")
}

export def dotstatus [] {
    let root = (
        data-root
    )

    print (
        "Private data: "
        + ($root | into string)
    )

    print ""

    let args = [
        "--source"
        ($root | into string)
        "status"
    ]

    ^chezmoi ...$args

    let state_file = (
        $nu.home-path
        | path join ".config" "dotfiles" "sync-state.nuon"
    )

    let conflict_file = (
        $nu.home-path
        | path join ".config" "dotfiles" "SYNC-CONFLICT.txt"
    )

    print ""
    print "Automatic synchronization:"

    if ($state_file | path exists) {
        open $state_file
    } else {
        print "[--] Sync state has not been initialized."
    }

    if ($conflict_file | path exists) {
        print ""
        print "[CONFLICT] Automatic synchronization requires attention."
        print (
            "Details: "
            + ($conflict_file | into string)
        )
    }
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

export def dotnvim [] {
    edit-managed-target (
        $nu.home-path
        | path join ".config" "nvim"
    )
}

export def dotnu [] {
    edit-managed-target (
        $nu.home-path
        | path join ".config" "nushell" "config.nu"
    )
}

export def dotenv [] {
    edit-managed-target (
        $nu.home-path
        | path join ".config" "nushell" "env.nu"
    )
}

export def dotwezterm [] {
    edit-managed-target (
        $nu.home-path
        | path join ".config" "wezterm" "wezterm.lua"
    )
}

export def dotstarship [] {
    edit-managed-target (
        $nu.home-path
        | path join ".config" "starship.toml"
    )
}

export def dotdata [] {
    ^nvim (data-root)
}

export def dottools [] {
    ^nvim (tools-root)
}
