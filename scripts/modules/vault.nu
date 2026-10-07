# age-backed, explicit-allowlist secret storage. The remote never supplies a
# plaintext destination path. SSH and age private keys are never capture targets.
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
const CONSOLE = path self ./console.nu
const STATE_SCHEMA = path self ./state-schema.nu
use $CORE [nu-home machine-context error-message failure-envelope captured-failure]
use $SAFETY [state-root checked private-directory private-file atomic-record disjoint-paths]
use $STATE_SCHEMA [assert-state-schema-readable detect-state-schema current-state-schema]
use $CONSOLE [print-heading print-status print-key-value print-choice print-text]
const SUBPROCESS = path self ./subprocess.nu
use $SUBPROCESS [run-command]

export def vault-config-path [] { (state-root) | path join "vault.nuon" }
export def vault-configured [] { (vault-config-path) | path exists }

def load-vault-record [file: path] {
    if not ($file | path exists) { error make {msg: "Secret vault is not configured. Run dotvault init first."} }
    if ($file | path type) != "file" { error make {msg: ("Vault policy must be a regular file: " + ($file | into string))} }
    let loaded = (try { open --raw $file | from nuon } catch {|err|
        error make {msg: ("Unable to parse vault policy as NUON: " + ($file | into string) + (char nl) + (error-message $err))}
    })
    if not (($loaded | describe) | str starts-with "record") {
        error make {msg: ("Vault policy must contain a NUON record: " + ($file | into string))}
    }
    $loaded
}

export def validate-vault-state [config: record] {
    let schema = (assert-state-schema-readable "vault" $config)
    if $schema.detected < 1 {
        error make {msg: ("Unsupported legacy vault schema " + ($schema.detected | into string) + "; automatic migration starts at schema 1.")}
    }

    let identity = (try { $config.identity? | default "" | into string | str trim } catch { "" })
    if ($identity | is-empty) { error make {msg: "Vault policy requires a non-empty age identity path."} }

    let recipients = ($config.recipients? | default [])
    if not (($recipients | describe) | str starts-with "list") or ($recipients | is-empty) {
        error make {msg: "Configure at least one age recipient."}
    }
    for recipient in $recipients {
        let text = (try { $recipient | into string } catch { "" })
        if not ($text =~ '^age1[0-9a-z]+$') { error make {msg: "Only native age public recipients are accepted."} }
    }

    let entries = ($config.entries? | default [])
    # Nushell describes a homogeneous list of records as a table.
    let entries_type = ($entries | describe)
    if not (($entries_type | str starts-with "list") or ($entries_type | str starts-with "table")) {
        error make {msg: "Vault entries must be a list."}
    }
    mut names = []
    for entry in $entries {
        if not (($entry | describe) | str starts-with "record") { error make {msg: "Every vault entry must be a record."} }
        let name = (try { $entry.name? | default "" | into string | str trim } catch { "" })
        if not ($name =~ '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$') { error make {msg: "Vault entries require valid unique names."} }
        let local = (try { $entry.local? | default "" | into string | str trim } catch { "" })
        if ($local | is-empty) { error make {msg: ("Vault entry " + $name + " requires a local path.")} }
        for field in ["last_plaintext_sha256" "last_ciphertext_sha256"] {
            let value = ($entry | get --optional $field)
            if $value != null {
                let hash = (try { $value | into string | str trim } catch { "" })
                if not ($hash =~ '^[a-f0-9]{64}$') { error make {msg: ("Vault entry " + $name + " has an invalid " + $field + ".")} }
            }
        }
        $names = ($names | append $name)
    }
    if ($names | uniq | length) != ($names | length) { error make {msg: "Duplicate vault entry names."} }
    $schema
}

export def read-vault-file [file: path] {
    let config = (load-vault-record $file)
    validate-vault-state $config | ignore
    $config
}

export def load-vault [] { read-vault-file (vault-config-path) }

export def canonical-vault [config: record] {
    let schema = (validate-vault-state $config)
    if $schema.detected == (current-state-schema "vault") and $schema.source_field == "schema_version" {
        return $config
    }
    if $schema.detected != 1 and not ($schema.detected == 2 and $schema.source_field in ["version" "both"]) {
        error make {msg: ("No vault migration is defined from schema " + ($schema.detected | into string) + ".")}
    }

    mut migrated = $config
    if (($migrated | columns) | any {|name| $name == "version" }) {
        $migrated = ($migrated | reject version)
    }
    $migrated = ($migrated | upsert schema_version (current-state-schema "vault"))
    validate-vault-state $migrated | ignore
    $migrated
}

def write-vault [config: record] {
    let file = (vault-config-path)
    let canonical = (canonical-vault $config)
    let schema = (detect-state-schema "vault" $canonical)
    if $schema.status != "current" { error make {msg: "Refusing to write a non-current vault policy."} }
    atomic-record $file $canonical
    private-file $file
    let saved = (read-vault-file $file)
    if $saved != $canonical { error make {msg: "Vault policy verification failed after atomic write."} }
    $saved
}

