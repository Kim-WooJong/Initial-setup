#!/usr/bin/env nu
# No real editor, cloud credentials or user's HOME. Runs the actual edit script
# with a tiny Nushell editor fixture. Requires only the running Nushell executable.
const ROOT = path self ..
const CORE = path self ./modules/core.nu
const OUTPUT = path self ./modules/process-output.nu
use $CORE [error-message failure-envelope captured-failure]
use $OUTPUT [output-text]

def expect [ok: bool label: string] {
    if not $ok { error make {msg: ("FAILED: " + $label)} }
    print ("[pass] " + $label)
}

def editor-child [target: path editor: path --push] {
    let exe = $nu.current-exe
    let base_args = ["--no-config-file" ($ROOT | path join "scripts" "edit-managed.nu") $target "--editor" $exe "--editor-argument" $editor]
    let args = if $push { $base_args | append "--push" } else { $base_args }
    let resolved_args = $args
    do { ^$exe ...$resolved_args } | complete
}

def fixtures [sandbox: path] {
    let home = ($sandbox | path join "home")
    let state = ($home | path join ".config" "dotfiles")
    let target = ($home | path join ".config" "nushell" "config [한글].nu")
    mkdir ($target | path dirname) ($state | path join "locks")
    # Deliberately invalid machine context and an existing lock must not prevent
    # local editing. Neither file may be consumed/rewritten by default editing.
    let config = ($state | path join "config.nuon")
    "not a NUON record" | save $config
    "existing-test-owner" | save ($state | path join "locks" "operation.lock")
    let good_editor = ($sandbox | path join "editor fixture.nu")
    'def main [target: path] { "# edited locally" | save --force $target }' | save $good_editor
    let failed_editor = ($sandbox | path join "failing editor.nu")
    'def main [target: path] { "# saved before editor failure" | save --force $target; exit 17 }' | save $failed_editor
    let no_editor = ($sandbox | path join "unchanged editor.nu")
    'def main [target: path] { }' | save $no_editor
    "# original" | save $target

    let edited = (editor-child $target $good_editor)
    expect ($edited.exit_code == 0) "Local editing works despite invalid sync config and an existing operation lock"
    expect ((open --raw $target) == "# edited locally") "The actual local target, including Unicode/spaces/brackets, was edited"
    expect ((open --raw $config) == "not a NUON record") "Editing did not read or rewrite machine configuration"
    expect ((open --raw ($state | path join "locks" "operation.lock")) == "existing-test-owner") "Editing did not delete or change somebody else's lock"
    expect (not (($state | path join "provider-state.nuon") | path exists)) "No provider baseline was created or acknowledged"

    let unchanged = (editor-child $target $no_editor --push)
    expect ($unchanged.exit_code == 0) "Closing without changes does not initiate an explicit push"
    let editor_error = (editor-child $target $failed_editor --push)
    expect ($editor_error.exit_code != 0) "An editor failure is reported before any push"
    expect ((open --raw $target) == "# saved before editor failure") "An editor failure does not delete already-saved edits"
    let missing = ($home | path join "missing.nu")
    let missing_result = (editor-child $missing $good_editor)
    expect ($missing_result.exit_code != 0 and not ($missing | path exists)) "A missing local target is not silently pulled or created"

    # The copied convenience module must return its canonical path without
    # resolving a provider; this also parses its actual --push/--path exports.
    let caller = ($sandbox | path join "command-path.nu")
    [
        ("use " + (($ROOT | path join "scripts" "modules" "dotfiles.nu") | to nuon) + " *")
        "dotnu --path"
    ] | str join (char nl) | save $caller
    let exe = $nu.current-exe
    let command_path = (do { ^$exe --no-config-file $caller } | complete)
    expect ($command_path.exit_code == 0) "Installed command surface imports with --path"
    expect (($command_path.stdout | output-text | str trim) == ($home | path join ".config" "nushell" "config.nu")) "dotnu selects the project's canonical config, not the native shim"

    # Refresh from this checkout without running setup or touching a cloud file.
    rm ($state | path join "locks" "operation.lock") # Our own fixture, not a live lock
    let private = ($sandbox | path join "private")
    mkdir ($private | path join "rclone")
    let legacy = ($private | path join "rclone" "rclone.conf")
    "dummy legacy bytes" | save $legacy
    {tools_root: "old-checkout" data_root: $private schema_version: 5} | to nuon | save --force $config
    let installed = ($home | path join ".config" "nushell" "modules" "dotfiles.nu")
    mkdir ($installed | path dirname)
    "# previous command module" | save $installed
    let refreshed = (do { ^$exe --no-config-file ($ROOT | path join "scripts" "refresh-commands.nu") } | complete)
    if $refreshed.exit_code != 0 { print --stderr ($refreshed.stderr | output-text) }
    expect ($refreshed.exit_code == 0) "Local command refresh works without publishing or a vault"
    expect ((open --raw $installed | hash sha256) == (open --raw ($ROOT | path join "scripts" "modules" "dotfiles.nu") | hash sha256)) "The installed command module matches the checkout"
    expect ((open $config).tools_root == ($ROOT | into string)) "Refresh binds tools_root to the checkout that supplied the commands"
    expect ((open --raw $legacy) == "dummy legacy bytes") "Refresh does not delete, migrate or change legacy cloud credentials"
    expect (not (($state | path join "provider-state.nuon") | path exists)) "Refresh does not acknowledge a provider baseline"
    expect (not (($state | path join "locks" "operation.lock") | path exists)) "Refresh releases its own operation lock"

    # Regression: homogeneous lists of records may be described as a table.
    let markers = [(failure-envelope {msg: "first"}) (failure-envelope {msg: "second"})]
    expect ((error-message (captured-failure $markers)) == "first") "Failure envelopes are recognized inside tables as well as mixed lists"
    expect ((error-message {unrelated: "do-not-log"} "fallback") == "fallback") "Unknown error values do not leak unrelated record contents"
}

def main [--keep] {
    let base = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand)
    let sandbox = ($base | path join ("initial-setup-edit-test-" + (random uuid)))
    let home = ($sandbox | path join "home")
    mkdir $home
    let result = (try {
        with-env {
            INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($home | into string)
            HOME: ($home | into string) USERPROFILE: ($home | into string)
            APPDATA: ($home | path join "AppData" "Roaming") LOCALAPPDATA: ($home | path join "AppData" "Local")
            XDG_CONFIG_HOME: ($home | path join ".config") XDG_DATA_HOME: ($home | path join ".local" "share")
            XDG_STATE_HOME: ($home | path join ".local" "state") XDG_CACHE_HOME: ($home | path join ".cache")
        } { fixtures $sandbox }
        null
    } catch {|err| failure-envelope $err })
    let failure = (captured-failure $result)
    if $failure != null {
        print --stderr ("[kept] " + $sandbox)
        error make {msg: (error-message $failure "Editor regression failed.")}
    }
    if $keep { print ("[kept] " + $sandbox) } else { rm --recursive $sandbox }
    print "[ok] Managed-editor regressions passed. No real cloud or editor was used."
}
