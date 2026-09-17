#!/usr/bin/env nu
const TOOLS_ROOT = path self ..
const OUTPUT = path self ./modules/process-output.nu
use $OUTPUT [output-text]

def run-script [name: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)
    let exe = $nu.current-exe
    let result = (do { ^$exe --no-config-file $script } | complete)
    let out = ($result.stdout | output-text)
    let err = ($result.stderr | output-text)
    if not ($out | is-empty) { print $out }
    if not ($err | is-empty) { print --stderr $err }
    {script: $name exit_code: $result.exit_code}
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
