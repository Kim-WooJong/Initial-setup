#!/usr/bin/env nu

# ============================================================
# Apply private VS Code settings, keybindings, and snippets to
# the platform-native VS Code User directory.
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

def apply-file-if-exists [source: path destination: path] {
    if not ($source | path exists) {
        return
    }

    mkdir ($destination | path dirname)
    cp $source $destination

    print ("[apply] " + ($destination | into string))
}

def apply-dir-if-exists [source: path destination: path] {
    if not ($source | path exists) {
        return
    }

    if ($destination | path exists) {
        rm -r $destination
    }

    mkdir ($destination | path dirname)
    cp -r $source $destination

    print ("[apply] " + ($destination | into string))
}

def main [] {
    let user_dir = (vscode-user-dir)

    if $user_dir == null {
        print "[skip] Unsupported OS for VS Code config apply."
        return
    }

    let context = (machine-context)
    let private_root = (
        $context.data_root
        | path expand
        | path join "vscode"
    )

    if not ($private_root | path exists) {
        print "[skip] Private VS Code configuration not found."
        return
    }

    mkdir $user_dir

    apply-file-if-exists (
        $private_root | path join "settings.json"
    ) (
        $user_dir | path join "settings.json"
    )

    apply-file-if-exists (
        $private_root | path join "keybindings.json"
    ) (
        $user_dir | path join "keybindings.json"
    )

    apply-dir-if-exists (
        $private_root | path join "snippets"
    ) (
        $user_dir | path join "snippets"
    )
}
