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

def app-version [] {
    open --raw ($TOOLS_ROOT | path join "VERSION")
    | into string
    | str trim
}

def schema-version [] {
    open --raw ($TOOLS_ROOT | path join "SCHEMA_VERSION")
    | into string
    | str trim
    | into int
}

def command-version [name: string args: list] {
    if (which $name | is-empty) {
        return null
    }

    try {
        ^$name ...$args
        | lines
        | first
        | str trim
    } catch {
        null
    }
}

def main [] {
    let state_dir = ((nu-home) | path join ".config" "dotfiles" "state")
    let state_file = ($state_dir | path join "tools.nuon")

    mkdir $state_dir

    let state = {
        state_schema_version: 1
        app_version: (app-version)
        machine_config_schema: (schema-version)
        captured_at: (date now)
        platform: {
            os: $nu.os-info.name
            arch: ($nu.os-info.arch? | default "unknown")
            nushell: $env.NU_VERSION
        }
        tools: {
            git: (command-version "git" ["--version"])
            neovim: (command-version "nvim" ["--version"])
            chezmoi: (command-version "chezmoi" ["--version"])
            starship: (command-version "starship" ["--version"])
            wezterm: (command-version "wezterm" ["--version"])
            code: (command-version "code" ["--version"])
            rustup: (command-version "rustup" ["--version"])
            cargo: (command-version "cargo" ["--version"])
            juliaup: (command-version "juliaup" ["--version"])
            julia: (command-version "julia" ["--version"])
            ripgrep: (command-version "rg" ["--version"])
            fd: (command-version "fd" ["--version"])
            fdfind: (command-version "fdfind" ["--version"])
            fzf: (command-version "fzf" ["--version"])
            bat: (command-version "bat" ["--version"])
            batcat: (command-version "batcat" ["--version"])
            zoxide: (command-version "zoxide" ["--version"])
            delta: (command-version "delta" ["--version"])
            lazygit: (command-version "lazygit" ["--version"])
            rclone: (command-version "rclone" ["--version"])
        }
    }

    $state
    | to nuon
    | save --force $state_file

    print ("[save] Tool state -> " + ($state_file | into string))
}
