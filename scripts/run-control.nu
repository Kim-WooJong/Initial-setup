#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const RUN_MODULE = path self ./modules/run-state.nu
const CORE_MODULE = path self ./modules/core.nu
const SUBPROCESS = path self ./modules/subprocess.nu

use $RUN_MODULE [list-runs load-run latest-resumable-run resolve-resume-run events-path finish-run]
use $CORE_MODULE [nu-home error-message failure-envelope captured-failure]
use $SUBPROCESS [run-command command-failure-message]
const SAFETY = path self ./modules/safety.nu
use $SAFETY [operation-lease release-lease]

def choose-run [requested: string] {
    if not ($requested | is-empty) {
        load-run $requested | ignore
        return $requested
    }

    let rows = (list-runs)
    if ($rows | is-empty) {
        error make { msg: "No setup run history exists." }
    }

    $rows | first | get run_id
}

def matching-backup [run_id: string] {
    let root = ((nu-home) | path join ".config" "dotfiles" "local-backups")
    if not ($root | path exists) { return null }

    let token = ("setup-" + $run_id)
    let rows = (
        ls $root
        | where type == dir
        | where { |row|
            let name = ($row.name | path basename)
            not ($name | str starts-with ".") and ($name | str contains $token) and (($row.name | path join "manifest.nuon") | path exists)
        }
        | sort-by name
        | reverse
    )

    if ($rows | is-empty) { null } else { $rows | first | get name }
}


def matching-snapshot [run_id: string] {
    let root = ((nu-home) | path join ".config" "dotfiles" "snapshots")
    if not ($root | path exists) { return null }

    let token = ("setup-" + $run_id)
    let rows = (
        ls $root
        | where type == dir
        | where { |row|
            let name = ($row.name | path basename)
            not ($name | str starts-with ".") and ($name | str contains $token) and (($row.name | path join "snapshot.nuon") | path exists)
        }
        | sort-by name
        | reverse
    )

    if ($rows | is-empty) { null } else { $rows | first | get name }
}

def print-state [state: record] {
    print ("Run ID   : " + $state.run_id)
    print ("Version  : " + ($state.version? | default "unknown"))
    print ("Status   : " + ($state.status? | default "unknown"))
    print ("Profile  : " + ($state.profile? | default ""))
    print ("Mode     : " + ($state.resolved_mode? | default ($state.requested_mode? | default "")))
    print ("Policy   : " + ($state.resolved_policy? | default ($state.requested_policy? | default "")))
    print ("Started  : " + ($state.started_at? | default ""))
    print ("Updated  : " + ($state.updated_at? | default ""))
    print ""
    print "Stages"
    print "────────────────────────────────────────────────────────────"

    let stages = ($state.stages? | default [])
    if ($stages | is-empty) {
        print "  No checkpointed stages yet."
    } else {
        for stage in $stages {
            print ("  [" + $stage.status + "] " + $stage.name)
            if not (($stage.detail? | default "") | is-empty) {
                print ("      " + $stage.detail)
            }
        }
    }
}

def main [
    --list
    --status
    --logs
    --resume
    --rollback
    --run-id: string = ""
] {
    if $list {
        let rows = (list-runs)
        if ($rows | is-empty) {
            print "No setup run history."
        } else {
            print $rows
        }
        return
    }

    if $resume {
        let resumable = (resolve-resume-run $run_id)
        let result = (run-command $nu.current-exe ["--no-config-file" ($TOOLS_ROOT | path join "setup.nu") "--resume" "--run-id" $resumable] --live)
        if not $result.ok { error make {msg: (command-failure-message "Resume setup run" $result)} }
        return
    }

    let selected = (choose-run $run_id)

    if $rollback {
        let lease = (operation-lease)
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lease.lock.token
        let operation = (try {
            let backup = (matching-backup $selected)
            if $backup == null {
                error make { msg: ("No completed transaction configuration backup found for run " + $selected) }
            }

            let snapshot = (matching-snapshot $selected)
            if $snapshot != null {
                print ("Restoring private configuration snapshot for run " + $selected)
                let private_restore = (run-command $nu.current-exe [
                    "--no-config-file"
                    ($TOOLS_ROOT | path join "scripts" "rollback.nu")
                    "--snapshot"
                    ($snapshot | path basename)
                    "--source-only"
                ] --live)
                if not $private_restore.ok {
                    error make {msg: (command-failure-message "Private source rollback" $private_restore)}
                }
            } else {
                print "[info] No private snapshot existed for this run; restoring the local backup next."
            }

            print ("Restoring the independent live-configuration backup for run " + $selected)
            let live_restore = (run-command $nu.current-exe [
                "--no-config-file"
                ($TOOLS_ROOT | path join "scripts" "backup-local-config.nu")
                "--restore"
                ($backup | path basename)
                "--force"
            ] --live)
            if not $live_restore.ok {
                error make {msg: (command-failure-message "Live-configuration rollback" $live_restore)}
            }
            null
        } catch {|err| failure-envelope $err })
        let failure = (captured-failure $operation)
        let cleanup = (try { release-lease $lease; null } catch {|err| failure-envelope $err })
        let cleanup_failure = (captured-failure $cleanup)

        if $failure != null {
            finish-run $selected "rollback-failed" (error-message $failure "Rollback failed.")
            mut message = (error-message $failure ("Rollback failed for run " + $selected))
            if $cleanup_failure != null {
                $message = ($message + (char nl) + "Operation-lock cleanup also failed: " + (error-message $cleanup_failure))
            }
            error make {msg: $message}
        }
        if $cleanup_failure != null {
            finish-run $selected "rollback-failed" (error-message $cleanup_failure "Operation-lock cleanup failed.")
            error make {msg: ("Operation-lock cleanup failed: " + (error-message $cleanup_failure))}
        }
        finish-run $selected "rolled-back"
        return
    }

    if $logs {
        let file = (events-path $selected)
        if not ($file | path exists) {
            print "No event log exists for this run."
        } else {
            let content = (open --raw $file)
            print $content
        }
        return
    }

    # --status is accepted for readability; status is also the default action.
    let state = (load-run $selected)
    print-state $state
}
