#!/usr/bin/env nu

const POLICY_MODULE = path self ./modules/setup-policy.nu
const CORE = path self ./modules/core.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
const SUBPROCESS = path self ./modules/subprocess.nu
const CONSOLE = path self ./modules/console.nu
use $POLICY_MODULE [local-config-exists private-config-exists]
use $CORE [machine-context]
use $INSTALL_UTILS [probe-tool]
use $SUBPROCESS [run-command command-failure-message]
use $CONSOLE [print-heading print-info print-diff-text]

def main [--diff] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    print-heading "Initial-setup preflight"
    print "────────────────────────────────────────────────────────────"
    print ("Machine       : " + $context.machine.name)
    print ("Profile       : " + $context.machine.profile)
    print ("Private data  : " + ($data_root | into string))
    print ("Local config  : " + (if (local-config-exists) { "detected" } else { "not detected" }))
    print ("Private config: " + (if (private-config-exists $data_root) { "detected" } else { "not detected" }))
    print ""

    let chezmoi = (probe-tool "chezmoi" ["--version"])
    if not $chezmoi.healthy {
        let detail = if $chezmoi.found {
            $chezmoi.result.diagnostic? | default "chezmoi health probe failed"
        } else {
            "chezmoi executable was not found"
        }
        error make {msg: ("Preflight requires a healthy chezmoi executable. " + $detail)}
    }

    let data_root_ok = if ($data_root | path exists) { ($data_root | path type) == "dir" } else { false }
    if not $data_root_ok {
        error make {msg: ("Private data root is unavailable: " + ($data_root | into string))}
    }

    print ("chezmoi       : " + $chezmoi.version + " | " + $chezmoi.path)
    print ""
    print "chezmoi status:"
    let status_args = [
        "--source"
        ($data_root | into string)
        "status"
    ]
    let status = (run-command $chezmoi.path $status_args --live)
    if not $status.ok {
        error make {msg: (command-failure-message "chezmoi status" $status)}
    }

    if $diff {
        print ""
        print "chezmoi diff:"
        let diff_args = [
            "--source"
            ($data_root | into string)
            "--no-pager" "--use-builtin-diff" "diff"
        ]
        let diff_result = (run-command $chezmoi.path $diff_args)
        if not $diff_result.ok {
            error make {msg: (command-failure-message "chezmoi diff" $diff_result)}
        }
        let diff_text = ($diff_result.stdout | str trim --right)
        if ($diff_text | is-empty) { print-info "No managed-file differences." } else { print-diff-text $diff_text }
    } else {
        print ""
        print "Use `dotpreflight --diff` to show the full managed-file diff."
    }
}
