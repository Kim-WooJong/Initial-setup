#!/usr/bin/env nu

# ============================================================
# sync-down.nu
#
# Force private cloud configuration to become authoritative.
#
# private cloud source -> chezmoi apply -> local
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
                "Private cloud data unavailable: "
                + ($data_root | into string)
            )
        }
    }

    let chezmoi_root = (
        $data_root
        | path join ".chezmoiroot"
    )

    if not ($chezmoi_root | path exists) {
        error make {
            msg: (
                "Invalid private dotfiles source: "
                + ($data_root | into string)
            )
        }
    }

    print (
        "Private data: "
        + ($data_root | into string)
    )

    print "[1/4] Applying private chezmoi source..."

    let args = [
        "--source"
        ($data_root | into string)
        "apply"
    ]

    ^chezmoi ...$args

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: "chezmoi apply failed"
        }
    }

    print "[2/4] Applying VS Code settings..."

    run-script
        $tools_root
        "apply-vscode-config.nu"

    print "[3/4] Reconciling VS Code extensions..."

    run-script
        $tools_root
        "install-vscode-extensions.nu"

    print "[4/4] Updating sync baseline..."

    run-script
        $tools_root
        "update-sync-state.nu"

    print ""
    print "[ok] Private cloud configuration is now authoritative."
}
