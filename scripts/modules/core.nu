# Shared Initial-setup helpers.

const SUBPROCESS = path self ./subprocess.nu
use $SUBPROCESS [run-command]

export def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

export def machine-config-path [] {
    (nu-home) | path join ".config" "dotfiles" "config.nuon"
}

# Private synchronized settings always live in <tools_root>/private. A
# data_root saved by an older version (the checkout's parent folder, ../home,
# or any other path) is ignored, never read or written. Isolated tests keep an
# explicit data_root unless INITIAL_SETUP_ENFORCE_PRIVATE=1 asks for the rule.
export def fixed-private-context [config: record] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim) == "1"
    let enforce = ($env.INITIAL_SETUP_ENFORCE_PRIVATE? | default "" | str trim) == "1"
    if $test_mode and not $enforce { return $config }
    let tools = ($config.tools_root? | default "" | into string)
    if ($tools | is-empty) { return $config }
    $config | upsert data_root ($tools | path expand | path join "private" | into string)
}

export def machine-context [] {
    let file = (machine-config-path)

    if not ($file | path exists) {
        error make {
            msg: ("Machine config not found: " + ($file | into string))
        }
    }

    fixed-private-context (open $file)
}

export def try-machine-context [] {
    let file = (machine-config-path)
    if not ($file | path exists) { return null }
    try { fixed-private-context (open $file) } catch { null }
}

export def vscode-user-dir [] {
    match $nu.os-info.name {
        "windows" => {
            let appdata = ($env.APPDATA? | default "")
            if ($appdata | is-empty) { null } else { $appdata | path join "Code" "User" }
        }
        "macos" => { (nu-home) | path join "Library" "Application Support" "Code" "User" }
        "linux" => { (nu-home) | path join ".config" "Code" "User" }
        _ => { null }
    }
}

export def project-version [tools_root: path] {
    open --raw ($tools_root | path join "VERSION")
    | into string
    | str trim
}

export def project-schema-version [tools_root: path] {
    open --raw ($tools_root | path join "SCHEMA_VERSION")
    | into string
    | str trim
    | into int
}

export def useful-lines [file: path] {
    open --raw $file
    | lines
    | each {|line| $line | str trim }
    | where {|line| not ($line | is-empty) and not ($line | str starts-with "#") }
}

export def try-read-nuon-record [file: path label: string = "NUON state"] {
    if not ($file | path exists) {
        return {ok: false status: "missing" detail: "not initialized" value: null}
    }
    if ($file | path type) != "file" {
        return {ok: false status: "not-file" detail: "not a regular file" value: null}
    }

    let parsed = (try {
        {ok: true status: "ok" detail: "" value: (open --raw $file | from nuon)}
    } catch {|err|
        {ok: false status: "parse-error" detail: ("invalid NUON: " + ($err.msg? | default ($err | into string))) value: null}
    })
    if not $parsed.ok {
        return $parsed
    }
    if not (($parsed.value | describe) | str starts-with "record") {
        return {ok: false status: "not-record" detail: "NUON root is not a record" value: null}
    }

    $parsed
}

export def read-nuon-record [file: path label: string = "NUON state"] {
    let parsed = (try-read-nuon-record $file $label)
    if $parsed.ok {
        return $parsed.value
    }

    if $parsed.status == "missing" or $parsed.status == "not-file" {
        error make {msg: ($label + " must be a regular file: " + ($file | into string))}
    }
    if $parsed.status == "parse-error" {
        error make {msg: ("Unable to parse " + $label + " as NUON: " + ($file | into string) + (char nl) + $parsed.detail)}
    }
    error make {msg: ($label + " must contain a NUON record: " + ($file | into string))}
}

export def detect-machine-name [] {
    let computer_name = ($env.COMPUTERNAME? | default "" | str trim)

    if not ($computer_name | is-empty) {
        return $computer_name
    }

    let host_name = ($env.HOSTNAME? | default "" | str trim)

    if not ($host_name | is-empty) {
        return $host_name
    }

    if not (which hostname | is-empty) {
        let result = (run-command "hostname" [])
        let external_name = (if $result.ok { $result.stdout | str trim } else { "" })

        if not ($external_name | is-empty) {
            return $external_name
        }
    }

    "unknown-machine"
}


# Normalize caught values without assuming every failure is a record with `.msg`.
# Some `try` blocks can surface strings/lists/records from normal pipeline output;
# these helpers make explicit failure envelopes distinguishable from success output.
export def error-message [value: any fallback: string = "Operation failed."] {
    let kind = ($value | describe)
    if $kind == "string" {
        if not ($value | str trim | is-empty) { return $value }
    }
    if ($kind | str starts-with "record") {
        for key in ["msg" "rendered"] {
            let candidate = ($value | get --optional $key)
            if ($candidate | describe) == "string" {
                if not ($candidate | str trim | is-empty) { return $candidate }
            }
        }
    }
    $fallback
}

export def failure-envelope [value: any] {
    {
        __initial_setup_failure: true
        error: $value
    }
}

export def captured-failure [value: any] {
    let kind = ($value | describe)
    let values = if ($kind | str starts-with "list") or ($kind | str starts-with "table") { $value } else { [$value] }

    for item in $values {
        let item_kind = ($item | describe)
        if ($item_kind | str starts-with "record") {
            let marker = ($item | get --optional __initial_setup_failure)
            if $marker == true {
                return ($item | get --optional error)
            }
        }
    }

    null
}
