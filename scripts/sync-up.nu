#!/usr/bin/env nu

# ============================================================
# sync-up.nu
#
# Force local configuration to become authoritative.
#
# local -> chezmoi re-add -> private cloud source
#
# This command also clears a previous conflict by writing a new
# synchronization baseline after a successful update.
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

def run-script [
    tools_root: path
    name: string
] {
    let script = (
        $tools_root
        | path join "scripts" $name
    )

    ^nu $script

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: (
                "Script failed: "
                + ($script | into string)
            )
        }
    }
}

def main [] {
    let context = (
        machine-context
    )

    let data_root = (
        $context.data_root
        | path expand
    )

    let tools_root = (
        $context.tools_root
        | path expand
    )

    if not ($data_root | path exists) {
        error make {
            msg: (
                "Private data root unavailable: "
                + ($data_root | into string)
            )
        }
    }

    print (
        "Private data: "
        + ($data_root | into string)
    )

    print "[1/4] Updating private chezmoi source..."

    let args = [
        "--source"
        ($data_root | into string)
        "re-add"
    ]

    ^chezmoi ...$args

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: "chezmoi re-add failed"
        }
    }

    print "[2/4] Updating VS Code extension list..."

    run-script
        $tools_root
        "capture-vscode-extensions.nu"

    print "[3/4] Updating VS Code settings..."

    run-script
        $tools_root
        "capture-vscode-config.nu"

    print "[4/4] Updating sync baseline..."

    run-script
        $tools_root
        "update-sync-state.nu"

    print ""
    print "[ok] Local configuration is now authoritative."
    print "[info] Network synchronization is handled by your cloud client."
}
