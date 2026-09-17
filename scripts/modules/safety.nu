const PROCESS_OUTPUT = path self ./process-output.nu
use $PROCESS_OUTPUT [output-text]
const TEXT_CASE = path self ./text-case.nu
use $TEXT_CASE [text-lower]
# Shared checked I/O, path validation, operation locking, and content manifests.
# No shell-evaluated user strings and no secrets in error messages.
const CORE = path self ./core.nu
const WINDOWS_LOCK = path self ../windows/acquire-operation-lock.ps1
const POSIX_LOCK = path self ../posix/acquire-operation-lock.sh
const WINDOWS_PRIVATE = path self ../windows/protect-secret-path.ps1
use $CORE [nu-home error-message]

export def state-root [] { (nu-home) | path join ".config" "dotfiles" }

export def checked [program: string args: list label: string] {
    if (which $program | is-empty) { error make { msg: ("Missing required command: " + $program) } }
    let result = (do { ^$program ...$args } | complete)
    if $result.exit_code != 0 {
        error make { msg: ($label + " failed (exit " + ($result.exit_code | into string) + ").") }
    }
    $result.stdout
}

export def private-directory [dir: path] {
    mkdir $dir
    if $nu.os-info.name == "windows" {
        checked "powershell.exe" ["-NoProfile" "-NonInteractive" "-ExecutionPolicy" "Bypass" "-File" $WINDOWS_PRIVATE "-Path" $dir] "Restrict directory ACL" | ignore
    } else {
        checked "chmod" ["700" $dir] "Restrict directory permissions" | ignore
    }
}

export def private-file [file: path] {
    if $nu.os-info.name == "windows" {
        checked "powershell.exe" ["-NoProfile" "-NonInteractive" "-ExecutionPolicy" "Bypass" "-File" $WINDOWS_PRIVATE "-Path" $file] "Restrict file ACL" | ignore
    } else {
        checked "chmod" ["600" $file] "Restrict file permissions" | ignore
    }
}

export def atomic-record [file: path value: record] {
    mkdir ($file | path dirname)
    let temp = (($file | into string) + ".tmp-" + (random uuid))
    try {
        $value | to nuon | save $temp
        mv --force $temp $file
    } catch {|err|
        if ($temp | path exists) { rm --force $temp }
        error make { msg: (error-message $err "Atomic write failed.") }
    }
}

# Keep helper failures distinct from real exclusive-create collisions. This
# function is pure so the diagnostic contract can be tested without PowerShell.
export def lock-result-message [file: path result: record token: string] {
    if $result.exit_code == 0 { return "" }
    let original = ($result.stderr? | output-text | str trim)
    let detail = if ($token | is-empty) { $original } else {
        $original | str replace --all $token "<redacted-lock-token>"
    }
    let suffix = if ($detail | is-empty) { "" } else { "\nHelper diagnostic:\n" + $detail }
    let target = ($file | into string)
    if $result.exit_code == 17 and ($original | str contains "INITIAL_SETUP_LOCK_EXISTS:") {
        # Keep message fragments separate without leading continuation operators;
        # validate-project.nu enforces that repository formatting rule.
        return ([
            ("LOCK_EXISTS: " + $target)
            "\nAn existing lock file blocked exclusive creation. It may be active OR left by an interrupted operation; existence alone does not prove either."
            "\nDo not delete it while any writer is running. Inspect with: nu --no-config-file scripts/lock-status.nu --file <the-exact-path>"
            $suffix
        ] | str join "")
    }
    return ([
        ("LOCK_CREATE_FAILED: " + $target + " (helper exit " + ($result.exit_code | into string) + ").")
        "\nThis is NOT proof that another operation is running. Check the diagnostic below for permissions, an enforced PowerShell policy, a missing helper, or I/O errors."
        "\nNo existing lock has been removed. Use scripts/lock-status.nu --probe to test creation separately."
        $suffix
    ] | str join "")
}

