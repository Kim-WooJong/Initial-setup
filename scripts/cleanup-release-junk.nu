#!/usr/bin/env nu

# Remove only unambiguous repository/build/editor artifacts before a release.
# Default mode deletes matched junk. Use --check for a read-only inventory.
const ROOT = path self ..
const RELEASE_VERSION = "0.26.0"
const CONSOLE = path self ./modules/console.nu
const TEXT_CASE = path self ./modules/text-case.nu
use $CONSOLE [print-heading print-key-value print-status]
use $TEXT_CASE [text-lower]

# Files deliberately retired by the current release. Keep this list explicit:
# it is safer than guessing whether an arbitrary unreferenced source file is
# obsolete. Future releases may add paths here when an endpoint is superseded.
const OBSOLETE_PATHS = [
    "scripts/migrate-sync-state.nu"
    "scripts/migrate-provider-state.nu"
    "scripts/migrate-vault-state.nu"
    "scripts/state-schema-status.nu"
    "scripts/verify-0.13.2.nu"
]


def relative-path [path: path] {
    $path | path relative-to $ROOT | into string | str replace --all '\' '/'
}


def junk-file-reason [path: path] {
    let name = ($path | path basename)
    let lower = ($name | text-lower)

    if $name in [".DS_Store" "Thumbs.db" ".directory" ".coverage"] {
        return "OS/test artifact"
    }
    if ($lower | str contains "# edit conflict") {
        return "editor conflict copy"
    }
    if ($name | str starts-with ".~lock.") and ($name | str ends-with "#") {
        return "office lock file"
    }
    null
}


def junk-dir-reason [path: path] {
    let name = ($path | path basename)
    let rel = (relative-path $path)

    if $name in ["__pycache__" ".pytest_cache" ".mypy_cache" ".ruff_cache" "node_modules"] {
        return "generated cache/dependency directory"
    }
    if $rel == "tools/cloudwins/target" {
        return "Rust build output"
    }
    null
}


def collect-junk [dir: path] {
    mut rows = []
    for item in (ls --all $dir | sort-by name) {
        let name = ($item.name | path basename)
        if $name == ".git" { continue }
        # Never touch user settings in <checkout>/private (CHECKOUT_PRIVATE_DIR).
        if ($item.name | path expand) == ($ROOT | path expand | path join "private") { continue }

        if $item.type == "dir" {
            let reason = (junk-dir-reason $item.name)
            if $reason != null {
                $rows = ($rows | append {path: $item.name type: "dir" reason: $reason})
            } else {
                $rows = ($rows | append (collect-junk $item.name))
            }
        } else if $item.type == "file" {
            let reason = (junk-file-reason $item.name)
            if $reason != null {
                $rows = ($rows | append {path: $item.name type: "file" reason: $reason})
            }
        }
    }
    $rows
}


def main [
    --check # Report release junk without deleting anything.
] {
    let version_file = ($ROOT | path join "VERSION")
    if not ($version_file | path exists) or (($version_file | path type) != "file") {
        error make {msg: "Release cleanup requires the project VERSION file."}
    }
    let actual_version = (open --raw $version_file | str trim)
    if $actual_version != $RELEASE_VERSION {
        error make {msg: ("This cleanup list is for Initial-setup v" + $RELEASE_VERSION + "; current project version is " + $actual_version + ".")}
    }
    let obsolete = ($OBSOLETE_PATHS | each {|rel|
        let file = ($ROOT | path join $rel)
        if ($file | path exists) { {path: $file type: (if ($file | path type) == "dir" { "dir" } else { "file" }) reason: "obsolete release endpoint"} } else { null }
    } | compact)
    let rows = ($obsolete | append (collect-junk $ROOT) | uniq-by path)
    if ($rows | is-empty) {
        print-status "ok" "ok" "No release junk found; nothing to remove."
        return
    }

    print-heading ("Release hygiene — v" + $RELEASE_VERSION)
    for row in $rows {
        print-key-value "Candidate : " ((relative-path $row.path) + " | " + $row.reason)
    }

    if $check {
        print-status "warn" "check" ((($rows | length) | into string) + " junk item(s) found; no files were removed.")
        return
    }

    for row in $rows {
        let rel = (relative-path $row.path)
        if $row.type == "dir" {
            rm --recursive --force $row.path
        } else {
            rm --force $row.path
        }
        print-status "ok" "removed" $rel
    }
    print-status "ok" "ok" ((($rows | length) | into string) + " release junk item(s) removed.")
}
