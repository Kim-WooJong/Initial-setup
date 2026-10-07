# Shared schema registry and safe migration primitives for machine-local state.
#
# This module intentionally does not define concrete migration transforms.
# The all-state transaction owns migration ordering; these helpers provide
# version detection, compatibility checks, verified backups, and atomic
# commit/rollback behavior.
const CORE = path self ./core.nu
use $CORE [error-message]
const SAFETY = path self ./safety.nu
use $SAFETY [state-root private-directory private-file atomic-record]

export def state-schema-catalog [] {
    [
        {kind: "sync-state" current: 3 canonical_field: "schema_version" legacy_field: "version" migration_enabled: true}
        {kind: "provider-state" current: 2 canonical_field: "schema_version" legacy_field: "version" migration_enabled: true}
        {kind: "vault" current: 2 canonical_field: "schema_version" legacy_field: "version" migration_enabled: true}
    ]
}

export def current-state-schema [kind: string] {
    let rows = (state-schema-catalog | where kind == $kind)
    if ($rows | length) != 1 {
        error make {msg: ("Unknown state schema kind: " + $kind)}
    }
    ($rows | first).current
}

export def detect-state-schema [kind: string value: record] {
    let rows = (state-schema-catalog | where kind == $kind)
    if ($rows | length) != 1 {
        error make {msg: ("Unknown state schema kind: " + $kind)}
    }
    let current = (($rows | first).current)
    let canonical = ($value | get --optional schema_version)
    let legacy = ($value | get --optional version)
    let canonical_value = if $canonical == null { null } else {
        try { $canonical | into int } catch {
            error make {msg: ("Invalid schema_version in " + $kind + ": expected an integer-compatible value.")}
        }
    }
    let legacy_value = if $legacy == null { null } else {
        try { $legacy | into int } catch {
            error make {msg: ("Invalid legacy version in " + $kind + ": expected an integer-compatible value.")}
        }
    }
    if $canonical_value != null and $legacy_value != null and $canonical_value != $legacy_value {
        error make {msg: ("Conflicting schema_version/version fields in " + $kind + ". Refusing to guess which state schema is authoritative.")}
    }
    let source = if $canonical_value != null and $legacy_value != null {
        "both"
    } else if $canonical_value != null {
        "schema_version"
    } else if $legacy_value != null {
        "version"
    } else {
        "missing"
    }
    let detected = if $canonical_value != null { $canonical_value } else if $legacy_value != null { $legacy_value } else { 0 }
    let status = if $detected > $current {
        "newer-than-supported"
    } else if $detected == $current and $source == "schema_version" {
        "current"
    } else {
        "migration-required"
    }
    let row = ($rows | first)
    {
        kind: $kind
        detected: $detected
        current: $current
        source_field: $source
        migration_enabled: ($row.migration_enabled? | default false)
        status: $status
    }
}

export def assert-state-schema-readable [kind: string value: record] {
    let status = (detect-state-schema $kind $value)
    if $status.status == "newer-than-supported" {
        error make {
            msg: (
                $kind + " schema " + ($status.detected | into string) +
                " is newer than this Initial-setup supports (" + ($status.current | into string) + ")."
            )
        }
    }
    $status
}

export def state-migration-backup-root [] {
    (state-root) | path join "state-migration-backups"
}

# Create an owner-only, content-verified backup before a state migration.
# The returned directory is intentionally retained for manual recovery.
export def backup-state-file [kind: string file: path from_schema: int to_schema: int] {
    current-state-schema $kind | ignore
    if not ($file | path exists) or (($file | path type) != "file") {
        error make {msg: ("State migration backup requires a regular file: " + ($file | into string))}
    }

    let root = (state-migration-backup-root)
    private-directory $root
    let id = ((date now | format date "%Y%m%d-%H%M%S") + "-" + (random uuid))
    let dir = ($root | path join $kind $id)
    private-directory $dir
    let backup = ($dir | path join ($file | path basename))
    let before = (open --raw $file | hash sha256)
    cp $file $backup
    private-file $backup
    let after = (open --raw $backup | hash sha256)
    if $before != $after {
        try { rm --recursive --force $dir } catch { }
        error make {msg: "State migration backup hash verification failed; the live state was not changed."}
    }

    let metadata = {
        version: 1
        kind: $kind
        source: ($file | path expand | into string)
        backup: ($backup | path expand | into string)
        from_schema: $from_schema
        to_schema: $to_schema
        sha256: $before
        created_at: (date now | format date "%+")
    }
    let metadata_file = ($dir | path join "migration.nuon")
    atomic-record $metadata_file $metadata
    private-file $metadata_file
    {directory: $dir file: $backup sha256: $before metadata: $metadata_file}
}

