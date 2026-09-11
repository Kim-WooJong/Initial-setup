#!/usr/bin/env nu

# ============================================================
# Ensure canonical config.nu imports the management module.
# ============================================================

def machine-context [] {
    let file = (
        $nu.home-path
        | path join ".config" "dotfiles" "config.nuon"
    )

    if not ($file | path exists) {
        error make {
            msg: $"Machine config not found: ($file)"
        }
    }

    open $file
}

def main [] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    let config_file = (
        $nu.home-path
        | path join ".config" "nushell" "config.nu"
    )

    let module_file = (
        $nu.home-path
        | path join ".config" "nushell" "modules" "dotfiles.nu"
    )

    if not ($module_file | path exists) {
        error make {
            msg: $"Managed module not found: ($module_file)"
        }
    }

    if not ($config_file | path exists) {
        mkdir ($config_file | path dirname)
        "" | save $config_file
    }

    let import_line = "use ~/.config/nushell/modules/dotfiles.nu *"
    let current = (open --raw $config_file)

    if not ($current | str contains $import_line) {
        let separator = (
            if ($current | str trim | is-empty) {
                ""
            } else {
                char nl
            }
        )

        (
            $current
            + $separator
            + "# Dotfiles management"
            + (char nl)
            + $import_line
            + (char nl)
        )
        | save --force $config_file

        print $"[update] ($config_file)"
    } else {
        print "[ok] Dotfiles module already enabled"
    }

    let args = [
        "--source"
        ($data_root | into string)
        "add"
        "--secrets"
        "error"
        ($config_file | into string)
    ]

    ^chezmoi ...$args

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: "Failed to update Nushell config in private source."
        }
    }
}
