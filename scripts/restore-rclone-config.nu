#!/usr/bin/env nu
# Restore rclone.conf from authenticated age ciphertext. Authentication/decryption
# is completed in restricted local staging before the active config is replaced.
const CORE = path self ./modules/core.nu
const RCLONE_SECRET = path self ./modules/rclone-secret-sync.nu
use $CORE [machine-context error-message]
use $RCLONE_SECRET [prepare-rclone-restore commit-prepared-rclone discard-prepared-rclone]

def main [--source-root: string = "" --manual] {
    let context = (machine-context)
    if not ($context.features.rclone_config? | default false) {
        if $manual {
            error make {msg: "The rclone_config feature is disabled for this machine. Enable features.rclone_config before using manual encrypted rclone restore."}
        }
        return
    }

    let root = if ($source_root | str trim | is-empty) {
        $context.data_root | path expand
    } else {
        $source_root | path expand
    }

    let prepared = (prepare-rclone-restore $root)
    if ($prepared.status? | default "") != "prepared" { return }

    try {
        commit-prepared-rclone $prepared | ignore
    } catch {|err| discard-prepared-rclone $prepared
        error make {msg: (error-message $err "Encrypted rclone restore failed.")}
    }
}
