const CORE = path self ./core.nu
use $CORE [read-nuon-record]
# Canonical sync baseline state access and migration.
#
# Readers accept the legacy v2 record and the canonical v3 record. Existing
# files are never migrated as a side effect of status/sync operations; explicit
# migration is performed by scripts/migrate-state-transaction.nu via dotmigrate.
const SAFETY = path self ./safety.nu
const STATE_SCHEMA = path self ./state-schema.nu
use $SAFETY [state-root atomic-record]
use $STATE_SCHEMA [assert-state-schema-readable detect-state-schema current-state-schema]

export def sync-state-file [] {
    let scope = ($env.INITIAL_SETUP_PROVIDER_STATE_SCOPE? | default "" | str trim)
    let root = (state-root)
    if ($scope | is-empty) {
        return ($root | path join "sync-state.nuon")
    }
    if not ($scope =~ '^[a-f0-9]{64}$') {
        error make {msg: "Invalid sync-state scope."}
    }
    $root | path join "sync-states" ("sync-state-" + $scope + ".nuon")
}

export def discover-sync-state-files [] {
    let root = (state-root)
    mut files = []
    let legacy = ($root | path join "sync-state.nuon")
    if ($legacy | path exists) and (($legacy | path type) == "file") {
        $files = ($files | append $legacy)
    }

    let scoped = ($root | path join "sync-states")
    if ($scoped | path exists) and (($scoped | path type) == "dir") {
        for row in (ls --all $scoped | where type == "file" | where {|item| ($item.name | path basename) =~ '^sync-state-[a-f0-9]{64}\.nuon$' }) {
            $files = ($files | append $row.name)
        }
    }

    $files | uniq | sort
}

def validate-hash [name: string value: any --allow-empty] {
    let text = (try { $value | into string | str trim } catch { "" })
    if $allow_empty and ($text | is-empty) { return $text }
    if not ($text =~ '^[a-f0-9]{64}$') {
        error make {msg: ("Invalid " + $name + " in sync state; expected a SHA-256 value.")}
    }
    $text
}

export def validate-sync-state [value: record] {
    let schema = (assert-state-schema-readable "sync-state" $value)
    if $schema.detected < 2 {
        error make {msg: ("Unsupported legacy sync-state schema " + ($schema.detected | into string) + "; automatic migration starts at schema 2.")}
    }

    validate-hash "local_hash" ($value.local_hash? | default "") | ignore
    validate-hash "cloud_hash" ($value.cloud_hash? | default "") --allow-empty | ignore
    $schema
}

# Read without mutating the live state. Legacy v2 remains readable until an
# explicit dotmigrate converts it to the canonical v3 representation.
export def read-sync-state [file: path] {
    let value = (read-nuon-record $file "sync state")
    validate-sync-state $value | ignore
    $value
}

export def canonical-sync-state [value: record] {
    let schema = (validate-sync-state $value)
    if $schema.detected == (current-state-schema "sync-state") and $schema.source_field == "schema_version" {
        return $value
    }
    if $schema.detected != 2 and not ($schema.detected == 3 and $schema.source_field in ["version" "both"]) {
        error make {msg: ("No sync-state migration is defined from schema " + ($schema.detected | into string) + ".")}
    }

    mut migrated = $value
    if (($migrated | columns) | any {|name| $name == "version" }) {
        $migrated = ($migrated | reject version)
    }
    $migrated = ($migrated | upsert schema_version (current-state-schema "sync-state"))
    validate-sync-state $migrated | ignore
    $migrated
}

export def write-sync-state [file: path value: record] {
    let canonical = (canonical-sync-state $value)
    let schema = (detect-state-schema "sync-state" $canonical)
    if $schema.status != "current" {
        error make {msg: "Refusing to write a non-current sync-state record."}
    }
    mkdir ($file | path dirname)
    atomic-record $file $canonical
    let saved = (read-sync-state $file)
    if $saved != $canonical {
        error make {msg: "Sync-state verification failed after atomic write."}
    }
    $saved
}