def resolve-vault-entry [name: string] {
    if not ($name =~ '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$') { error make { msg: "Invalid vault entry name." } }
    let config = (load-vault)
    let rows = ($config.entries | where name == $name)
    if ($rows | length) != 1 { error make { msg: "Secret must be explicitly registered in the machine-local vault.nuon." } }
    let entry = ($rows | first)
    let local = ($entry.local | path expand)
    let home = (nu-home)
    # Reject the whole SSH directory, not only familiar default key names.
    disjoint-paths $local ($home | path join ".ssh")
    disjoint-paths $local ((state-root) | path join "age")
    let context = (machine-context)
    disjoint-paths $local $context.data_root
    disjoint-paths $local $context.tools_root
    let identity = ($config.identity | path expand)
    disjoint-paths $identity $context.data_root
    disjoint-paths $identity $context.tools_root
    if $local == $identity { error make { msg: "The decryption identity cannot be a capture target." } }
    $entry | upsert local ($local | into string)
}

export def ciphertext-path [name: string] {
    resolve-vault-entry $name | ignore
    (machine-context).data_root | path expand | path join "secrets" ($name + ".age")
}

# Public key/path output is machine data: decode strictly, never use lossy
# diagnostic conversion and never include rejected bytes in an error message.
export def vault-command-text [value: any label: string]: nothing -> string {
    let kind = ($value | describe)
    let text = if $kind == "string" {
        $value
    } else if $kind == "binary" {
        let decoded = (try { $value | decode utf-8 } catch { null })
        if $decoded == null { error make {msg: ($label + " returned non-UTF-8 output.")} }
        if ($decoded | encode utf-8) != $value {
            error make {msg: ($label + " returned invalid UTF-8 output; no bytes were guessed.")}
        }
        $decoded
    } else {
        error make {msg: ($label + " did not return text.")}
    }
    $text | str trim --left --char (char --unicode feff) | str trim
}

def discover-rclone-config-path [] {
    if (which rclone | is-empty) {
        error make {msg: "rclone is not installed, so its configuration path cannot be discovered."}
    }

    let result = (checked "rclone" ["config" "file"] "Find local rclone config")
    let rows = (vault-command-text $result "rclone config file" | lines | each {|line| $line | str trim } | where {|line| not ($line | is-empty) })
    if ($rows | is-empty) { error make {msg: "rclone config file returned no path."} }
    let local = ($rows | last)
    let absolute = if $nu.os-info.name == "windows" {
        ($local =~ '^[A-Za-z]:[\\/]') or ($local | str starts-with '\\')
    } else { $local | str starts-with "/" }
    if not $absolute { error make {msg: "rclone config file did not return an absolute path."} }
    $local | path expand | into string
}

# Read-only probe for other modules (e.g. rpool artifact sync): the absolute
# active rclone.conf path, or null when rclone is missing or discovery fails.
# Never reads the file, registers entries or changes vault state.
# Does the local age identity belong to a vault recipient? Files encrypted to
# the vault recipients can only be decrypted here when it does. Public keys
# only: the identity's private key is never read by this module.
export def identity-recipient-status [] {
    if not (vault-configured) { return {status: "no-vault" identity_recipient: "" recipients: []} }
    let config = (try { load-vault } catch { return {status: "invalid-vault" identity_recipient: "" recipients: []} })
    let recipients = ($config.recipients? | default [] | each {|r| $r | into string | str trim })
    let identity = ($config.identity? | default "" | into string | str trim)
    if ($identity | is-empty) or not ($identity | path expand | path exists) { return {status: "no-identity" identity_recipient: "" recipients: $recipients} }
    if (which age-keygen | where type == "external" | is-empty) { return {status: "unknown" identity_recipient: "" recipients: $recipients} }
    let result = (run-command "age-keygen" ["-y" ($identity | path expand | into string)])
    let public = ($result.stdout? | default "" | into string | lines | each {|l| $l | str trim } | where {|l| $l =~ '^age1[0-9a-z]+$' } | last | default "")
    if not $result.ok or ($public | is-empty) { return {status: "unreadable-identity" identity_recipient: "" recipients: $recipients} }
    {status: (if $public in $recipients { "match" } else { "mismatch" }) identity_recipient: $public recipients: $recipients}
}

# Can the local identity decrypt this age file? In memory only; the
# plaintext is discarded and never printed.
export def ciphertext-decryptable [file: path] {
    if not ($file | path exists) or not (vault-configured) { return false }
    let identity = (try { (load-vault).identity? | default "" | into string | str trim } catch { "" })
    if ($identity | is-empty) or not ($identity | path expand | path exists) { return false }
    (run-command "age" ["--decrypt" "--identity" ($identity | path expand | into string) ($file | into string)] --sensitive).ok
}

