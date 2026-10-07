# Prevent manual pulls from silently replacing live configuration that changed
# after the last successful synchronization baseline.
const ROOT = path self ../..
const CORE = path self ./core.nu
const SUBPROCESS = path self ./subprocess.nu
const CONSOLE = path self ./console.nu
const SYNC_STATE = path self ./sync-state.nu
use $CORE [nu-home]
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-info print-warn print-diff-text print-choice print-text]
use $SYNC_STATE [sync-state-file read-sync-state]

def local-fingerprint [] {
    let script = ($ROOT | path join "scripts" "sync-fingerprint.nu")
    let result = (run-command $nu.current-exe ["--no-config-file" $script "--kind" "local"])
    if not $result.ok {
        error make {msg: (command-failure-message "Local sync fingerprint" $result)}
    }
    let value = ($result.stdout | str trim)
    if not ($value =~ '^[a-f0-9]{64}$') {
        error make {msg: "Local sync fingerprint returned an invalid value."}
    }
    $value
}

def show-incoming-diff [source_root: path] {
    let result = (run-command "chezmoi" [
        "--source" ($source_root | into string)
        "--no-pager" "--use-builtin-diff" "diff"
    ])
    if not $result.ok {
        print-warn ("Unable to render the incoming chezmoi diff: " + (command-failure-message "chezmoi diff" $result))
        return
    }
    let text = ($result.stdout | str trim --right)
    if ($text | is-empty) {
        print-info "No chezmoi-managed file diff was produced; the local fingerprint changed in another tracked component."
    } else {
        print-info "Incoming pull diff (private source -> current machine):"
        print-diff-text $text
    }
}


def confirm-private-authority [] {
    if not (is-terminal --stdin) or not (is-terminal --stderr) { return false }

    print --stderr ""
    print-text "warn" "dotctl pull is about to replace local changes with the private source." --stderr
    print-choice "y" "Keep the private source and replace the local changes" --stderr
    print-choice "N" "Cancel and keep the local changes" --stderr
    print-text "prompt" "Select [N]:" --stderr
    let choice = (input | str trim)
    $choice in ["y" "Y" "yes" "YES" "Yes"]
}

export def guard-pull-local [source_root: path --discard-local --interactive] {
    let current = (local-fingerprint)
    let file = (sync-state-file)
    if not ($file | path exists) {
        print-info "No local sync baseline exists yet; local-change protection cannot compare this first pull."
        return {baseline_missing: true changed: false local_hash: $current}
    }

    let state = (read-sync-state $file)
    let baseline = ($state.local_hash? | default "" | str trim)
    if not ($baseline =~ '^[a-f0-9]{64}$') {
        print-warn "The saved local sync baseline is invalid; refusing to assume the live configuration is safe to replace."
        show-incoming-diff $source_root
        if not $discard_local {
            error make {msg: "Local pull blocked because the saved local baseline is invalid. Review the diff, run `dotctl push` if the local state should win, or rerun `dotctl pull --discard-local` to explicitly replace local changes."}
        }
        return {baseline_missing: false changed: true local_hash: $current}
    }

    let changed = ($current != $baseline)
    if not $changed {
        return {baseline_missing: false changed: false local_hash: $current}
    }

    print-warn "Local configuration changed after the last successful sync. Review the incoming state before replacing it."
    show-incoming-diff $source_root

    if not $discard_local {
        if $interactive and (confirm-private-authority) {
            print-warn "Private-authoritative pull confirmed; the reviewed local changes may be replaced after the verified backup."
            return {baseline_missing: false changed: true local_hash: $current}
        }
        error make {
            msg: "Local pull cancelled to prevent rollback of recent edits. Review the diff and run `dotctl push` if the local state should win. To keep the private source, rerun `dotctl pull` and confirm the prompt, or use `dotctl pull --discard-local` for an explicit non-interactive replacement."
        }
    }

    print-warn "--discard-local was supplied; the reviewed local changes may be replaced by the private source."
    {baseline_missing: false changed: true local_hash: $current}
}

export def assert-local-unchanged [expected_hash: string] {
    let current = (local-fingerprint)
    if $current != $expected_hash {
        error make {msg: "Local configuration changed while the pull was being prepared. Nothing was applied; review the new local edits and retry."}
    }
}
