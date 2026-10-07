#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const CONFLICTS_MODULE = path self ./modules/conflicts.nu
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
const CORE = path self ./modules/core.nu
const RCLONE_SECRET = path self ./modules/rclone-secret-sync.nu
const WIREGUARD = path self ./modules/wireguard-sync.nu
const RPOOL = path self ./modules/rpool-sync.nu
const SSH_KEYS = path self ./modules/ssh-key-sync.nu
use $CONFLICTS_MODULE [protected-conflicts print-protected-conflicts]
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-info print-ok print-warn print-status]
use $CORE [error-message nu-home machine-context]
use $RCLONE_SECRET [prepare-rclone-restore commit-prepared-rclone discard-prepared-rclone]
use $WIREGUARD [prepare-wireguard-restore commit-prepared-wireguard discard-prepared-wireguard]
use $RPOOL [rpool-restore-preflight]
use $SSH_KEYS [prepare-ssh-restore commit-prepared-ssh discard-prepared-ssh]

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

def main [--prune --force --allow-protected --discard-local --source-root: string = ""] {
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
    let source_root = if ($source_root | str trim | is-empty) { $data_root } else { $source_root | path expand }
    let tools_root = ($context.tools_root | path expand)

    if not ($source_root | path exists) {
        error make {
            msg: ("Private source unavailable: " + ($source_root | into string))
        }
    }
    let selector = ($source_root | path join ".chezmoiroot")
    if not ($selector | path exists) or (open --raw $selector | str trim) != "home" {
        error make {msg: "Private source is not a valid Initial-setup chezmoi root."}
    }

    print-info ("Private data: " + ($source_root | into string))

    if not $allow_protected {
        let protected = (protected-conflicts $source_root)
        if not ($protected | is-empty) {
            print-protected-conflicts $protected
            error make {
                msg: "Protected configuration differs from the private source. Run `dotresolve` to merge or explicitly apply protected files first."
            }
        }
    }

    # Fail closed before any live change when an incoming rpool artifact carries
    # crypt secrets this machine cannot import (vault/identity/age/rpool 0.7+).
    # The actual import still runs after the rclone commit below.
    rpool-restore-preflight $source_root | ignore

    # Authenticate/decrypt incoming rclone.age before chezmoi or any other live
    # configuration is changed. The restricted plaintext staging is committed
    # later only if the local apply path reaches the rclone restore phase.
    let rclone_plan = if ($context.features.rclone_config? | default false) {
        prepare-rclone-restore $source_root
    } else {
        {status: "disabled"}
    }

    let wireguard_plan = (try {
        prepare-wireguard-restore $source_root --discard-local=$discard_local
    } catch {|err|
        discard-prepared-rclone $rclone_plan
        error make {msg: (error-message $err "WireGuard restore preparation failed.")}
    })

    let ssh_plan = (try {
        prepare-ssh-restore $source_root --discard-local=$discard_local
    } catch {|err|
        discard-prepared-rclone $rclone_plan
        discard-prepared-wireguard $wireguard_plan
        error make {msg: (error-message $err "SSH key restore preparation failed.")}
    })

    let apply_result = (try {
        print-status "info" "1/4" "Applying private chezmoi source..."

        mut args = [
            "--source"
            ($source_root | into string)
        ]

        if $force {
            $args = ($args | append "--force")
        }

        $args = ($args | append "apply")

        let apply = (run-command "chezmoi" $args --live)
        if not $apply.ok {
            log "ERROR" "chezmoi apply failed."
            error make {msg: (command-failure-message "chezmoi apply" $apply)}
        }

        if $context.features.rust or $context.features.julia {
            run-script $tools_root "restore-work-environment.nu" "--source-root" ($source_root | into string)
        }

        if ($context.features.rclone_config? | default false) and (($rclone_plan.status? | default "") == "prepared") {
            commit-prepared-rclone $rclone_plan | ignore
        }

        # Import rpool only after the incoming rclone config is committed so
        # portable remote/default-path references resolve against the new remotes.
        run-script $tools_root "restore-rpool-config.nu" "--source-root" ($source_root | into string)

        # Restores stored profiles only; does not start/restart VPN services.
        commit-prepared-wireguard $wireguard_plan | ignore

        # Restore enrolled SSH private keys (owner-only) after other secrets.
        commit-prepared-ssh $ssh_plan | ignore

        if $context.features.vscode {
            let configured_prune = ($context.sync.prune_extras? | default false)
            let should_prune = ($prune or $configured_prune)

            print-status "info" "2/4" "Applying VS Code settings..."

            if $should_prune {
                run-script $tools_root "apply-vscode-config.nu" "--prune" "--source-root" ($source_root | into string)
            } else {
                run-script $tools_root "apply-vscode-config.nu" "--source-root" ($source_root | into string)
            }

            print-status "info" "3/4" "Reconciling VS Code extensions..."

            if $should_prune {
                run-script $tools_root "install-vscode-extensions.nu" "--prune" "--source-root" ($source_root | into string)
            } else {
                run-script $tools_root "install-vscode-extensions.nu" "--source-root" ($source_root | into string)
            }
        } else {
            print-status "warn" "2/4" "VS Code synchronization disabled"
            print-status "warn" "3/4" "VS Code synchronization disabled"
        }

        print-status "info" "4/4" "Updating sync baseline..."
        # Sync baseline is committed by sync-transport.nu after remote verification.

        log "INFO" "Private cloud configuration applied locally."
        print-ok "Private cloud configuration is now authoritative."
        null
    } catch {|err| $err })

    if $apply_result != null {
        discard-prepared-rclone $rclone_plan
        discard-prepared-wireguard $wireguard_plan
        discard-prepared-ssh $ssh_plan
        error make {msg: (error-message $apply_result "Private pull application failed.")}
    }
    discard-prepared-wireguard $wireguard_plan
    discard-prepared-ssh $ssh_plan
}