# Make this machine's identity the vault's only recipient (after a mismatch).
# Preview by default. Previously encrypted copies stay as they are until the
# next dotpush re-encrypts them; machines that only hold an old key then need
# this identity (restore it from the same offline backup).
export def rekey-vault-to-identity [--execute] {
    let status = (identity-recipient-status)
    if $status.status not-in ["match" "mismatch"] {
        error make {msg: ("Cannot rekey: identity/recipient check returned " + $status.status + ". Make sure `dotvault init` was run and age-keygen is installed.")}
    }
    let target = [$status.identity_recipient]
    print-status "info" "vault" ("current recipients : " + ($status.recipients | str join ", "))
    print-status "info" "vault" ("this identity      : " + $status.identity_recipient)
    if $status.recipients == $target {
        print-status "ok" "vault" "The vault already uses only this machine's identity; nothing to change."
        return
    }
    print-status "warn" "vault" "After rekey + dotpush, encrypted copies are readable only with THIS identity (~/.config/dotfiles/age/identity.txt). Copy that file (offline backup) to your other machines."
    if not $execute {
        print-status "info" "vault" "Preview only. Re-run with --execute, then run dotpush."
        return
    }
    let backup = ((state-root) | path join "vault-backups" (date now | format date "%Y%m%d-%H%M%S"))
    private-directory $backup
    cp (vault-config-path) ($backup | path join "vault.nuon")
    write-vault ((load-vault) | upsert recipients $target) | ignore
    print-status "ok" "vault" ("Vault recipient set to this identity. Previous policy backup: " + ($backup | into string))
    print-status "info" "vault" "Next: run dotpush to re-encrypt rclone.conf and rpool crypt passwords for this key, then dotctl verify."
}

export def active-rclone-config-path [] {
    try { discover-rclone-config-path } catch { null }
}

# Ensure the machine-local vault knows where rclone.conf lives. Existing vaults
# from <=0.17 keep working: the rclone entry is registered/migrated lazily and
# the former opt-in flags are upgraded because dotpush/dotpull now own this sync.
export def ensure-rclone-entry [] {
    if not (vault-configured) {
        error make {msg: "Encrypted rclone synchronization requires the age vault. Run `dotvault init` (or `dotctl config vault init`) once, and keep an offline backup of the age identity."}
    }

    let config = (load-vault)
    let rows = ($config.entries | where name == "rclone")
    if ($rows | length) > 1 { error make {msg: "Duplicate rclone vault entries are not allowed."} }
    let active_local = (discover-rclone-config-path)

    if ($rows | length) == 1 {
        let current = ($rows | first)
        let upgraded = (
            $current
            | upsert local $active_local
            | upsert auto_capture true
            | upsert auto_restore true
        )
        if $upgraded != $current {
            let entries = ($config.entries | each {|entry| if $entry.name == "rclone" { $upgraded } else { $entry } })
            write-vault ($config | upsert entries $entries) | ignore
        }
        return (resolve-vault-entry "rclone")
    }

    let entry = {name: "rclone" local: $active_local auto_capture: true auto_restore: true}
    write-vault ($config | upsert entries ($config.entries | append $entry)) | ignore
    resolve-vault-entry "rclone"
}

export def record-secret-sync-state [name: string plaintext_sha256: string ciphertext_sha256: string] {
    if not ($plaintext_sha256 =~ '^[a-f0-9]{64}$') or not ($ciphertext_sha256 =~ '^[a-f0-9]{64}$') {
        error make {msg: "Secret synchronization hashes must be SHA-256 values."}
    }
    resolve-vault-entry $name | ignore
    let config = (load-vault)
    let entries = ($config.entries | each {|entry|
        if $entry.name == $name {
            $entry | upsert last_plaintext_sha256 $plaintext_sha256 | upsert last_ciphertext_sha256 $ciphertext_sha256
        } else {
            $entry
        }
    })
    write-vault ($config | upsert entries $entries) | ignore
}

def vault-init-preflight [recipient: string] {
    let config_file = (vault-config-path)
    if ($config_file | path exists) {
        error make {msg: "VAULT_ALREADY_EXISTS: vault.nuon already exists. Use dotvault status; do not delete the policy or age identity just to retry init."}
    }
    if not ($recipient | is-empty) and not ($recipient =~ '^age1[0-9a-z]+$') {
        error make {msg: "VAULT_RECIPIENT_INVALID: supply one native age public recipient, never a private key."}
    }
    # Only the machine's path configuration is required. Provider configuration,
    # remote availability, export blockers and baseline hashes are irrelevant.
    let context = (machine-context)
    let key_dir = ((state-root) | path join "age")
    let identity = ($key_dir | path join "identity.txt")
    disjoint-paths $key_dir $context.data_root
    disjoint-paths $key_dir $context.tools_root
    if ($key_dir | path exists) and (($key_dir | path type) != "dir") {
        error make {msg: "VAULT_KEY_PATH_INVALID: the identity directory is not a regular directory. Nothing was removed."}
    }
    if ($identity | path exists) and (($identity | path type) != "file") {
        error make {msg: "VAULT_IDENTITY_PATH_INVALID: identity.txt is not a regular file. Nothing was removed."}
    }
    let missing = (["age" "age-keygen"] | where {|program| (which $program | is-empty) })
    if not ($missing | is-empty) {
        let installation = if $nu.os-info.name == "windows" {
            "Install the age package: winget install --id FiloSottile.age --exact. Then open a new terminal."
        } else if $nu.os-info.name == "macos" {
            "Install the age package: brew install age. Then open a new terminal."
        } else {
            "Install age and age-keygen using your distribution's package manager, then retry."
        }
        error make {msg: ("VAULT_DEPENDENCY_MISSING: " + ($missing | str join ", ") + ". " + $installation)}
    }
    # Version probes do not create a key or read a secret. Installation is never
    # attempted here and a broken executable is not treated as a missing one.
    checked "age" ["--version"] "VAULT_TOOL_UNUSABLE: age --version" | ignore
    checked "age-keygen" ["--version"] "VAULT_TOOL_UNUSABLE: age-keygen --version" | ignore
    {config_file: $config_file key_dir: $key_dir identity: $identity recipient: $recipient}
}

