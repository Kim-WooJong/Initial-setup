#!/usr/bin/env nu
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command print-result]

def run-script [name: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)
    let exe = $nu.current-exe
    let result = (run-command ($exe | into string) ["--no-config-file" ($script | into string)])
    print-result ("Capture " + $name) $result
    {script: $name exit_code: ($result.exit_code? | default 1)}
}

def main [] {
    mut failures = []
    for name in ["capture-rust-state.nu" "capture-julia-environments.nu"] {
        let result = (run-script $name)
        if $result.exit_code != 0 { $failures = ($failures | append $result) }
    }
    if not ($failures | is-empty) {
        error make {msg: ("WORK_ENVIRONMENT_INCOMPLETE: " + ($failures | get script | str join ", ") + "; successful partial results are retained, but this operation did not complete.")}
    }
}
