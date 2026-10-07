# Portable rpool configuration synchronization.
# rpool owns the portable schema; Initial-setup selects one of two modes from
# the installed rpool CLI:
# - artifact (rpool 0.7+, top-level `rpool export/import <root>`): the private
#   source holds rpool/config/portable-config.json (non-secret) and, only when
#   crypt remotes exist, rpool/secrets/rclone.age. That file carries the crypt
#   remotes' obscured password/password2 values, encrypted by rpool to the
#   Initial-setup age vault recipient. Initial-setup never writes decrypted
#   secrets to disk and never prints them; it decrypts only in memory, with the
#   local vault identity, to detect whether the secrets changed.
# - legacy (rpool 0.5.3-0.6, `rpool config export/import <json>`): the flat
#   rpool/portable-config.json bundle is non-secret and no rclone credentials
#   are copied. Legacy bundles remain readable by artifact-capable machines.

const CORE = path self ./core.nu
use $CORE [nu-home try-machine-context]

const SUBPROCESS = path self ./subprocess.nu
const CONSOLE = path self ./console.nu
const SAFETY = path self ./safety.nu
const VAULT = path self ./vault.nu
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-info print-ok print-warn print-key-value print-output-text]
use $SAFETY [state-root private-directory]
use $VAULT [vault-configured load-vault active-rclone-config-path]
const RCLONE_COMPARE = path self ./rclone-compare.nu
use $RCLONE_COMPARE [rclone-crypt-sections-hash encrypted-rclone-config]

# Fields that rpool rewrites on every export without changing the user's actual
# configuration. They are excluded from the semantic hash so that a timestamp
# bump alone does not register as a change.
const VOLATILE_FIELDS = ["exported_at_unix"]
# Artifact exports also bind the (randomized) ciphertext by BLAKE3; secret
# equality is decided separately by decrypting in memory.
const ARTIFACT_VOLATILE_FIELDS = ["exported_at_unix" "secret_vault"]
const AGE_BINARY_HEADER = "age-encryption.org/v1"

def semantic-hash-without [parsed: any fields: list] {
    if not (($parsed | describe) | str starts-with "record") {
        return ""
    }
    let cols = ($parsed | columns)
    mut stripped = $parsed
    for field in $fields {
        if ($cols | any {|c| $c == $field}) {
            $stripped = ($stripped | reject $field)
        }
    }
    $stripped | to json | hash sha256
}

# Semantic hash of a parsed rpool portable-config record: the serialized JSON of
# the record with volatile fields removed, then SHA-256. Returns "" for any
# non-record input so callers can treat a missing/corrupt old bundle as "no
# prior semantic" without crashing.
export def rpool-semantic-hash [parsed: any] {
    semantic-hash-without $parsed $VOLATILE_FIELDS
}

# Same as rpool-semantic-hash, but also ignores the artifact ciphertext binding.
export def rpool-artifact-semantic-hash [parsed: any] {
    semantic-hash-without $parsed $ARTIFACT_VOLATILE_FIELDS
}

# Re-raise a value captured by `catch {|err| $err }`. `default` evaluates its
# argument eagerly, so never stringify the record as a fallback there.
def rethrow [result: any] {
    let msg = (try { $result.msg? } catch { null })
    if $msg != null { error make {msg: ($msg | into string)} }
    error make {msg: (try { $result | to nuon } catch { "rpool synchronization failed." })}
}

def rpool-bundle-path [root: path] {
    $root | path expand | path join "rpool" "portable-config.json"
}

def rpool-artifact-config-path [root: path] {
    $root | path expand | path join "rpool" "config" "portable-config.json"
}

def rpool-artifact-secret-path [root: path] {
    $root | path expand | path join "rpool" "secrets" "rclone.age"
}

# Resolve once per operation; subprocesses use this exact external executable.
export def resolve-rpool-executable [] {
    let override = ($env.RPOOL_BIN? | default "" | str trim)
    if not ($override | is-empty) {
        let absolute = if $nu.os-info.name == "windows" {
            $override =~ '^(?:[A-Za-z]:[\\/]|\\\\)'
        } else { $override | str starts-with "/" }
        if not $absolute or not ($override | path exists) or ($override | path type) != "file" {
            error make {msg: "RPOOL_BIN must name an existing absolute rpool executable path; refusing fallback. To use your Nushell PATH instead, remove the old RPOOL_BIN assignment from config/local.nu and run: hide-env -i RPOOL_BIN. Add the directory containing rpool and rclone to $env.PATH (see templates/sync-tools.nu.example)."}
        }
        return ($override | path expand)
    }
    let external = (which rpool --all | where type == "external")
    if not ($external | is-empty) { return ($external | first | get path | path expand) }
    let name = if $nu.os-info.name == "windows" { "rpool.exe" } else { "rpool" }
    let context = (try-machine-context)
    let tools_root = ($context.tools_root? | default "")
    mut candidates = []
    if not ($tools_root | is-empty) {
        let sibling = ($tools_root | path expand | path dirname | path join "rpool")
        $candidates = [($sibling | path join $name) ($sibling | path join "target" "release" $name)]
    }
    $candidates = ($candidates | append ((nu-home) | path join ".cargo" "bin" $name))
    for candidate in $candidates {
        if ($candidate | path exists) and ($candidate | path type) == "file" { return $candidate }
    }
    ""
}

