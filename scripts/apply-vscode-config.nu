#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [machine-context vscode-user-dir]
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

def main [--prune --source-root: string = ""] {
    let user_dir = (vscode-user-dir)

    if $user_dir == null {
        print "[skip] Unsupported OS for VS Code config apply."
        return
    }

    let context = (machine-context)
    let configured_prune = ($context.sync.prune_extras? | default false)
    let should_prune = ($prune or $configured_prune)
    let source_root = if ($source_root | str trim | is-empty) { $context.data_root | path expand } else { $source_root | path expand }
    let private_root = ($source_root | path join "vscode")

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
