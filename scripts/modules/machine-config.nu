# Canonical access layer for the local machine configuration.
# Normal production writers should use this module instead of writing
# ~/.config/dotfiles/config.nuon directly.
const ROOT = path self ../..
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
use $CORE [machine-config-path]
use $SAFETY [atomic-record]


def current-machine-schema [] {
    open --raw ($ROOT | path join "SCHEMA_VERSION")
    | str trim
    | into int
}


def validate-machine-config-record [value: record --allow-legacy] {
    let schema = (try { $value.schema_version? | default 0 | into int } catch {
        error make {msg: "Machine config schema_version must be integer-compatible."}
    })
    if $schema < 0 {
        error make {msg: "Machine config has an invalid negative schema version."}
    }
    let current = (current-machine-schema)
    if $schema > $current {
        error make {msg: ("Machine config schema " + ($schema | into string) + " is newer than supported " + ($current | into string) + ".")}
    }
    if (not $allow_legacy) and $schema != $current {
        error make {msg: ("Refusing to write non-current machine config schema " + ($schema | into string) + "; expected " + ($current | into string) + ".")}
    }
    for key in ["data_root" "tools_root"] {
        let field = ($value | get --optional $key)
        if ($field | describe) != "string" or ($field | str trim | is-empty) {
            error make {msg: ("Machine config requires a non-empty string field: " + $key)}
        }
    }
    $value
}


def read-machine-config [--allow-legacy] {
    let file = (machine-config-path)
    if not ($file | path exists) {
        error make {msg: ("Machine config not found: " + ($file | into string))}
    }
    if ($file | path type) != "file" {
        error make {msg: ("Machine config is not a regular file: " + ($file | into string))}
    }
    let value = (try { open --raw $file | from nuon } catch {|err|
        error make {msg: ("Unable to parse machine config as NUON: " + ($err.msg? | default ($err | into string)))}
    })
    if not (($value | describe) | str starts-with "record") {
        error make {msg: "Machine config must contain a NUON record."}
    }
    validate-machine-config-record $value --allow-legacy=$allow_legacy | ignore
    $value
}


export def write-machine-config [value: record] {
    validate-machine-config-record $value | ignore
    let file = (machine-config-path)
    atomic-record $file $value
    let saved = (read-machine-config)
    if $saved != $value {
        error make {msg: "Machine config verification failed after atomic write."}
    }
    $file
}
