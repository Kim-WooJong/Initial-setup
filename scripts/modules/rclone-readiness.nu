# Read-only readiness inspection for encrypted rclone configuration sync.
# This module never creates keys, mutates vault policy, or changes rclone.conf.
const CORE = path self ./core.nu
const INSTALL_UTILS = path self ./install-utils.nu
const SUBPROCESS = path self ./subprocess.nu
const CONSOLE = path self ./console.nu
const VAULT = path self ./vault.nu
use $CORE [nu-home machine-context]
use $INSTALL_UTILS [probe-tool]
use $SUBPROCESS [run-command]
use $CONSOLE [style print-heading print-status]
use $VAULT [vault-config-path read-vault-file validate-vault-state identity-recipient-status]

def probe-summary [name: string args: list] {
    let probe = (probe-tool $name $args)
    {
        found: $probe.found
        healthy: $probe.healthy
        path: ($probe.path? | default "")
        version: ($probe.version? | default "")
        diagnostic: (if $probe.healthy { "" } else if $probe.found { $probe.result.diagnostic? | default "unhealthy executable" } else { "not installed" })
    }
}

def active-rclone-config [rclone: record] {
    if not $rclone.healthy {
        return {discovered: false path: "" exists: false regular: false diagnostic: "rclone is unavailable or unhealthy"}
    }

    let result = (run-command $rclone.path ["config" "file"])
    if not $result.ok {
        return {discovered: false path: "" exists: false regular: false diagnostic: ($result.diagnostic? | default "rclone config file failed")}
    }

    let rows = ($result.stdout | lines | each {|line| $line | str trim } | where {|line| not ($line | is-empty) })
    if ($rows | is-empty) {
        return {discovered: false path: "" exists: false regular: false diagnostic: "rclone config file returned no path"}
    }

    let raw = ($rows | last)
    let absolute = if $nu.os-info.name == "windows" {
        ($raw =~ '^[A-Za-z]:[\\/]') or ($raw | str starts-with '\\')
    } else {
        $raw | str starts-with "/"
    }
    if not $absolute {
        return {discovered: false path: $raw exists: false regular: false diagnostic: "rclone config file returned a non-absolute path"}
    }

    let path = ($raw | path expand)
    let exists = ($path | path exists)
    let regular = if $exists { ($path | path type) == "file" } else { false }
    {
        discovered: true
        path: ($path | into string)
        exists: $exists
        regular: $regular
        diagnostic: (if $exists and (not $regular) { "active rclone config path is not a regular file" } else { "" })
    }
}

def vault-readiness [] {
    let path = (vault-config-path)
    if not ($path | path exists) {
        return {
            path: ($path | into string)
            exists: false
            regular: false
            valid: false
            policy_valid: false
            version: 0
            recipient_count: 0
            recipients_ready: false
            identity: ""
            identity_exists: false
            identity_regular: false
            diagnostic: "vault policy is not configured"
        }
    }
    if ($path | path type) != "file" {
        return {
            path: ($path | into string)
            exists: true
            regular: false
            valid: false
            policy_valid: false
            version: 0
            recipient_count: 0
            recipients_ready: false
            identity: ""
            identity_exists: false
            identity_regular: false
            diagnostic: "vault.nuon is not a regular file"
        }
    }

    try {
        let config = (read-vault-file $path)
        let schema = (validate-vault-state $config)
        let recipients = ($config.recipients? | default [])
        let recipients_ready = (not ($recipients | is-empty)) and (($recipients | all {|recipient| $recipient =~ '^age1[0-9a-z]+$' }))
        let identity_raw = ($config.identity? | default "" | into string | str trim)
        let identity = if ($identity_raw | is-empty) { "" } else { $identity_raw | path expand | into string }
        let identity_exists = if ($identity | is-empty) { false } else { $identity | path exists }
        let identity_regular = if $identity_exists { ($identity | path type) == "file" } else { false }
        {
            path: ($path | into string)
            exists: true
            regular: true
            valid: $recipients_ready
            policy_valid: true
            version: $schema.detected
            recipient_count: ($recipients | length)
            recipients_ready: $recipients_ready
            identity: $identity
            identity_exists: $identity_exists
            identity_regular: $identity_regular
            diagnostic: ""
        }
    } catch {|err|
        {
            path: ($path | into string)
            exists: true
            regular: true
            valid: false
            policy_valid: false
            version: 0
            recipient_count: 0
            recipients_ready: false
            identity: ""
            identity_exists: false
            identity_regular: false
            diagnostic: ($err.msg? | default "vault.nuon could not be parsed")
        }
    }
}

