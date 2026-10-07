#!/usr/bin/env nu
# dotpush always captures rclone.conf through the age-backed vault when enabled.
const CORE = path self ./modules/core.nu
const VAULT = path self ./modules/vault.nu
const CONSOLE = path self ./modules/console.nu
use $CORE [machine-context]
use $VAULT [vault-configured ensure-rclone-entry capture-secret ciphertext-path record-secret-sync-state ciphertext-decryptable]
use $CONSOLE [print-status]

def main [--manual] {
    if not ((machine-context).features.rclone_config? | default false) {
        if $manual {
            error make {msg: "The rclone_config feature is disabled for this machine. Enable features.rclone_config before using manual encrypted rclone capture."}
        }
        return
    }

    if not (vault-configured) {
        error make {msg: "rclone_config is enabled, but the encrypted vault is not configured. Run `dotvault init` (or `dotctl config vault init`) once before dotpush. The age identity is machine-local and must be backed up separately."}
    }

    let entry = (ensure-rclone-entry)
    let local = ($entry.local | path expand)
    if not ($local | path exists) or (($local | path type) != "file") {
        error make {msg: ("The active rclone config is missing: " + ($local | into string) + ". dotpush will not publish an older encrypted copy as if it were current.")}
    }

    let encrypted = (ciphertext-path "rclone")
    let plaintext_hash = (open --raw $local | hash sha256)
    let encrypted_hash = if ($encrypted | path exists) { open --raw $encrypted | hash sha256 } else { "" }
    let known_plaintext = ($entry.last_plaintext_sha256? | default "")
    let known_ciphertext = ($entry.last_ciphertext_sha256? | default "")

    # Reuse only a copy this machine can still decrypt: after a vault rekey the
    # recorded hashes match but the ciphertext is for the old recipient.
    if ($encrypted | path exists) and $plaintext_hash == $known_plaintext and $encrypted_hash == $known_ciphertext and (ciphertext-decryptable $encrypted) {
        print-status "ok" "rclone" "Active rclone config is unchanged; existing encrypted copy is reused."
        return
    }

    print-status "info" "rclone" "Encrypting the active rclone config into the private source..."
    capture-secret "rclone"
    let committed_ciphertext = (open --raw $encrypted | hash sha256)
    record-secret-sync-state "rclone" $plaintext_hash $committed_ciphertext
    print-status "ok" "rclone" "Encrypted rclone config is ready for publication."
}
