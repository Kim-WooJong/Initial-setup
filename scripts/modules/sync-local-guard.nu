# Prevent manual pulls from silently replacing live configuration that changed
# after the last successful synchronization baseline.
const ROOT = path self ../..
const CORE = path self ./core.nu
const SUBPROCESS = path self ./subprocess.nu
const CONSOLE = path self ./console.nu
use $CORE [nu-home]
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-info print-warn print-diff-text]

def state-file [] {
    let scope = ($env.INITIAL_SETUP_PROVIDER_STATE_SCOPE? | default "" | str trim)
    if ($scope | is-empty) {
        return ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    }
    if not ($scope =~ '^[a-f0-9]{64}$') { error make {msg: "Invalid sync-state scope."} }
    (nu-home) | path join ".config" "dotfiles" "sync-states" ("sync-state-" + $scope + ".nuon")
}

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

export def guard-pull-local [source_root: path --discard-local] {
    let current = (local-fingerprint)
    let file = (state-file)
    if not ($file | path exists) {
        print-info "No local sync baseline exists yet; local-change protection cannot compare this first pull."
        return {baseline_missing: true changed: false local_hash: $current}
    }

    let state = (open $file)
    let baseline = ($state.local_hash? | default "" | str trim)
    if not ($baseline =~ '^[a-f0-9]{64}$') {
        print-warn "The saved local sync baseline is invalid; refusing to assume the live configuration is safe to replace."
        show-incoming-diff $source_root
        if not $discard_local {
            error make {msg: "Local pull blocked because the saved local baseline is invalid. Review the diff, run dotpush if the local state should win, or rerun dotpull --discard-local to explicitly replace local changes."}
        }
        return {baseline_missing: false changed: true local_hash: $current}
    }

    let changed = ($current != $baseline)
    if not $changed {
        return {baseline_missing: false changed: false local_hash: $current}
    }

    print-warn "Local configuration changed after the last successful sync. A normal dotpull will not overwrite it."
    show-incoming-diff $source_root

    if not $discard_local {
        error make {
            msg: "Local pull blocked to prevent rollback of recent edits. Review the diff, run dotpush if the local state should win, or rerun dotpull --discard-local to explicitly replace the local changes. A verified pre-pull backup is still created before any permitted apply."
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
