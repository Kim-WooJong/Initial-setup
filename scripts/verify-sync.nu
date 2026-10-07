#!/usr/bin/env nu
# Read-only check that this machine's rclone.conf and rpool settings match the
# private source. Decrypts only in memory, prints names/statuses only (never
# secret values), and writes neither the private source nor live config.
# Exit code: 0 = everything checked matches, 1 = a difference or failure.
const CORE = path self ./modules/core.nu
const VAULT = path self ./modules/vault.nu
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
const RCLONE_COMPARE = path self ./modules/rclone-compare.nu
const RPOOL = path self ./modules/rpool-sync.nu
const SSH_KEYS = path self ./modules/ssh-key-sync.nu
use $CORE [machine-context]
use $VAULT [vault-configured load-vault active-rclone-config-path ciphertext-path identity-recipient-status]
use $SUBPROCESS [run-command]
use $CONSOLE [print-heading print-status print-key-value]
use $RCLONE_COMPARE [compare-rclone-texts encrypted-rclone-config]
use $RPOOL [rpool-verify]
use $SSH_KEYS [ssh-keys-verify]

def kv [label: string value: any] { print-key-value ("  " + $label + ": ") $value }

def decryptor [] {
    let age = (which age --all | where type == "external")
    if ($age | is-empty) or not (vault-configured) { return null }
    let identity = (try { (load-vault).identity? | default "" | into string | str trim } catch { "" })
    if ($identity | is-empty) or not ($identity | path expand | path exists) { return null }
    {age: ($age | first | get path) identity: ($identity | path expand | into string)}
}

export def verify-rclone [context: record keys: record] {
    if not ($context.features?.rclone_config? | default false) {
        return {status: "disabled" detail: "rclone.conf synchronization is off for this machine (features.rclone_config)."}
    }
    let live = (active-rclone-config-path)
    if $live == null or not ($live | path exists) { return {status: "missing-locally" detail: "No active rclone.conf on this machine."} }
    let synced = (try { ciphertext-path "rclone" } catch { "" })
    if ($synced | is-empty) or not ($synced | path exists) { return {status: "not-synchronized" detail: "No encrypted rclone.conf in the private source yet. Run dotpush."} }
    let dec = (decryptor)
    if $dec == null { return {status: "unverifiable" detail: "age or the vault identity is unavailable; cannot decrypt the private copy for comparison."} }
    let result = (run-command $dec.age ["--decrypt" "--identity" $dec.identity ($synced | into string)] --sensitive)
    if not $result.ok {
        let why = if $keys.status == "match" { "it was encrypted for a different key (another machine probably ran dotvault rekey): copy that machine's ~/.config/dotfiles/age/identity.txt here and set the vault recipient to it" } else { "see the key check above" }
        return {status: "decrypt-failed" detail: ("The private rclone.conf could not be decrypted with this machine's identity; " + $why + ".")}
    }
    let local_text = (open --raw $live | decode utf-8)
    let synced_text = ($result.stdout | into string)
    if ($local_text | hash sha256) == ($synced_text | hash sha256) { return {status: "match" detail: ""} }
    if (encrypted-rclone-config $local_text) or (encrypted-rclone-config $synced_text) {
        return {status: "differ" detail: "rclone.conf differs (password-encrypted rclone config; sections cannot be compared)."}
    }
    let diff = (compare-rclone-texts $local_text $synced_text)
    if $diff.identical { return {status: "match" detail: "Only formatting/comments differ."} }
    let crypt_changed = ($diff.changed | where crypt)
    # A changed `token` key alone in a non-crypt remote is normal OAuth refresh.
    let token_only = ($diff.only_local | is-empty) and ($diff.only_synced | is-empty) and ($crypt_changed | is-empty) and ($diff.changed | all {|c| $c.keys == ["token"] })
    {
        status: (if $token_only { "token-refresh" } else { "differ" })
        detail: ""
        only_local: $diff.only_local
        only_synced: $diff.only_synced
        changed: $diff.changed
    }
}

def ok-status [status: string] { $status in ["match" "token-refresh" "disabled" "none"] }

def print-rclone [r: record] {
    print-heading "rclone.conf"
    let level = if $r.status == "match" { "ok" } else if (ok-status $r.status) { "info" } else { "warn" }
    let label = match $r.status {
        "match" => "matches the private source"
        "token-refresh" => "matches; only OAuth tokens were refreshed (normal)"
        "disabled" => "synchronization disabled"
        "differ" => "DIFFERS from the private source"
        _ => $r.status
    }
    print-status $level "rclone" $label
    if not ($r.detail | is-empty) { kv "detail" $r.detail }
    for name in ($r.only_local? | default []) { kv "only on this machine" $name }
    for name in ($r.only_synced? | default []) { kv "only in private" $name }
    for c in ($r.changed? | default []) {
        kv (if $c.crypt { "crypt remote changed" } else { "remote changed" }) ($c.name + " (keys: " + ($c.keys | str join ", ") + ")")
    }
}

