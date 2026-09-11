#!/usr/bin/env nu

# ============================================================
# Capture VS Code settings, keybindings, and snippets into the
# private cloud `vscode/` directory.
# ============================================================

def machine-context [] {
    let file = (
        $nu.home-path
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
            $nu.home-path
            | path join "Library" "Application Support" "Code" "User"
        }

        "linux" => {
            $nu.home-path
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

    copy-file-if-exists (
        $user_dir | path join "settings.json"
    ) (
        $private_root | path join "settings.json"
    )

    copy-file-if-exists (
        $user_dir | path join "keybindings.json"
    ) (
        $private_root | path join "keybindings.json"
    )

    copy-dir-if-exists (
        $user_dir | path join "snippets"
    ) (
        $private_root | path join "snippets"
    )
}
