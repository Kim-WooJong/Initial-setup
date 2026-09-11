#!/usr/bin/env nu

def machine-context [] {
    let file = ($nu.home-path | path join ".config" "dotfiles" "config.nuon")
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
    let state_file = ($nu.home-path | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict_file = ($nu.home-path | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")
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
        ("Initial-setup  : " + $context.version)
        ("Machine        : " + $context.machine.name)
        ("Profile        : " + $context.machine.profile)
        ("OS             : " + $nu.os-info.name)
        ("Nushell        : " + $env.NU_VERSION)
        ("Git            : " + (first-version "git" ["--version"]))
        ("Neovim         : " + (first-version "nvim" ["--version"]))
        ("chezmoi        : " + (first-version "chezmoi" ["--version"]))
        ("Starship       : " + (first-version "starship" ["--version"]))
        ("WezTerm        : " + (first-version "wezterm" ["--version"]))
        ("Rustup         : " + (first-version "rustup" ["--version"]))
        ("Cargo          : " + (first-version "cargo" ["--version"]))
        ("Julia          : " + (first-version "julia" ["--version"]))
        ("git-delta      : " + (first-version "delta" ["--version"]))
        ("lazygit        : " + (first-version "lazygit" ["--version"]))
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
            "Conflict       : "
            + (
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
        let report_dir = ($nu.home-path | path join ".config" "dotfiles" "reports")
        mkdir $report_dir

        let stamp = (date now | format date "%Y%m%d-%H%M%S")
        let file = ($report_dir | path join ("environment-" + $stamp + ".txt"))

        $text | save $file

        print ""
        print ("[save] " + ($file | into string))
    }
}
