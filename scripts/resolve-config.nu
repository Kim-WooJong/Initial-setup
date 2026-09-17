#!/usr/bin/env nu

# Bidirectional configuration reconciliation with protected-file policy and
# explicit chezmoi three-way merge support.

const TOOLS_ROOT = path self ..
const CORE_MODULE = path self ./modules/core.nu
const CONFLICTS_MODULE = path self ./modules/conflicts.nu

use $CORE_MODULE [nu-home machine-context error-message failure-envelope captured-failure]
use $CONFLICTS_MODULE [load-conflict-policy local-policy-path protected-conflicts print-protected-conflicts target-path is-protected-target]

const SAFETY = path self ./modules/safety.nu
const PROVIDER = path self ./modules/sync-provider.nu
use $SAFETY [operation-lock lock-release checked]
use $PROVIDER [load-provider assert-expected-head assert-same-head provider-head record-provider-state remote-lock release-remote-lock]

def run-script [name: string ...args: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)
    ^$nu.current-exe --no-config-file $script ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)
    if $exit_code != 0 {
        error make { msg: ("Script failed: " + ($script | into string)) }
    }
}

def guarded-resolve [action: closure] {
    let lock = (operation-lock)
    mut shared = null
    let operation_result = (try {
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lock.token
        let config = (load-provider)
        $shared = (remote-lock $config)
        let head = (assert-expected-head $config)
        run-script "backup-local-config.nu" "--label" "before-resolve"
        do $action
        if $config.kind == "directory" { record-provider-state $config (provider-head $config) } else {
            assert-same-head $config $head
            print "[source only] Merged source is not uploaded. Review it, then run dotpush."
        }
        null
    } catch {|err| failure-envelope $err })
    let operation_failure = (captured-failure $operation_result)

    # Snapshot the error in catch; inspect mutable handles in the outer block.
    # Attempt both releases, including when the remote lock cannot be removed.
    let remote_cleanup_result = (try { release-remote-lock $shared; null } catch {|err| failure-envelope $err })
    let local_cleanup_result = (try { lock-release $lock; null } catch {|err| failure-envelope $err })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)
    if $operation_failure != null { error make {msg: (error-message $operation_failure "Configuration resolve failed.")} }
    if $remote_cleanup_error != null { error make {msg: (error-message $remote_cleanup_error "Remote-lock cleanup failed.")} }
    if $local_cleanup_error != null { error make {msg: (error-message $local_cleanup_error "Local-lock cleanup failed.")} }
}

def resolve-target-input [prompt: string] {
    let value = (input $prompt | str trim)
    if ($value | is-empty) {
        error make { msg: "No target path was entered." }
    }
    target-path $value
}

def merge-target [data_root: path target: path] {
    print ("[merge] " + ($target | into string))
    ^chezmoi --source ($data_root | into string) merge ($target | into string)

    let merge_exit = ($env.LAST_EXIT_CODE | default 0)
    if $merge_exit != 0 {
        error make { msg: "chezmoi merge failed." }
    }

    print "[apply] Applying merged target..."
    checked "chezmoi" ["--source" ($data_root | into string) "--force" "apply" ($target | into string)] "Apply selected target" | ignore
}

def force-private-target [data_root: path target: path] {
    if not (is-protected-target $target) {
        print "[warn] The selected target is not marked protected; explicit force will still be applied."
    }

    print ("[force] Private source -> " + ($target | into string))
    checked "chezmoi" ["--source" ($data_root | into string) "--force" "apply" ($target | into string)] "Apply selected target" | ignore
}

def show-policy [] {
    let policy = (load-conflict-policy)
    print "Conflict policy"
    print "────────────────────────────────────────────────────────────"
    print "Protected targets:"
    for item in $policy.protected { print ("  " + ((target-path $item) | into string)) }
    print ""
    print "Merge-preferred targets:"
    for item in $policy.merge_preferred { print ("  " + ((target-path $item) | into string)) }
    print ""
    print ("Machine-local override: " + ((local-policy-path) | into string))
}

def main [--policy] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    if not ($data_root | path exists) {
        error make { msg: ("Private data root unavailable: " + ($data_root | into string)) }
    }

    if $policy {
        show-policy
        return
    }

    let provider = (load-provider)
    if $provider.kind != "directory" { print "[info] Differences below describe the local workspace. Fetch a newer remote using dotpull --source-only before merging." }
    print "Configuration differences"
    print "────────────────────────────────────────────────────────────"
    print ("Private data: " + ($data_root | into string))
    print ""

    ^chezmoi --source ($data_root | into string) status
    print ""
    ^chezmoi --source ($data_root | into string) diff
    print ""

    let protected = (protected-conflicts $data_root)
    print-protected-conflicts $protected

    print ""
    print "Resolve configuration"
    print "────────────────────────────────────────────────────────────"
    print "  1) Three-way merge one managed file"
    print "  2) Three-way merge all changed managed files"
    print "  3) Save this machine -> private drive"
    print "  4) Apply private drive -> this machine (protected files remain guarded)"
    print "  5) Backup this machine, then apply private drive"
    print "  6) Explicitly force one protected file from private drive"
    print "  7) Show protected-file policy"
    print "  8) Cancel"
    print ""

    mut selected = ""
    while ($selected | is-empty) {
        let answer = (input "Select [1]: " | str trim)
        let choice = (if ($answer | is-empty) { "1" } else { $answer })

        if $choice in ["1" "2" "3" "4" "5" "6" "7" "8"] {
            $selected = $choice
        } else {
            print "Choose 1 through 8."
        }
    }

    match $selected {
        "1" => {
            let target = (resolve-target-input "Managed target (for example .ssh/config): ")
            guarded-resolve { merge-target $data_root $target }
        }
        "2" => {
            print "[merge] Launching the configured three-way merge tool for every changed managed file..."
            guarded-resolve {
                checked "chezmoi" ["--source" ($data_root | into string) "merge-all"] "Merge changed files" | ignore
                print "[review] Source merged. No blanket --force apply was performed. Apply selected protected targets explicitly before dotpull."
            }
        }
        "3" => {
            print "[sync] Publishing local managed configuration to private drive..."
            run-script "sync-up.nu"
        }
        "4" => {
            print "[sync] Applying private configuration to this machine..."
            run-script "sync-down.nu" "--force"
        }
        "5" => {
            print "[backup] Saving current local configuration..."
            run-script "backup-local-config.nu" "--label" "before-private-pull"
            print "[sync] Applying private configuration to this machine..."
            run-script "sync-down.nu" "--force"
        }
        "6" => {
            let target = (resolve-target-input "Protected target (for example .ssh/config): ")
            guarded-resolve { force-private-target $data_root $target }
        }
        "7" => { show-policy }
        _ => { print "No configuration changes were applied." }
    }
}
