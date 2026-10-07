const CORE = path self ./core.nu
use $CORE [read-nuon-record]
# Canonical provider baseline state access and migration.
#
# Readers accept legacy v1 records and canonical v2 records. Existing files are
# never migrated as a side effect of status/sync operations; explicit migration
# is performed by scripts/migrate-state-transaction.nu via dotmigrate.
const SAFETY = path self ./safety.nu
const STATE_SCHEMA = path self ./state-schema.nu
use $SAFETY [state-root atomic-record]
use $STATE_SCHEMA [assert-state-schema-readable detect-state-schema current-state-schema]

export def provider-state-file [] {
    let scope = ($env.INITIAL_SETUP_PROVIDER_STATE_SCOPE? | default "" | str trim)
    let root = (state-root)
    if ($scope | is-empty) {
        return ($root | path join "provider-state.nuon")
    }
    if not ($scope =~ '^[a-f0-9]{64}$') {
        error make {msg: "Invalid provider state scope."}
    }
    $root | path join "provider-states" ("provider-state-" + $scope + ".nuon")
}

export def discover-provider-state-files [] {
    let root = (state-root)
    mut files = []
    let legacy = ($root | path join "provider-state.nuon")
    if ($legacy | path exists) and (($legacy | path type) == "file") {
        $files = ($files | append $legacy)
    }

    let scoped = ($root | path join "provider-states")
    if ($scoped | path exists) and (($scoped | path type) == "dir") {
        for row in (ls --all $scoped | where type == "file" | where {|item| ($item.name | path basename) =~ '^provider-state-[a-f0-9]{64}\.nuon$' }) {
            $files = ($files | append $row.name)
        }
    }

    $files | uniq | sort
}

def validate-sha256 [name: string value: any] {
    let text = (try { $value | into string | str trim } catch { "" })
    if not ($text =~ '^[a-f0-9]{64}$') {
        error make {msg: ("Invalid " + $name + " in provider state; expected a SHA-256 value.")}
    }
    $text
}

def validate-revision [value: any] {
    let text = (try { $value | into string | str trim } catch { "" })
    # Directory providers use a SHA-256 workspace revision; local/rclone stores
    # use UUID revisions. Both forms are part of the existing provider contract.
    if not (($text =~ '^[a-f0-9]{64}$') or ($text =~ '^[a-f0-9-]{36}$')) {
        error make {msg: "Invalid revision in provider state; expected a provider SHA-256 or UUID revision."}
    }
    $text
}

export def validate-provider-state [value: record] {
    let schema = (assert-state-schema-readable "provider-state" $value)
    if $schema.detected < 1 {
        error make {msg: ("Unsupported legacy provider-state schema " + ($schema.detected | into string) + "; automatic migration starts at schema 1.")}
    }

    validate-sha256 "provider_id" ($value.provider_id? | default "") | ignore
    validate-revision ($value.revision? | default "") | ignore
    validate-sha256 "tree_hash" ($value.tree_hash? | default "") | ignore
    validate-sha256 "source_hash" ($value.source_hash? | default "") | ignore
    let observed = (try { $value.observed_at? | default "" | into string | str trim } catch { "" })
    if ($observed | is-empty) {
        error make {msg: "Invalid observed_at in provider state; expected a non-empty timestamp."}
    }
    $schema
}

# Read without mutating the live state. Legacy v1 remains readable until an
# explicit dotmigrate converts it to the canonical v2 representation.
export def read-provider-state [file: path] {
    let value = (read-nuon-record $file "provider state")
    validate-provider-state $value | ignore
    $value
}

export def canonical-provider-state [value: record] {
    let schema = (validate-provider-state $value)
    if $schema.detected == (current-state-schema "provider-state") and $schema.source_field == "schema_version" {
        return $value
    }
    if $schema.detected != 1 and not ($schema.detected == 2 and $schema.source_field in ["version" "both"]) {
        error make {msg: ("No provider-state migration is defined from schema " + ($schema.detected | into string) + ".")}
    }

    mut migrated = $value
    if (($migrated | columns) | any {|name| $name == "version" }) {
        $migrated = ($migrated | reject version)
    }
    $migrated = ($migrated | upsert schema_version (current-state-schema "provider-state"))
    validate-provider-state $migrated | ignore
    $migrated
}

export def write-provider-state [file: path value: record] {
    let canonical = (canonical-provider-state $value)
    let schema = (detect-state-schema "provider-state" $canonical)
    if $schema.status != "current" {
        error make {msg: "Refusing to write a non-current provider-state record."}
    }
    mkdir ($file | path dirname)
    atomic-record $file $canonical
    let saved = (read-provider-state $file)
    if $saved != $canonical {
        error make {msg: "Provider-state verification failed after atomic write."}
    }
    $saved
}

