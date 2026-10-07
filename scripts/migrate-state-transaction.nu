#!/usr/bin/env nu

# One transaction boundary for machine-config plus sync/provider/vault schema
# migrations. Every pending file is preflighted and backed up before the first
# commit. A later failure rolls back every file changed by this invocation.
const TOOLS_ROOT = path self ..
const CORE = path self ./modules/core.nu
use $CORE [error-message]
const SAFETY = path self ./modules/safety.nu
const STATE_SCHEMA = path self ./modules/state-schema.nu
const SYNC_STATE = path self ./modules/sync-state.nu
const PROVIDER_STATE = path self ./modules/provider-state.nu
const VAULT = path self ./modules/vault.nu
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
const MIGRATE_CONFIG = path self ./migrate-config.nu

use $SAFETY [state-root private-directory private-file atomic-record operation-lease release-lease]
use $STATE_SCHEMA [
    backup-state-file
    commit-prepared-state-migration
    detect-state-schema
    restore-state-backup
    state-migration-backup-root
]
use $SYNC_STATE [discover-sync-state-files read-sync-state validate-sync-state canonical-sync-state]
use $PROVIDER_STATE [discover-provider-state-files read-provider-state validate-provider-state canonical-provider-state]
use $VAULT [vault-config-path read-vault-file validate-vault-state canonical-vault]
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-heading print-key-value print-output-text print-status]


def machine-config-plan [] {
    let file = ((state-root) | path join "config.nuon")
    let current = (open --raw ($TOOLS_ROOT | path join "SCHEMA_VERSION") | str trim | into int)
    if not ($file | path exists) {
        return {kind: "machine-config" file: $file exists: false pending: false from_schema: null to_schema: $current}
    }
    if ($file | path type) != "file" {
        error make {msg: ("Machine config is not a regular file: " + ($file | into string))}
    }
    let value = (try { open --raw $file | from nuon } catch {|err|
        error make {msg: ("Unable to parse machine config as NUON: " + (error-message $err))}
    })
    if not (($value | describe) | str starts-with "record") {
        error make {msg: "Machine config must contain a NUON record."}
    }
    let detected = (try { $value.schema_version? | default 0 | into int } catch {
        error make {msg: "Machine config schema_version must be integer-compatible."}
    })
    if $detected < 0 {
        error make {msg: "Machine config has an invalid negative schema version."}
    }
    if $detected > $current {
        error make {msg: ("Machine config schema " + ($detected | into string) + " is newer than supported " + ($current | into string) + ".")}
    }
    {kind: "machine-config" file: $file exists: true pending: ($detected < $current) from_schema: $detected to_schema: $current}
}


def prepare-state-plan [] {
    mut rows = []
    for file in (discover-sync-state-files) {
        let original = (read-sync-state $file)
        let schema = (validate-sync-state $original)
        if $schema.status == "migration-required" {
            $rows = ($rows | append {
                kind: "sync-state"
                file: $file
                from_schema: $schema.detected
                to_schema: $schema.current
                private: false
                original: $original
                migrated: (canonical-sync-state $original)
            })
        }
    }
    for file in (discover-provider-state-files) {
        let original = (read-provider-state $file)
        let schema = (validate-provider-state $original)
        if $schema.status == "migration-required" {
            $rows = ($rows | append {
                kind: "provider-state"
                file: $file
                from_schema: $schema.detected
                to_schema: $schema.current
                private: false
                original: $original
                migrated: (canonical-provider-state $original)
            })
        }
    }
    let vault_file = (vault-config-path)
    if ($vault_file | path exists) {
        if ($vault_file | path type) != "file" {
            error make {msg: ("Vault policy is not a regular file: " + ($vault_file | into string))}
        }
        let original = (read-vault-file $vault_file)
        let schema = (validate-vault-state $original)
        if $schema.status == "migration-required" {
            $rows = ($rows | append {
                kind: "vault"
                file: $vault_file
                from_schema: $schema.detected
                to_schema: $schema.current
                private: true
                original: $original
                migrated: (canonical-vault $original)
            })
        }
    }
    $rows
}


