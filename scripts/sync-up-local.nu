#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

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

def main [] {
    let lock_file = ((nu-home) | path join ".config" "dotfiles" "locks" "operation.lock")
    let token = ($env.INITIAL_SETUP_OPERATION_TOKEN? | default "")
    if ($token | is-empty) or not ($lock_file | path exists) {
        error make { msg: "Internal callback: use dotpush/dotpull instead." }
    }
    if (open --raw $lock_file | str trim) != $token {
        error make { msg: "Operation lock ownership mismatch." }
    }

    let context = (machine-context)
    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)

    if not ($data_root | path exists) {
        error make {
            msg: ("Private data root unavailable: " + ($data_root | into string))
        }
    }

    if $context.maintenance.snapshots_enabled {
        run-script $tools_root "create-snapshot.nu" "--label" "pre-push" "--quiet"
    }

    if $context.features.rust or $context.features.julia {
        run-script $tools_root "capture-work-environment.nu"
    }

    if ($context.features.rclone_config? | default false) {
        run-script $tools_root "capture-rclone-config.nu"
    }

    print ("Private data: " + ($data_root | into string))
    print "[1/4] Updating managed chezmoi files..."

    let args = [
        "--source"
        ($data_root | into string)
        "re-add"
    ]

    ^chezmoi ...$args

    let readd_exit = ($env.LAST_EXIT_CODE | default 0)

    if $readd_exit != 0 {
        log "ERROR" "chezmoi re-add failed."
        error make {
            msg: "chezmoi re-add failed"
        }
    }

    if $context.features.vscode {
        print "[2/4] Updating VS Code extension list..."
        run-script $tools_root "capture-vscode-extensions.nu"

        print "[3/4] Updating VS Code settings..."
        run-script $tools_root "capture-vscode-config.nu"
    } else {
        print "[2/4] VS Code synchronization disabled"
        print "[3/4] VS Code synchronization disabled"
    }

    print "[4/4] Updating synchronization metadata..."
    run-script $tools_root "write-sync-meta.nu" "--action" "push"
    # Sync baseline is committed by sync-transport.nu after remote verification.

    log "INFO" "Local configuration published to private cloud source."
    print "[ok] Local configuration is now authoritative."
}
