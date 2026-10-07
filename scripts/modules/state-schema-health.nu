# Read-only schema health inventory shared by dotdoctor and migration status.
# This module never writes state, creates backups, or runs migrations.
const TOOLS_ROOT = path self ../..
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
const STATE_SCHEMA = path self ./state-schema.nu
const SYNC_STATE = path self ./sync-state.nu
const PROVIDER_STATE = path self ./provider-state.nu
const VAULT = path self ./vault.nu

use $CORE [project-schema-version try-read-nuon-record]
use $SAFETY [state-root]
use $STATE_SCHEMA [detect-state-schema state-schema-catalog]
use $SYNC_STATE [discover-sync-state-files validate-sync-state]
use $PROVIDER_STATE [discover-provider-state-files validate-provider-state]
use $VAULT [vault-config-path validate-vault-state]


def machine-schema-health [] {
    let file = ((state-root) | path join "config.nuon")
    let current = (project-schema-version $TOOLS_ROOT)
    let loaded = (try-read-nuon-record $file "state schema")
    if not $loaded.ok {
        let status = if $loaded.detail == "not initialized" { "not-initialized" } else { "invalid" }
        return {
            kind: "machine-config"
            file: $file
            detected: null
            current: $current
            source_field: "schema_version"
            status: $status
            migration_enabled: true
            detail: $loaded.detail
        }
    }

    let parsed_schema = (try {
        {ok: true value: ($loaded.value.schema_version? | default 0 | into int) detail: ""}
    } catch {
        {ok: false value: null detail: "schema_version is not integer-compatible"}
    })
    if not $parsed_schema.ok {
        return {
            kind: "machine-config"
            file: $file
            detected: null
            current: $current
            source_field: "schema_version"
            status: "invalid"
            migration_enabled: true
            detail: $parsed_schema.detail
        }
    }
    let detected = $parsed_schema.value
    if $detected < 0 {
        return {
            kind: "machine-config"
            file: $file
            detected: $detected
            current: $current
            source_field: "schema_version"
            status: "invalid"
            migration_enabled: true
            detail: "schema version cannot be negative"
        }
    }

    let status = if $detected > $current {
        "newer-than-supported"
    } else if $detected == $current {
        "current"
    } else {
        "migration-required"
    }
    {
        kind: "machine-config"
        file: $file
        detected: $detected
        current: $current
        source_field: "schema_version"
        status: $status
        migration_enabled: true
        detail: ""
    }
}


def state-row [kind: string file: path] {
    let current_row = (state-schema-catalog | where kind == $kind | first)
    let loaded = (try-read-nuon-record $file "state schema")
    if not $loaded.ok {
        return {
            kind: $kind
            file: $file
            detected: null
            current: $current_row.current
            source_field: ""
            status: "invalid"
            migration_enabled: ($current_row.migration_enabled? | default false)
            detail: $loaded.detail
        }
    }

    let detected_result = (try {
        {ok: true value: (detect-state-schema $kind $loaded.value) detail: ""}
    } catch {|err|
        {ok: false value: null detail: ($err.msg? | default ($err | into string))}
    })
    if not $detected_result.ok {
        return {
            kind: $kind
            file: $file
            detected: null
            current: $current_row.current
            source_field: ""
            status: "invalid"
            migration_enabled: ($current_row.migration_enabled? | default false)
            detail: $detected_result.detail
        }
    }
    let detected = $detected_result.value
    if $detected.status == "newer-than-supported" {
        return ($detected | merge {file: $file detail: ""})
    }

    let validated_result = (try {
        let validated = if $kind == "sync-state" {
            validate-sync-state $loaded.value
        } else if $kind == "provider-state" {
            validate-provider-state $loaded.value
        } else if $kind == "vault" {
            validate-vault-state $loaded.value
        } else {
            error make {msg: ("Unknown state kind: " + $kind)}
        }
        {ok: true value: $validated detail: ""}
    } catch {|err|
        {ok: false value: null detail: ($err.msg? | default ($err | into string))}
    })
    if not $validated_result.ok {
        return ($detected | merge {
            file: $file
            status: "invalid"
            detail: $validated_result.detail
        })
    }
    $validated_result.value | merge {file: $file detail: ""}
}


def missing-state-row [kind: string] {
    let current_row = (state-schema-catalog | where kind == $kind | first)
    {
        kind: $kind
        file: null
        detected: null
        current: $current_row.current
        source_field: ""
        status: "not-initialized"
        migration_enabled: ($current_row.migration_enabled? | default false)
        detail: "no state file exists yet"
    }
}


def state-schema-health [] {
    mut rows = []

    let sync_files = (discover-sync-state-files)
    if ($sync_files | is-empty) {
        $rows = ($rows | append (missing-state-row "sync-state"))
    } else {
        for file in $sync_files {
            $rows = ($rows | append (state-row "sync-state" $file))
        }
    }

    let provider_files = (discover-provider-state-files)
    if ($provider_files | is-empty) {
        $rows = ($rows | append (missing-state-row "provider-state"))
    } else {
        for file in $provider_files {
            $rows = ($rows | append (state-row "provider-state" $file))
        }
    }

    let vault_file = (vault-config-path)
    if ($vault_file | path exists) {
        $rows = ($rows | append (state-row "vault" $vault_file))
    } else {
        $rows = ($rows | append (missing-state-row "vault"))
    }

    $rows
}


export def schema-health [] {
    [(machine-schema-health)] | append (state-schema-health)
}