def backup-machine-config [plan: record] {
    let root = (state-migration-backup-root)
    private-directory $root
    let id = ((date now | format date "%Y%m%d-%H%M%S") + "-" + (random uuid))
    let dir = ($root | path join "machine-config" $id)
    private-directory $dir
    let backup = ($dir | path join "config.nuon")
    let before = (open --raw $plan.file | hash sha256)
    cp $plan.file $backup
    private-file $backup
    if (open --raw $backup | hash sha256) != $before {
        try { rm --recursive --force $dir } catch { }
        error make {msg: "Machine-config migration backup failed SHA-256 verification."}
    }
    let metadata = {
        version: 1
        kind: "machine-config"
        source: ($plan.file | path expand | into string)
        backup: ($backup | path expand | into string)
        from_schema: $plan.from_schema
        to_schema: $plan.to_schema
        sha256: $before
        created_at: (date now | format date "%+")
    }
    let metadata_file = ($dir | path join "migration.nuon")
    atomic-record $metadata_file $metadata
    private-file $metadata_file
    {directory: $dir file: $backup sha256: $before metadata: $metadata_file}
}


def restore-raw-backup [file: path backup: record --private] {
    let source = ($backup.file | path expand)
    let expected = ($backup.sha256 | into string)
    if not ($source | path exists) or (($source | path type) != "file") {
        error make {msg: ("Migration recovery backup is missing: " + ($source | into string))}
    }
    if (open --raw $source | hash sha256) != $expected {
        error make {msg: "Migration recovery backup failed SHA-256 verification."}
    }
    mkdir ($file | path dirname)
    let temp = (($file | into string) + ".rollback-" + (random uuid))
    try {
        cp $source $temp
        if (open --raw $temp | hash sha256) != $expected {
            error make {msg: "Migration rollback staging copy failed SHA-256 verification."}
        }
        mv --force $temp $file
        if $private { private-file $file }
        if (open --raw $file | hash sha256) != $expected {
            error make {msg: "Migration rollback verification failed."}
        }
    } catch {|err|
        if ($temp | path exists) { try { rm --force $temp } catch { } }
        error make {msg: (error-message $err)}
    }
}


def transaction-dir [] {
    let root = ((state-migration-backup-root) | path join "transactions")
    private-directory $root
    let dir = ($root | path join ((date now | format date "%Y%m%d-%H%M%S") + "-" + (random uuid)))
    private-directory $dir
    $dir
}


def write-transaction [dir: path status: string machine: record state_rows: list --detail: string = ""] {
    let rows = ($state_rows | each {|row|
        {
            kind: $row.kind
            file: ($row.file | path expand | into string)
            from_schema: $row.from_schema
            to_schema: $row.to_schema
            backup: ($row.backup.file | path expand | into string)
            sha256: $row.backup.sha256
        }
    })
    let machine_row = if ($machine.pending? | default false) and ($machine.backup? | default null) != null {
        {
            kind: "machine-config"
            file: ($machine.file | path expand | into string)
            from_schema: $machine.from_schema
            to_schema: $machine.to_schema
            backup: ($machine.backup.file | path expand | into string)
            sha256: $machine.backup.sha256
        }
    } else { null }
    let files = if $machine_row == null { $rows } else { [$machine_row] | append $rows }
    let manifest = {
        version: 1
        status: $status
        created_at: (date now | format date "%+")
        detail: $detail
        files: $files
    }
    let file = ($dir | path join "transaction.nuon")
    atomic-record $file $manifest
    private-file $file
    $file
}


def show-plan [machine: record state_rows: list] {
    print-heading "Schema migration transaction plan"
    if $machine.exists {
        print-key-value "Machine config : " ($machine.file | into string)
        if $machine.pending {
            print-status "warn" "migrate" (("schema " + ($machine.from_schema | into string)) + " -> " + ($machine.to_schema | into string))
        } else {
            print-status "ok" "ok" (("schema " + ($machine.to_schema | into string)) + " is current")
        }
    } else {
        print-status "ok" "ok" "No machine config exists; nothing to migrate there."
    }
    for row in $state_rows {
        print-key-value "State          : " $row.kind
        print-key-value "File           : " ($row.file | into string)
        print-status "warn" "migrate" (("schema " + ($row.from_schema | into string)) + " -> " + ($row.to_schema | into string))
    }
    if (not $machine.pending) and ($state_rows | is-empty) {
        print-status "ok" "ok" "All discovered schemas are current."
    }
}


