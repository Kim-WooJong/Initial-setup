#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const RUN_MODULE = path self ./modules/run-state.nu
const CORE_MODULE = path self ./modules/core.nu

use $RUN_MODULE [list-runs load-run latest-resumable-run resolve-resume-run events-path finish-run]
use $CORE_MODULE [nu-home error-message]
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
        | where { |row| (($row.name | path basename) | str contains $token) }
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
        | where { |row| (($row.name | path basename) | str contains $token) }
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
        ^$nu.current-exe --no-config-file ($TOOLS_ROOT | path join "setup.nu") --resume --run-id $resumable
        return
    }

    let selected = (choose-run $run_id)

    if $rollback {
        let lease = (operation-lease)
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lease.lock.token
        try {
            let backup = (matching-backup $selected)
            if $backup == null {
                error make { msg: ("No transaction configuration backup found for run " + $selected) }
            }

            let snapshot = (matching-snapshot $selected)
            if $snapshot != null {
                print ("Restoring private configuration snapshot for run " + $selected)
                ^$nu.current-exe --no-config-file ($TOOLS_ROOT | path join "scripts" "rollback.nu") --snapshot ($snapshot | path basename) --source-only
                if ($env.LAST_EXIT_CODE | default 1) != 0 { error make {msg: "Private source rollback failed."} }
            } else {
                print "[info] No private snapshot existed for this run; restoring the local backup next."
            }

            print ("Restoring the independent live-configuration backup for run " + $selected)
            ^$nu.current-exe --no-config-file ($TOOLS_ROOT | path join "scripts" "backup-local-config.nu") --restore ($backup | path basename) --force
            if ($env.LAST_EXIT_CODE | default 1) != 0 { error make {msg: "Live-configuration rollback failed."} }
            finish-run $selected "rolled-back"
            release-lease $lease
        } catch { |err|
            release-lease $lease
            finish-run $selected "rollback-failed"
            error make { msg: (error-message $err ("Rollback failed for run " + $selected)) }
        }
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
