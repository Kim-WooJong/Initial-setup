#!/usr/bin/env nu

# ============================================================
# Create machine-local Git and SSH override files.
#
# Shared:
#   ~/.gitconfig
#   ~/.ssh/config
#
# Machine-local and intentionally NOT managed by chezmoi:
#   ~/.gitconfig.local
#   ~/.ssh/config.local
# ============================================================

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

def machine-context [] {
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

    open $file
}

def update-managed-file [
    data_root: path
    file: path
] {
    if not ($file | path exists) {
        return
    }

    let args = [
        "--source"
        ($data_root | into string)
        "add"
        "--secrets"
        "error"
        ($file | into string)
    ]

    ^chezmoi ...$args

    let exit_code = (
        $env.LAST_EXIT_CODE
        | default 0
    )

    if $exit_code != 0 {
        error make {
            msg: (
                "Failed to update managed file: " + ($file | into string)
            )
        }
    }
}

def ensure-git [
    context: record
] {
    if not $context.features.git_config {
        print "[skip] Git config synchronization disabled"
        return
    }

    let common = (
        (nu-home)
        | path join ".gitconfig"
    )

    let local = (
        (nu-home)
        | path join ".gitconfig.local"
    )

    if not ($local | path exists) {
        [
            "# Machine-local Git overrides."
            "# This file is intentionally not synchronized."
            "#"
            "# Example:"
            "# [user]"
            "#     name = Your Name"
            "#     email = you@example.com"
            ""
        ]
        | str join (char nl)
        | save $local

        print (
            "[create] " + ($local | into string)
        )
    }

    if not ($common | path exists) {
        [
            "# Shared Git configuration managed by Initial-setup."
            ""
            "[include]"
            "    path = ~/.gitconfig.local"
            ""
        ]
        | str join (char nl)
        | save $common
    } else {
        let content = (
            open --raw $common
        )

        if not ($content | str contains ".gitconfig.local") {
            (
                $content + (char nl) + "# Initial-setup machine-local overrides" + (char nl) + "[include]" + (char nl) + "    path = ~/.gitconfig.local" + (char nl)
            )
            | save --force $common

            print "[update] Git local include enabled"
        }
    }

    if not (which delta | is-empty) {
        let local_content = (
            open --raw $local
        )

        if not ($local_content | str contains "pager = delta") {
            (
                $local_content + (char nl) + "# Initial-setup: delta is available on this machine" + (char nl) + "[core]" + (char nl) + "    pager = delta" + (char nl) + "[interactive]" + (char nl) + "    diffFilter = delta --color-only" + (char nl) + "[delta]" + (char nl) + "    navigate = true" + (char nl) + "    line-numbers = true" + (char nl) + "[merge]" + (char nl) + "    conflictStyle = zdiff3" + (char nl) + "[diff]" + (char nl) + "    colorMoved = default" + (char nl)
            )
            | save --force $local

            print "[update] Machine-local git-delta configuration enabled"
        }
    }

    update-managed-file ($context.data_root | path expand) $common
}

def ensure-ssh [
    context: record
] {
    if not $context.features.ssh_config {
        print "[skip] SSH config synchronization disabled"
        return
    }

    let ssh_dir = (
        (nu-home)
        | path join ".ssh"
    )

    let common = (
        $ssh_dir
        | path join "config"
    )

    let local = (
        $ssh_dir
        | path join "config.local"
    )

    mkdir $ssh_dir

    if not ($local | path exists) {
        [
            "# Machine-local SSH configuration."
            "# This file is intentionally not synchronized."
            ""
        ]
        | str join (char nl)
        | save $local

        print (
            "[create] " + ($local | into string)
        )
    }

    if not ($common | path exists) {
        [
            "# Shared SSH configuration managed by Initial-setup."
            "Include ~/.ssh/config.local"
            ""
        ]
        | str join (char nl)
        | save $common
    } else {
        let content = (
            open --raw $common
        )

        if not ($content | str contains "config.local") {
            (
                "Include ~/.ssh/config.local" + (char nl) + (char nl) + $content
            )
            | save --force $common

            print "[update] SSH local include enabled"
        }
    }

    update-managed-file ($context.data_root | path expand) $common
}

def main [] {
    let context = (
        machine-context
    )

    ensure-git $context
    print ""
    ensure-ssh $context
}