# Restore the exact verified backup bytes to a live state path. This is used by
# multi-file migration transactions so already-committed state can be rolled
# back in reverse order if a later migration fails.
export def restore-state-backup [kind: string file: path backup: record --private] {
    current-state-schema $kind | ignore
    let backup_file = ($backup.file | path expand)
    if not ($backup_file | path exists) or (($backup_file | path type) != "file") {
        error make {msg: ("State migration recovery backup is missing: " + ($backup_file | into string))}
    }
    let expected = ($backup.sha256? | default "" | into string | str trim)
    if not ($expected =~ '^[a-f0-9]{64}$') {
        error make {msg: "State migration recovery backup has an invalid SHA-256 record."}
    }
    let actual = (open --raw $backup_file | hash sha256)
    if $actual != $expected {
        error make {msg: "State migration recovery backup failed SHA-256 verification."}
    }

    mkdir ($file | path dirname)
    let temp = (($file | into string) + ".rollback-" + (random uuid))
    try {
        cp $backup_file $temp
        if (open --raw $temp | hash sha256) != $expected {
            error make {msg: "Rollback staging copy failed SHA-256 verification."}
        }
        mv --force $temp $file
        if $private { private-file $file }
        if (open --raw $file | hash sha256) != $expected {
            error make {msg: "Rollback verification failed after restoring the live state."}
        }
    } catch {|err|
        if ($temp | path exists) { try { rm --force $temp } catch { } }
        error make {msg: ("State migration rollback failed for " + ($file | into string) + ": " + (error-message $err))}
    }
}

# Commit a state record after a transaction has already backed up every pending
# file. The live file must still match the preflight backup hash; otherwise the
# transaction stops rather than overwriting concurrent state changes.
export def commit-prepared-state-migration [kind: string file: path original: record migrated: record backup: record --private] {
    let before = (detect-state-schema $kind $original)
    let after = (detect-state-schema $kind $migrated)
    if $after.detected != $after.current or $after.source_field != "schema_version" {
        error make {msg: ("Prepared " + $kind + " migration is not at the current canonical schema.")}
    }
    let expected = ($backup.sha256? | default "" | into string | str trim)
    if not ($expected =~ '^[a-f0-9]{64}$') {
        error make {msg: "Prepared migration backup has an invalid SHA-256 record."}
    }
    if not ($file | path exists) or (($file | path type) != "file") {
        error make {msg: ("State file changed after migration preflight: " + ($file | into string))}
    }
    if (open --raw $file | hash sha256) != $expected {
        error make {msg: ("State file changed after migration preflight; refusing to commit: " + ($file | into string))}
    }

    let write_error = (try {
        atomic-record $file $migrated
        if $private { private-file $file }
        let saved = (open --raw $file | from nuon)
        let saved_status = (detect-state-schema $kind $saved)
        if $saved_status.status != "current" or $saved != $migrated {
            error make {msg: "Migrated state verification failed after atomic replacement."}
        }
        null
    } catch {|err| $err })

    if $write_error != null {
        let rollback_error = (try {
            if $private { restore-state-backup $kind $file $backup --private } else { restore-state-backup $kind $file $backup }
            null
        } catch {|err| $err })
        if $rollback_error != null {
            error make {msg: (
                "STATE_ROLLBACK_FAILED: State migration commit failed and immediate rollback also failed for " +
                ($file | into string) + ". Recovery backup: " + ($backup.file | into string)
            )}
        }
        error make {msg: (
            "State migration commit failed; this file was restored before aborting the transaction. Recovery backup: " +
            ($backup.file | into string)
        )}
    }

    {kind: $kind file: $file from_schema: $before.detected to_schema: $after.detected backup: $backup.file}
}
