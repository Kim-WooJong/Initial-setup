#!/usr/bin/env nu
const PROCESS_OUTPUT = path self ./modules/process-output.nu
use $PROCESS_OUTPUT [output-text]
# Run the actual interpreter matrix. Both binaries must already be installed.
# No package manager, download, cloud account, or live setup is invoked here.
const ROOT = path self ..

def invoke-nu [exe: path args: list] {
    try { do { ^$exe --no-config-file ...$args } | complete } catch {|err|
        {exit_code: 1 stdout: "" stderr: $err.msg}
    }
}

def interpreter [path: path family: string] {
    let exe = ($path | path expand)
    if not ($exe | path exists) { error make {msg: ("Interpreter not found: " + ($exe | into string))} }
    let result = (invoke-nu $exe ["--commands" "version | to json --raw"])
    if $result.exit_code != 0 { error make {msg: ("Cannot run interpreter: " + ($exe | into string))} }
    let info = ($result.stdout | from json)
    let parts = ($info.version | split row ".")
    let major = ($parts.0 | into int)
    let minor = ($parts.1 | into int)
    let patch = ($parts.2 | split row "-" | first | split row "+" | first | into int)
    let supported = if $family == "baseline" {
        $major == 0 and $minor < 114 and ($minor > 109 or ($minor == 109 and $patch >= 1))
    } else {
        $major > 0 or ($major == 0 and $minor >= 114)
    }
    if not $supported {
        error make {msg: ("Wrong " + $family + " interpreter: " + $info.version + ". Use 0.109.1-0.113.x for baseline and >=0.114.0 for modern.")}
    }
    {family: $family exe: $exe version: $info.version}
}

# Example:
# nu scripts/check-compatibility.nu /path/to/nu-0.109.1 /path/to/nu-0.115.1 --report-dir ../nu-matrix
# Reports distinguish this two-binary matrix from a one-interpreter syntax check.
def main [baseline: path modern: path --report-dir: path] {
    let interpreters = [(interpreter $baseline "baseline") (interpreter $modern "modern")]
    let directory = if $report_dir == null {
        let base = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp"))
        $base | path join ("initial-setup-compatibility-" + (random uuid))
    } else { $report_dir | path expand }
    mkdir $directory
    mut results = []
    for engine in $interpreters {
        print ("[interpreter] " + $engine.family + " " + $engine.version)
        let syntax_report = ($directory | path join ($engine.family + "-syntax.json"))
        let steps = [
            {name: "syntax" args: [($ROOT | path join "scripts" "validate-syntax.nu") "--deny-warnings" "--report" $syntax_report]}
            {name: "syntax-fixtures" args: [($ROOT | path join "scripts" "syntax-self-test.nu")]}
            {name: "regressions" args: [($ROOT | path join "scripts" "regression-test.nu")]}
        ]
        for step in $steps {
            let result = (invoke-nu $engine.exe $step.args)
            let file = ($directory | path join ($engine.family + "-" + $step.name + ".log"))
            ([($result.stdout | output-text) ($result.stderr | output-text)] | str join (char nl)) | save --force $file
            $results = ($results | append {
                family: $engine.family version: $engine.version exe: ($engine.exe | into string)
                stage: $step.name exit_code: $result.exit_code log: ($file | into string)
            })
            print ((if $result.exit_code == 0 { "[ok] " } else { "[FAIL] " }) + $engine.family + " / " + $step.name)
        }
    }
    let failed = ($results | where exit_code != 0 | length)
    {format: 1 platform: $nu.os-info.name matrix_complete: ($failed == 0) failed: $failed results: $results}
    | to json | save --force ($directory | path join "matrix.json")
    print ("[reports] " + ($directory | into string))
    if $failed > 0 { exit 1 }
}
