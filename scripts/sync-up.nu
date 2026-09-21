#!/usr/bin/env nu
const TRANSPORT = path self ./sync-transport.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message]

# Concurrency guard runs before the internal re-add/capture callback.
def main [] {
    let exe = $nu.current-exe
    let result = (run-command $exe ["--no-config-file" $TRANSPORT "push"] --live)
    if not $result.ok {
        error make { msg: (command-failure-message "Push" $result) }
    }
}