export def initialize-vault [recipient: string --check] {
    print-status "info" "vault:init" "Checking local paths and age prerequisites" --stderr
    let plan = (vault-init-preflight $recipient)
    if $check {
        print-status "ok" "ok" "Vault preflight passed. No keys, policy files, ACLs, locks or provider state were changed."
        return
    }
    let config_file = $plan.config_file
    let key_dir = $plan.key_dir
    let identity = $plan.identity
    print-status "info" "vault:init" "Protecting the local identity directory" --stderr
    private-directory $key_dir
    mut public_key = $recipient
    if ($public_key | is-empty) {
        if not ($identity | path exists) {
            print-status "info" "vault:init" "Generating an age identity (never overwriting an existing key)" --stderr
            checked "age-keygen" ["-o" $identity] "Generate age identity" | ignore
        } else {
            print-status "info" "vault:init" "Reusing the existing age identity" --stderr
        }
        print-status "info" "vault:init" "Protecting the identity and deriving its public recipient" --stderr
        private-file $identity
        let result = (checked "age-keygen" ["-y" $identity] "Derive public recipient from the existing identity")
        $public_key = (vault-command-text $result "age-keygen -y")
    }
    if not ($public_key =~ '^age1[0-9a-z]+$') {
        error make {msg: "VAULT_RECIPIENT_INVALID: age-keygen must return exactly one native public recipient. The identity was not replaced."}
    }
    mut entries = []
    if not (which rclone | is-empty) {
        print-status "info" "vault:init" "Discovering the optional local rclone configuration path" --stderr
        # Discovery failure must not invalidate a usable age key. A failed probe
        # registers nothing; it never guesses a path or captures credentials.
        let discovered = (try {
            let result = (checked "rclone" ["config" "file"] "Find local rclone config")
            let rows = (vault-command-text $result "rclone config file" | lines | where {|line| not ($line | str trim | is-empty) })
            if ($rows | is-empty) { error make {msg: "rclone config file returned no path."} }
            let local = ($rows | last | str trim)
            let absolute = if $nu.os-info.name == "windows" {
                ($local =~ '^[A-Za-z]:[\\/]') or ($local | str starts-with '\\')
            } else { $local | str starts-with "/" }
            if not $absolute { error make {msg: "rclone config file did not return an absolute path."} }
            {name: "rclone" local: $local auto_capture: true auto_restore: true}
        } catch {
            print-status "warn" "warn" "rclone path discovery failed. Vault initialization can continue with no rclone entry; register its local path in vault.nuon before migration. No credentials were copied." --stderr
            null
        })
        if $discovered != null { $entries = [$discovered] }
    }
    print-status "info" "vault:init" "Preparing owner-only vault policy" --stderr
    let stage = ((state-root) | path join (".vault-init-" + (random uuid)))
    let candidate = ($stage | path join "vault.nuon")
    try {
        private-directory $stage
        let policy = {schema_version: 2 identity: ($identity | into string) recipients: [$public_key] entries: $entries}
        validate-vault-state $policy | ignore
        $policy | to nuon | save $candidate
        private-file $candidate
        if ($config_file | path exists) { error make {msg: "Vault policy appeared during initialization; it was not overwritten."} }
        # Rename an already protected file on the same filesystem. Do not commit
        # policy first and then discover an ACL failure that leaves init blocked.
        mv --no-clobber $candidate $config_file
        if ($candidate | path exists) { error make {msg: "Vault policy could not be committed without overwriting another file."} }
    } catch {|err|
        try { if ($stage | path exists) { rm --recursive --force $stage } } catch {
            print-status "warn" "warn" "A restricted vault-init staging directory remains; no identity was deleted." --stderr
        }
        # Keep the original record/labels rather than substituting only its msg.
        error make $err
    }
    try { rm --recursive --force $stage } catch {
        print-status "warn" "warn" "Vault is initialized; the empty staging directory could not be removed." --stderr
    }
    print-status "ok" "ok" ("Vault policy: " + ($config_file | into string))
    print-key-value "Public recipient: " $public_key
    if ($recipient | is-empty) {
        print-text "warn" "Keep a separate offline backup of identity.txt. It is never synchronized."
    } else {
        print-text "warn" "Recipient-only policy: no private key was generated. Restore requires the matching private identity, not merely a local file with the expected name."
    }
    print-text "info" "Registered rclone.conf is encrypted automatically by dotpush and restored automatically by dotpull."
}