def encrypted-copy [data_root: path] {
    let path = ($data_root | path join "secrets" "rclone.age")
    let exists = ($path | path exists)
    let regular = if $exists { ($path | path type) == "file" } else { false }
    {
        path: ($path | into string)
        exists: $exists
        regular: $regular
        diagnostic: (if $exists and (not $regular) { "secrets/rclone.age is not a regular file" } else { "" })
    }
}

def append-issue [issues: list condition: bool message: string] {
    if $condition { $issues | append $message } else { $issues }
}

def rclone-readiness [] {
    let context = (machine-context)
    let feature_enabled = ($context.features.rclone_config? | default false)
    let rclone = (probe-summary "rclone" ["version"])
    let age = (probe-summary "age" ["--version"])
    let age_keygen = (probe-summary "age-keygen" ["--version"])
    let active = (active-rclone-config $rclone)
    let vault = (vault-readiness)
    let encrypted = (encrypted-copy ($context.data_root | path expand))
    let key_match = (try { identity-recipient-status } catch { {status: "unknown"} })

    mut push_issues = []
    mut pull_issues = []
    if not $feature_enabled {
        $push_issues = ["rclone_config feature is disabled"]
        $pull_issues = ["rclone_config feature is disabled"]
    } else {
        $push_issues = (append-issue $push_issues (not $rclone.healthy) "rclone is missing or unhealthy")
        $push_issues = (append-issue $push_issues (not $age.healthy) "age is missing or unhealthy")
        $push_issues = (append-issue $push_issues (not $vault.policy_valid) (if ($vault.diagnostic | is-empty) { "age vault policy is not ready" } else { $vault.diagnostic }))
        $push_issues = (append-issue $push_issues (not $vault.recipients_ready) "no valid age recipient is configured")
        $push_issues = (append-issue $push_issues (not $active.discovered) (if ($active.diagnostic | is-empty) { "active rclone config path cannot be discovered" } else { $active.diagnostic }))
        $push_issues = (append-issue $push_issues ($active.discovered and (not $active.exists)) "active rclone config does not exist yet")
        $push_issues = (append-issue $push_issues ($active.exists and (not $active.regular)) "active rclone config is not a regular file")
        $push_issues = (append-issue $push_issues ($encrypted.exists and (not $encrypted.regular)) "encrypted rclone destination is not a regular file")

        $pull_issues = (append-issue $pull_issues (not $rclone.healthy) "rclone is missing or unhealthy")
        $pull_issues = (append-issue $pull_issues (not $age.healthy) "age is missing or unhealthy")
        $pull_issues = (append-issue $pull_issues (not $vault.policy_valid) (if ($vault.diagnostic | is-empty) { "age vault policy is not ready" } else { $vault.diagnostic }))
        $pull_issues = (append-issue $pull_issues (not $vault.recipients_ready) "no valid age recipient is configured")
        $pull_issues = (append-issue $pull_issues (not $vault.identity_regular) "matching age identity is missing or invalid")
        $pull_issues = (append-issue $pull_issues ($key_match.status == "mismatch") "the local age identity is not the vault recipient. If this identity is your shared one, run `dotvault rekey --execute` to set the recipient to it, then dotpush. Otherwise restore the shared identity with `dotvault edit-identity`. (`dotctl verify` tests actual decryption.)")
        $pull_issues = (append-issue $pull_issues (not $encrypted.exists) "encrypted rclone copy is not available")
        $pull_issues = (append-issue $pull_issues ($encrypted.exists and (not $encrypted.regular)) "encrypted rclone copy is not a regular file")
        $pull_issues = (append-issue $pull_issues (not $active.discovered) (if ($active.diagnostic | is-empty) { "active rclone config path cannot be discovered" } else { $active.diagnostic }))
        $pull_issues = (append-issue $pull_issues ($active.exists and (not $active.regular)) "active rclone config is not a regular file")
    }

    {
        feature_enabled: $feature_enabled
        tools: {rclone: $rclone age: $age age_keygen: $age_keygen}
        active_config: $active
        vault: $vault
        encrypted_copy: $encrypted
        key_match: $key_match
        push: {ready: ($push_issues | is-empty) issues: $push_issues}
        pull: {ready: ($pull_issues | is-empty) issues: $pull_issues}
    }
}

