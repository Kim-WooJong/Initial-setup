#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def useful-lines [file: path] {
    open --raw $file
    | lines
    | each { |line| $line | str trim }
    | where { |line| not ($line | is-empty) and not ($line | str starts-with "#") }
}

def fail [message: string] {
    print ("[FAIL] " + $message)
    exit 1
}

def main [] {
    let version = (
        open --raw ($TOOLS_ROOT | path join "VERSION")
        | decode utf-8
        | str trim
    )

    let schema = (
        open --raw ($TOOLS_ROOT | path join "SCHEMA_VERSION")
        | decode utf-8
        | str trim
        | into int
    )

    if ($version | is-empty) {
        fail "VERSION is empty."
    }

    if $schema < 2 {
        fail "SCHEMA_VERSION must be at least 2."
    }

    let readme = (open --raw ($TOOLS_ROOT | path join "README.md"))

    if not ($readme | str starts-with ("# Initial-setup v" + $version)) {
        fail "README version heading does not match VERSION."
    }

    for required in [
        "VERSION"
        "SCHEMA_VERSION"
        "setup.nu"
        "README.md"
        "CHANGELOG.md"
        "scripts/migrate-config.nu"
        "scripts/capture-tool-state.nu"
        "scripts/audit.nu"
        "scripts/winget-package-state.nu"
        "scripts/windows/winget-package-state.ps1"
        "scripts/modules/dotfiles.nu"
        ".github/workflows/ci.yml"
    ] {
        let file = ($TOOLS_ROOT | path join $required)

        if not ($file | path exists) {
            fail ("Required file missing: " + $required)
        }
    }

    let common = (useful-lines ($TOOLS_ROOT | path join "packages" "common.txt"))

    for mapping_file in [
        "packages/windows.txt"
        "packages/macos.txt"
        "packages/linux.txt"
    ] {
        let rows = (
            useful-lines ($TOOLS_ROOT | path join $mapping_file)
            | each { |line| $line | split row "|" | get 0 }
        )

        for package in $common {
            if not ($package in $rows) {
                fail ($mapping_file + " has no mapping for " + $package)
            }
        }
    }

    let forbidden_home_path = ("$nu." + "home-path")
    let forbidden_home_dir = ("$nu." + "home-dir")
    let forbidden_nu_version = ("$nu." + "version")
    let deprecated_downcase = ("str " + "downcase")
    let deprecated_upcase = ("str " + "upcase")
    let sync_fingerprint = (open --raw ($TOOLS_ROOT | path join "scripts" "sync-fingerprint.nu"))

    if ($sync_fingerprint | lines | any { |line| ($line | str trim | str starts-with "+") }) {
        fail "sync-fingerprint.nu contains a physical line beginning with `+`."
    }

    if not ($sync_fingerprint | str contains "into glob") {
        fail "sync-fingerprint.nu must convert variable glob patterns with `into glob`."
    }

    let exists_guard = ($sync_fingerprint | str index-of "path exists")
    let expand_call = ($sync_fingerprint | str index-of "path expand")
    let type_call = ($sync_fingerprint | str index-of "path type")

    if $exists_guard == -1 {
        fail "sync-fingerprint.nu must check path existence before fingerprint inspection."
    }

    if $expand_call == -1 or $type_call == -1 {
        fail "sync-fingerprint.nu is missing path inspection commands."
    }

    if $exists_guard > $expand_call {
        fail "sync-fingerprint.nu must check path existence before path expansion."
    }

    if $exists_guard > $type_call {
        fail "sync-fingerprint.nu must check path existence before path type detection."
    }

    let normalized_root = ($TOOLS_ROOT | into string | str replace --all '\' '/')
    let pattern = ($normalized_root + "/**/*.nu" | into glob)
    let nu_files = (glob $pattern)

    if ($nu_files | is-empty) {
        fail "No Nushell source files were found."
    }

    for file in $nu_files {
        let normalized = ($file | into string | str replace --all '\' '/')
        let is_module = ($normalized | str contains "/scripts/modules/")
        let parsed = (
            if $is_module {
                nu-check --as-module $file
            } else {
                nu-check $file
            }
        )

        if not $parsed {
            print ("[FAIL] Nushell parser rejected: " + ($file | into string))

            if $is_module {
                nu-check --debug --as-module $file | ignore
            } else {
                nu-check --debug $file | ignore
            }

            exit 1
        }

        let source = (open --raw $file)

        if ($source | str contains $deprecated_downcase) {
            fail (($file | into string) + " uses a deprecated lowercase conversion command.")
        }

        if ($source | str contains $deprecated_upcase) {
            fail (($file | into string) + " uses a deprecated uppercase conversion command.")
        }

        if ($source | str contains $forbidden_home_path) {
            fail (($file | into string) + " contains direct version-specific home-path access.")
        }

        if ($source | str contains $forbidden_home_dir) {
            fail (($file | into string) + " contains direct version-specific home-dir access.")
        }

        if ($source | str contains $forbidden_nu_version) {
            fail (($file | into string) + " contains invalid Nushell version-field access.")
        }

        for line in ($source | lines) {
            let trimmed = ($line | str trim)

            if ($trimmed | str starts-with "and ") {
                fail (($file | into string) + " starts a physical line with `and`.")
            }

            if ($trimmed | str starts-with "or ") {
                fail (($file | into string) + " starts a physical line with `or`.")
            }
        }
    }

    print ("[ok] VERSION = " + $version)
    print ("[ok] SCHEMA_VERSION = " + ($schema | into string))
    print ("[ok] Package manifests are complete.")
    print ("[ok] Nushell parser validation passed for " + (($nu_files | length) | into string) + " files.")
    print "[ok] Project validation passed."
}
