#!/usr/bin/env nu
# Verification entrypoint. No automatic package/runtime installation.
const ROOT = path self .
const SUBPROCESS = path self ./scripts/modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

def main [--full --offline --report-dir: path --runtime: path --skip-build --working-tree] {
    let exe = if $runtime == null { $nu.current-exe } else { $runtime | path expand }
    if not ($exe | path exists) { error make {msg: "NU_EXECUTABLE_MISSING: --runtime must name an existing executable."} }
    let runner = ($ROOT | path join "scripts" "verify-all.nu")
    if not ($runner | path exists) { error make {msg: "INCOMPLETE_RELEASE: scripts/verify-all.nu is missing."} }
    mut args = ["--no-config-file" ($runner | into string)]
    if $full { $args = ($args | append "--full") }
    if $offline { $args = ($args | append "--offline") }
    if $skip_build { $args = ($args | append "--skip-build") }
    if $working_tree { $args = ($args | append "--working-tree") }
    if $report_dir != null { $args = ($args | append ["--report-dir" ($report_dir | into string)]) }

    let result = (run-command ($exe | into string) $args --live)
    if not $result.ok {
        print --stderr (command-failure-message "Initial-setup verification" $result)
        exit (if $result.exit_code == null { 1 } else { $result.exit_code })
    }
}
