# Age-encrypted synchronization of selected SSH private keys.
#
# Enrollment is explicit (`dotvault ssh-key add <name>` / `add-all`). Each
# enrolled private key is encrypted to the vault recipients at
# <data_root>/secrets/ssh/<name>.age. The set of those .age files IS the
# manifest, so no extra metadata file is published. dotpush re-encrypts changed
# enrolled keys; dotpull decrypts them back into ~/.ssh/<name> with owner-only
# permissions, backing up any existing local key first. Public keys are not
# stored (they derive from the private key); plaintext private keys never enter
# the chezmoi tree and are never printed.
const CORE = path self ./core.nu
const VAULT = path self ./vault.nu
const SAFETY = path self ./safety.nu
const CONSOLE = path self ./console.nu
use $CORE [nu-home error-message]
use $VAULT [vault-configured load-vault]
use $SAFETY [state-root checked private-directory private-file]
use $CONSOLE [print-status print-warn print-key-value]

const PRIVATE_MARKER = "PRIVATE KEY-----"

def file-sha256 [file: path] {
    let target = ($file | path expand)
    if not ($target | path exists) { error make {msg: ("Expected file is missing: " + ($target | into string))} }
    if ($target | path type) != "file" { error make {msg: ("Expected a regular file: " + ($target | into string))} }
    open --raw $target | hash sha256
}

# Key basenames may include dots (e.g. "ssh-key.key") but not path separators.
export def ssh-key-name-valid [name: string] {
    $name =~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$'
}

def require-name [name: string] {
    if not (ssh-key-name-valid $name) {
        error make {msg: ("Invalid SSH key name: " + $name + ". Use the key's basename under ~/.ssh (letters, digits, '.', '_', '-'), not a path.")}
    }
}

export def ssh-dir [] { (nu-home) | path join ".ssh" }
export def local-key-path [name: string] { (ssh-dir) | path join $name }

def secrets-dir [root: path] { ($root | path expand) | path join "secrets" "ssh" }
def cipher-path [root: path name: string] { (secrets-dir $root) | path join ($name + ".age") }

# Enrolled key basenames = the published .age files under secrets/ssh.
export def enrolled-keys [root: path] {
    let dir = (secrets-dir $root)
    if not ($dir | path exists) or (($dir | path type) != "dir") { return [] }
    ls $dir
    | where type == "file"
    | get name
    | each {|f| $f | path basename }
    | where {|n| $n | str ends-with ".age" }
    | each {|n| $n | str substring 0..(($n | str length) - 5) }
    | where {|n| ssh-key-name-valid $n }
    | uniq
    | sort
}

def looks-private [file: path] {
    let bytes = (open --raw $file)
    let text = (try { $bytes | into string } catch { "" })
    $text | str contains $PRIVATE_MARKER
}

def recipients [] {
    let list = ((load-vault).recipients? | default [])
    if ($list | is-empty) { error make {msg: "The age vault has no recipients; run `dotvault init` first."} }
    $list
}

# Encrypt one local key into the source. Returns the ciphertext sha256.
def encrypt-key [root: path name: string] {
    let local = (local-key-path $name)
    let dir = (secrets-dir $root)
    private-directory $dir
    let dest = (cipher-path $root $name)
    let temp = (($dest | into string) + ".tmp-" + (random uuid))
    mut args = ["--encrypt" "--output" $temp]
    for r in (recipients) { $args = ($args | append ["--recipient" $r]) }
    $args = ($args | append ($local | into string))
    let before = (file-sha256 $local)
    try {
        checked "age" $args "Encrypt SSH key" | ignore
        if (file-sha256 $local) != $before { error make {msg: "SSH key changed during encryption; capture was not committed."} }
        mv --force $temp $dest
    } catch {|err|
        if ($temp | path exists) { rm --force $temp }
        error make {msg: (error-message $err "SSH key encryption failed.")}
    }
    private-file $dest
    file-sha256 $dest
}

# --- sync state (machine-local, not published) ---
def ssh-state-path [] { (state-root) | path join "ssh-key-sync-state.nuon" }
def read-ssh-state [] { if ((ssh-state-path) | path exists) { (open (ssh-state-path)).keys? | default {} } else { {} } }
def write-ssh-state [keys: record] {
    let file = (ssh-state-path)
    {schema_version: 1 keys: $keys} | to nuon | save --force $file
    private-file $file
}

