#!/usr/bin/env nu

# ============================================================
# Capture VS Code settings, keybindings, and snippets into the
# private cloud `vscode/` directory.
# ============================================================

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
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

    if not ($file | path exists) {
        error make {
            msg: ("Machine config not found: " + ($file | into string))
        }
    }

    open $file
}

def vscode-user-dir [] {
    match $nu.os-info.name {
        "windows" => {
            let appdata = ($env.APPDATA? | default "")

            if ($appdata | is-empty) {
                return null
            }

            $appdata | path join "Code" "User"
        }

        "macos" => {
            (nu-home)
            | path join "Library" "Application Support" "Code" "User"
        }

        "linux" => {
            (nu-home)
            | path join ".config" "Code" "User"
        }

        _ => {
            null
        }
    }
}

def copy-file-if-exists [source: path destination: path] {
    if not ($source | path exists) {
        return
    }

    mkdir ($destination | path dirname)
    cp $source $destination

    print ("[capture] " + ($source | into string))
}

def copy-dir-if-exists [source: path destination: path] {
    if not ($source | path exists) {
        return
    }

    if ($destination | path exists) {
        rm -r $destination
    }

    mkdir ($destination | path dirname)
    cp -r $source $destination

    print ("[capture] " + ($source | into string))
}

def main [] {
    let user_dir = (vscode-user-dir)

    if $user_dir == null {
        print "[skip] Unsupported OS for VS Code config capture."
        return
    }

    if not ($user_dir | path exists) {
        print "[skip] VS Code user configuration directory not found."
        return
    }

    let context = (machine-context)
    let private_root = (
        $context.data_root
        | path expand
        | path join "vscode"
    )

    mkdir $private_root

    let source_settings = ($user_dir | path join "settings.json")
    let target_settings = ($private_root | path join "settings.json")
    copy-file-if-exists $source_settings $target_settings

    let source_keybindings = ($user_dir | path join "keybindings.json")
    let target_keybindings = ($private_root | path join "keybindings.json")
    copy-file-if-exists $source_keybindings $target_keybindings

    let source_snippets = ($user_dir | path join "snippets")
    let target_snippets = ($private_root | path join "snippets")
    copy-dir-if-exists $source_snippets $target_snippets
}
