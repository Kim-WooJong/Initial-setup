#!/usr/bin/env nu
# Standalone diagnostics. This command never changes configuration. Manifest drift
# is advisory unless --strict-manifest is requested; normal setup is allowed to
# continue to the existing configuration diff/review flow.
const ROOT = path self ..

def version-at-least [actual: string required: list<int>] {
    if not ($actual =~ '^[0-9]+\.[0-9]+\.[0-9]+$') { return false }
    let parts = ($actual | split row "." | each {|s| $s | into int })
    for i in [0 1 2] {
        if ($parts | get $i) > ($required | get $i) { return true }
        if ($parts | get $i) < ($required | get $i) { return false }
    }
    true
}

def safe-relative [value: string] {
    let parts = ($value | split row "/")
    not (($value | is-empty) or ($value | str contains '\\') or ($value | str contains ':') or ("" in $parts) or ("." in $parts) or (".." in $parts) or ($value =~ '[\x00-\x1f]'))
}

def plain-file [root: path relative: string] {
    if not (safe-relative $relative) { return false }
    let parts = ($relative | split row "/")
    mut cursor = ($root | into string)
    for item in ($parts | enumerate) {
        $cursor = ($cursor | path join $item.item)
        if not ($cursor | path exists) { return false }
        let kind = ($cursor | path type)
        if $item.index == (($parts | length) - 1) {
            if $kind != "file" { return false }
        } else if $kind != "dir" { return false }
    }
    true
}

def main [--root: path --manifest --strict-manifest --require-runtime --quiet] {
    let root = if $root == null { $ROOT } else { $root | path expand --no-symlink }
    mut failures: list<string> = []
    mut manifest_diff: list<string> = []

    if not ($root | path exists) or ($root | path type) != "dir" {
        error make {msg: ("PROJECT_ROOT_MISSING: " + ($root | into string))}
    }

    let required = [
        "setup.nu" "setup-main.nu" "verify.nu" "VERSION" "SCHEMA_VERSION"
        "bootstrap.sh" "bootstrap.ps1"
        "scripts/setup-entry.nu" "scripts/diagnose-project.nu" "scripts/verify-all.nu"
        "scripts/modules/nu-runtime.nu" "scripts/modules/core.nu"
        "scripts/modules/cloud-wins-config.nu" "scripts/modules/cloud-wins-engine.nu"
        "scripts/validate-project.nu" "scripts/validate-syntax.nu" "scripts/syntax-check-file.nu"
        "tools/cloudwins/Cargo.toml" "tools/cloudwins/src/main.rs" "tools/cloudwins/src/tests.rs"
    ]
    let files = ($required | each {|name| {path: $name present: (plain-file $root $name)} })
    for item in ($files | where present == false) {
        $failures = ($failures | append ("INCOMPLETE_RELEASE: " + $item.path))
    }

    let actual = (version).version
    let seed_ok = (version-at-least $actual [0 106 1])
    let runtime_ok = (version-at-least $actual [0 109 1])
    if not $seed_ok {
        $failures = ($failures | append "SEED_TOO_OLD: this entry requires Nushell >=0.106.1.")
    }
    if $require_runtime and not $runtime_ok {
        $failures = ($failures | append "NU_RUNTIME_TOO_OLD: full validation requires >=0.109.1. Run scripts/update-nushell.nu --shell, then rerun verify.nu in that shell; or pass verify.nu --runtime <absolute-nu-path>.")
    }

    let candidates = (try { which --all nu | where type == "external" | get path } catch { [] })
    let project_version = if (plain-file $root "VERSION") { open --raw ($root | path join "VERSION") | str trim } else { "unknown" }
    mut manifest_count = 0

    if $manifest {
        let validation = (try {
            if not (plain-file $root "RELEASE-MANIFEST.json") { error make {msg: "RELEASE_MANIFEST_MISSING"} }
            let index = (open --raw ($root | path join "RELEASE-MANIFEST.json") | from json)
            if ($index.format? | default 0) != 1 or $index.version != $project_version {
                error make {msg: "RELEASE_MANIFEST_VERSION_MISMATCH"}
            }
            mut issues: list<string> = []
            mut seen: list<string> = []
            for row in $index.files {
                if ($row.path | describe) != "string" or not (safe-relative $row.path) { error make {msg: "UNSAFE_MANIFEST_PATH"} }
                if $row.path in $seen { error make {msg: "DUPLICATE_MANIFEST_PATH"} }
                $seen = ($seen | append $row.path)
                if not ($row.sha256 =~ '^[a-f0-9]{64}$') { error make {msg: "INVALID_MANIFEST_CHECKSUM"} }
                if not (plain-file $root $row.path) {
                    $issues = ($issues | append ("MISSING_OR_NONREGULAR: " + $row.path))
                } else {
                    let actual_sha = (open --raw ($root | path join $row.path) | hash sha256)
                    if $actual_sha != $row.sha256 {
                        $issues = ($issues | append ("CONTENT_CHANGED: " + $row.path))
                    }
                }
            }
            for name in $required {
                if $name not-in $seen { $issues = ($issues | append ("MANIFEST_ENTRY_MISSING: " + $name)) }
            }
            {ok: true count: ($index.files | length) issues: $issues}
        } catch {|err|
            {ok: false count: 0 issues: [("MANIFEST_ERROR: " + ($err.msg? | default "MANIFEST_READ_FAILED"))]}
        })
        $manifest_count = $validation.count
        $manifest_diff = $validation.issues
        if $strict_manifest and not ($manifest_diff | is-empty) {
            $failures = ($failures | append $manifest_diff)
        }
    }

    let manifest_status = if not $manifest {
        "not-requested"
    } else if ($manifest_diff | is-empty) {
        "clean"
    } else {
        "changed"
    }

    let summary = {
        format: 2
        project_version: $project_version
        cwd: ($env.PWD | into string)
        project_root: ($root | into string)
        setup_entry: ($root | path join "setup.nu")
        nushell: {
            executable: ($nu.current-exe | into string)
            version: $actual
            seed_supported: $seed_ok
            runtime_minimum_met: $runtime_ok
            path_candidates: $candidates
        }
        platform: $nu.os-info.name
        required_files: $files
        manifest_requested: $manifest
        manifest_strict: $strict_manifest
        manifest_status: $manifest_status
        manifest_matches_release: (if $manifest { $manifest_diff | is-empty } else { null })
        manifest_files_checked: $manifest_count
        manifest_diff: $manifest_diff
        failures: $failures
        diagnostic_only: true
        setup_blocked: (not ($failures | is-empty))
        note: "diagnostic_only describes this diagnostic command only; it is not a setup policy. Normal setup reviews managed configuration differences separately before destructive synchronization choices."
    }

    if not $quiet or not ($failures | is-empty) {
        $summary | to json | print
    } else if $manifest and not ($manifest_diff | is-empty) {
        print --stderr "[review] Project files differ from RELEASE-MANIFEST.json. Normal setup may continue; run `nu setup.nu --diagnose` for the list or `nu setup.nu --check` for strict validation."
    }

    if not ($failures | is-empty) { exit 1 }
    if $quiet { print --stderr ("[preflight] Required project files verified: " + ($root | into string)) }
}
