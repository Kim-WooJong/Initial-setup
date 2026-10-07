#!/usr/bin/env nu
const TRANSPORT = path self ./sync-transport.nu
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-error]

# Concurrency guard runs before the internal re-add/capture callback.
def main [--manual --local-wins] {
    let exe = $nu.current-exe
    mut args = ["--no-config-file" $TRANSPORT "push"]
    if $local_wins {
        # Explicit reviewed local-authoritative choice from dotresolve.
        exec $exe ...($args | append ["--manual" "--local-wins"])
    }
    if $manual {
        $args = ($args | append "--manual")
        exec $exe ...$args
    }
    let result = (run-command $exe $args --live)
    if not $result.ok {
        if not $result.launched { print-error (command-failure-message "Push" $result) }
        exit ($result.exit_code? | default 1)
    }
}