# Absolute path of an external program on PATH, or "".
def resolve-external [name: string] {
    let found = (which $name --all | where type == "external")
    if ($found | is-empty) { "" } else { $found | first | get path | path expand | into string }
}

def active-settings-exist [] {
    let root = match $nu.os-info.name {
        "windows" => {
            let base = ($env.APPDATA? | default "")
            if ($base | is-empty) { "" } else { $base | path join "rpool" }
        }
        "macos" => { (nu-home) | path join "Library" "Application Support" "rpool" }
        _ => { ($env.XDG_CONFIG_HOME? | default ((nu-home) | path join ".config")) | path join "rpool" }
    }
    if ($root | is-empty) { return false }
    ["gui.json" "pools.json" "remote_roots.json"] | any {|name| $root | path join $name | path exists }
}

def help-text [result: record] {
    ($result.stdout? | default "") + (char nl) + ($result.stderr? | default "")
}

def capability [] {
    let executable = (resolve-rpool-executable)
    if ($executable | is-empty) {
        return {installed: false portable_config: false artifact: false legacy_config: false mode: "unavailable" executable: "" active_settings: (active-settings-exist) reason: "rpool executable was not found; set RPOOL_BIN to its absolute path"}
    }
    # Artifact mode: top-level `export`/`import` subcommands whose export
    # accepts an age recipient for crypt secrets (rpool 0.7+).
    let top = (run-command $executable ["--help"])
    let top_text = (help-text $top)
    let artifact = if $top.ok and ($top_text =~ '(?m)^\s+export\s') and ($top_text =~ '(?m)^\s+import\s') {
        let export_help = (run-command $executable ["export" "--help"])
        $export_help.ok and ((help-text $export_help) | str contains "--age-recipient")
    } else { false }

    let legacy_result = (run-command $executable ["config" "--help"])
    let legacy_text = (help-text $legacy_result)
    let legacy = ($legacy_result.ok and ($legacy_text | str contains "export") and ($legacy_text | str contains "import"))

    let supported = ($artifact or $legacy)
    let reason = if $supported { "" } else if not $legacy_result.ok {
        command-failure-message "rpool config --help" $legacy_result
    } else {
        "rpool config export/import is unavailable; update rpool or set RPOOL_BIN to a compatible executable"
    }
    {
        installed: true
        portable_config: $supported
        artifact: $artifact
        legacy_config: $legacy
        mode: (if $artifact { "artifact" } else if $legacy { "legacy" } else { "unsupported" })
        executable: $executable
        reason: $reason
    }
}

def require-usable [cap: record] {
    if (not $cap.installed) and ($cap.active_settings? | default false) {
        error make {msg: ("Active rpool settings exist, but " + $cap.reason + ". Synchronization stopped to avoid stale settings.")}
    }
    if $cap.installed and not $cap.portable_config { error make {msg: $cap.reason} }
}

def require-artifact [cap: record] {
    require-usable $cap
    if not $cap.installed {
        error make {msg: ($cap.reason + "; the synchronized rpool artifact (rpool/config + rpool/secrets) requires rpool 0.7+ before it can be restored.")}
    }
    if not $cap.artifact {
        error make {msg: ("The synchronized rpool config uses the artifact layout (rpool/config/portable-config.json, optional rpool/secrets/rclone.age), but " + $cap.executable + " lacks top-level `rpool export/import`. Update rpool to 0.7+ (or set RPOOL_BIN) before syncing.")}
    }
}

export def rpool-sync-status [root: path] {
    let cap = (capability)
    let bundle = (rpool-bundle-path $root)
    let artifact_config = (rpool-artifact-config-path $root)
    let artifact_secret = (rpool-artifact-secret-path $root)
    let artifact_exists = ($artifact_config | path exists)
    {
        installed: $cap.installed
        executable: $cap.executable
        portable_config: $cap.portable_config
        mode: $cap.mode
        artifact: $cap.artifact
        reason: $cap.reason
        bundle: ((if $artifact_exists { $artifact_config } else { $bundle }) | into string)
        bundle_exists: ($artifact_exists or ($bundle | path exists))
        layout: (if $artifact_exists { "artifact" } else if ($bundle | path exists) { "legacy" } else { "none" })
        artifact_config: ($artifact_config | into string)
        artifact_secret: ($artifact_secret | into string)
        artifact_secret_exists: ($artifact_secret | path exists)
    }
}

