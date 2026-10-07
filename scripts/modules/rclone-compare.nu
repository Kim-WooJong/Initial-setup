# rclone.conf comparison by section and key. Values never leave this module:
# callers get section/key names and SHA-256 digests only.

# Parse rclone.conf text into {section: {key: value}}. Comments/blank lines
# and lines outside a section are ignored.
export def rclone-sections [text: string] {
    mut sections = {}
    mut current = ""
    for raw in ($text | lines) {
        let line = ($raw | str trim)
        if ($line | is-empty) or ($line | str starts-with "#") or ($line | str starts-with ";") { continue }
        let header = ($line | parse --regex '^\[(?<name>[^\]]+)\]$')
        if not ($header | is-empty) {
            $current = ($header | first | get name | str trim)
            if not ($current in ($sections | columns)) { $sections = ($sections | upsert $current {}) }
            continue
        }
        if ($current | is-empty) { continue }
        let kv = ($line | parse --regex '^(?<key>[^=]+?)\s*=\s*(?<value>.*)$')
        if ($kv | is-empty) { continue }
        let entry = ($kv | first)
        $sections = ($sections | upsert $current (($sections | get $current) | upsert ($entry.key | str trim) $entry.value))
    }
    $sections
}

export def is-crypt-section [section: record] {
    ($section.type? | default "" | str trim) == "crypt"
}

# Text that rclone wrote with RCLONE_CONFIG_PASS cannot be parsed.
export def encrypted-rclone-config [text: string] {
    $text | str trim --left | str starts-with "# Encrypted rclone configuration"
}

# Section-level comparison of two rclone.conf texts. Returns names only:
# {identical, only_local, only_synced, changed: [{name crypt keys}]}.
export def compare-rclone-texts [local: string synced: string] {
    let a = (rclone-sections $local)
    let b = (rclone-sections $synced)
    let names_a = ($a | columns)
    let names_b = ($b | columns)
    let changed = ($names_a | where {|n| $n in $names_b } | each {|n|
        let sa = ($a | get $n)
        let sb = ($b | get $n)
        let keys = ($sa | columns | append ($sb | columns) | uniq | where {|k| ($sa | get --optional $k) != ($sb | get --optional $k) } | sort)
        if ($keys | is-empty) { null } else { {name: $n crypt: ((is-crypt-section $sa) or (is-crypt-section $sb)) keys: $keys} }
    } | compact)
    let only_local = ($names_a | where {|n| $n not-in $names_b } | sort)
    let only_synced = ($names_b | where {|n| $n not-in $names_a } | sort)
    {
        identical: (($changed | is-empty) and ($only_local | is-empty) and ($only_synced | is-empty))
        only_local: $only_local
        only_synced: $only_synced
        changed: $changed
    }
}

# SHA-256 over the crypt remote sections (names plus every key/value,
# canonically sorted), or "" when there are none.
export def rclone-crypt-sections-hash [text: string] {
    let sections = (rclone-sections $text)
    let crypt = ($sections | columns | where {|n| is-crypt-section ($sections | get $n) })
    if ($crypt | is-empty) { return "" }
    $crypt
    | each {|n| ([$"[($n)]"] | append ($sections | get $n | transpose key value | each {|kv| $"($kv.key)=($kv.value)" } | sort)) | str join (char nl) }
    | sort
    | str join (char nl)
    | hash sha256
}
