#!/usr/bin/env nu
# Explicit runtime-only updater. --check never creates keys/config/runtime files.
const RUNTIME = path self ./modules/nu-runtime.nu
use $RUNTIME [runtime-check runtime-ensure]
def main [--check --shell] {
    if $check and $shell { error make {msg: "Choose --check or --shell."} }
    if $check { return (runtime-check | reject release) }
    let selected = (runtime-ensure)
    if $shell {
        let exe = $selected.exe
        let paths = if ($env.PATH | describe) == "string" { $env.PATH | split row (if $nu.os-info.name == "windows" { ";" } else { ":" }) } else { $env.PATH }
        # A new interactive shell is a new trust/freshness scope: never carry
        # the per-operation latest check into future unrelated user commands.
        with-env {PATH: ([($exe | path dirname)] | append $paths)
                  INITIAL_SETUP_NU_SESSION_EXE: "" INITIAL_SETUP_NU_SESSION_VERSION: "" INITIAL_SETUP_NU_SESSION_PROVIDER: ""} {
            ^$exe
            exit ($env.LAST_EXIT_CODE | default 1)
        }
    }
    print {executable: $selected.exe version: $selected.version provider: ($selected.provider? | default "current-v1")}
    print "Setup/sync uses this runtime automatically. Your already-open terminal process is unchanged."
}
