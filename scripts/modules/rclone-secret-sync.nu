# Prepared, authenticated rclone.conf restore for dotpull.
# Incoming age ciphertext is decrypted into a machine-local restricted staging
# directory before any live configuration is changed. The verified plaintext is
# committed later, after chezmoi/work-environment apply has started successfully.
const CORE = path self ./core.nu
const VAULT = path self ./vault.nu
const SAFETY = path self ./safety.nu
const CONSOLE = path self ./console.nu
const TEXT_CASE = path self ./text-case.nu
use $CORE [error-message]
use $VAULT [vault-configured ensure-rclone-entry load-vault record-secret-sync-state]
use $SAFETY [state-root checked private-directory private-file]
use $CONSOLE [print-status print-warn print-key-value]
use $TEXT_CASE [text-lower]

def normalized-path [value: path] {
    let expanded = ($value | path expand | into string | str replace --all '\' '/' | str trim --right --char '/')
    if $nu.os-info.name == "windows" { $expanded | text-lower } else { $expanded }
}

def file-sha256 [file: path] {
    let target = ($file | path expand)
    if not ($target | path exists) { error make {msg: ("Expected file is missing: " + ($target | into string))} }
    if ($target | path type) != "file" { error make {msg: ("Expected a regular file: " + ($target | into string))} }
    open --raw $target | hash sha256
}

const RCLONE_BACKUP_KEEP = 5
const UUID_DIR_PATTERN = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

def rclone-backups-root [] { (state-root) | path join "rclone-restore-backups" }

# Keep only the newest RCLONE_BACKUP_KEEP plaintext recovery backups. Only real
# directories named like `random uuid` directly under the backups root are
# candidates; symlinks (root or entries) are never followed or removed, and the
# backup that was just created is always kept.
def prune-rclone-backups [keep_dir: path] {
    let backups_root = (rclone-backups-root)
    if not ($backups_root | path exists) or (($backups_root | path type) != "dir") { return }
    let keep = (normalized-path $keep_dir)
    let stale = (
        ls --all $backups_root
        | where type == "dir"
        | where {|row| ($row.name | path basename) =~ $UUID_DIR_PATTERN }
        | where {|row| (normalized-path $row.name) != $keep }
        | sort-by modified --reverse
        | skip ([($RCLONE_BACKUP_KEEP - 1) 0] | math max)
    )
    for row in $stale {
        let dir = ($row.name | path expand --no-symlink)
        if ($dir | path type) != "dir" { continue }
        try { rm --recursive --force $dir } catch {
            print-warn ("Old restricted rclone backup could not be pruned: " + ($dir | into string))
        }
    }
}

def backup-existing-rclone [destination: path] {
    let target = ($destination | path expand)
    if not ($target | path exists) { return null }
    if ($target | path type) != "file" { error make {msg: "The active rclone config is not a regular file."} }

    let root = ((rclone-backups-root) | path join (random uuid))
    private-directory $root
    let backup = ($root | path join "rclone.conf")
    cp $target $backup
    private-file $backup
    if (file-sha256 $target) != (file-sha256 $backup) {
        rm --recursive --force $root
        error make {msg: "rclone config backup verification failed; encrypted restore was not started."}
    }
    try { prune-rclone-backups $root } catch {|err|
        print-warn (error-message $err "Old restricted rclone backups could not be pruned.")
    }
    $root
}

export def discard-prepared-rclone [prepared: record] {
    if ($prepared.status? | default "") != "prepared" { return }
    let stage = ($prepared.stage_dir? | default "" | str trim)
    if ($stage | is-empty) { return }
    let path = ($stage | path expand)
    if ($path | path exists) {
        try { rm --recursive --force $path } catch {
            print-warn ("Restricted prepared rclone plaintext remains at: " + ($path | into string))
        }
    }
}

export def prepare-rclone-restore [source_root: path] {
    let root = ($source_root | path expand)
    let ciphertext = ($root | path join "secrets" "rclone.age")
    if not ($ciphertext | path exists) {
        print-warn "No encrypted rclone config exists in the pulled private source; the local rclone config will be left unchanged."
        return {status: "missing"}
    }
    if ($ciphertext | path type) != "file" { error make {msg: "Pulled secrets/rclone.age is not a regular file."} }

    if not (vault-configured) {
        error make {msg: "The pulled source contains secrets/rclone.age, but this machine has no age vault identity. Restore the matching offline age identity and vault policy, then retry dotpull. No live configuration was changed."}
    }

    let entry = (ensure-rclone-entry)
    let destination = ($entry.local | path expand)
    let ciphertext_hash = (file-sha256 $ciphertext)
    let local_hash = if not ($destination | path exists) {
        ""
    } else if ($destination | path type) == "file" {
        file-sha256 $destination
    } else {
        error make {msg: "The active rclone config path exists but is not a regular file."}
    }
    let known_plaintext = ($entry.last_plaintext_sha256? | default "")
    let known_ciphertext = ($entry.last_ciphertext_sha256? | default "")

    # Incoming ciphertext identical to the last synced ciphertext carries no new
    # information. Restoring it would roll back local-only changes such as OAuth
    # token refreshes, so skip regardless of the local plaintext state. A missing
    # local file is still restored.
    if not ($local_hash | is-empty) and not ($known_ciphertext | is-empty) and $ciphertext_hash == $known_ciphertext {
        if $local_hash == $known_plaintext {
            print-status "ok" "rclone" "Incoming encrypted rclone config already matches the active machine config."
        } else {
            print-status "ok" "rclone" "Incoming encrypted rclone config is unchanged since the last sync; keeping newer local rclone config."
            print-warn "Local rclone config has changes not yet published; run dotpush to capture them."
        }
        return {
            status: "current"
            destination: ($destination | into string)
            ciphertext_sha256: $ciphertext_hash
            plaintext_sha256: $local_hash
        }
    }

    let config = (load-vault)
    let identity = ($config.identity | path expand)
    if not ($identity | path exists) {
        error make {msg: "Local age identity is missing. Recover the matching identity from the offline backup, then retry dotpull. No live configuration was changed."}
    }
    if ($identity | path type) != "file" { error make {msg: "The configured age identity is not a regular file."} }
    if (which age | is-empty) { error make {msg: "age is required to authenticate the incoming rclone config before dotpull can modify local configuration."} }

    let stage_dir = ((state-root) | path join "rclone-pull-staging" (random uuid))
    private-directory $stage_dir
    let plaintext = ($stage_dir | path join "rclone.conf")
    print-status "info" "rclone" "Authenticating the incoming encrypted rclone config before local apply..."

    let prepared = (try {
        checked "age" ["--decrypt" "--identity" $identity "--output" $plaintext $ciphertext] "Preflight decrypt/authenticate rclone config" | ignore
        private-file $plaintext
        let after_hash = (file-sha256 $ciphertext)
        if $after_hash != $ciphertext_hash {
            error make {msg: "Incoming secrets/rclone.age changed while it was being authenticated. Retry after the private source is stable."}
        }
        let plaintext_hash = (file-sha256 $plaintext)
        {
            status: "prepared"
            stage_dir: ($stage_dir | into string)
            plaintext: ($plaintext | into string)
            destination: ($destination | into string)
            ciphertext: ($ciphertext | into string)
            ciphertext_sha256: $ciphertext_hash
            plaintext_sha256: $plaintext_hash
        }
    } catch {|err| if ($stage_dir | path exists) { try { rm --recursive --force $stage_dir } catch { } }
        error make {msg: (error-message $err "Incoming rclone config authentication failed before local apply. No live configuration was changed.")}
    })

    print-status "ok" "rclone" "Incoming encrypted rclone config authenticated; local apply may proceed."
    $prepared
}

export def commit-prepared-rclone [prepared: record] {
    if ($prepared.status? | default "") != "prepared" { return null }

    let stage_dir = ($prepared.stage_dir | path expand)
    let plaintext = ($prepared.plaintext | path expand)
    let ciphertext = ($prepared.ciphertext | path expand)
    let expected_plaintext = ($prepared.plaintext_sha256 | into string)
    let expected_ciphertext = ($prepared.ciphertext_sha256 | into string)

    if not ($expected_plaintext =~ '^[a-f0-9]{64}$') or not ($expected_ciphertext =~ '^[a-f0-9]{64}$') {
        discard-prepared-rclone $prepared
        error make {msg: "Prepared rclone restore metadata contains invalid SHA-256 values."}
    }
    if (file-sha256 $plaintext) != $expected_plaintext {
        discard-prepared-rclone $prepared
        error make {msg: "Prepared rclone plaintext changed before commit; local rclone config was not replaced."}
    }
    if (file-sha256 $ciphertext) != $expected_ciphertext {
        discard-prepared-rclone $prepared
        error make {msg: "Incoming encrypted rclone config changed after preflight; local rclone config was not replaced."}
    }

    # Re-discover the active path after chezmoi/work-environment application. If
    # that path changed, fail closed instead of writing verified plaintext to a
    # destination that was not part of the preflight decision.
    let active_entry = (ensure-rclone-entry)
    let destination = ($active_entry.local | path expand)
    if (normalized-path $destination) != (normalized-path ($prepared.destination | path expand)) {
        discard-prepared-rclone $prepared
        error make {msg: "The active rclone config path changed after preflight. Retry dotpull so the new path can be authenticated and reviewed."}
    }

    let recovery = (backup-existing-rclone $destination)
    let parent = ($destination | path dirname)
    mkdir $parent
    let transaction = ($parent | path join (".initial-setup-rclone-" + (random uuid)))
    private-directory $transaction
    let candidate = ($transaction | path join "rclone.conf")
    let previous = ($transaction | path join "previous")
    cp $plaintext $candidate
    private-file $candidate
    mut committed = false

    let commit_result = (try {
        if ($destination | path exists) { mv $destination $previous }
        mv --force $candidate $destination
        $committed = true
        private-file $destination
        if (file-sha256 $destination) != $expected_plaintext {
            error make {msg: "Committed rclone config failed SHA-256 verification."}
        }
        null
    } catch {|err| $err })

    if $commit_result != null {
        if ($previous | path exists) {
            if ($destination | path exists) { rm --force $destination }
            mv $previous $destination
        } else if $committed and ($destination | path exists) {
            rm --force $destination
        }
        try { if ($transaction | path exists) { rm --recursive --force $transaction } } catch { }
        discard-prepared-rclone $prepared
        error make {msg: (error-message $commit_result "Prepared rclone config commit failed; the previous active config was restored when available.")}
    }

    try { rm --recursive --force $transaction } catch {
        print-warn ("rclone config was restored, but restricted transaction files remain at: " + ($transaction | into string))
    }
    record-secret-sync-state "rclone" $expected_plaintext $expected_ciphertext
    discard-prepared-rclone $prepared
    print-status "ok" "rclone" "Authenticated rclone config committed to the active machine path."
    if $recovery != null {
        print-key-value "Previous config backup: " ($recovery | into string)
    }
    {changed: true recovery: $recovery}
}
