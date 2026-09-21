#!/usr/bin/env nu

const ROOT = path self ..

def fail [message: string] {
    print --stderr ("[FAIL] " + $message)
    exit 1
}

def require-text [text: string needle: string label: string] {
    if not ($text | str contains $needle) { fail $label }
}

def forbid-text [text: string needle: string label: string] {
    if ($text | str contains $needle) { fail $label }
}

def main [] {
    let entry = (open --raw ($ROOT | path join "setup.nu"))
    let orchestration = (open --raw ($ROOT | path join "setup-main.nu"))
    let run_state = (open --raw ($ROOT | path join "scripts" "modules" "run-state.nu"))

    forbid-text $entry '$env.LAST_EXIT_CODE' "setup.nu must not use LAST_EXIT_CODE"
    forbid-text $orchestration '$env.LAST_EXIT_CODE' "setup-main.nu must not use LAST_EXIT_CODE"
    forbid-text $orchestration "do { ^chezmoi" "setup-main.nu must use the shared subprocess layer for chezmoi"
    forbid-text $orchestration "The original diagnostic was printed above" "generic diagnostic replacement must not return"

    require-text $entry "def interactive-child" "setup.nu must define an interactive TTY child boundary"
    require-text $entry "exec $exe --no-config-file $script ...$args" "interactive setup must use exec instead of captured subprocess execution"
    require-text $entry 'interactive-child ($ROOT | path join "setup-main.nu") $args' "setup-main.nu must be launched through the interactive boundary"

    require-text $orchestration "--optional" "optional stage policy is missing"
    require-text $orchestration "--always-run" "resume recheck policy is missing"
    require-text $orchestration 'mark-stage $run_id $title "warning"' "optional warning checkpoint is missing"
    require-text $orchestration 'run-command ($nu.current-exe | into string) $child_args --live' "child scripts must use live shared subprocess execution"
    require-text $orchestration 'finish-run $failed_run $final_status $detail' "top-level failures/interruption must persist the original detail"
    require-text $orchestration 'finish-run $completed_run "success"' "success must be committed after provider finalization"
    require-text $orchestration 'section "Setup transaction complete"' "final success section is missing"
    forbid-text $orchestration 'section "Setup complete"' "setup must not announce final success before provider finalization"

    require-text $run_state '"warning" "skipped" "interrupted"' "warning/interrupted stages must receive an end timestamp"
    require-text $run_state "final_detail" "final run diagnostics must be persisted"

    let optional_count = ($orchestration | lines | where {|line| ($line | str contains "run-script") and ($line | str contains "--optional") } | length)
    if $optional_count < 10 { fail "too few feature stages are explicitly classified as optional" }

    print ("[pass] setup orchestration policy (optional stages: " + ($optional_count | into string) + ")")
}