def validate-bundle [file: path] {
    if not ($file | path exists) or ($file | path type) != "file" {
        error make {msg: ("rpool portable config was not created as a regular file: " + ($file | into string))}
    }

    let parsed = (try { open --raw $file | from json } catch {|err|
        error make {msg: ("rpool portable config is not valid JSON: " + ($err.msg? | default ($err | into string)))}
    })
    if not (($parsed | describe) | str starts-with "record") {
        error make {msg: "rpool portable config must be a JSON object."}
    }

    let raw = (open --raw $file)
    for forbidden in [("AGE-SECRET-" + "KEY-") ("PRIVATE" + " KEY-----")] {
        if ($raw | str contains $forbidden) {
            error make {msg: "rpool portable config unexpectedly contains private-key material; refusing to synchronize it."}
        }
    }

    {sha256: ($raw | hash sha256) semantic: (rpool-semantic-hash $parsed) artifact_semantic: (rpool-artifact-semantic-hash $parsed) parsed: $parsed}
}

# The encrypted crypt-secret file must be a binary age file, never plaintext.
def validate-age-file [file: path] {
    if not ($file | path exists) or ($file | path type) != "file" {
        error make {msg: ("rpool crypt secret vault is not a regular file: " + ($file | into string))}
    }
    let header = (try {
        open --raw $file | into binary | bytes at 0..20 | decode utf-8
    } catch { "" })
    if $header != $AGE_BINARY_HEADER {
        error make {msg: ("rpool crypt secret vault is not an age-encrypted file; refusing to synchronize it: " + ($file | into string))}
    }
}

# SHA-256 of the decrypted content, computed in memory only; null on failure.
def decrypted-sha256 [age: string identity: string file: path] {
    # --sensitive: plaintext stays in memory and diagnostics are withheld.
    let result = (run-command $age ["--decrypt" "--identity" $identity ($file | into string)] --sensitive)
    if not $result.ok { return null }
    $result.stdout | hash sha256
}

# Local identity + age executable for in-memory comparisons, or null.
def local-decryptor [] {
    let age = (resolve-external "age")
    if ($age | is-empty) or not (vault-configured) { return null }
    let vault = (try { load-vault } catch { null })
    if $vault == null { return null }
    let identity = ($vault.identity? | default "" | into string | str trim)
    if ($identity | is-empty) { return null }
    let expanded = ($identity | path expand | into string)
    if not ($expanded | path exists) { return null }
    {age: $age identity: $expanded}
}

def secrets-equal [old: path new: path] {
    let old_exists = ($old | path exists)
    let new_exists = ($new | path exists)
    if (not $old_exists) and (not $new_exists) { return true }
    if $old_exists != $new_exists { return false }
    let decryptor = (local-decryptor)
    # Without a usable identity the secrets cannot be compared; publish the new
    # ciphertext rather than risk keeping stale crypt passwords.
    if $decryptor == null { return false }
    let old_hash = (decrypted-sha256 $decryptor.age $decryptor.identity $old)
    let new_hash = (decrypted-sha256 $decryptor.age $decryptor.identity $new)
    ($old_hash != null) and ($new_hash != null) and ($old_hash == $new_hash)
}

# rpool 0.7 encrypts to exactly one --age-recipient. Pass the vault recipient
# only when it is unambiguous; with several recipients we refuse (below) rather
# than silently encrypting the crypt secrets to a subset of the vault.
def artifact-export-args [artifact_root: path] {
    mut args = ["export" ($artifact_root | into string)]
    let rclone_config = (active-rclone-config-path)
    if $rclone_config != null { $args = ($args | append ["--rclone-config" $rclone_config]) }
    let age = (resolve-external "age")
    if not ($age | is-empty) { $args = ($args | append ["--age" $age]) }
    if (vault-configured) {
        let recipients = ((load-vault).recipients? | default [])
        if ($recipients | length) == 1 {
            $args = ($args | append ["--age-recipient" ($recipients | first | into string)])
        }
    }
    $args
}