def apply-transaction [machine_plan: record state_plan: list] {
    if (not $machine_plan.pending) and ($state_plan | is-empty) {
        print-status "ok" "ok" "No schema migration is required."
        return
    }

    # Phase 1: every pending file receives a verified backup before any commit.
    mut machine = $machine_plan
    if $machine.pending {
        $machine = ($machine | upsert backup (backup-machine-config $machine))
    }
    mut prepared = []
    for row in $state_plan {
        let backup = (backup-state-file $row.kind $row.file $row.from_schema $row.to_schema)
        $prepared = ($prepared | append ($row | upsert backup $backup))
    }

    let tx_dir = (transaction-dir)
    let tx_file = (write-transaction $tx_dir "prepared" $machine $prepared)
    print-key-value "Transaction : " ($tx_dir | into string)
    print-status "ok" "backup" "All pending migration files have verified recovery backups."

    mut machine_touched = false
    mut committed = []
    let failure = (try {
        if $machine.pending {
            if (open --raw $machine.file | hash sha256) != $machine.backup.sha256 {
                error make {msg: "Machine config changed after migration preflight; refusing to commit."}
            }
            $machine_touched = true
            let result = (run-command $nu.current-exe [
                "--no-config-file"
                $MIGRATE_CONFIG
                "--transaction"
                "--expected-sha256"
                $machine.backup.sha256
            ])
            if not $result.ok {
                error make {msg: (command-failure-message "Machine config migration" $result)}
            }
            let saved = (open --raw $machine.file | from nuon)
            let saved_schema = ($saved.schema_version? | default (-1) | into int)
            if $saved_schema != $machine.to_schema {
                error make {msg: "Machine config migration did not produce the expected schema."}
            }
            if not ($result.stdout | str trim | is-empty) { print-output-text ($result.stdout | str trim --right) }
            if not ($result.stderr | str trim | is-empty) { print-output-text ($result.stderr | str trim --right) --stderr }
        }

        for row in $prepared {
            if $row.private {
                commit-prepared-state-migration $row.kind $row.file $row.original $row.migrated $row.backup --private | ignore
            } else {
                commit-prepared-state-migration $row.kind $row.file $row.original $row.migrated $row.backup | ignore
            }
            $committed = ($committed | append $row)
            print-status "ok" "migrated" (($row.kind + " | ") + ($row.file | into string))
        }
        null
    } catch {|err| $err })

    if $failure == null {
        write-transaction $tx_dir "committed" $machine $prepared | ignore
        print-status "ok" "ok" "Schema migration transaction committed successfully. Recovery backups were retained."
        return
    }

    # Phase 3: rollback every file changed by this transaction, in reverse order.
    # A state commit performs its own immediate rollback. If that rollback failed,
    # preserve the failure explicitly so the transaction cannot be mislabeled as
    # fully rolled back merely because earlier files restored successfully.
    let failure_message = (error-message $failure)
    mut rollback_errors = if ($failure_message | str contains "STATE_ROLLBACK_FAILED:") {
        [$failure_message]
    } else {
        []
    }
    for row in ($committed | reverse) {
        let err = (try {
            if $row.private {
                restore-state-backup $row.kind $row.file $row.backup --private
            } else {
                restore-state-backup $row.kind $row.file $row.backup
            }
            null
        } catch {|rollback_err| $rollback_err })
        if $err != null {
            $rollback_errors = ($rollback_errors | append (($row.kind + ": ") + (error-message $err)))
        }
    }
    if $machine_touched {
        let err = (try { restore-raw-backup $machine.file $machine.backup --private; null } catch {|rollback_err| $rollback_err })
        if $err != null {
            $rollback_errors = ($rollback_errors | append ("machine-config: " + (error-message $err)))
        }
    }

    let original_message = $failure_message
    if ($rollback_errors | is-empty) {
        write-transaction $tx_dir "rolled-back" $machine $prepared --detail=$original_message | ignore
        error make {msg: ("Schema migration transaction failed; every committed file was restored. Transaction: " + ($tx_file | into string) + (char nl) + $original_message)}
    }

    let rollback_detail = ($rollback_errors | str join (char nl))
    write-transaction $tx_dir "rollback-failed" $machine $prepared --detail=($original_message + (char nl) + $rollback_detail) | ignore
    error make {msg: (
        "Schema migration transaction failed and one or more rollback operations also failed. " +
        "Use the verified backups recorded in: " + ($tx_file | into string) + (char nl) +
        $original_message + (char nl) + $rollback_detail
    )}
}


def main [--check] {
    if $check {
        let machine = (machine-config-plan)
        let states = (prepare-state-plan)
        show-plan $machine $states
        return
    }

    let lease = (operation-lease)
    let outcome = (try {
        let machine = (machine-config-plan)
        let states = (prepare-state-plan)
        show-plan $machine $states
        apply-transaction $machine $states
        {ok: true error: null}
    } catch {|err| {ok: false error: $err} })
    release-lease $lease
    if not $outcome.ok {
        error make {msg: (error-message $outcome.error)}
    }
}
