#!/usr/bin/env nu

# ============================================================
# Initial-setup 0.5.0
#
# Default private source:
#   parent directory of this repository
#
# First machine:
#   nu setup.nu --mode initial
#
# Additional machine:
#   nu setup.nu --mode existing
#
# Override private source:
#   nu setup.nu --data-dir 'D:\Private\dotfiles'
# ============================================================

const TOOLS_ROOT = path self .
const DEFAULT_DATA_ROOT = path self ..

def section [title: string] {
    print ""
    print "============================================================"
    print $" ($title)"
    print "============================================================"
    print ""
}

def require [name: string] {
    if (which $name | is-empty) {
        error make {
            msg: $"Required command not found: ($name)"
        }
    }
}

def machine-config-path [] {
    $nu.home-path
    | path join ".config" "dotfiles" "config.nuon"
}

def save-machine-config [data_root: path] {
    let config_file = (machine-config-path)

    mkdir ($config_file | path dirname)

    {
        version: "0.5.0"
        data_root: ($data_root | path expand | into string)
        tools_root: ($TOOLS_ROOT | path expand | into string)
    }
    | to nuon
    | save --force $config_file

    print $"[save] Machine config -> ($config_file)"
}

def load-saved-data-root [] {
    let config_file = (machine-config-path)

    if not ($config_file | path exists) {
        return null
    }

    let config = (open $config_file)
    let data_root = ($config.data_root? | default "")

    if ($data_root | is-empty) {
        return null
    }

    $data_root | path expand
}

def resolve-data-root [requested: string] {
    if not ($requested | is-empty) {
        return ($requested | path expand)
    }

    let saved = (load-saved-data-root)

    if $saved != null {
        return $saved
    }

    $DEFAULT_DATA_ROOT | path expand
}

def private-source-has-user-config [data_root: path] {
    let markers = [
        ($data_root | path join "home" "dot_config" "nvim" "init.lua")
        ($data_root | path join "home" "dot_config" "nushell" "config.nu")
        ($data_root | path join "home" "dot_config" "nushell" "env.nu")
        ($data_root | path join "home" "dot_gitconfig")
        ($data_root | path join "home" "private_dot_ssh" "config")
    ]

    $markers
    | any { |item| $item | path exists }
}

def resolve-mode [requested: string data_root: path] {
    match $requested {
        "initial" => {
            "initial"
        }

        "existing" => {
            "existing"
        }

        "auto" => {
            if (private-source-has-user-config $data_root) {
                "existing"
            } else {
                "initial"
            }
        }

        _ => {
            error make {
                msg: $"Unknown mode '($requested)'. Use auto, initial, or existing."
            }
        }
    }
}

def run-script [title: string file: path ...args: string] {
    section $title

    let script = ($file | path expand)

    if not ($script | path exists) {
        error make {
            msg: $"Required script not found: ($script)"
        }
    }

    print $"[run] ($script)"

    ^nu $script ...$args

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: $"Script failed: ($script)"
        }
    }
}

def apply-private-source [data_root: path] {
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
}

def main [
    --mode: string = "auto"
    --data-dir: string = ""
    --no-auto-sync
] {
    section "Initial-setup 0.5.0"

    require chezmoi

    let scripts = ($TOOLS_ROOT | path join "scripts")

    let data_root = (resolve-data-root $data_dir)
    save-machine-config $data_root

    print $"Tools root   : ($TOOLS_ROOT)"
    print $"Private data : ($data_root)"
    print $"OS           : ($nu.os-info.name)"
    print $"Home         : ($nu.home-path)"
    print $"Nushell      : ($env.NU_VERSION)"

    run-script (
        "Initializing private data structure"
    ) (
        $scripts | path join "init-private-data.nu"
    )

    run-script (
        "Installing common CLI tools"
    ) (
        $scripts | path join "install-cli-tools.nu"
    )

    run-script (
        "Installing Rust and Julia toolchains"
    ) (
        $scripts | path join "install-language-tools.nu"
    )

    run-script (
        "Installing VS Code"
    ) (
        $scripts | path join "install-vscode.nu"
    )

    let resolved_mode = (resolve-mode $mode $data_root)

    section $"Selected mode: ($resolved_mode)"

    if $resolved_mode == "initial" {
        run-script (
            "Importing existing local configuration"
        ) (
            $scripts | path join "migrate-dotfiles.nu"
        )

        section "Applying imported/private configuration"
        apply-private-source $data_root

        run-script (
            "Configuring platform-specific paths"
        ) (
            $scripts | path join "setup-platform-shims.nu"
        )

        run-script (
            "Enabling Nushell dotfiles commands"
        ) (
            $scripts | path join "enable-nushell-dotfiles.nu"
        )

        run-script (
            "Capturing VS Code extensions"
        ) (
            $scripts | path join "capture-vscode-extensions.nu"
        )

        run-script (
            "Capturing VS Code settings"
        ) (
            $scripts | path join "capture-vscode-config.nu"
        )
    } else {
        section "Applying private cloud configuration"
        apply-private-source $data_root

        run-script (
            "Configuring platform-specific paths"
        ) (
            $scripts | path join "setup-platform-shims.nu"
        )

        run-script (
            "Enabling Nushell dotfiles commands"
        ) (
            $scripts | path join "enable-nushell-dotfiles.nu"
        )

        run-script (
            "Applying VS Code settings"
        ) (
            $scripts | path join "apply-vscode-config.nu"
        )

        run-script (
            "Installing VS Code extensions"
        ) (
            $scripts | path join "install-vscode-extensions.nu"
        )
    }

    run-script (
        "Installing Starship"
    ) (
        $scripts | path join "install-starship.nu"
    )

    run-script (
        "Configuring Starship for Nushell"
    ) (
        $scripts | path join "setup-starship.nu"
    )

    run-script (
        "Installing WezTerm"
    ) (
        $scripts | path join "install-wezterm.nu"
    )

    run-script (
        "Initializing synchronization baseline"
    ) (
        $scripts | path join "update-sync-state.nu"
    )

    if $no_auto_sync {
        section "Automatic synchronization"
        print "[skip] --no-auto-sync specified"
    } else {
        run-script (
            "Installing automatic synchronization"
        ) (
            $scripts | path join "install-auto-sync.nu"
        )
    }

    run-script (
        "Final environment check"
    ) (
        $scripts | path join "doctor.nu"
    )

    section "Setup complete"

    print $"Public tools : ($TOOLS_ROOT)"
    print $"Private data : ($data_root)"
    print ""
    print "Restart Nushell once:"
    print ""
    print "  exec nu"
    print ""
    print "Commands after restart:"
    print ""
    print "  dotstatus"
    print "  dotdiff"
    print "  dotpush"
    print "  dotpull"
    print "  dotsync"
    print "  dotnvim"
    print "  dotnu"
    print "  dotenv"
    print "  dotwezterm"
    print "  dotstarship"
    print "  dotdata"
    print "  dottools"
}