def artifact-export-failure [label: string result: record] {
    let base = (command-failure-message $label $result)
    let text = (help-text $result)
    if not ($text | str contains "--age-recipient is required") { return $base }
    if not (vault-configured) {
        return ("rpool has crypt remotes whose passwords must be encrypted before synchronization, but the Initial-setup age vault is not configured. Run `dotvault init` (or `dotctl config vault init`) once, keep an offline backup of the age identity, then retry dotpush.\n" + $base)
    }
    let count = ((try { (load-vault).recipients? | default [] } catch { [] }) | length)
    if $count > 1 {
        return ("rpool encrypts crypt-remote secrets to exactly one age recipient, but the vault lists " + ($count | into string) + " recipients. Refusing to encrypt to a subset of the vault; reduce vault recipients to the shared identity's recipient, then retry.\n" + $base)
    }
    $base
}

# Run `rpool export` into a fresh private stage. Returns the stage record; the
# caller must remove stage_root.
def artifact-export [cap: record label: string] {
    let stage_root = ((state-root) | path join "rpool-staging" (random uuid))
    private-directory $stage_root
    let artifact_root = ($stage_root | path join "artifact")
    private-directory $artifact_root
    let exported = (run-command $cap.executable (artifact-export-args $artifact_root))
    if not $exported.ok {
        rm --recursive --force $stage_root
        error make {msg: (artifact-export-failure $label $exported)}
    }
    {
        stage_root: $stage_root
        config: ($artifact_root | path join "config" "portable-config.json")
        secret: ($artifact_root | path join "secrets" "rclone.age")
    }
}

def capture-artifact [root: path cap: record] {
    let dest_config = (rpool-artifact-config-path $root)
    let dest_secret = (rpool-artifact-secret-path $root)
    let legacy = (rpool-bundle-path $root)
    let stage = (artifact-export $cap "rpool export")

    let result = (try {
        let checked = (validate-bundle $stage.config)
        let has_secret = ($stage.secret | path exists)
        if $has_secret { validate-age-file $stage.secret }

        let old_parsed = (try { open --raw $dest_config | from json } catch { null })
        let config_same = ($old_parsed != null) and ((rpool-artifact-semantic-hash $old_parsed) == $checked.artifact_semantic)
        let unchanged = $config_same and (secrets-equal $dest_secret $stage.secret)
        if $unchanged {
            {status: "unchanged" mode: "artifact" path: ($dest_config | into string) secrets: ($dest_secret | path exists) sha256: (open --raw $dest_config | hash sha256) semantic: $checked.artifact_semantic}
        } else {
            # Secrets first, then the config that binds them, so an
            # interrupted install never leaves a config pointing at a
            # missing/older ciphertext without the next capture fixing it.
            mkdir ($dest_config | path dirname)
            if $has_secret {
                mkdir ($dest_secret | path dirname)
                mv --force $stage.secret $dest_secret
            } else if ($dest_secret | path exists) {
                rm --force $dest_secret
            }
            mv --force $stage.config $dest_config
            if ($legacy | path exists) { rm --force $legacy }
            {status: "captured" mode: "artifact" path: ($dest_config | into string) secrets: $has_secret sha256: $checked.sha256 semantic: $checked.artifact_semantic}
        }
    } catch {|err| $err })

    if ($stage.stage_root | path exists) { rm --recursive --force $stage.stage_root }
    $result
}

def capture-legacy [root: path cap: record] {
    if ((rpool-artifact-config-path $root) | path exists) {
        error make {msg: ("The private source already uses the rpool artifact layout (rpool/config, rpool/secrets), but " + $cap.executable + " only supports legacy `rpool config export`. Update rpool to 0.7+ on this machine; capture stopped to avoid publishing stale settings.")}
    }
    let bundle = (rpool-bundle-path $root)
    mkdir ($bundle | path dirname)
    let stage_root = ((state-root) | path join "rpool-staging" (random uuid))
    private-directory $stage_root
    let staged = ($stage_root | path join "portable-config.json")

    let result = (try {
        let exported = (run-command $cap.executable ["config" "export" ($staged | into string)])
        if not $exported.ok {
            error make {msg: (command-failure-message "rpool config export" $exported)}
        }
        let checked = (validate-bundle $staged)
        # Compare on semantic content, not raw bytes: a timestamp bump must not
        # register as a change. The raw SHA is preserved for the unchanged path
        # so the synchronized file is left byte-for-byte intact.
        let old_parsed = (try { open --raw $bundle | from json } catch { null })
        let old_semantic = (rpool-semantic-hash $old_parsed)
        if $old_semantic == $checked.semantic {
            let old_raw = (open --raw $bundle | hash sha256)
            {status: "unchanged" mode: "legacy" path: ($bundle | into string) sha256: $old_raw semantic: $checked.semantic}
        } else {
            mv --force $staged $bundle
            {status: "captured" mode: "legacy" path: ($bundle | into string) sha256: $checked.sha256 semantic: $checked.semantic}
        }
    } catch {|err| $err })

    if ($stage_root | path exists) { rm --recursive --force $stage_root }
    $result
}

