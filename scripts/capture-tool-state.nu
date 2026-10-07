#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home project-version project-schema-version]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command]

def command-version [name: string args: list] {
    if (which $name | is-empty) {
        return null
    }

    let result = (run-command $name $args)
    if not $result.ok { return null }
    let lines = ($result.stdout | lines | where {|line| not ($line | str trim | is-empty) })
    if ($lines | is-empty) { null } else { $lines | first | str trim }
}

def main [] {
    let state_dir = ((nu-home) | path join ".config" "dotfiles" "state")
    let state_file = ($state_dir | path join "tools.nuon")

    mkdir $state_dir

    let state = {
        state_schema_version: 1
        app_version: (project-version $TOOLS_ROOT)
        machine_config_schema: (project-schema-version $TOOLS_ROOT)
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
