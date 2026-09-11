#!/usr/bin/env nu

# ============================================================
# Write shared synchronization metadata.
# This file is stored at the private data root and is not part
# of the chezmoi source fingerprint.
# ============================================================

def machine-context [] {
    let file = (
        $nu.home-path
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