export def capture-secret [name: string] {
    let entry = (resolve-vault-entry $name)
    let config = (load-vault)
    let local = $entry.local
    if not ($local | path exists) or (($local | path type) != "file") {
        error make { msg: "Secret capture requires an existing regular file." }
    }
    # Do not accidentally encrypt a renamed SSH/age identity.
    let bytes = (open --raw $local)
    let text = (try { $bytes | into string } catch { "" })
    if ($text | str contains ("PRIVATE" + " KEY-----")) or ($text | str contains ("AGE-SECRET-" + "KEY-")) {
        error make { msg: "Private key material is excluded from the secret vault." }
    }
    let before = ($bytes | hash sha256)
    let destination = (ciphertext-path $name)
    mkdir ($destination | path dirname)
    let temp = (($destination | into string) + ".tmp-" + (random uuid))
    mut args = ["--encrypt" "--output" $temp]
    for recipient in $config.recipients { $args = ($args | append ["--recipient" $recipient]) }
    $args = ($args | append $local)
    try {
        checked "age" $args "Encrypt secret" | ignore
        if (open --raw $local | hash sha256) != $before { error make { msg: "Secret changed during encryption; capture was not committed." } }
        mv --force $temp $destination
    } catch {|err|
        if ($temp | path exists) { rm --force $temp }
        error make { msg: (error-message $err "Secret capture failed.") }
    }
    print-status "ok" "ok" ("Encrypted capture: " + $name + ". Run dotpush to publish it.")
}

def restore-secret-source [name: string force: bool source: path] {
    let entry = (resolve-vault-entry $name)
    let config = (load-vault)
    let destination = ($entry.local | path expand)
    if not ($source | path exists) { error make { msg: "No encrypted copy exists for this entry." } }
    if ($source | path type) != "file" { error make {msg: "Encrypted secret source must be a regular file."} }
    if not ($config.identity | path exists) { error make { msg: "Local age identity is missing. Recover it from your offline backup." } }
    if ($destination | path exists) and not $force { error make { msg: "Destination exists. Review it before using dotvault restore NAME --force." } }
    let parent = ($destination | path dirname)
    mkdir $parent
    let temp_dir = ($parent | path join (".initial-setup-secret-" + (random uuid)))
    private-directory $temp_dir
    let temp = ($temp_dir | path join "plaintext")
    let previous = ($temp_dir | path join "previous")
    mut committed = false
    let restore_result = (try {
        checked "age" ["--decrypt" "--identity" ($config.identity | path expand) "--output" $temp $source] "Decrypt/authenticate secret" | ignore
        private-file $temp
        # Keep the old value in the restricted sibling directory until replacement
        # and permissions succeed. A process kill may require manual recovery.
        if ($destination | path exists) { mv $destination $previous }
        mv --force $temp $destination
        $committed = true
        private-file $destination
        null
    } catch {|err| failure-envelope $err })
    let restore_failure = (captured-failure $restore_result)
    if $restore_failure != null {
        let err = $restore_failure
        if ($previous | path exists) {
            if ($destination | path exists) { rm --force $destination }
            mv $previous $destination
        } else if $committed and ($destination | path exists) { rm --force $destination }
        if ($temp_dir | path exists) { rm --recursive --force $temp_dir }
        error make { msg: (error-message $err "Secret restore failed.") }
    }
    # The restore has committed. Failure to delete the restricted recovery
    # directory must never erase the newly restored destination.
    try { rm --recursive --force $temp_dir } catch {
        print-status "warn" "warn" ("Secret restored, but restricted recovery files remain at: " + ($temp_dir | into string))
    }
    print-status "ok" "ok" ("Restored secret: " + $name)
}

export def restore-secret [name: string force: bool] {
    restore-secret-source $name $force (ciphertext-path $name)
}

def rclone-config-sha256 [file: string] {
    let path = ($file | path expand)

    if not ($path | path exists) {
        return null
    }

    if ($path | path type) != "file" {
        error make {
            msg: $"Rclone config is not a regular file: ($path)"
        }
    }

    open --raw $path | hash sha256
}

