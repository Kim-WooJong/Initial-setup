#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

# ============================================================
# Capture the exact current VS Code extension set.
# ============================================================

def main [] {
    if (which code | is-empty) {
        print "[skip] VS Code CLI not found"
        return
    }

    let context = (
        machine-context
    )

    let data_root = (
        $context.data_root
        | path expand
    )

    let extension_file = (
        $data_root
        | path join "vscode" "extensions.txt"
    )

    mkdir (
        $extension_file
        | path dirname
    )

    let args = [
        "--list-extensions"
    ]

    let result = (run-command "code" $args)
    if not $result.ok { error make {msg: (command-failure-message "List VS Code extensions" $result)} }
    let current = (
        $result.stdout
        | lines
        | where { |item| not ($item | is-empty) }
        | sort
        | uniq
        | str join (char nl)
    )

    let output = (
        if ($current | is-empty) {
            ""
        } else {
            $current + (char nl)
        }
    )

    $output
    | save --force $extension_file

    print (
        "[ok] VS Code extension set -> " + ($extension_file | into string)
    )
}
