const TEXT_CASE = path self ./text-case.nu
use $TEXT_CASE [text-upper]
# Persistent setup run state, checkpoints, and history.

const CORE_MODULE = path self ./core.nu
use $CORE_MODULE [nu-home]

export def runs-root [] {
    (nu-home) | path join ".config" "dotfiles" "runs"
}

def now-text [] {
    date now | format date "%Y-%m-%d %H:%M:%S %z"
}

def run-dir [run_id: string] {
    runs-root | path join $run_id
}

def run-file [run_id: string] {
    run-dir $run_id | path join "state.nuon"
}

def events-file [run_id: string] {
    run-dir $run_id | path join "events.log"
}

def append-event [run_id: string level: string message: string] {
    let line = ((now-text) + " | " + $level + " | " + $message + (char nl))
    let file = (events-file $run_id)

    if ($file | path exists) {
        $line | save --append $file
    } else {
        $line | save $file
    }
}

def save-run [state: record] {
    let file = (run-file $state.run_id)
    mkdir ($file | path dirname)
    $state | to nuon | save --force $file
}

export def load-run [run_id: string] {
    let file = (run-file $run_id)

    if not ($file | path exists) {
        error make { msg: ("Setup run not found: " + $run_id) }
    }

    open $file
}

export def create-run [
    version: string
    requested_mode: string
    requested_policy: string
    profile: string
    data_root: string
    no_auto_sync: bool
] {
    let root = (runs-root)
    mkdir $root

    let base = (date now | format date "%Y%m%d-%H%M%S")
    mut run_id = $base
    mut suffix = 1

    while ((run-dir $run_id) | path exists) {
        $suffix = $suffix + 1
        $run_id = ($base + "-" + ($suffix | into string))
    }

    mkdir (run-dir $run_id)

    let state = {
        format_version: 1
        run_id: $run_id
        version: $version
        status: "running"
        started_at: (now-text)
        updated_at: (now-text)
        requested_mode: $requested_mode
        requested_policy: $requested_policy
        resolved_mode: ""
        resolved_policy: ""
        profile: $profile
        data_root: $data_root
        no_auto_sync: $no_auto_sync
        stages: []
    }

    save-run $state
    append-event $run_id "START" ("Initial-setup " + $version)
    $run_id
}

export def update-run-context [
    run_id: string
    resolved_mode: string
    resolved_policy: string
    profile: string
    data_root: string
    no_auto_sync: bool
] {
    let state = (load-run $run_id)
    let next = (
        $state
        | upsert resolved_mode $resolved_mode
        | upsert resolved_policy $resolved_policy
        | upsert profile $profile
        | upsert data_root $data_root
        | upsert no_auto_sync $no_auto_sync
        | upsert updated_at (now-text)
    )
    save-run $next
    append-event $run_id "CONTEXT" ("mode=" + $resolved_mode + " policy=" + $resolved_policy + " profile=" + $profile)
}

export def stage-status [run_id: string stage: string] {
    let state = (load-run $run_id)
    let rows = (($state.stages? | default []) | where name == $stage)

    if ($rows | is-empty) {
        "pending"
    } else {
        $rows | first | get status
    }
}

export def mark-stage [
    run_id: string
    stage: string
    status: string
    detail: string = ""
] {
    let state = (load-run $run_id)
    let stages = ($state.stages? | default [])
    let timestamp = (now-text)
    let existing = ($stages | where name == $stage)

    let updated = (
        if ($existing | is-empty) {
            $stages | append {
                name: $stage
                status: $status
                started_at: (if $status == "running" { $timestamp } else { "" })
                ended_at: (if $status in ["success" "failed" "skipped"] { $timestamp } else { "" })
                detail: $detail
            }
        } else {
            $stages | each { |item|
                if $item.name == $stage {
                    {
                        name: $item.name
                        status: $status
                        started_at: (
                            if $status == "running" {
                                if (($item.started_at? | default "") | is-empty) { $timestamp } else { $item.started_at }
                            } else {
                                $item.started_at? | default ""
                            }
                        )
                        ended_at: (if $status in ["success" "failed" "skipped"] { $timestamp } else { "" })
                        detail: $detail
                    }
                } else {
                    $item
                }
            }
        }
    )

    let run_status = (if $status == "failed" { "failed" } else { "running" })
    let next = (
        $state
        | upsert status $run_status
        | upsert stages $updated
        | upsert updated_at $timestamp
    )

    save-run $next
    append-event $run_id ($status | text-upper) ($stage + (if ($detail | is-empty) { "" } else { " | " + $detail }))
}

export def finish-run [run_id: string status: string] {
    let state = (load-run $run_id)
    let next = (
        $state
        | upsert status $status
        | upsert updated_at (now-text)
        | upsert finished_at (now-text)
    )
    save-run $next
    append-event $run_id ($status | text-upper) "setup run finished"
}

export def latest-resumable-run [] {
    let root = (runs-root)

    if not ($root | path exists) {
        return null
    }

    let rows = (ls $root | where type == dir | sort-by name | reverse)

    for row in $rows {
        let file = ($row.name | path join "state.nuon")
        if not ($file | path exists) { continue }

        let state = (open $file)
        if ($state.status? | default "") in ["running" "failed"] {
            return ($state.run_id? | default ($row.name | path basename))
        }
    }

    null
}

export def resolve-resume-run [requested: string] {
    if not ($requested | is-empty) {
        let state = (load-run $requested)
        if not (($state.status? | default "") in ["running" "failed"]) {
            error make { msg: ("Setup run " + $requested + " is not resumable (status: " + ($state.status? | default "unknown") + ").") }
        }
        return $requested
    }

    let latest = (latest-resumable-run)

    if $latest == null {
        error make { msg: "No failed or interrupted setup run is available to resume." }
    }

    $latest
}

export def list-runs [] {
    let root = (runs-root)

    if not ($root | path exists) {
        return []
    }

    ls $root
    | where type == dir
    | sort-by name
    | reverse
    | each { |row|
        let file = ($row.name | path join "state.nuon")
        if ($file | path exists) {
            let state = (open $file)
            {
                run_id: ($state.run_id? | default ($row.name | path basename))
                status: ($state.status? | default "unknown")
                version: ($state.version? | default "unknown")
                profile: ($state.profile? | default "")
                mode: ($state.resolved_mode? | default ($state.requested_mode? | default ""))
                started_at: ($state.started_at? | default "")
                updated_at: ($state.updated_at? | default "")
            }
        }
    }
}

export def events-path [run_id: string] {
    events-file $run_id
}
