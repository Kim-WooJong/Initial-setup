#!/usr/bin/env nu
const TEXT_CASE = path self ./modules/text-case.nu
use $TEXT_CASE [text-lower]
const ROOT = path self ..
const CORE = path self ./modules/core.nu
const UPGRADE = path self ./modules/upgrade.nu
const SAFETY = path self ./modules/safety.nu
use $UPGRADE *
use $CORE [error-message failure-envelope captured-failure]
use $SAFETY [state-root checked atomic-record operation-lock lock-release private-directory disjoint-paths]

def git [args: list label: string] { checked "git" (["-C" ($ROOT | into string)] | append $args) $label | str trim }

def main [
    --from: string = ""
    --manifest-sha256: string = ""
    --ref: string = ""
    --commit: string = ""
    --yes
    --list
    --rollback: string = ""
] {
    let upgrades = ((state-root) | path join "upgrades")
    if $list {
        if not ($upgrades | path exists) { print "No upgrade history."; return }
        print (ls $upgrades | where type == dir | each {|row|
            let file = ($row.name | path join "upgrade.nuon")
            if ($file | path exists) { open --raw $file | from nuon | select id status from_version to_version } else { {id: ($row.name | path basename) status: "incomplete" from_version: "" to_version: ""} }
        })
        return
    }
    if ($from | is-empty) and ($ref | is-empty) and ($rollback | is-empty) {
        print "Artifact: dotupgrade --from <extracted-project> --manifest-sha256 <trusted-digest> [--yes]"
        print "Git:      dotupgrade --ref <remote-tag-or-branch> --commit <trusted-full-commit> [--yes]"
        print "History:  dotupgrade --list / dotupgrade --rollback <ID> [--yes]"
        return
    }
    let lock = (operation-lock)
    mut record_file = ""
    mut record = {}
    mut promoting = false
    let upgrade_result = (try {
        if not ($rollback | is-empty) {
            if not ($rollback =~ '^[a-f0-9-]{36}$') { error make { msg: "Invalid upgrade ID." } }
            let dir = ($upgrades | path join $rollback)
            let saved = (open --raw ($dir | path join "upgrade.nuon") | from nuon)
            if not ($saved.status in ["applied" "rollback-needed"]) { error make {msg: "This upgrade has not been applied or is already rolled back."} }
            if ($saved.target | path expand) != ($ROOT | path expand) { error make { msg: "Upgrade belongs to another checkout." } }
            if not $yes { error make { msg: "Use --yes to explicitly restore the selected release. Configuration files are not migrated backward." } }
            if $saved.kind == "git" {
                if (git ["rev-parse" "HEAD"] "Read HEAD") != $saved.to_commit { error make { msg: "Git HEAD has changed since that update; refusing rollback." } }
                git ["reset" "--keep" $saved.from_commit] "Restore previous Git commit without discarding local edits" | ignore
            } else { rollback-files $ROOT ($dir | path join "previous") ($dir | path join "candidate") }
            atomic-record ($dir | path join "upgrade.nuon") ($saved | upsert status "rolled-back")
            lock-release $lock
            print "[ok] Previous tools restored. Machine/private configuration was not changed."
            return
        }
        if not ($from | is-empty) and not ($ref | is-empty) { error make { msg: "Choose --from or --ref, not both." } }
        let old = (verify-release $ROOT "")
        let is_git = (($ROOT | path join ".git") | path exists)
        if $is_git and ($ref | is-empty) { error make { msg: "Use --ref and --commit for a Git checkout; artifact promotion never rewrites .git." } }
        if not $is_git and not ($ref | is-empty) { error make { msg: "Git update requires an existing checkout with a configured origin." } }
        let id = (random uuid)
        let dir = ($upgrades | path join $id)
        private-directory $dir
        let candidate = ($dir | path join "candidate")
        mut from_commit = ""
        mut to_commit = ""
        if $is_git {
            if not ($ref =~ '^[a-zA-Z0-9][a-zA-Z0-9._/-]*$') or not ($commit =~ '^[a-fA-F0-9]{40}$') { error make { msg: "Supply a safe ref name and a trusted full 40-character Git commit." } }
            if not ((git ["status" "--porcelain"] "Check worktree") | is-empty) { error make { msg: "Working tree is dirty. Commit or stash edits before upgrading." } }
            $from_commit = (git ["rev-parse" "HEAD"] "Read current commit")
            git ["fetch" "--no-tags" "origin" $ref] "Fetch candidate ref" | ignore
            $to_commit = (git ["rev-parse" "FETCH_HEAD^{commit}"] "Read fetched commit")
            if $to_commit != ($commit | text-lower) { error make { msg: "Fetched commit does not match the trusted pin." } }
            git ["merge-base" "--is-ancestor" $from_commit $to_commit] "Require fast-forward ancestry" | ignore
            let checkout = ($dir | path join "checkout")
            git ["worktree" "add" "--detach" ($checkout | into string) $to_commit] "Stage pinned checkout" | ignore
            try {
                copy-release $checkout $candidate
                git ["worktree" "remove" "--force" ($checkout | into string)] "Remove staging worktree" | ignore
            } catch {|err|
                git ["worktree" "remove" "--force" ($checkout | into string)] "Remove failed staging worktree" | ignore
                error make { msg: (error-message $err "Failed to clean staged Git worktree.") }
            }
        } else {
            if ($manifest_sha256 | is-empty) { error make { msg: "Provide a manifest digest from a trusted channel, not from the candidate itself." } }
            let source = ($from | path expand)
            disjoint-paths $ROOT $source
            disjoint-paths $dir $source
            verify-release $source $manifest_sha256 | ignore
            copy-release $source $candidate
        }
        let new = (verify-release $candidate (if $is_git { "" } else { $manifest_sha256 }))
        let old_patch = ($old.version | split row "." | last | into int)
        let new_patch = ($new.version | split row "." | last | into int)
        if $new_patch <= $old_patch { error make { msg: "Use the rollback command for downgrades; normal updates must increase the 0.12.* patch version." } }
        $record_file = ($dir | path join "upgrade.nuon" | into string)
        $record = {version: 1 id: $id kind: (if $is_git {"git"} else {"artifact"}) target: ($ROOT | into string) status: "staged" from_version: $old.version to_version: $new.version from_commit: $from_commit to_commit: $to_commit}
        atomic-record $record_file $record
        validate-candidate $candidate $dir
        verify-release $candidate (if $is_git {""} else {$manifest_sha256}) | ignore
        print ("[validated] " + $old.version + " -> " + $new.version)
        if not $yes {
            atomic-record $record_file ($record | upsert status "validated-not-applied")
            print "[preview] Installed files are unchanged. Repeat with --yes to promote."
            lock-release $lock
            return
        }
        verify-release $ROOT "" | ignore
        copy-release $ROOT ($dir | path join "previous")
        atomic-record $record_file ($record | upsert status "promoting")
        if $is_git {
            if (git ["rev-parse" "HEAD"] "Recheck HEAD") != $from_commit or not ((git ["status" "--porcelain"] "Recheck worktree") | is-empty) { error make { msg: "Checkout changed during candidate validation." } }
            $promoting = true
            git ["merge" "--ff-only" $to_commit] "Promote validated Git commit" | ignore
        } else {
            $promoting = true
            promote-files $ROOT $candidate $old $new
        }
        verify-release $ROOT "" | ignore
        atomic-record $record_file ($record | upsert status "applied")
        $promoting = false
        lock-release $lock
        print ("[ok] Installed " + $new.version + ". Rollback ID: " + $id)
        null
    } catch {|err| failure-envelope $err })
    let upgrade_failure = (captured-failure $upgrade_result)
    if $upgrade_failure != null {
        let err = $upgrade_failure
        let recovery_record = $record
        let recovery_file = $record_file
        let recovery_result = (try {
        if $promoting {
            let dir = ($recovery_file | path dirname)
            try {
                if $recovery_record.kind == "git" {
                    let now = (git ["rev-parse" "HEAD"] "Read fallback HEAD")
                    if not ($now in [$recovery_record.from_commit $recovery_record.to_commit]) { error make {msg: "Another Git writer changed HEAD; automatic fallback was stopped."} }
                    git ["reset" "--keep" $recovery_record.from_commit] "Fallback to previous Git commit" | ignore
                } else { rollback-files $ROOT ($dir | path join "previous") ($dir | path join "candidate") }
                atomic-record $recovery_file ($recovery_record | upsert status "rolled-back-after-failure")
            } catch {
                atomic-record $recovery_file ($recovery_record | upsert status "rollback-needed")
                print ("[recovery] Previous tools remain in: " + ($dir | into string))
            }
        } else if not ($recovery_file | is-empty) {
            atomic-record $recovery_file ($recovery_record | upsert status "rejected")
        }
        null
        } catch {|recovery_err| failure-envelope $recovery_err })
        let recovery_failure = (captured-failure $recovery_result)
        let cleanup_result = (try { lock-release $lock; null } catch {|cleanup_err| failure-envelope $cleanup_err })
        let cleanup_failure = (captured-failure $cleanup_result)
        if $recovery_failure != null {
            print ("[recovery] Fallback/status recording also failed: " + (error-message $recovery_failure "unknown recovery failure"))
        }
        if $cleanup_failure != null {
            print ("[recovery] Lock cleanup also failed: " + (error-message $cleanup_failure "unknown lock cleanup failure"))
        }
        error make { msg: (error-message $err "Upgrade failed.") }
    }
}