export def capture-rpool-config [root: path] {
    let cap = (capability)
    require-usable $cap
    if not $cap.installed {
        return {status: "skipped" reason: $cap.reason}
    }
    let result = if $cap.artifact { capture-artifact $root $cap } else { capture-legacy $root $cap }
    if (($result | describe) | str starts-with "record") and (($result.status? | default "") in ["captured" "unchanged"]) {
        return $result
    }
    rethrow $result
}

# Fingerprint of the local crypt remote secrets that the rpool artifact
# carries. Encrypted rclone configs (RCLONE_CONFIG_PASS) cannot be inspected
# here; a stable marker keeps the fingerprint deterministic in that case.
def rpool-crypt-local-hash [] {
    let config = (active-rclone-config-path)
    if $config == null or not ($config | path exists) { return "NO-RCLONE-CONFIG" }
    let text = (open --raw $config | decode utf-8)
    if (encrypted-rclone-config $text) { return "ENCRYPTED-RCLONE-CONFIG" }
    let digest = (rclone-crypt-sections-hash $text)
    if ($digest | is-empty) { "NO-CRYPT" } else { $digest }
}

export def rpool-local-hash [] {
    let cap = (capability)
    require-usable $cap
    if not $cap.installed { return "UNAVAILABLE" }

    # Artifact mode also carries crypt passwords, so a password-only change
    # must alter the fingerprint even when rclone.conf sync is disabled.
    let crypt = if $cap.artifact { "|crypt:" + (rpool-crypt-local-hash) } else { "" }

    # The legacy JSON export needs neither age nor rclone and is enough to
    # fingerprint non-secret settings.
    if not $cap.legacy_config {
        # rpool 2.14+ `export` refuses to run without an rclone.conf. A fresh
        # machine has none yet (rclone.conf arrives during the same pull), so a
        # failed export here must NOT abort the whole sync fingerprint: fall back
        # to a stable marker and let sync proceed. The crypt component is read
        # from rclone.conf directly and already tolerates its absence.
        let stage = (try { artifact-export $cap "rpool export for local fingerprint" } catch {|err| null })
        if $stage == null { return ("EXPORT-UNAVAILABLE" + $crypt) }
        let result = (try { (validate-bundle $stage.config).artifact_semantic } catch {|err| $err })
        if ($stage.stage_root | path exists) { rm --recursive --force $stage.stage_root }
        if ($result | describe) == "string" { return ($result + $crypt) }
        rethrow $result
    }

    let stage_root = ((state-root) | path join "rpool-fingerprint" (random uuid))
    private-directory $stage_root
    let staged = ($stage_root | path join "portable-config.json")
    let result = (try {
        let exported = (run-command $cap.executable ["config" "export" ($staged | into string)])
        if not $exported.ok {
            error make {msg: (command-failure-message "rpool config export for local fingerprint" $exported)}
        }
        let checked = (validate-bundle $staged)
        $checked.semantic
    } catch {|err| $err })
    if ($stage_root | path exists) { rm --recursive --force $stage_root }
    if ($result | describe) == "string" { return ($result + $crypt) }
    # Legacy export failed (e.g. rpool unusable here); stable marker instead of
    # blocking the whole sync fingerprint.
    ("EXPORT-UNAVAILABLE" + $crypt)
}

# Checks every local prerequisite for importing the artifact and returns the
# extra `rpool import` arguments. Never runs rpool import or decrypts anything.
def artifact-import-plan [cap: record has_secret: bool] {
    require-artifact $cap
    let rclone_config = (active-rclone-config-path)
    mut args = []
    if $rclone_config != null { $args = ($args | append ["--rclone-config" $rclone_config]) }
    if not $has_secret { return {args: $args} }

    if not (vault-configured) {
        error make {msg: "The synchronized rpool config includes encrypted crypt-remote secrets (rpool/secrets/rclone.age), but the Initial-setup age vault is not configured on this machine. Run `dotvault init` with the shared age identity restored from your offline backup, then retry dotpull."}
    }
    let vault = (load-vault)
    let identity = ($vault.identity? | default "" | into string | str trim)
    let identity_path = if ($identity | is-empty) { "" } else { $identity | path expand | into string }
    if ($identity_path | is-empty) or not ($identity_path | path exists) {
        error make {msg: "The synchronized rpool crypt secrets require the local age identity, but it is missing. Recover it from your offline backup, then retry dotpull."}
    }
    let age = (resolve-external "age")
    if ($age | is-empty) {
        error make {msg: "The synchronized rpool crypt secrets require the age executable on PATH. Install age (macOS: brew install age; Windows: winget install --id FiloSottile.age --exact), then retry."}
    }
    if $rclone_config == null {
        error make {msg: "The synchronized rpool crypt secrets require rclone and a discoverable rclone.conf (`rclone config file`) on this machine."}
    }
    $args = ($args | append ["--age" $age "--age-identity" $identity_path])
    # The transaction-snapshot recipient must match the identity. Deriving it
    # from the identity via age-keygen is always consistent; fall back to the
    # vault recipient only when it is unambiguous.
    let keygen = (resolve-external "age-keygen")
    let recipients = ($vault.recipients? | default [])
    if not ($keygen | is-empty) {
        $args = ($args | append ["--age-keygen" $keygen])
    } else if ($recipients | length) == 1 {
        $args = ($args | append ["--age-recipient" ($recipients | first | into string)])
    } else {
        error make {msg: "rpool crypt restore needs the public recipient of the local identity: install age-keygen (part of the age package) or keep exactly one vault recipient."}
    }
    {args: $args}
}

