#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command]

def lock-file [] {
    (nu-home) | path join ".config" "dotfiles" "locks" "auto-sync.lock"
}

def log [level: string message: string] {
    let script = ($TOOLS_ROOT | path join "scripts" "log-event.nu")
    let args = [$script "--level" $level "--message" $message]
    let result = (run-command ($nu.current-exe | into string) (["--no-config-file"] | append $args))
    if not $result.ok {
        print --stderr ("[warn] Event logging failed: " + ($result.diagnostic? | default "unknown logging error" | str trim))
    }
}

def stale-lock [file: path] {
    if not ($file | path exists) { return false }

    let rows = (ls $file)
    if ($rows | is-empty) { return true }

    let modified = ($rows | get 0.modified)
    let age = ((date now) - $modified)
    $age > 10min
}

def acquire-lock [] {
    let file = (lock-file)
    mkdir ($file | path dirname)

    if ($file | path exists) {
        if (stale-lock $file) {
            rm $file
            log "WARN" "Removed stale automatic sync lock."
        } else {
            log "INFO" "Automatic sync skipped because another cycle is still running."
            return false
        }
    }

    { created_at: (date now), pid: $nu.pid }
    | to nuon
    | save --force $file

    true
}

def release-lock [] {
    let file = (lock-file)
    if ($file | path exists) { rm $file }
}

def main [] {
    if not (acquire-lock) { return }

    let worker = ($TOOLS_ROOT | path join "scripts" "auto-sync-worker.nu")
    let result = (run-command ($nu.current-exe | into string) ["--no-config-file" ($worker | into string)] --live)
    release-lock

    if not $result.ok {
        let code = ($result.exit_code? | default 1)
        let detail = ($result.diagnostic? | default "" | str trim)
        let message = if ($detail | is-empty) {
            "Automatic sync worker exited with code " + ($code | into string)
        } else {
            "Automatic sync worker exited with code " + ($code | into string) + ": " + $detail
        }
        log "ERROR" $message
        exit $code
    }
}