def inspect-rclone-remotes [file: string] {
    let path = ($file | path expand)

    if not ($path | path exists) {
        return {
            ok: false
            remotes: []
            detail: "file does not exist"
        }
    }

    if (which rclone | is-empty) {
        return {
            ok: false
            remotes: []
            detail: "rclone is not available"
        }
    }

    try {
        let result = (checked "rclone" ["listremotes" "--config" $path] "Inspect rclone configuration")

        let remotes = (
            vault-command-text $result "rclone listremotes"
            | lines
            | each {|line| $line | str trim }
            | where {|line| not ($line | is-empty) }
        )

        {
            ok: true
            remotes: $remotes
            detail: ""
        }
    } catch {|err|
        {
            ok: false
            remotes: []
            detail: (error-message $err "Unable to inspect rclone remotes.")
        }
    }
}

def remote-summary [info: record] {
    if not $info.ok {
        return "(unavailable)"
    }

    if ($info.remotes | is-empty) {
        return "(none)"
    }

    $info.remotes | str join ", "
}

def create-rclone-reconcile-backup [
    active: string
    legacy: string
] {
    let active_path = ($active | path expand)
    let legacy_path = ($legacy | path expand)

    let root = (
        (state-root)
        | path join "rclone-reconcile"
        | path join (random uuid)
    )

    private-directory $root

    let active_backup = ($root | path join "active-rclone.conf")
    let legacy_backup = ($root | path join "legacy-rclone.conf")

    let active_exists = ($active_path | path exists)
    let legacy_exists = ($legacy_path | path exists)

    try {
        if $active_exists {
            cp $active_path $active_backup
            private-file $active_backup

            if (rclone-config-sha256 $active_path) != (rclone-config-sha256 $active_backup) {
                error make {
                    msg: "Active rclone config backup verification failed."
                }
            }
        }

        if $legacy_exists {
            cp $legacy_path $legacy_backup
            private-file $legacy_backup

            if (rclone-config-sha256 $legacy_path) != (rclone-config-sha256 $legacy_backup) {
                error make {
                    msg: "Legacy rclone config backup verification failed."
                }
            }
        }

        {
            root: $root
            active_backup: $active_backup
            legacy_backup: $legacy_backup
            active_existed: $active_exists
            legacy_existed: $legacy_exists
        }
    } catch {|err|
        try {
            if ($root | path exists) {
                rm --recursive --force $root
            }
        }

        error make {
            msg: (error-message $err "Failed to create rclone reconciliation backup.")
        }
    }
}

def restore-rclone-reconcile-backup [
    backup: record
    active: string
    legacy: string
] {
    let active_path = ($active | path expand)
    let legacy_path = ($legacy | path expand)

    if $backup.active_existed {
        mkdir ($active_path | path dirname)
        cp --force $backup.active_backup $active_path
        private-file $active_path
    } else if ($active_path | path exists) {
        rm --force $active_path
    }

    if $backup.legacy_existed {
        mkdir ($legacy_path | path dirname)
        cp --force $backup.legacy_backup $legacy_path
        private-file $legacy_path
    } else if ($legacy_path | path exists) {
        rm --force $legacy_path
    }
}

def remove-rclone-reconcile-backup [backup: record] {
    if ($backup.root | path exists) {
        rm --recursive --force $backup.root
    }
}

