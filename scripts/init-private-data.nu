#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
const COMMAND_RUNTIME = path self ./modules/command-runtime.nu
use $CORE [nu-home machine-context]
use $COMMAND_RUNTIME [generate-command-shim]
# ============================================================
# Create the private data structure.
#
# Generic WezTerm/Starship defaults are copied from public
# static files only when the private files do not already exist.
# ============================================================

const TOOLS_ROOT = path self ..

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
    mkdir ($data_root | path join "toolchains")
    mkdir ($data_root | path join "toolchains" "rust")
    mkdir ($data_root | path join "toolchains" "julia" "environments")
    mkdir ($data_root | path join "rclone")
    mkdir ($data_root | path join "rpool")

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

    let module_target_root = (
        $data_root
        | path join "home" "dot_config" "nushell" "modules"
    )
    mkdir $module_target_root

    # Only the generated shim is seeded; commands run from tools_root.
    let shim_target = ($module_target_root | path join "dotfiles.nu")
    generate-command-shim $TOOLS_ROOT | save --force --raw $shim_target
    print $"[sync] Command shim -> ($shim_target)"


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
