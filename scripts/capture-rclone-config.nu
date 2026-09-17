#!/usr/bin/env nu
# rclone config file is resolved when the machine-local vault is initialized.
const CORE = path self ./modules/core.nu
const VAULT = path self ./modules/vault.nu
use $CORE [machine-context]
use $VAULT [vault-configured load-vault capture-secret]
def main [] {
    if not ((machine-context).features.rclone_config? | default false) { return }
    if not (vault-configured) { print "[skip] No plaintext rclone capture. Configure dotvault init and an encrypted rclone entry."; return }
    let rows = ((load-vault).entries | where name == "rclone")
    if ($rows | is-empty) or not (($rows | first).auto_capture? | default false) {
        print "[skip] rclone encrypted auto_capture is disabled; use dotvault capture rclone explicitly."
        return
    }
    capture-secret "rclone"
}
