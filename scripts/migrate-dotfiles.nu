#!/usr/bin/env nu

# ============================================================
# Import current settings into the private cloud chezmoi source.
#
# SSH private keys are intentionally excluded.
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

def chezmoi-add [data_root: path target: path] {
    let p = ($target | path expand)

    if not ($p | path exists) {
        print $"[skip] Not found: ($p)"
        return
    }

    print $"[add]  ($p)"

    let args = [
        "--source"
        ($data_root | into string)
        "add"
        "--secrets"
        "error"
        ($p | into string)
    ]

    ^chezmoi ...$args

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: $"chezmoi add failed: ($p)"
        }
    }
}

def copy-file-if-needed [source: path destination: path] {
    let src = ($source | path expand)
    let dst = ($destination | path expand)

    if not ($src | path exists) {
        return
    }

    if $src == $dst {
        return
    }

    if ($dst | path exists) {
        print $"[keep] ($dst)"
        return
    }

    mkdir ($dst | path dirname)
    cp $src $dst

    print $"[copy] ($src)"
    print $"       -> ($dst)"
}

def copy-dir-if-needed [source: path destination: path] {
    let src = ($source | path expand)
    let dst = ($destination | path expand)

    if not ($src | path exists) {
        return
    }

    if $src == $dst {
        return
    }

    if ($dst | path exists) {
        print $"[keep] ($dst)"
        return
    }

    mkdir ($dst | path dirname)
    cp -r $src $dst

    print $"[copy] ($src)"
    print $"       -> ($dst)"
}

def main [] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    let canonical_config = (
        (nu-home)
        | path join ".config"
    )

    let canonical_nvim = (
        $canonical_config
        | path join "nvim"
    )

    let canonical_nushell = (
        $canonical_config
        | path join "nushell"
    )

    mkdir $canonical_config

    print "--- Neovim ---"

    if not (which nvim | is-empty) {
        let nvim_args = [
            "--headless"
            "-u"
            "NONE"
            "-c"
            "lua io.write(vim.fn.stdpath('config'))"
            "-c"
            "qa"
        ]

        let current_nvim = (
            ^nvim ...$nvim_args
            | str trim
            | path expand
        )

        copy-dir-if-needed $current_nvim $canonical_nvim
        chezmoi-add $data_root $canonical_nvim
    } else {
        print "[skip] nvim not installed"
    }

    print ""
    print "--- Nushell ---"

    let current_nu_config = ($nu.config-path | path expand)
    let current_nu_env = ($nu.env-path | path expand)
    let current_nu_dir = ($current_nu_config | path dirname)

    let canonical_nu_config = (
        $canonical_nushell
        | path join "config.nu"
    )

    let canonical_nu_env = (
        $canonical_nushell
        | path join "env.nu"
    )

    mkdir $canonical_nushell

    copy-file-if-needed $current_nu_config $canonical_nu_config
    copy-file-if-needed $current_nu_env $canonical_nu_env

    for dir_name in ["modules" "autoload"] {
        let current_dir = ($current_nu_dir | path join $dir_name)
        let canonical_dir = ($canonical_nushell | path join $dir_name)
        copy-dir-if-needed $current_dir $canonical_dir
    }

    chezmoi-add $data_root $canonical_nu_config
    chezmoi-add $data_root $canonical_nu_env
    chezmoi-add $data_root ($canonical_nushell | path join "modules")
    chezmoi-add $data_root ($canonical_nushell | path join "autoload")

    if $context.features.git_config {
        print ""
        print "--- Git ---"

        let git_home = ((nu-home) | path join ".gitconfig")
        let git_xdg = ((nu-home) | path join ".config" "git" "config")
        chezmoi-add $data_root $git_home
        chezmoi-add $data_root $git_xdg
    }

    if $context.features.ssh_config {
        print ""
        print "--- SSH config only ---"

        let ssh_config = ((nu-home) | path join ".ssh" "config")
        chezmoi-add $data_root $ssh_config
    }

    if $context.features.wezterm {
        print ""
        print "--- WezTerm ---"

        let canonical_wezterm = ($canonical_config | path join "wezterm" "wezterm.lua")
        let legacy_wezterm = ((nu-home) | path join ".wezterm.lua")

        if not ($canonical_wezterm | path exists) {
            copy-file-if-needed $legacy_wezterm $canonical_wezterm
        }

        chezmoi-add $data_root $canonical_wezterm
    }

    if $context.features.starship {
        print ""
        print "--- Starship ---"

        let canonical_starship = ($canonical_config | path join "starship.toml")
        chezmoi-add $data_root $canonical_starship
    }

    if $context.features.rust {
        print ""
        print "--- Cargo ---"

        let cargo_config = ((nu-home) | path join ".cargo" "config.toml")
        chezmoi-add $data_root $cargo_config
    }

    if $context.features.julia {
        print ""
        print "--- Julia ---"

        let julia_startup = ((nu-home) | path join ".julia" "config" "startup.jl")
        chezmoi-add $data_root $julia_startup
    }

    print ""
    print "[ok] Existing configuration imported."
}
