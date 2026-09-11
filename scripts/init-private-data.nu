#!/usr/bin/env nu

# ============================================================
# Create the private data structure.
#
# Generic WezTerm/Starship defaults are copied from public
# static files only when the private files do not already exist.
# ============================================================

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

def copy-if-missing [source: path destination: path] {
    if ($destination | path exists) {
        print $"[keep] ($destination)"
        return
    }

    if not ($source | path exists) {
        error make {
            msg: $"Default source not found: ($source)"
        }
    }

    mkdir ($destination | path dirname)
    cp $source $destination

    print $"[create] ($destination)"
}

def main [] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    mkdir $data_root
    mkdir ($data_root | path join "home")
    mkdir ($data_root | path join "vscode")

    let chezmoi_root = ($data_root | path join ".chezmoiroot")

    if ($chezmoi_root | path exists) {
        let configured = (
            open --raw $chezmoi_root
            | str trim
        )

        if $configured != "home" {
            error make {
                msg: $"($chezmoi_root) must contain 'home', found '($configured)'"
            }
        }

        print "[ok] .chezmoiroot"
    } else {
        "home\n" | save $chezmoi_root
        print $"[create] ($chezmoi_root)"
    }

    let wezterm_default = (
        $TOOLS_ROOT
        | path join "defaults" "wezterm.lua"
    )

    let wezterm_target = (
        $data_root
        | path join "home" "dot_config" "wezterm" "wezterm.lua"
    )

    copy-if-missing $wezterm_default $wezterm_target

    let starship_default = (
        $TOOLS_ROOT
        | path join "defaults" "starship.toml"
    )

    let starship_target = (
        $data_root
        | path join "home" "dot_config" "starship.toml"
    )

    copy-if-missing $starship_default $starship_target

    let module_source = (
        $TOOLS_ROOT
        | path join "scripts" "modules" "dotfiles.nu"
    )

    let module_target = (
        $data_root
        | path join "home" "dot_config" "nushell" "modules" "dotfiles.nu"
    )

    if not ($module_source | path exists) {
        error make {
            msg: $"Management module not found: ($module_source)"
        }
    }

    mkdir ($module_target | path dirname)
    cp $module_source $module_target

    print $"[sync] Management module -> ($module_target)"

    let vscode_extensions = (
        $data_root
        | path join "vscode" "extensions.txt"
    )

    if not ($vscode_extensions | path exists) {
        "" | save $vscode_extensions
        print $"[create] ($vscode_extensions)"
    }

    print $"[ok] Private data root ready: ($data_root)"
}