def yes-no [value: bool] { if $value { "yes" } else { "no" } }
def health-text [probe: record] { if $probe.healthy { "ready" } else if $probe.found { "unhealthy" } else { "not installed" } }
def readiness-text [enabled: bool ready: bool issues: list] {
    if not $enabled { "DISABLED" } else if $ready { "READY" } else { "NOT READY — " + ($issues | get 0? | default "requirements are incomplete") }
}
def render-line [label: string value: string kind: string = ""] {
    let prefix = (style "label" ($label + ": "))
    let rendered = if ($kind | is-empty) { $value } else { style $kind $value }
    print ($prefix + $rendered)
}

export def print-rclone-readiness [--heading] {
    let state = (rclone-readiness)
    if $heading { print-heading "Rclone encrypted synchronization" }

    render-line "Feature" (if $state.feature_enabled { "enabled" } else { "disabled" }) (if $state.feature_enabled { "ok" } else { "warn" })
    render-line "Active config" (if $state.active_config.discovered { $state.active_config.path } else { "<unavailable>" })
    render-line "Config exists" (yes-no $state.active_config.exists) (if $state.active_config.exists and $state.active_config.regular { "ok" } else { "warn" })
    render-line "rclone" (health-text $state.tools.rclone) (if $state.tools.rclone.healthy { "ok" } else if $state.feature_enabled { "error" } else { "warn" })
    render-line "age" (health-text $state.tools.age) (if $state.tools.age.healthy { "ok" } else if $state.feature_enabled { "error" } else { "warn" })
    render-line "age-keygen" (health-text $state.tools.age_keygen) (if $state.tools.age_keygen.healthy { "ok" } else { "warn" })
    render-line "Vault policy" (if $state.vault.policy_valid { "ready" } else { "not ready" }) (if $state.vault.policy_valid { "ok" } else if $state.feature_enabled { "error" } else { "warn" })
    render-line "Recipients" (($state.vault.recipient_count | into string) + (if $state.vault.recipients_ready { " valid" } else { " valid required" })) (if $state.vault.recipients_ready { "ok" } else if $state.feature_enabled { "error" } else { "warn" })
    render-line "Identity" (if $state.vault.identity_regular { "present" } else { "missing or invalid" }) (if $state.vault.identity_regular { "ok" } else { "warn" })
    render-line "Identity key" (match $state.key_match.status { "match" => "matches a vault recipient" "mismatch" => "MISMATCH: not a vault recipient" _ => $state.key_match.status }) (if $state.key_match.status == "match" { "ok" } else if $state.key_match.status == "mismatch" { "error" } else { "warn" })
    render-line "Encrypted copy" (if $state.encrypted_copy.regular { "available" } else if $state.encrypted_copy.exists { "invalid" } else { "not available" }) (if $state.encrypted_copy.regular { "ok" } else { "warn" })
    render-line "Push" (readiness-text $state.feature_enabled $state.push.ready $state.push.issues) (if not $state.feature_enabled { "warn" } else if $state.push.ready { "ok" } else { "error" })
    render-line "Pull" (readiness-text $state.feature_enabled $state.pull.ready $state.pull.issues) (if not $state.feature_enabled { "warn" } else if $state.pull.ready { "ok" } else { "error" })

    if not $state.push.ready {
        for issue in ($state.push.issues | skip 1) { print-status "warn" "push" $issue }
    }
    if not $state.pull.ready {
        for issue in ($state.pull.issues | skip 1) { print-status "warn" "pull" $issue }
    }

    $state
}
