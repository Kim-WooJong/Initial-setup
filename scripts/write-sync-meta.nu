#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
# ============================================================
# Write shared synchronization metadata.
# This file is stored at the private data root and is not part
# of the chezmoi source fingerprint.
# ============================================================

const SAFETY = path self ./modules/safety.nu
use $SAFETY [atomic-record]

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

    atomic-record $file {
        version: "1"
        last_writer: $context.machine.name
        last_action: $action
        updated_at: (
            date now
            | format date "%Y-%m-%d %H:%M:%S %z"
        )
    }

    print (
        "[meta] Last writer: " + $context.machine.name
    )
}
