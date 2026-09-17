#!/usr/bin/env nu
# Editing is independent of publication. No source/provider is read unless --push
# is explicit. Keep credentials and unavailable cloud storage out of the edit path.
const ROOT = path self ..
const CORE = path self ./modules/core.nu
use $CORE [nu-home]
const OUTPUT = path self ./modules/process-output.nu
use $OUTPUT [output-text]

# Machine data must be decoded losslessly, unlike human-readable diagnostics.
def checked-source [root: path target: path] {
    if (which chezmoi | is-empty) {
        error make {msg: "Local edit is preserved. chezmoi is required only for --push."}
    }
    let result = (do { ^chezmoi --source $root source-path $target } | complete)
    if $result.exit_code != 0 {
        print --stderr ($result.stderr | output-text)
        error make {msg: "Local edit is preserved. chezmoi could not resolve the managed source; nothing was published."}
    }
    let raw = $result.stdout
    let decoded = if ($raw | describe) == "binary" {
        let text = ($raw | decode utf-8)
        if ($text | encode utf-8) != $raw {
            error make {msg: "Local edit is preserved. Source-path output is not valid UTF-8."}
        }
        $text
    } else { $raw }
    let text = ($decoded | str trim)
    if ($text | is-empty) {
        error make {msg: "Local edit is preserved. chezmoi returned an empty source path; refusing to use the working directory."}
    }
    let source = ($text | path expand --no-symlink)
    if not ($source | path exists) {
        error make {msg: "Local edit is preserved. The resolved managed source does not exist."}
    }
    $source
}

# A directory editor can modify templates anywhere in its tree. Until a proper
# template-aware capture workflow exists, explicit editor-push must not claim
# success for a source tree that `chezmoi re-add` deliberately ignores.
def contains-template [source: path] {
    if ($source | str ends-with ".tmpl") { return true }
    if ($source | path type) != "dir" { return false }
    for row in (ls --all $source) {
        if $row.type == "dir" {
            if (contains-template $row.name) { return true }
        } else if ($row.name | str ends-with ".tmpl") { return true }
    }
    false
}

def main [
    target: path
    --push                 # Explicitly run the existing guarded push after editing
    --editor: string = "nvim"
    --editor-argument: string = "" # Optional single argument, e.g. --wait
] {
    let local = ($target | path expand --no-symlink)
    if not ($local | path exists) {
        error make {msg: ("Local target is missing: " + $local + ". Run setup/restore first. Editing does not implicitly pull private configuration.")}
    }
    let kind = ($local | path type)
    if $kind not-in ["file" "dir"] {
        error make {msg: "The local edit target must be a regular file or directory, not a link or special file."}
    }
    if (which $editor | is-empty) {
        error make {msg: ("Editor not found: " + $editor + ". Install it or use --editor with an executable path.")}
    }
    let before = if $kind == "file" { open --raw $local | hash sha256 } else { null }
    mut args = []
    if not ($editor_argument | is-empty) { $args = ($args | append $editor_argument) }
    $args = ($args | append ["--" ($local | into string)])
    ^$editor ...$args
    let editor_exit = ($env.LAST_EXIT_CODE | default 1)
    if $editor_exit != 0 {
        error make {msg: "Editor exited unsuccessfully. Any saved local edits were kept; no push was requested."}
    }
    if not $push {
        print "[local] Editor closed. No push or private-source update was requested by this command."
        print "Use dotpush separately after reviewing changes; an already-enabled auto-sync scheduler is independent."
        return
    }
    if $kind == "file" and ($local | path exists) {
        if (open --raw $local | hash sha256) == $before {
            print "[unchanged] Nothing was edited; no push requested."
            return
        }
    }
    let config_file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    if not ($config_file | path exists) {
        error make {msg: "Local edit is preserved. Machine configuration is missing; --push was not started."}
    }
    let config = (open --raw $config_file | from nuon)
    let source = (checked-source ($config.data_root | path expand) $local)
    if (contains-template $source) {
        error make {msg: "Local edit is preserved. This target uses a chezmoi template; re-add does not update templates. Review the template or use chezmoi merge explicitly before publishing."}
    }
    let exe = $nu.current-exe
    ^$exe --no-config-file ($ROOT | path join "scripts" "sync-up.nu")
    let push_exit = ($env.LAST_EXIT_CODE | default 1)
    if $push_exit != 0 {
        error make {msg: "Local edit is preserved, but --push was blocked or failed. Resolve the preceding publication error; editing itself succeeded."}
    }
}
