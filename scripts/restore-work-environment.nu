#!/usr/bin/env nu
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command]

def run-script [name: string source_root: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)
    mut args = ["--no-config-file" $script]
    if not ($source_root | str trim | is-empty) { $args = ($args | append ["--source-root" $source_root]) }
    let result = (run-command $nu.current-exe $args --live)
    {script: $name ok: $result.ok exit_code: $result.exit_code diagnostic: $result.diagnostic}
}

def main [--source-root: string = ""] {
    mut failures = []
    for name in ["restore-rust-state.nu" "restore-julia-environments.nu"] {
        let result = (run-script $name $source_root)
        if not $result.ok { $failures = ($failures | append $result) }
    }
    if not ($failures | is-empty) {
        let detail = ($failures | each {|row|
            let code = if $row.exit_code == null { "not launched" } else { $row.exit_code | into string }
            let diag = ($row.diagnostic | str trim)
            if ($diag | is-empty) { $row.script + " (" + $code + ")" } else { $row.script + " (" + $code + "): " + $diag }
        } | str join (char nl))
        error make {msg: ("WORK_ENVIRONMENT_INCOMPLETE:" + (char nl) + $detail)}
    }
}
