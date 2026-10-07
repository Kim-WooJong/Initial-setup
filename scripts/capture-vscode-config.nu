#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [machine-context vscode-user-dir]
# ============================================================
# Capture VS Code settings, keybindings, and snippets into the
# private cloud `vscode/` directory.
# ============================================================

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
