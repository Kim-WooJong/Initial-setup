#!/usr/bin/env nu
# After copying a new release over an existing Initial-setup folder, remove
# files that are no longer part of the release (per RELEASE-MANIFEST.json).
#
#   nu --no-config-file scripts/prune-obsolete.nu            # preview only
#   nu --no-config-file scripts/prune-obsolete.nu --execute  # delete them
#
# Never touched: private/ (your synchronized settings), .git/, and local build
# output (tools/cloudwins/target/). Also reports release files that are
# missing or modified, which indicates an incomplete copy.
const ROOT = path self ..
const CONSOLE = path self ./modules/console.nu
use $CONSOLE [print-heading print-status]

# Top-level or nested paths (relative, '/'-separated) that are never pruned.
const KEEP = ["private" ".git" "tools/cloudwins/target"]

def relative [file: path] { $file | path relative-to $ROOT | into string | str replace --all '\' '/' }

def kept [rel: string] { $KEEP | any {|k| $rel == $k or ($rel | str starts-with ($k + "/")) } }

# Files under the checkout, skipping kept directories before descending.
def walk [dir: path] {
    mut files = []
    for item in (ls --all $dir | sort-by name) {
        let rel = (relative $item.name)
        if (kept $rel) { continue }
        if $item.type == "dir" {
            $files = ($files | append (walk $item.name))
        } else {
            $files = ($files | append {path: $rel type: $item.type})
        }
    }
    $files
}

# Remove directories left empty after pruning (children first, so a parent
# emptied by its child's removal goes too). Kept directories are skipped.
def remove-empty-dirs [dir: path] {
    mut removed = 0
    for item in (ls --all $dir | where type == "dir" | sort-by name) {
        if (kept (relative $item.name)) { continue }
        $removed += (remove-empty-dirs $item.name)
        if (ls --all $item.name | is-empty) {
            rm $item.name
            $removed += 1
        }
    }
    $removed
}

def main [--execute --json] {
    let manifest_file = ($ROOT | path join "RELEASE-MANIFEST.json")
    if not ($manifest_file | path exists) { error make {msg: "RELEASE-MANIFEST.json is missing; copy the complete release folder first."} }
    let manifest = (open --raw $manifest_file | from json)
    let version = (open --raw ($ROOT | path join "VERSION") | str trim)
    if $manifest.version != $version {
        error make {msg: ("VERSION (" + $version + ") does not match RELEASE-MANIFEST.json (" + $manifest.version + "); the copy looks incomplete. Copy the whole release folder again before pruning.")}
    }
    let expected = ($manifest.files | get path | append "RELEASE-MANIFEST.json")
    let present = (walk $ROOT)
    let obsolete = ($present | where {|f| $f.path not-in $expected } | get path | sort)
    let missing = ($manifest.files | where {|f| not ($ROOT | path join $f.path | path exists) } | get path)
    let modified = ($manifest.files | where {|f|
        let file = ($ROOT | path join $f.path)
        ($file | path exists) and ((open --raw $file | hash sha256) != $f.sha256)
    } | get path)

    if $json {
        print ({version: $version obsolete: $obsolete missing: $missing modified: $modified executed: $execute} | to json)
    } else {
        print-heading ("Initial-setup " + $version + " release file check")
        if ($obsolete | is-empty) { print-status "ok" "prune" "No obsolete files." } else {
            print-status "info" "prune" (($obsolete | length | into string) + " file(s) are not part of this release:")
            for p in $obsolete { print ("  " + $p) }
        }
        for p in $missing { print-status "warn" "missing" $p }
        for p in $modified { print-status "warn" "modified" $p }
        if not (($missing | is-empty) and ($modified | is-empty)) {
            print-status "warn" "copy" "Some release files are missing or differ: copy the complete release folder again."
        }
    }

    if not $execute {
        if not ($obsolete | is-empty) and not $json { print-status "info" "prune" "Preview only. Re-run with --execute to delete them." }
        return
    }
    for p in $obsolete { rm --force ($ROOT | path join $p) }
    let dirs = (remove-empty-dirs $ROOT)
    if not $json {
        print-status "ok" "prune" ("Deleted " + ($obsolete | length | into string) + " file(s) and " + ($dirs | into string) + " empty folder(s). private/ was not touched.")
    }
}
