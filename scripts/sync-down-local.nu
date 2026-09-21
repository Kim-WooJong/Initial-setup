#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const CONFLICTS_MODULE = path self ./modules/conflicts.nu
use $CONFLICTS_MODULE [protected-conflicts print-protected-conflicts]
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-info print-ok print-warn]

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

def main [--prune --force --allow-protected --source-root: string = ""] {
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

    print "[1/4] Applying private chezmoi source..."

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

    if ($context.features.rclone_config? | default false) {
        run-script $tools_root "restore-rclone-config.nu" "--source-root" ($source_root | into string)
    }

    if $context.features.vscode {
        let configured_prune = ($context.sync.prune_extras? | default false)
        let should_prune = ($prune or $configured_prune)

        print "[2/4] Applying VS Code settings..."

        if $should_prune {
            run-script $tools_root "apply-vscode-config.nu" "--prune" "--source-root" ($source_root | into string)
        } else {
            run-script $tools_root "apply-vscode-config.nu" "--source-root" ($source_root | into string)
        }

        print "[3/4] Reconciling VS Code extensions..."

        if $should_prune {
            run-script $tools_root "install-vscode-extensions.nu" "--prune" "--source-root" ($source_root | into string)
        } else {
            run-script $tools_root "install-vscode-extensions.nu" "--source-root" ($source_root | into string)
        }
    } else {
        print "[2/4] VS Code synchronization disabled"
        print "[3/4] VS Code synchronization disabled"
    }

    print "[4/4] Updating sync baseline..."
    # Sync baseline is committed by sync-transport.nu after remote verification.

    log "INFO" "Private cloud configuration applied locally."
    print-ok "Private cloud configuration is now authoritative."
}
