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

    if not ($file | path exists) {
        error make { msg: ("Machine config not found: " + ($file | into string)) }
    }

    open $file
}

def main [--prune] {
    if (which code | is-empty) {
        print "[skip] VS Code CLI not found"
        return
    }

    let context = (machine-context)
    let configured_prune = ($context.sync.prune_extras? | default false)
    let should_prune = ($prune or $configured_prune)
    let extension_file = ($context.data_root | path expand | path join "vscode" "extensions.txt")

    if not ($extension_file | path exists) {
        print "[skip] VS Code extension list not found"
        return
    }

    let installed = (^code --list-extensions | lines | where { |item| not ($item | is-empty) } | sort | uniq)
    let desired = (open --raw $extension_file | lines | where { |item| not ($item | is-empty) } | sort | uniq)
    let missing = ($desired | where { |extension| not ($extension in $installed) })
    let extra = ($installed | where { |extension| not ($extension in $desired) })

    for extension in $missing {
        print ("[install] " + $extension)
        ^code --install-extension $extension

        if ($env.LAST_EXIT_CODE | default 0) != 0 {
            print ("[warn] Failed to install " + $extension)
        }
    }

    if $should_prune {
        for extension in $extra {
            print ("[remove] " + $extension)
            ^code --uninstall-extension $extension

            if ($env.LAST_EXIT_CODE | default 0) != 0 {
                print ("[warn] Failed to remove " + $extension)
            }
        }

        print "[ok] VS Code extension set reconciled in prune mode"
    } else {
        if not ($extra | is-empty) {
            print ("[keep] Preserving " + (($extra | length) | into string) + " local-only VS Code extension(s)")
        }

        print "[ok] VS Code extension set reconciled in merge mode"
    }
}