def enroll-one [root: path name: string] {
    let plaintext_hash = (file-sha256 (local-key-path $name))
    let ciphertext_hash = (encrypt-key $root $name)
    write-ssh-state ((read-ssh-state) | upsert $name {plaintext_sha256: $plaintext_hash ciphertext_sha256: $ciphertext_hash})
}

# Basenames of files in ~/.ssh that are real private keys (contain the private
# marker). Excludes .pub, certs, config, known_hosts, PuTTY .ppk, and any name
# with unsupported characters.
export def scan-local-private-keys [] {
    let dir = (ssh-dir)
    if not ($dir | path exists) or (($dir | path type) != "dir") { return [] }
    ls $dir
    | where type == "file"
    | get name
    | each {|f| $f | path basename }
    | where {|n| (ssh-key-name-valid $n) and not ($n | str ends-with ".pub") }
    | where {|n| looks-private (local-key-path $n) }
    | uniq
    | sort
}

export def ssh-key-add [root: path name: string] {
    require-name $name
    if not (vault-configured) { error make {msg: "Enroll SSH keys only after `dotvault init`. Keys are encrypted to the vault recipients."} }
    if (which age | is-empty) { error make {msg: "age is required to encrypt SSH keys."} }
    let local = (local-key-path $name)
    if not ($local | path exists) or (($local | path type) != "file") {
        error make {msg: ("No such SSH private key: " + ($local | into string))}
    }
    if not (looks-private $local) {
        error make {msg: ($name + " does not look like a private key (no '" + $PRIVATE_MARKER + "'). Enroll the private key, not the .pub.")}
    }
    enroll-one $root $name
    print-status "ok" "ssh-key" ("Enrolled and encrypted: " + $name + ". Run dotpush to publish it.")
}

# Enroll every private key found in ~/.ssh that is not already enrolled.
export def ssh-key-add-all [root: path] {
    if not (vault-configured) { error make {msg: "Enroll SSH keys only after `dotvault init`. Keys are encrypted to the vault recipients."} }
    if (which age | is-empty) { error make {msg: "age is required to encrypt SSH keys."} }
    let found = (scan-local-private-keys)
    if ($found | is-empty) {
        print-status "warn" "ssh-key" ("No private keys found in " + ((ssh-dir) | into string) + " (looked for files containing '" + $PRIVATE_MARKER + "').")
        return
    }
    let existing = (enrolled-keys $root)
    let to_add = ($found | where {|n| $n not-in $existing })
    for name in $to_add { enroll-one $root $name }
    let already = ($found | where {|n| $n in $existing } | length)
    if ($to_add | is-empty) {
        print-status "ok" "ssh-key" ("All " + ($found | length | into string) + " private key(s) in ~/.ssh were already enrolled; nothing to add.")
    } else {
        print-status "ok" "ssh-key" ("Enrolled " + ($to_add | length | into string) + " key(s): " + ($to_add | str join ", ") + ". Already enrolled: " + ($already | into string) + ". Run dotpush to publish.")
    }
}

export def ssh-key-remove [root: path name: string] {
    require-name $name
    let cipher = (cipher-path $root $name)
    if not ($cipher | path exists) {
        print-status "warn" "ssh-key" ($name + " is not enrolled; nothing changed.")
        return
    }
    rm --force $cipher
    let state = (read-ssh-state)
    if ($name in ($state | columns)) { write-ssh-state ($state | reject $name) }
    print-status "ok" "ssh-key" ("Removed from sync: " + $name + " (the local key in ~/.ssh was kept). Run dotpush.")
}

export def ssh-key-list [root: path] {
    enrolled-keys $root | each {|name|
        {name: $name encrypted: ((cipher-path $root $name) | path exists) local: ((local-key-path $name) | path exists)}
    }
}

# --- Capture (dotpush) ---

