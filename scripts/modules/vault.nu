# age-backed, explicit-allowlist secret storage. The remote never supplies a
# plaintext destination path. SSH and age private keys are never capture targets.
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
use $CORE [nu-home machine-context error-message failure-envelope captured-failure]
use $SAFETY [state-root checked private-directory private-file atomic-record disjoint-paths]

export def vault-config-path [] { (state-root) | path join "vault.nuon" }
export def vault-configured [] { (vault-config-path) | path exists }

export def load-vault [] {
    let file = (vault-config-path)
    if not ($file | path exists) { error make { msg: "Secret vault is not configured. Run dotvault init first." } }
    let config = (open --raw $file | from nuon)
    if ($config.version? | default 0) != 1 { error make { msg: "Unsupported vault configuration version." } }
    if ($config.recipients? | default [] | is-empty) { error make { msg: "Configure at least one age recipient." } }
    for recipient in $config.recipients {
        if not ($recipient =~ '^age1[0-9a-z]+$') { error make { msg: "Only native age public recipients are accepted." } }
    }
    let names = ($config.entries | each {|entry| $entry.name})
    if ($names | uniq | length) != ($names | length) { error make { msg: "Duplicate vault entry names." } }
    $config
}

export def resolve-vault-entry [name: string] {
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

export def vault-init-preflight [recipient: string] {
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
    print --stderr "[vault:init] Checking local paths and age prerequisites"
    let plan = (vault-init-preflight $recipient)
    if $check {
        print "[ok] Vault preflight passed. No keys, policy files, ACLs, locks or provider state were changed."
        return
    }
    let config_file = $plan.config_file
    let key_dir = $plan.key_dir
    let identity = $plan.identity
    print --stderr "[vault:init] Protecting the local identity directory"
    private-directory $key_dir
    mut public_key = $recipient
    if ($public_key | is-empty) {
        if not ($identity | path exists) {
            print --stderr "[vault:init] Generating an age identity (never overwriting an existing key)"
            checked "age-keygen" ["-o" $identity] "Generate age identity" | ignore
        } else {
            print --stderr "[vault:init] Reusing the existing age identity"
        }
        print --stderr "[vault:init] Protecting the identity and deriving its public recipient"
        private-file $identity
        let result = (checked "age-keygen" ["-y" $identity] "Derive public recipient from the existing identity")
        $public_key = (vault-command-text $result "age-keygen -y")
    }
    if not ($public_key =~ '^age1[0-9a-z]+$') {
        error make {msg: "VAULT_RECIPIENT_INVALID: age-keygen must return exactly one native public recipient. The identity was not replaced."}
    }
    mut entries = []
    if not (which rclone | is-empty) {
        print --stderr "[vault:init] Discovering the optional local rclone configuration path"
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
            {name: "rclone" local: $local auto_capture: false auto_restore: false}
        } catch {
            print --stderr "[warn] rclone path discovery failed. Vault initialization can continue with no rclone entry; register its local path in vault.nuon before migration. No credentials were copied."
            null
        })
        if $discovered != null { $entries = [$discovered] }
    }
    print --stderr "[vault:init] Preparing owner-only vault policy"
    let stage = ((state-root) | path join (".vault-init-" + (random uuid)))
    let candidate = ($stage | path join "vault.nuon")
    try {
        private-directory $stage
        {version: 1 identity: ($identity | into string) recipients: [$public_key] entries: $entries} | to nuon | save $candidate
        private-file $candidate
        if ($config_file | path exists) { error make {msg: "Vault policy appeared during initialization; it was not overwritten."} }
        # Rename an already protected file on the same filesystem. Do not commit
        # policy first and then discover an ACL failure that leaves init blocked.
        mv --no-clobber $candidate $config_file
        if ($candidate | path exists) { error make {msg: "Vault policy could not be committed without overwriting another file."} }
    } catch {|err|
        try { if ($stage | path exists) { rm --recursive --force $stage } } catch {
            print --stderr "[warn] A restricted vault-init staging directory remains; no identity was deleted."
        }
        # Keep the original record/labels rather than substituting only its msg.
        error make $err
    }
    try { rm --recursive --force $stage } catch {
        print --stderr "[warn] Vault is initialized; the empty staging directory could not be removed."
    }
    print ("[ok] Vault policy: " + ($config_file | into string))
    print ("Public recipient: " + $public_key)
    if ($recipient | is-empty) {
        print "Keep a separate offline backup of identity.txt. It is never synchronized."
    } else {
        print "Recipient-only policy: no private key was generated. Restore requires the matching private identity, not merely a local file with the expected name."
    }
    print "Only explicitly registered files can be captured or restored; automatic capture/restore is off."
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
    if ($text | str contains "PRIVATE KEY-----") or ($text | str contains "AGE-SECRET-KEY-") {
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
    print ("[ok] Encrypted capture: " + $name + ". Run dotpush to publish it.")
}

export def restore-secret [name: string force: bool] {
    let entry = (resolve-vault-entry $name)
    let config = (load-vault)
    let source = (ciphertext-path $name)
    let destination = ($entry.local | path expand)
    if not ($source | path exists) { error make { msg: "No encrypted copy exists for this entry." } }
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
        print ("[warn] Secret restored, but restricted recovery files remain at: " + ($temp_dir | into string))
    }
    print ("[ok] Restored secret: " + $name)
}

export def migrate-rclone-secret [remove_legacy: bool] {
    let entry = (resolve-vault-entry "rclone")
    let legacy = ((machine-context).data_root | path expand | path join "rclone" "rclone.conf")
    if not ($legacy | path exists) { error make { msg: "No legacy plaintext rclone copy exists." } }
    if not ($entry.local | path exists) or ((open --raw $entry.local | hash sha256) != (open --raw $legacy | hash sha256)) {
        error make { msg: "Legacy and active rclone configs differ. Reconcile them locally before migration; neither was changed." }
    }
    capture-secret "rclone"
    let config = (load-vault)
    let dir = ((state-root) | path join "age" ("verify-" + (random uuid)))
    private-directory $dir
    let verification = ($dir | path join "plaintext")
    try {
        checked "age" ["--decrypt" "--identity" ($config.identity | path expand) "--output" $verification (ciphertext-path "rclone")] "Verify encrypted migration" | ignore
        if (open --raw $verification | hash sha256) != (open --raw $legacy | hash sha256) { error make { msg: "Migration verification failed." } }
        if $remove_legacy { rm --force $legacy }
        rm --recursive --force $dir
    } catch {|err|
        if ($dir | path exists) { rm --recursive --force $dir }
        error make { msg: (error-message $err "Secret migration failed.") }
    }
    if $remove_legacy {
        print "[ok] Verified encryption and removed the active plaintext cloud copy."
        print "Old cloud versions and existing backups may still contain plaintext; review them separately and rotate exposed credentials."
    } else {
        print "[encrypted] Ciphertext created and verified; legacy plaintext retained. Repeat with --remove-legacy to remove the active plaintext copy."
    }
}
