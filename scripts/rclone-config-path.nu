#!/usr/bin/env nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command]

def main [] {
    if (which rclone | is-empty) { exit 2 }
    let result = (run-command "rclone" ["config" "file"])
    if not $result.ok {
        if not ($result.diagnostic | str trim | is-empty) { print --stderr $result.diagnostic }
        exit 2
    }
    let rows = ($result.stdout | lines | each {|line| $line | str trim } | where {|line| not ($line | is-empty) })
    if ($rows | is-empty) { exit 2 }
    $rows | last
}
