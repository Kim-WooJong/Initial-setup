#!/usr/bin/env nu

def main [] {
    if (which rclone | is-empty) {
        exit 2
    }

    let rows = (
        ^rclone config file
        | lines
        | each { |line| $line | str trim }
        | where { |line| not ($line | is-empty) }
    )

    let exit_code = ($env.LAST_EXIT_CODE | default 1)

    if $exit_code != 0 or ($rows | is-empty) {
        exit 2
    }

    $rows | last
}
