#!/usr/bin/env nu
# Import-free verification entry. No automatic package/runtime installation.
const ROOT = path self .
def main [--full --offline --report-dir: path --runtime: path --skip-build] {
    let exe = if $runtime == null { $nu.current-exe } else { $runtime | path expand }
    if not ($exe | path exists) { error make {msg: "NU_EXECUTABLE_MISSING: --runtime must name an existing executable."} }
    let runner = ($ROOT | path join "scripts" "verify-all.nu")
    if not ($runner | path exists) { error make {msg: "INCOMPLETE_RELEASE: scripts/verify-all.nu is missing."} }
    mut args = []
    if $full { $args = ($args | append "--full") }
    if $offline { $args = ($args | append "--offline") }
    if $skip_build { $args = ($args | append "--skip-build") }
    if $report_dir != null { $args = ($args | append ["--report-dir" ($report_dir | into string)]) }
    ^$exe --no-config-file $runner ...$args
    exit ($env.LAST_EXIT_CODE | default 1)
}
