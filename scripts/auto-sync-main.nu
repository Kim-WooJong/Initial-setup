#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def lock-file [] {
    (nu-home) | path join ".config" "dotfiles" "locks" "auto-sync.lock"
}

def log [level: string message: string] {
    let script = ($TOOLS_ROOT | path join "scripts" "log-event.nu")
    let args = [$script "--level" $level "--message" $message]
    ^$nu.current-exe --no-config-file ...$args | ignore
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
    ^$nu.current-exe --no-config-file $worker

    let exit_code = ($env.LAST_EXIT_CODE | default 0)
    release-lock

    if $exit_code != 0 {
        log "ERROR" ("Automatic sync worker exited with code " + ($exit_code | into string))
        exit $exit_code
    }
}
