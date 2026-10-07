#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
const WIREGUARD = path self ./modules/wireguard-sync.nu
use $WIREGUARD [capture-wireguard]
const SSH_KEYS = path self ./modules/ssh-key-sync.nu
use $SSH_KEYS [capture-ssh-keys]
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-info print-ok print-warn print-status]

def run-script [
    tools_root: path
    name: string
    ...args: string
] {
    let script = ($tools_root | path join "scripts" $name)
    let result = (run-command $nu.current-exe (["--no-config-file" $script] | append $args) --live)
    if not $result.ok {
        error make {msg: (command-failure-message ("Script " + $name) $result)}
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

    let result = (run-command $nu.current-exe (["--no-config-file"] | append $args))
    if not $result.ok {
        print-warn ("Event logging failed: " + (command-failure-message "log-event" $result))
    }
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

    # rpool owns its portable schema. Capture only when the CLI is available;
    # machines without rpool keep the existing synchronized bundle untouched.
    run-script $tools_root "capture-rpool-config.nu"

    # Explicitly enrolled devices only; protected native settings never enter
    # the ordinary chezmoi tree. Only the age-encrypted bundle is published.
    capture-wireguard $data_root | ignore

    # Explicitly enrolled SSH private keys, encrypted to the vault recipients.
    capture-ssh-keys $data_root

    print-info ("Private data: " + ($data_root | into string))
    print-status "info" "1/4" "Updating managed chezmoi files..."

    let args = [
        "--source"
        ($data_root | into string)
        "re-add"
    ]

    let readd = (run-command "chezmoi" $args --live)
    if not $readd.ok {
        log "ERROR" "chezmoi re-add failed."
        error make {msg: (command-failure-message "chezmoi re-add" $readd)}
    }

    if $context.features.vscode {
        print-status "info" "2/4" "Updating VS Code extension list..."
        run-script $tools_root "capture-vscode-extensions.nu"

        print-status "info" "3/4" "Updating VS Code settings..."
        run-script $tools_root "capture-vscode-config.nu"
    } else {
        print-status "warn" "2/4" "VS Code synchronization disabled"
        print-status "warn" "3/4" "VS Code synchronization disabled"
    }

    print-status "info" "4/4" "Updating synchronization metadata..."
    run-script $tools_root "write-sync-meta.nu" "--action" "push"
    # Sync baseline is committed by sync-transport.nu after remote verification.

    log "INFO" "Local configuration published to private cloud source."
    print-ok "Local configuration is now authoritative."
}
