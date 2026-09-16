#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

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
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    open $file
}

def run-script [
    tools_root: path
    name: string
    ...args: string
] {
    let script = ($tools_root | path join "scripts" $name)

    ^nu $script ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        error make {
            msg: ("Script failed: " + ($script | into string))
        }
    }
}

def log [level: string message: string] {
    let script = ($TOOLS_ROOT | path join "scripts" "log-event.nu")
    let args = [
        $script
        "--level"
        $level
        "--message"
        $message
    ]

    ^nu ...$args | ignore
}

def main [--prune --force] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)

    if not ($data_root | path exists) {
        error make {
            msg: ("Private cloud data unavailable: " + ($data_root | into string))
        }
    }

    print ("Private data: " + ($data_root | into string))
    print "[1/4] Applying private chezmoi source..."

    mut args = [
        "--source"
        ($data_root | into string)
    ]

    if $force {
        $args = ($args | append "--force")
    }

    $args = ($args | append "apply")

    ^chezmoi ...$args

    let apply_exit = ($env.LAST_EXIT_CODE | default 0)

    if $apply_exit != 0 {
        log "ERROR" "chezmoi apply failed."
        error make {
            msg: "chezmoi apply failed"
        }
    }

    if $context.features.rust or $context.features.julia {
        run-script $tools_root "restore-work-environment.nu"
    }

    if ($context.features.rclone_config? | default false) {
        run-script $tools_root "restore-rclone-config.nu"
    }

    if $context.features.vscode {
        let configured_prune = ($context.sync.prune_extras? | default false)
        let should_prune = ($prune or $configured_prune)

        print "[2/4] Applying VS Code settings..."

        if $should_prune {
            run-script $tools_root "apply-vscode-config.nu" "--prune"
        } else {
            run-script $tools_root "apply-vscode-config.nu"
        }

        print "[3/4] Reconciling VS Code extensions..."

        if $should_prune {
            run-script $tools_root "install-vscode-extensions.nu" "--prune"
        } else {
            run-script $tools_root "install-vscode-extensions.nu"
        }
    } else {
        print "[2/4] VS Code synchronization disabled"
        print "[3/4] VS Code synchronization disabled"
    }

    print "[4/4] Updating sync baseline..."
    run-script $tools_root "update-sync-state.nu"

    log "INFO" "Private cloud configuration applied locally."
    print "[ok] Private cloud configuration is now authoritative."
}