export def lock-acquire [file: path] {
    let target = ($file | path expand --no-symlink)
    try { mkdir ($target | path dirname) } catch {|err|
        error make {msg: ("LOCK_CREATE_FAILED: cannot prepare parent directory for " + ($target | into string) + ".\n" + (error-message $err "unknown directory preparation failure"))}
    }
    let token = (random uuid)
    let program = if $nu.os-info.name == "windows" { "powershell.exe" } else { "sh" }
    if (which $program | is-empty) {
        error make {msg: ("LOCK_HELPER_MISSING: " + $program + ". This is not an existing-lock conflict.")}
    }
    let result = (try {
        if $nu.os-info.name == "windows" {
            do { ^powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WINDOWS_LOCK -Path $target -Token $token } | complete
        } else {
            do { ^sh $POSIX_LOCK $target $token } | complete
        }
    } catch {|err|
        error make {msg: ("LOCK_HELPER_FAILED: could not execute the lock helper for " + ($target | into string) + ".\n" + (error-message $err "unknown helper execution failure"))}
    })
    let message = (lock-result-message $target $result $token)
    if not ($message | is-empty) { error make {msg: $message} }
    # Validate the helper result before allowing any protected operation.
    let actual = (try { open --raw $target | str trim } catch { "" })
    if $actual != $token {
        error make {msg: ("LOCK_CREATE_FAILED: helper reported success but token verification failed: " + ($target | into string) + ". No protected work was started; inspect the path.")}
    }
    { path: ($target | into string) token: $token }
}

export def lock-release [lock: record] {
    if ($lock.path | path exists) {
        if (open --raw $lock.path | str trim) == $lock.token { rm --force $lock.path }
    }
}

export def operation-lock [] { lock-acquire ((state-root) | path join "locks" "operation.lock") }

export def validate-relative [value: string] {
    let parts = ($value | split row "/")
    if ($value | is-empty) or ($value | str starts-with "/") or ($value | str contains '\') or ($value | str contains ':') or (".." in $parts) or ("." in $parts) or ("" in $parts) or ($value =~ '[\x00-\x1f]') {
        error make { msg: "Unsafe relative path in manifest." }
    }
    for part in $parts {
        if ($part =~ '[. ]$') or ($part =~ '[<>"|?*]') or ($part =~ '(?i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') {
            error make {msg: "Manifest path is not portable to Windows."}
        }
    }
    $value
}

export def disjoint-paths [first: path second: path] {
    let a = ($first | path expand | into string | str replace --all '\' '/' | str trim --right --char '/')
    let b = ($second | path expand | into string | str replace --all '\' '/' | str trim --right --char '/')
    let aa = if $nu.os-info.name == "windows" { $a | text-lower } else { $a }
    let bb = if $nu.os-info.name == "windows" { $b | text-lower } else { $b }
    if $aa == $bb or ($aa | str starts-with ($bb + "/")) or ($bb | str starts-with ($aa + "/")) {
        error make { msg: "Source, destination, repository, and credential directories must not overlap." }
    }
}

export def tree-files [root: path] {
    if not ($root | path exists) { return [] }
    mut result = []
    for item in (ls --all $root | sort-by name) {
        if $item.type == "dir" {
            $result = ($result | append (tree-files $item.name))
        } else if $item.type == "file" {
            $result = ($result | append $item.name)
        } else {
            error make { msg: ("Symlinks and special files are not permitted in a release or transport snapshot: " + $item.name) }
        }
    }
    $result
}

export def tree-manifest [root: path] {
    tree-files $root | each {|file|
        let rel = ($file | path relative-to $root | into string | str replace --all '\' '/')
        validate-relative $rel | ignore
        { path: $rel sha256: (open --raw $file | hash sha256) }
    } | sort-by path
}

export def manifest-hash [entries: list] {
    $entries | sort-by path | to json --raw | hash sha256
}

export def verify-tree [root: path entries: list] {
    mut seen = []
    for entry in $entries {
        validate-relative $entry.path | ignore
        if not ($entry.sha256 =~ '^[a-f0-9]{64}$') { error make { msg: "Invalid checksum in manifest." } }
        let key = ($entry.path | text-lower)
        if $key in $seen { error make { msg: "Duplicate or case-colliding file in manifest." } }
        $seen = ($seen | append $key)
    }
    let actual = (tree-manifest $root)
    if $actual != ($entries | sort-by path) { error make { msg: "Snapshot contents differ from the expected SHA-256 manifest." } }
    true
}

export def operation-lease [] {
    let file = ((state-root) | path join "locks" "operation.lock")
    let token = ($env.INITIAL_SETUP_OPERATION_TOKEN? | default "")
    if not ($token | is-empty) and ($file | path exists) {
        if (open --raw $file | str trim) == $token { return {lock: {path: ($file | into string) token: $token} owned: false} }
    }
    {lock: (operation-lock) owned: true}
}
export def release-lease [lease: record] { if $lease.owned { lock-release $lease.lock } }
