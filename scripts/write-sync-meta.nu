#!/usr/bin/env nu

# ============================================================
# Write shared synchronization metadata.
# This file is stored at the private data root and is not part
# of the chezmoi source fingerprint.
# ============================================================

def nu-home [] {
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

    open $file
}

def main [
    --action: string = "push"
] {
    let context = (
        machine-context
    )

    let data_root = (
        $context.data_root
        | path expand
    )

    let file = (
        $data_root
        | path join ".dotfiles-sync-meta.nuon"
    )

    {
        version: "1"
        last_writer: $context.machine.name
        last_action: $action
        updated_at: (
            date now
            | format date "%Y-%m-%d %H:%M:%S %z"
        )
    }
    | to nuon
    | save --force $file

    print (
        "[meta] Last writer: "
        + $context.machine.name
    )
}
