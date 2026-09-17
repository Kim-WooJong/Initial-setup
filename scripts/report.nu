#!/usr/bin/env nu

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

def first-version [
    command: string
    args: list
] {
    if (which $command | is-empty) {
        return "not installed"
    }

    let output = (^$command ...$args | lines)

    if ($output | is-empty) {
        "installed"
    } else {
        $output | first | str trim
    }
}

def main [
    --save
] {
    let context = (machine-context)
    let state_file = ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict_file = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")
    let state = (
        if ($state_file | path exists) {
            open $state_file
        } else {
            {}
        }
    )

    let lines = [
        "Initial-setup environment report"
        "================================"
        ("Generated      : " + (date now | format date "%Y-%m-%d %H:%M:%S %z"))
        ("Initial-setup  : " + ($context.app_version? | default (($context | get --optional version) | default "unknown")))
        ("Config schema   : " + (($context.schema_version? | default 0) | into string))
        ("Machine        : " + $context.machine.name)
        ("Profile        : " + $context.machine.profile)
        ("OS             : " + $nu.os-info.name)
        ("Nushell        : " + $env.NU_VERSION)
        ("Git            : " + (first-version "git" ["--version"]))
        (
            "Git describe   : " + (
                if (($context.tools_root | path expand | path join ".git") | path exists) {
                    ^git -C ($context.tools_root | path expand) describe --tags --always --dirty | str trim
                } else {
                    "not a Git checkout"
                }
            )
        )
        ("Neovim         : " + (first-version "nvim" ["--version"]))
        ("chezmoi        : " + (first-version "chezmoi" ["--version"]))
        ("Starship       : " + (first-version "starship" ["--version"]))
        ("WezTerm        : " + (first-version "wezterm" ["--version"]))
        ("Rustup         : " + (first-version "rustup" ["--version"]))
        ("Cargo          : " + (first-version "cargo" ["--version"]))
        ("Julia          : " + (first-version "julia" ["--version"]))
        ("git-delta      : " + (first-version "delta" ["--version"]))
        ("lazygit        : " + (first-version "lazygit" ["--version"]))
        (
            "D2Coding       : " + (
                if (((nu-home) | path join ".config" "dotfiles" "fonts" "d2coding.nuon") | path exists) {
                    "detected/installed"
                } else {
                    "not confirmed"
                }
            )
        )
        (
            "Rust state     : " + (
                if (($context.data_root | path expand | path join "toolchains" "rust" "state.nuon") | path exists) {
                    "captured"
                } else {
                    "not captured"
                }
            )
        )
        (
            "Julia envs     : " + (
                if (($context.data_root | path expand | path join "toolchains" "julia" "environments") | path exists) {
                    "captured"
                } else {
                    "not captured"
                }
            )
        )
        (
            "Tool state     : " + (
                if (((nu-home) | path join ".config" "dotfiles" "state" "tools.nuon") | path exists) {
                    "captured"
                } else {
                    "not captured"
                }
            )
        )
        ""
        "Synchronization"
        "---------------"
        ("Enabled        : " + ($context.sync.enabled | into string))
        ("Interval       : " + ($context.sync.interval_minutes | into string) + " minute(s)")
        ("Conflict mode  : " + $context.sync.conflict_policy)
        ("Last sync      : " + ($state.last_sync? | default "unknown"))
        ("Last writer    : " + ($state.last_writer? | default "unknown"))
        ("Last action    : " + ($state.last_action? | default "unknown"))
        (
            "Conflict       : " + (
                if ($conflict_file | path exists) {
                    "YES"
                } else {
                    "none"
                }
            )
        )
        ""
        ("Private data   : " + $context.data_root)
        ("Tools root     : " + $context.tools_root)
    ]

    let text = ($lines | str join (char nl))
    print $text

    if $save {
        let report_dir = ((nu-home) | path join ".config" "dotfiles" "reports")
        mkdir $report_dir

        let stamp = (date now | format date "%Y%m%d-%H%M%S")
        let file = ($report_dir | path join ("environment-" + $stamp + ".txt"))

        $text | save $file

        print ""
        print ("[save] " + ($file | into string))
    }
}