export def capture-ssh-keys [root: path] {
    let keys = (enrolled-keys $root)
    if ($keys | is-empty) { return }
    if not (vault-configured) {
        print-warn "SSH keys are enrolled but no age vault is configured here; skipping SSH key capture."
        return
    }
    if (which age | is-empty) {
        print-warn "age is unavailable; skipping SSH key capture."
        return
    }
    mut state = (read-ssh-state)
    for name in $keys {
        let local = (local-key-path $name)
        if not ($local | path exists) {
            print-warn ("Enrolled SSH key is not present locally; keeping the existing encrypted copy: " + $name)
            continue
        }
        if ($local | path type) != "file" or not (looks-private $local) {
            print-warn ("Enrolled SSH key is not a usable private key locally; skipping: " + $name)
            continue
        }
        let plaintext_hash = (file-sha256 $local)
        let known = ($state | get --optional $name)
        let cipher = (cipher-path $root $name)
        if $known != null and ($known.plaintext_sha256? | default "") == $plaintext_hash and ($cipher | path exists) and (file-sha256 $cipher) == ($known.ciphertext_sha256? | default "") {
            continue
        }
        let ciphertext_hash = (encrypt-key $root $name)
        $state = ($state | upsert $name {plaintext_sha256: $plaintext_hash ciphertext_sha256: $ciphertext_hash})
        print-status "ok" "ssh-key" ("Encrypted updated SSH key: " + $name)
    }
    write-ssh-state $state
}

# --- Restore (dotpull): prepare / commit / discard ---

def ssh-backups-root [] { (state-root) | path join "ssh-restore-backups" }

export def discard-prepared-ssh [prepared: record] {
    if ($prepared.status? | default "") != "prepared" { return }
    let stage = ($prepared.stage_root? | default "" | str trim)
    if ($stage | is-empty) { return }
    let path = ($stage | path expand)
    if ($path | path exists) {
        try { rm --recursive --force $path } catch {
            print-warn ("Restricted prepared SSH plaintext remains at: " + ($path | into string))
        }
    }
}

export def prepare-ssh-restore [root: path --discard-local] {
    let keys = (enrolled-keys $root)
    if ($keys | is-empty) { return {status: "disabled"} }
    if not (vault-configured) {
        error make {msg: "The pulled source enrolls SSH keys, but this machine has no age vault identity. Restore the matching offline identity, then retry dotpull. No live configuration was changed."}
    }
    let config = (load-vault)
    let identity = ($config.identity | path expand)
    if not ($identity | path exists) or (($identity | path type) != "file") {
        error make {msg: "The age identity for SSH key restore is missing. Recover it from your offline backup, then retry dotpull."}
    }
    if (which age | is-empty) { error make {msg: "age is required to restore SSH keys before dotpull can change local files."} }

    let state = (read-ssh-state)
    let stage_root = ((state-root) | path join "ssh-pull-staging" (random uuid))
    private-directory $stage_root
    mut items = []
    let prepared = (try {
        for name in $keys {
            let cipher = (cipher-path $root $name)
            if ($cipher | path type) != "file" { error make {msg: ("Pulled SSH ciphertext is not a regular file: " + $name)} }
            let cipher_hash = (file-sha256 $cipher)
            let dest = (local-key-path $name)
            let local_hash = if ($dest | path exists) and (($dest | path type) == "file") { file-sha256 $dest } else { "" }
            let known = ($state | get --optional $name)
            if not $discard_local and not ($local_hash | is-empty) and $known != null and ($known.ciphertext_sha256? | default "") == $cipher_hash {
                continue
            }
            let plaintext = ($stage_root | path join $name)
            checked "age" ["--decrypt" "--identity" ($identity | into string) "--output" $plaintext $cipher] ("Decrypt SSH key " + $name) | ignore
            private-file $plaintext
            if (file-sha256 $cipher) != $cipher_hash { error make {msg: ("Pulled SSH ciphertext changed while decrypting: " + $name)} }
            $items = ($items | append {
                name: $name
                plaintext: ($plaintext | into string)
                destination: ($dest | into string)
                plaintext_sha256: (file-sha256 $plaintext)
                ciphertext_sha256: $cipher_hash
            })
        }
        {status: (if ($items | is-empty) { "current" } else { "prepared" }) stage_root: ($stage_root | into string) items: $items}
    } catch {|err|
        if ($stage_root | path exists) { try { rm --recursive --force $stage_root } catch { } }
        error make {msg: (error-message $err "Incoming SSH key authentication failed before local apply. No live configuration was changed.")}
    })
    if ($prepared.status == "current") { discard-prepared-ssh $prepared; return {status: "current"} }
    print-status "ok" "ssh-key" (($items | length | into string) + " SSH key(s) authenticated; local apply may proceed.")
    $prepared
}