def print-rpool [r: record] {
    print-heading "rpool"
    if ($r.config_match? == null) {
        let level = if $r.status in ["not-installed"] { "info" } else { "warn" }
        print-status $level "rpool" $r.status
        if not ($r.detail? | default "" | is-empty) { kv "detail" $r.detail }
        return
    }
    print-status (if $r.config_match { "ok" } else { "warn" }) "settings" (if $r.config_match { "match the private source" } else { "DIFFER from the private source" })
    if not ($r.sections | is-empty) { kv "differing sections" ($r.sections | str join ", ") }
    let secret_label = match $r.secrets {
        "match" => "crypt passwords match"
        "none" => "no crypt remotes"
        "differ" => "crypt passwords DIFFER"
        "missing-in-private" => "this machine has crypt passwords the private source lacks"
        "missing-locally" => "private source has crypt passwords; this machine has no crypt remotes"
        "unverifiable" => "crypt passwords not compared (age identity unavailable)"
        "decrypt-failed" => "private crypt passwords cannot be decrypted with this machine's identity (key mismatch, or encrypted for another machine's key)"
        "decrypt-failed-local" => "freshly exported crypt passwords cannot be decrypted: the vault recipient is not this machine's identity"
        _ => $r.secrets
    }
    print-status (if $r.secrets in ["match" "none"] { "ok" } else { "warn" }) "crypt" $secret_label
    print-status (if $r.importable { "ok" } else { "warn" }) "import" (if $r.importable { "private artifact passes rpool import --dry-run" } else { "rpool import --dry-run FAILED" })
    if not ($r.import_detail | is-empty) { kv "import detail" $r.import_detail }
}

def print-keys [k: record] {
    print-heading "age keys"
    match $k.status {
        "match" => { print-status "ok" "keys" "this machine's identity belongs to a vault recipient" }
        "mismatch" => {
            print-status "warn" "keys" "MISMATCH: this machine's identity is not a vault recipient, so files encrypted for the vault cannot be decrypted here"
            kv "identity public key" $k.identity_recipient
            kv "vault recipients" ($k.recipients | str join ", ")
        }
        "no-vault" => { print-status "warn" "keys" "age vault is not configured (dotvault init)" }
        _ => { print-status "warn" "keys" $k.status }
    }
}

def print-ssh [r: record] {
    if $r.status == "none" { return }
    print-heading "ssh keys"
    let label = match $r.status {
        "match" => "all enrolled SSH keys match the private source"
        "no-vault" => "SSH keys are enrolled but no age vault is configured here"
        _ => "some enrolled SSH keys DIFFER from the private source"
    }
    print-status (if $r.status == "match" { "ok" } else { "warn" }) "ssh" $label
    for row in ($r.keys? | default []) {
        if (($row | describe) | str starts-with "record") and $row.status? != "match" {
            kv $row.name (match $row.status { "not-published" => "not published yet (run dotpush)" "missing-locally" => "not present on this machine (run dotpull)" "decrypt-failed" => "cannot be decrypted with this identity" "unverifiable" => "not compared (age/identity unavailable)" _ => $row.status })
        }
    }
}

def main [--json] {
    let context = (machine-context)
    let root = ($context.data_root | path expand)
    let keys = (try { identity-recipient-status } catch { {status: "unknown" identity_recipient: "" recipients: []} })
    let rclone = (try { verify-rclone $context $keys } catch {|err| {status: "error" detail: ($err.msg? | default "rclone verification failed")} })
    let rpool = (try { rpool-verify $root } catch {|err| {status: "error" detail: ($err.msg? | default "rpool verification failed")} })
    let ssh = (try { ssh-keys-verify $root } catch {|err| {status: "error" keys: [] detail: ($err.msg? | default "ssh verification failed")} })
    let keys_ok = ($keys.status in ["match" "no-vault"])
    let rclone_ok = (ok-status $rclone.status) and $keys_ok
    let rpool_ok = ($rpool.status in ["match" "not-installed"])
    let ssh_ok = ($ssh.status in ["match" "none"])
    if $json {
        print ({private_data: $root keys: $keys rclone: $rclone rpool: $rpool ssh: $ssh ok: ($rclone_ok and $rpool_ok and $ssh_ok)} | to json)
    } else {
        kv "Private data" $root
        print-keys $keys
        print-rclone $rclone
        print-rpool $rpool
        print-ssh $ssh
        print ""
        if $rclone_ok and $rpool_ok and $ssh_ok {
            print-status "ok" "verify" "rclone, rpool and SSH key settings are in sync with the private source."
        } else {
            print-status "warn" "verify" "Differences found. dotpush publishes this machine; dotpull applies the private source."
        }
    }
    if not ($rclone_ok and $rpool_ok and $ssh_ok) { exit 1 }
}