def reconcile-rclone-configs [
    active: string
    legacy: string
] {
    let active_path = ($active | path expand)
    let legacy_path = ($legacy | path expand)

    if not ($legacy_path | path exists) {
        error make {
            msg: "No legacy plaintext rclone copy exists."
        }
    }

    let active_exists = ($active_path | path exists)

    if $active_exists {
        let active_hash = (rclone-config-sha256 $active_path)
        let legacy_hash = (rclone-config-sha256 $legacy_path)

        if $active_hash == $legacy_hash {
            return {
                cancelled: false
                changed: false
                backup: null
                selected: "same"
                legacy_sha256: $legacy_hash
            }
        }

        let active_info = (inspect-rclone-remotes $active_path)
        let legacy_info = (inspect-rclone-remotes $legacy_path)

        print ""
        print-text "heading" "============================================================"
        print-heading "Rclone configuration conflict"
        print-text "heading" "============================================================"
        print ""

        print-text "warn" "The active and legacy rclone configurations are different."
        print-text "info" "No secret values are shown below."
        print ""

        print-heading "Active configuration"
        print-key-value "  Path:    " $active_path
        print-key-value "  SHA256:  " $active_hash
        print-key-value "  Remotes: " (remote-summary $active_info)
        print ""

        print-heading "Legacy configuration"
        print-key-value "  Path:    " $legacy_path
        print-key-value "  SHA256:  " $legacy_hash
        print-key-value "  Remotes: " (remote-summary $legacy_info)
        print ""

        print-heading "Choose which configuration should be preserved"
        print ""
        print-choice "1" "Use ACTIVE configuration"
        print-text "info" "      The current rclone config is encrypted directly; the legacy plaintext"
        print-text "info" "      copy is not rewritten and is treated as superseded (--remove-legacy deletes it)."
        print ""
        print-choice "2" "Use LEGACY configuration"
        print-text "info" "      The legacy config will replace the current rclone config."
        print ""
        print-choice "3" "Cancel"
        print-text "info" "      Leave both files unchanged so they can be inspected manually."
        print ""

        print-text "prompt" "Select [3]:"
        let choice = (input | str trim)
        let answer = if ($choice | is-empty) { "3" } else { $choice }

        if $answer == "3" {
            print ""
            print-status "warn" "cancelled" "Rclone configuration reconciliation was cancelled."
            print-text "info" "Neither configuration was changed."

            return {
                cancelled: true
                changed: false
                backup: null
                selected: "none"
                legacy_sha256: null
            }
        }

        if not ($answer in ["1" "2"]) {
            print ""
            print-status "warn" "cancelled" $"Unknown selection: ($answer)"
            print-text "info" "Neither configuration was changed."

            return {
                cancelled: true
                changed: false
                backup: null
                selected: "none"
                legacy_sha256: null
            }
        }

        let backup = (create-rclone-reconcile-backup $active_path $legacy_path)

        print ""
        print-status "info" "backup" $"Restricted recovery copy: ($backup.root)"

        try {
            match $answer {
                "1" => {
                    print ""
                    print-status "info" "rclone" "Selecting ACTIVE configuration."
                    # Never copy live plaintext into the cloud-synced private
                    # tree. The active file is encrypted directly by the caller;
                    # the legacy copy is left untouched and treated as superseded.
                }

                "2" => {
                    print ""
                    print-status "info" "rclone" "Selecting LEGACY configuration."

                    mkdir ($active_path | path dirname)
                    cp --force $legacy_path $active_path
                    private-file $active_path
                }
            }

            let final_active = (rclone-config-sha256 $active_path)
            let final_legacy = (rclone-config-sha256 $legacy_path)

            if $answer == "1" {
                if $final_active != $active_hash or $final_legacy != $legacy_hash {
                    error make {
                        msg: "Rclone configs changed during reconciliation review."
                    }
                }

                print-status "ok" "ok" "ACTIVE rclone configuration selected; the legacy copy was not modified."

                {
                    cancelled: false
                    changed: false
                    backup: $backup
                    selected: "active"
                    legacy_sha256: $legacy_hash
                }
            } else {
                if $final_active != $final_legacy {
                    error make {
                        msg: "Rclone configuration reconciliation verification failed."
                    }
                }

                print-status "ok" "ok" "Active and legacy rclone configurations now match."

                {
                    cancelled: false
                    changed: true
                    backup: $backup
                    selected: "legacy"
                    legacy_sha256: $final_legacy
                }
            }
        } catch {|err|
            print --stderr ""
            print-status "warn" "warn" "Rclone reconciliation failed." --stderr
            print-status "warn" "warn" "Restoring the original configuration files." --stderr

            try {
                restore-rclone-reconcile-backup $backup $active_path $legacy_path
            } catch {|restore_err|
                print --stderr ""
                print-status "error" "error" "Automatic rollback also failed." --stderr
                print-status "error" "recovery" $"Restricted backup remains at: ($backup.root)" --stderr
                print-text "error" (error-message $restore_err "Rollback failure.") --stderr
            }

            error make {
                msg: (error-message $err "Rclone configuration reconciliation failed.")
            }
        }
    }

    # The active config does not exist, but a legacy config does.
    let legacy_hash = (rclone-config-sha256 $legacy_path)
    let legacy_info = (inspect-rclone-remotes $legacy_path)

    print ""
    print-text "heading" "============================================================"
    print-heading "Active rclone configuration is missing"
    print-text "heading" "============================================================"
    print ""

    print-text "warn" "A legacy rclone configuration exists, but the active config is missing."
    print ""

    print-heading "Legacy configuration"
    print-key-value "  Path:    " $legacy_path
    print-key-value "  SHA256:  " $legacy_hash
    print-key-value "  Remotes: " (remote-summary $legacy_info)
    print ""

    print-heading "Choose an action"
    print ""
    print-choice "1" "Restore LEGACY configuration as the active config"
    print-choice "2" "Cancel"
    print ""

    print-text "prompt" "Select [2]:"
    let choice = (input | str trim)
    let answer = if ($choice | is-empty) { "2" } else { $choice }

    if $answer != "1" {
        print ""
        print-status "warn" "cancelled" "Rclone migration was cancelled."
        print-text "info" "The legacy configuration was not changed."

        return {
            cancelled: true
            changed: false
            backup: null
            selected: "none"
            legacy_sha256: null
        }
    }

    let backup = (create-rclone-reconcile-backup $active_path $legacy_path)

    try {
        mkdir ($active_path | path dirname)
        cp $legacy_path $active_path
        private-file $active_path

        if (rclone-config-sha256 $active_path) != (rclone-config-sha256 $legacy_path) {
            error make {
                msg: "Restored active rclone config failed verification."
            }
        }

        print-status "ok" "ok" "Legacy configuration restored as the active rclone config."

        {
            cancelled: false
            changed: true
            backup: $backup
            selected: "legacy"
            legacy_sha256: $legacy_hash
        }
    } catch {|err|
        try {
            restore-rclone-reconcile-backup $backup $active_path $legacy_path
        } catch {|restore_err|
            print-status "error" "recovery" $"Restricted backup remains at: ($backup.root)" --stderr
            print-text "error" (error-message $restore_err "Rollback failure.") --stderr
        }

        error make {
            msg: (error-message $err "Failed to restore the legacy rclone config.")
        }
    }
}