def backup-existing-key [name: string destination: path] {
    if not ($destination | path exists) { return null }
    if ($destination | path type) != "file" { error make {msg: ("Existing SSH key path is not a regular file: " + ($destination | into string))} }
    let root = ((ssh-backups-root) | path join (random uuid))
    private-directory $root
    let backup = ($root | path join $name)
    cp $destination $backup
    private-file $backup
    if (file-sha256 $destination) != (file-sha256 $backup) {
        rm --recursive --force $root
        error make {msg: ("SSH key backup verification failed for " + $name + "; restore was not started.")}
    }
    $root
}

export def commit-prepared-ssh [prepared: record] {
    if ($prepared.status? | default "") != "prepared" { return null }
    mut state = (read-ssh-state)
    mut restored = []
    for item in $prepared.items {
        let plaintext = ($item.plaintext | path expand)
        if (file-sha256 $plaintext) != ($item.plaintext_sha256 | into string) {
            discard-prepared-ssh $prepared
            error make {msg: ("Prepared SSH key changed before commit: " + $item.name)}
        }
        let dest = ($item.destination | path expand)
        let recovery = (backup-existing-key $item.name $dest)
        mkdir ($dest | path dirname)
        let transaction = (($dest | into string) + ".initial-setup-ssh-" + (random uuid))
        cp $plaintext $transaction
        private-file $transaction
        let commit = (try {
            mv --force $transaction $dest
            private-file $dest
            if (file-sha256 $dest) != ($item.plaintext_sha256 | into string) { error make {msg: "Committed SSH key failed verification."} }
            null
        } catch {|err| $err })
        if $commit != null {
            if ($transaction | path exists) { rm --force $transaction }
            discard-prepared-ssh $prepared
            error make {msg: (error-message $commit ("SSH key commit failed: " + $item.name))}
        }
        $state = ($state | upsert $item.name {plaintext_sha256: ($item.plaintext_sha256 | into string) ciphertext_sha256: ($item.ciphertext_sha256 | into string)})
        $restored = ($restored | append {name: $item.name recovery: $recovery})
        print-status "ok" "ssh-key" ("Restored SSH key: " + $item.name)
        if $recovery != null { print-key-value "  previous key backup" ($recovery | into string) }
    }
    write-ssh-state $state
    discard-prepared-ssh $prepared
    {changed: (not ($restored | is-empty)) restored: $restored}
}

# --- Read-only verification for dotctl verify ---

export def ssh-keys-verify [root: path] {
    let keys = (enrolled-keys $root)
    if ($keys | is-empty) { return {status: "none" keys: []} }
    if not (vault-configured) { return {status: "no-vault" keys: $keys} }
    let config = (load-vault)
    let identity = ($config.identity | path expand)
    let can_decrypt = ((which age | is-empty) == false) and ($identity | path exists)
    let rows = ($keys | each {|name|
        let cipher = (cipher-path $root $name)
        let dest = (local-key-path $name)
        let s = if not ($dest | path exists) { "missing-locally" } else if not $can_decrypt { "unverifiable" } else {
            let stage = ((state-root) | path join "ssh-verify" (random uuid))
            let r = (try {
                private-directory $stage
                let out = ($stage | path join $name)
                checked "age" ["--decrypt" "--identity" ($identity | into string) "--output" $out $cipher] ("Decrypt SSH key " + $name) | ignore
                if (open --raw $out | hash sha256) == (open --raw $dest | hash sha256) { "match" } else { "differ" }
            } catch { "decrypt-failed" })
            if ($stage | path exists) { rm --recursive --force $stage }
            $r
        }
        {name: $name status: $s}
    })
    let ok = ($rows | all {|r| $r.status == "match" })
    {status: (if $ok { "match" } else { "differ" }) keys: $rows}
}
