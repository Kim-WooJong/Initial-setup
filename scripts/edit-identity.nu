#!/usr/bin/env nu
# Open the machine-local age vault identity in an editor so it can be set to the
# same private key as another machine. Editing is local only: no provider is
# read or written, and no secret value is printed. The file is created with
# owner-only permissions if missing, re-restricted after editing, and validated.
const ROOT = path self ..
const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
const VAULT = path self ./modules/vault.nu
const CONSOLE = path self ./modules/console.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $CORE [nu-home]
use $SAFETY [state-root private-directory private-file]
use $VAULT [vault-configured load-vault identity-recipient-status]
use $CONSOLE [print-status print-key-value print-text]
use $SUBPROCESS [run-command]

# Resolve the identity path from the vault policy, else the default location.
def identity-path [] {
    if (vault-configured) {
        let configured = (try { (load-vault).identity? | default "" | into string | str trim } catch { "" })
        if not ($configured | is-empty) { return ($configured | path expand) }
    }
    (state-root) | path join "age" "identity.txt"
}

# Public recipient derived from the identity file, or "" when it is not a usable
# age identity. Only the public key leaves this function.
def derived-recipient [identity: path] {
    if (which age-keygen | where type == "external" | is-empty) { return "" }
    let result = (run-command "age-keygen" ["-y" ($identity | into string)])
    if not $result.ok { return "" }
    $result.stdout | into string | lines | each {|l| $l | str trim } | where {|l| $l =~ '^age1[0-9a-z]+$' } | last | default ""
}

def main [
    --editor: string = "nvim"
    --editor-argument: string = "" # Optional single flag, e.g. --wait
] {
    let identity = (identity-path)
    let key_dir = ($identity | path dirname)

    if ($identity | path exists) and (($identity | path type) != "file") {
        error make {msg: ("The age identity path is not a regular file: " + ($identity | into string) + ". Nothing was changed.")}
    }
    if (which $editor | where type == "external" | is-empty) {
        error make {msg: ("Editor not found: " + $editor + ". Install it or pass --editor with an executable path.")}
    }

    # Create the directory and an empty identity file (owner-only) when missing,
    # so another machine's identity can be pasted into a fresh machine.
    private-directory $key_dir
    if not ($identity | path exists) {
        "" | save $identity
        print-status "info" "identity" ("Created a new empty identity file: " + ($identity | into string))
        print-text "info" "Paste the shared age identity (the AGE-SECRET-KEY line, and its comment lines) from your other machine, then save."
    }
    private-file $identity

    let before = (open --raw $identity | hash sha256)

    # Interactive editors need the real terminal; this is a direct external
    # invocation. Read LAST_EXIT_CODE immediately, before any other command.
    mut args = []
    if not ($editor_argument | is-empty) { $args = ($args | append $editor_argument) }
    $args = ($args | append ["--" ($identity | into string)])
    ^$editor ...$args
    let editor_exit = ($env.LAST_EXIT_CODE | default 1)

    # Re-restrict permissions whether or not the editor reported success: the
    # file may have been written before a non-zero exit.
    private-file $identity

    if $editor_exit != 0 {
        error make {msg: ("Editor " + $editor + " exited with code " + ($editor_exit | into string) + ". The identity file permissions were re-restricted; its contents were left as saved.")}
    }

    if (open --raw $identity | hash sha256) == $before {
        print-status "ok" "identity" "No changes were made to the identity file."
        return
    }

    let recipient = (derived-recipient $identity)
    if ($recipient | is-empty) {
        print-status "warn" "identity" "The saved file is not a usable age identity (age-keygen could not derive a public key). Edit it again and paste a valid AGE-SECRET-KEY line."
        return
    }
    print-status "ok" "identity" "Saved a valid age identity (owner-only permissions enforced)."
    print-key-value "This identity's public key: " $recipient

    if not (vault-configured) {
        print-text "info" "No vault policy exists yet. Run `dotvault init --recipient <this public key>` to create one that uses this identity, or copy the other machine's vault.nuon."
        return
    }
    let status = (try { identity-recipient-status } catch { {status: "unknown" recipients: []} })
    if $status.status == "match" {
        print-status "ok" "identity" "This identity matches the vault recipient. dotpull can decrypt the synchronized secrets."
    } else {
        print-status "warn" "identity" "This identity does NOT match the vault recipient yet."
        print-key-value "Vault recipients: " (($status.recipients? | default []) | str join ", ")
        print-text "info" "If this identity is the shared one, set the vault recipient to its public key: edit `dotvault` policy, or run `dotvault rekey --execute` to set the recipient to THIS identity (then dotpush re-encrypts for it)."
    }
}