export def migrate-rclone-secret [remove_legacy: bool] {
    let entry = (resolve-vault-entry "rclone")

    let active = ($entry.local | path expand)

    let legacy = (
        (machine-context).data_root
        | path expand
        | path join "rclone" "rclone.conf"
    )

    if not ($legacy | path exists) {
        error make {
            msg: "No legacy plaintext rclone copy exists."
        }
    }

    let reconciliation = (reconcile-rclone-configs $active $legacy)

    if $reconciliation.cancelled {
        return
    }

    let backup = $reconciliation.backup

    let migration_result = (
        try {
            print ""
            print-status "info" "vault" "Encrypting the active rclone configuration."

            capture-secret "rclone"

            let config = (load-vault)

            let dir = (
                (state-root)
                | path join "age"
                | path join ("verify-" + (random uuid))
            )

            private-directory $dir

            let verification = ($dir | path join "plaintext")

            let verification_result = (
                try {
                    checked "age" ["--decrypt" "--identity" ($config.identity | path expand) "--output" $verification (ciphertext-path "rclone")] "Verify encrypted migration" | ignore

                    let encrypted_hash = (
                        open --raw $verification
                        | hash sha256
                    )

                    let active_hash = (
                        open --raw $active
                        | hash sha256
                    )

                    let legacy_hash = (
                        open --raw $legacy
                        | hash sha256
                    )

                    if $encrypted_hash != $active_hash {
                        error make {
                            msg: "Encrypted migration does not match the active rclone config."
                        }
                    }

                    # When ACTIVE was chosen the legacy copy is superseded and is
                    # intentionally not rewritten, so only require it to be the
                    # exact file that was reviewed (it may be removed below).
                    if $reconciliation.selected == "active" {
                        if $legacy_hash != $reconciliation.legacy_sha256 {
                            error make {
                                msg: "Legacy rclone config changed during migration."
                            }
                        }
                    } else if $active_hash != $legacy_hash {
                        error make {
                            msg: "Rclone configs changed during migration."
                        }
                    }

                    null
                } catch {|err|
                    failure-envelope $err
                }
            )

            let verification_failure = (
                captured-failure $verification_result
            )

            if $verification_failure != null {
                try {
                    if ($dir | path exists) {
                        rm --recursive --force $dir
                    }
                }

                error make {
                    msg: (error-message $verification_failure "Encrypted rclone migration verification failed.")
                }
            }

            try {
                if ($dir | path exists) {
                    rm --recursive --force $dir
                }
            } catch {
                print-status "warn" "warn" $"Verification directory remains at: ($dir)" --stderr
            }

            if $remove_legacy {
                print-status "info" "vault" "Removing the verified legacy plaintext cloud copy."
                rm --force $legacy
            }

            null
        } catch {|err|
            failure-envelope $err
        }
    )

    let migration_failure = (
        captured-failure $migration_result
    )

    if $migration_failure != null {
        print --stderr ""
        print-status "error" "error" "Rclone vault migration failed." --stderr

        if $backup != null {
            print-status "warn" "recovery" "Restoring the pre-migration rclone configurations." --stderr

            try {
                restore-rclone-reconcile-backup $backup $active $legacy

                remove-rclone-reconcile-backup $backup
                print-status "ok" "recovery" "Original rclone configurations restored." --stderr
            } catch {|restore_err|
                print-status "error" "error" "Automatic recovery failed." --stderr
                print-status "error" "recovery" $"Restricted backup remains at: ($backup.root)" --stderr
                print-text "error" (error-message $restore_err "Recovery failure.") --stderr
            }
        }

        error make {
            msg: (error-message $migration_failure "Secret migration failed.")
        }
    }

    if $backup != null {
        try {
            remove-rclone-reconcile-backup $backup
        } catch {
            print-status "warn" "warn" $"Restricted reconciliation backup remains at: ($backup.root)" --stderr
        }
    }

    if $remove_legacy {
        print ""
        print-status "ok" "ok" "Verified encryption and removed the active plaintext cloud copy."
        print-text "warn" "Old cloud versions and existing backups may still contain plaintext."
        print-text "warn" "Review them separately and rotate credentials if they may have been exposed."
    } else {
        print ""
        print-status "ok" "encrypted" "Ciphertext created and verified."
        if $reconciliation.selected == "active" {
            print-text "warn" "The legacy plaintext copy is still present and is superseded by the ACTIVE config."
        } else {
            print-text "warn" "The legacy plaintext copy is still present."
        }
        print-text "info" "Repeat with --remove-legacy when you are ready to remove it."
    }
}