# Cheap fail-closed pull preflight (no rpool import, no decryption): verifies
# that an incoming artifact can be imported on this machine before any live
# configuration is changed.
export def rpool-restore-preflight [root: path] {
    let config = (rpool-artifact-config-path $root)
    if not ($config | path exists) { return {status: "not-required"} }
    let cap = (capability)
    # A machine without rpool at all does not use rpool config: skip the restore
    # with a warning instead of blocking the whole pull. Still fail closed if
    # active rpool settings exist but the CLI vanished (a dangerous state).
    if not $cap.installed {
        if ($cap.active_settings? | default false) {
            error make {msg: ("Active rpool settings exist but " + $cap.reason + "; refusing to skip rpool restore. Install rpool (or set RPOOL_BIN), then dotpull.")}
        }
        print-warn ("rpool is not installed; skipping rpool config restore. Everything else still syncs. To restore rpool settings later, install rpool (or set RPOOL_BIN) and run dotpull again. (" + $cap.reason + ")")
        return {status: "skipped"}
    }
    let secret = (rpool-artifact-secret-path $root)
    let has_secret = ($secret | path exists)
    validate-bundle $config | ignore
    if $has_secret { validate-age-file $secret }
    artifact-import-plan $cap $has_secret | ignore
    {status: "ready" secrets: $has_secret}
}

def crypt-restore-line [stdout: string] {
    let found = ($stdout | lines | each {|line| $line | str trim } | where {|line| $line | str starts-with "crypt restore:" })
    if ($found | is-empty) { "" } else { $found | last }
}

def artifact-import-failure [label: string result: record] {
    let base = (command-failure-message $label $result)
    let text = (help-text $result)
    if ($text | str contains "target crypt remote is missing") or ($text | str contains "target remote is not crypt") {
        return ("A crypt remote in the synchronized rpool config does not exist (as a crypt remote) in this machine's rclone.conf. rpool only rewrites passwords of existing crypt remotes: create them first (enable encrypted rclone sync via the vault so dotpull restores rclone.conf, or run `rclone config` with the same names and structure), then retry.\n" + $base)
    }
    if ($text | str contains "target crypt structure does not match") {
        return ("A local crypt remote differs in structure (backing remote/options) from the synchronized rpool config; rpool refuses to overwrite its passwords. Align the crypt remote in rclone.conf, then retry.\n" + $base)
    }
    $base
}

def print-import-output [result: record] {
    let text = ($result.stdout? | default "" | str trim --right)
    if not ($text | str trim | is-empty) { print-output-text $text }
}

def restore-artifact [root: path dry_run: bool] {
    let config = (rpool-artifact-config-path $root)
    let secret = (rpool-artifact-secret-path $root)
    let has_secret = ($secret | path exists)
    validate-bundle $config | ignore
    if $has_secret { validate-age-file $secret }
    let cap = (capability)
    let plan = (artifact-import-plan $cap $has_secret)

    let stage_root = ((state-root) | path join "rpool-staging" (random uuid))
    let result = (try {
        private-directory $stage_root
        let artifact_root = ($stage_root | path join "artifact")
        private-directory $artifact_root
        # rpool import requires both directories, even without crypt secrets.
        private-directory ($artifact_root | path join "config")
        private-directory ($artifact_root | path join "secrets")
        cp $config ($artifact_root | path join "config" "portable-config.json")
        if $has_secret { cp $secret ($artifact_root | path join "secrets" "rclone.age") }

        let base = (["import" ($artifact_root | into string)] | append $plan.args)
        let preview = (run-command $cap.executable ($base | append "--dry-run"))
        if not $preview.ok {
            error make {msg: (artifact-import-failure "rpool import --dry-run" $preview)}
        }
        print-import-output $preview
        if $dry_run {
            {status: "validated" mode: "artifact" path: ($config | into string) secrets: $has_secret crypt: (crypt-restore-line ($preview.stdout? | default ""))}
        } else {
            let imported = (run-command $cap.executable $base)
            if not $imported.ok {
                error make {msg: (artifact-import-failure "rpool import" $imported)}
            }
            print-import-output $imported
            let crypt = (crypt-restore-line ($imported.stdout? | default ""))
            if ($crypt | str contains "cleanup pending") {
                print-warn "rpool restored crypt secrets, but its recovery cleanup is pending; run `rpool import` diagnostics or retry dotpull later."
            }
            {status: "restored" mode: "artifact" path: ($config | into string) secrets: $has_secret crypt: $crypt}
        }
    } catch {|err| $err })
    if ($stage_root | path exists) { rm --recursive --force $stage_root }
    if (($result | describe) | str starts-with "record") and (($result.status? | default "") in ["validated" "restored"]) {
        return $result
    }
    rethrow $result
}

