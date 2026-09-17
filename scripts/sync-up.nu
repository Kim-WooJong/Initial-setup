#!/usr/bin/env nu
const TRANSPORT = path self ./sync-transport.nu
# Concurrency guard runs before the internal re-add/capture callback.
def main [] {
    let exe = $nu.current-exe
    ^$exe --no-config-file $TRANSPORT push
    if ($env.LAST_EXIT_CODE | default 1) != 0 { error make { msg: "Push stopped; inspect the reported conflict or transport error." } }
}
