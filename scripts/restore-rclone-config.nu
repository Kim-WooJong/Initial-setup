#!/usr/bin/env nu
# rclone config file restoration is opt-in, authenticated, and never plaintext sync.
const CORE = path self ./modules/core.nu
const VAULT = path self ./modules/vault.nu
use $CORE [machine-context]
use $VAULT [vault-configured load-vault restore-secret ciphertext-path]
def main [] {
    if not ((machine-context).features.rclone_config? | default false) or not (vault-configured) { return }
    let rows = ((load-vault).entries | where name == "rclone")
    if ($rows | is-empty) or not (($rows | first).auto_restore? | default false) {
        print "[skip] rclone auto_restore is disabled; use dotvault restore rclone explicitly."
        return
    }
    if not ((ciphertext-path "rclone") | path exists) { return }
    # Even opt-in automatic restore must not overwrite existing transport credentials.
    if (($rows | first).local | path exists) { print "[keep] Existing rclone credentials require an explicit dotvault restore rclone --force."; return }
    restore-secret "rclone" false
}