def restore-legacy [bundle: path dry_run: bool] {
    validate-bundle $bundle | ignore

    let cap = (capability)
    require-usable $cap
    if not $cap.installed {
        error make {msg: ($cap.reason + "; an incoming portable bundle requires rpool before it can be restored.")}
    }
    if not $cap.legacy_config {
        error make {msg: "The synchronized rpool bundle uses the legacy JSON layout, but this rpool lacks `rpool config import`."}
    }

    let preview = (run-command $cap.executable ["config" "import" ($bundle | into string) "--dry-run"])
    if not $preview.ok {
        error make {msg: (command-failure-message "rpool config import --dry-run" $preview)}
    }
    if not (($preview.stdout? | default "" | str trim) | is-empty) {
        print-output-text ($preview.stdout | str trim --right)
    }
    if $dry_run {
        return {status: "validated" mode: "legacy" path: ($bundle | into string)}
    }

    let imported = (run-command $cap.executable ["config" "import" ($bundle | into string)])
    if not $imported.ok {
        error make {msg: (command-failure-message "rpool config import" $imported)}
    }
    if not (($imported.stdout? | default "" | str trim) | is-empty) {
        print-output-text ($imported.stdout | str trim --right)
    }
    {status: "restored" mode: "legacy" path: ($bundle | into string)}
}

# Top-level portable-config sections whose content differs (names only).
def differing-sections [local: record synced: record] {
    let keys = ($local | columns | append ($synced | columns) | uniq | where {|k| $k not-in $ARTIFACT_VOLATILE_FIELDS })
    $keys | where {|k| (($local | get --optional $k) | to json) != (($synced | get --optional $k) | to json) }
}

# Read-only check that this machine's rpool settings and crypt passwords match
# the private source. Exports to a private stage, compares in memory, and runs
# `rpool import --dry-run` to confirm the synchronized artifact is importable.
# Never writes the private source or rpool's active configuration and never
# returns secret values.
export def rpool-verify [root: path] {
    let cap = (capability)
    if not $cap.installed { return {status: "not-installed" detail: $cap.reason} }
    if not $cap.portable_config { return {status: "unsupported" detail: $cap.reason} }
    if not $cap.artifact { return {status: "unsupported" detail: "This rpool lacks `rpool export/import`; update rpool to 0.7+ to verify crypt passwords."} }
    let dest_config = (rpool-artifact-config-path $root)
    let dest_secret = (rpool-artifact-secret-path $root)
    if not ($dest_config | path exists) { return {status: "not-synchronized" detail: ("No rpool artifact in the private source yet: " + ($dest_config | into string) + ". Run dotpush.")} }
    let stage = (artifact-export $cap "rpool export for verification")
    let result = (try {
        let local = (validate-bundle $stage.config)
        let synced = (validate-bundle $dest_config)
        let config_match = ($local.artifact_semantic == $synced.artifact_semantic)
        let sections = if $config_match { [] } else { differing-sections $local.parsed $synced.parsed }
        let local_secret = ($stage.secret | path exists)
        let synced_secret = ($dest_secret | path exists)
        let secrets = if (not $local_secret) and (not $synced_secret) { "none" } else if $local_secret != $synced_secret {
            if $local_secret { "missing-in-private" } else { "missing-locally" }
        } else {
            let dec = (local-decryptor)
            if $dec == null { "unverifiable" } else {
                let synced_hash = (decrypted-sha256 $dec.age $dec.identity $dest_secret)
                let local_hash = (decrypted-sha256 $dec.age $dec.identity $stage.secret)
                if $synced_hash == null { "decrypt-failed" } else if $local_hash == null { "decrypt-failed-local" } else if $synced_hash == $local_hash { "match" } else { "differ" }
            }
        }
        {config_match: $config_match sections: $sections secrets: $secrets}
    } catch {|err| $err })
    if ($stage.stage_root | path exists) { rm --recursive --force $stage.stage_root }
    if not (($result | describe) | str starts-with "record") or ($result.config_match? == null) { rethrow $result }

    let plan = (try { artifact-import-plan $cap ($dest_secret | path exists) } catch {|err| {error: ($err.msg? | default "import preflight failed")} })
    let importable = if ($plan.error? != null) { {ok: false detail: $plan.error} } else {
        let probe_root = ((state-root) | path join "rpool-staging" (random uuid))
        let probe = (try {
            private-directory $probe_root
            let artifact_root = ($probe_root | path join "artifact")
            private-directory ($artifact_root | path join "config")
            private-directory ($artifact_root | path join "secrets")
            cp $dest_config ($artifact_root | path join "config" "portable-config.json")
            if ($dest_secret | path exists) { cp $dest_secret ($artifact_root | path join "secrets" "rclone.age") }
            let preview = (run-command $cap.executable (["import" ($artifact_root | into string)] | append $plan.args | append "--dry-run"))
            if $preview.ok { {ok: true detail: (crypt-restore-line ($preview.stdout? | default ""))} } else { {ok: false detail: (artifact-import-failure "rpool import --dry-run" $preview)} }
        } catch {|err| {ok: false detail: ($err.msg? | default "rpool import --dry-run failed")} })
        if ($probe_root | path exists) { rm --recursive --force $probe_root }
        $probe
    }
    let ok = ($result.config_match and ($result.secrets in ["match" "none"]) and $importable.ok)
    $result | merge {status: (if $ok { "match" } else { "differ" }) importable: $importable.ok import_detail: $importable.detail}
}

