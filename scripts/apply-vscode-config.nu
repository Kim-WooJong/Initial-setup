#!/usr/bin/env nu

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    if not ($file | path exists) {
        error make { msg: ("Machine config not found: " + ($file | into string)) }
    }

    open $file
}

def vscode-user-dir [] {
    match $nu.os-info.name {
        "windows" => {
            let appdata = ($env.APPDATA? | default "")
            if ($appdata | is-empty) { return null }
            $appdata | path join "Code" "User"
        }

        "macos" => {
            (nu-home) | path join "Library" "Application Support" "Code" "User"
        }

        "linux" => {
            (nu-home) | path join ".config" "Code" "User"
        }

        _ => { null }
    }
}

def apply-file-if-exists [source: path destination: path] {
    if not ($source | path exists) { return }

    mkdir ($destination | path dirname)
    cp $source $destination
    print ("[apply] " + ($destination | into string))
}

def merge-dir [source: path destination: path] {
    if not ($source | path exists) { return }

    mkdir $destination

    for item in (ls -a $source) {
        let source_item = ($item.name | path expand)
        let target_item = ($destination | path join ($source_item | path basename))

        if $item.type == "dir" {
            merge-dir $source_item $target_item
        } else {
            cp $source_item $target_item
            print ("[apply] " + ($target_item | into string))
        }
    }
}

def apply-dir [source: path destination: path prune: bool] {
    if not ($source | path exists) { return }

    if $prune and ($destination | path exists) {
        rm -r $destination
    }

    merge-dir $source $destination
}

def main [--prune] {
    let user_dir = (vscode-user-dir)

    if $user_dir == null {
        print "[skip] Unsupported OS for VS Code config apply."
        return
    }

    let context = (machine-context)
    let configured_prune = ($context.sync.prune_extras? | default false)
    let should_prune = ($prune or $configured_prune)
    let private_root = ($context.data_root | path expand | path join "vscode")

    if not ($private_root | path exists) {
        print "[skip] Private VS Code configuration not found."
        return
    }

    mkdir $user_dir

    apply-file-if-exists ($private_root | path join "settings.json") ($user_dir | path join "settings.json")
    apply-file-if-exists ($private_root | path join "keybindings.json") ($user_dir | path join "keybindings.json")
    apply-dir ($private_root | path join "snippets") ($user_dir | path join "snippets") $should_prune

    if $should_prune {
        print "[ok] VS Code configuration applied in prune mode"
    } else {
        print "[ok] VS Code configuration applied in merge mode"
    }
}
