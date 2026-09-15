#!/usr/bin/env nu

# ============================================================
# Ensure canonical config.nu imports the management module.
# ============================================================

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
    let file = (
        (nu-home)
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
        (nu-home)
        | path join ".config" "nushell" "config.nu"
    )

    let module_file = (
        (nu-home)
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
    let local_line = "source ~/.config/dotfiles/local.nu"
    mut current = (open --raw $config_file)

    if not ($current | str contains $import_line) {
        let separator = (
            if ($current | str trim | is-empty) {
                ""
            } else {
                char nl
            }
        )

        $current = (
            $current + $separator + "# Dotfiles management" + (char nl) + $import_line + (char nl)
        )
    }

    if not ($current | str contains $local_line) {
        let separator = (
            if ($current | str trim | is-empty) {
                ""
            } else {
                char nl
            }
        )

        $current = (
            $current + $separator + "# Machine-local setup (not synchronized)" + (char nl) + $local_line + (char nl)
        )
    }

    $current | save --force $config_file
    print $"[update] ($config_file)"

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