export def restore-rpool-config [root: path --dry-run] {
    let cap = (capability)
    if not $cap.installed {
        if ($cap.active_settings? | default false) {
            error make {msg: ("Active rpool settings exist but " + $cap.reason + "; refusing to skip rpool restore. Install rpool (or set RPOOL_BIN), then dotpull.")}
        }
        print-warn ("rpool is not installed; skipping rpool config restore. (" + $cap.reason + ")")
        return {status: "skipped"}
    }
    if ((rpool-artifact-config-path $root) | path exists) {
        return (restore-artifact $root $dry_run)
    }
    let bundle = (rpool-bundle-path $root)
    if not ($bundle | path exists) {
        return {status: "missing" path: ($bundle | into string)}
    }
    restore-legacy $bundle $dry_run
}

export def print-rpool-status [root: path] {
    let status = (rpool-sync-status $root)
    print-key-value "rpool executable      : " $status.executable
    print-key-value "rpool installed       : " ($status.installed | into string)
    print-key-value "Portable config API   : " (if $status.portable_config { "ready" } else { "unavailable" })
    print-key-value "Sync mode              : " (match $status.mode {
        "artifact" => "artifact (rpool export/import; crypt secrets via age vault)"
        "legacy" => "legacy (rpool config export/import; no crypt secrets)"
        _ => $status.mode
    })
    print-key-value "Synchronized layout    : " $status.layout
    print-key-value "Synchronized bundle    : " $status.bundle
    print-key-value "Bundle exists          : " ($status.bundle_exists | into string)
    print-key-value "Crypt secrets (age)    : " (if $status.artifact_secret_exists { $status.artifact_secret } else { "none" })
    if $status.artifact {
        print-key-value "Age vault configured   : " ((vault-configured) | into string)
    }
    if $status.installed {
        let result = (run-command $status.executable ["config" "paths"])
        let paths = if $result.ok {
            try { $result.stdout | from json } catch { null }
        } else { null }
        if $paths != null {
            print-key-value "Active GUI config      : " ($paths.gui? | default "unknown")
            print-key-value "Active pools config    : " ($paths.pools? | default "unknown")
            print-key-value "Active remote roots    : " ($paths.remote_roots? | default "unknown")
            if not ($paths.portable_encryption_preferences? | default false) {
                print-warn "This rpool build does not report portable encryption-preference support."
            }
        } else {
            print-warn "Update rpool for active-path diagnostics and encryption-preference synchronization."
        }
    }
    print-info "The synchronized bundle is an export, not the active gui.json. Import writes to rpool's platform-specific config directory."
    if $status.artifact {
        print-info "Artifact mode also carries crypt-remote passwords, age-encrypted to the vault recipient; import only updates crypt remotes that already exist in rclone.conf."
    } else if $status.layout == "artifact" {
        print-warn "The synchronized source uses the artifact layout; update rpool to 0.7+ on this machine."
    }
    if not ($status.reason | str trim | is-empty) { print-warn $status.reason }
    if $status.portable_config { print-ok "dotpush/dotpull rpool compatibility is ready." }
}
