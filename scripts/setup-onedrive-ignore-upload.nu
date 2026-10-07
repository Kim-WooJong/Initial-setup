#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command command-failure-message print-result]

def powershell-command [] {
    if not (which pwsh | is-empty) { return "pwsh" }
    if not (which powershell | is-empty) { return "powershell" }
    ""
}

def main [--check] {
    if $nu.os-info.name != "windows" {
        print "[skip] OneDrive upload exclusion policy is Windows-only"
        return
    }

    let context = (machine-context)

    if not ($context.features.onedrive_ignore_uploads? | default false) {
        print "[skip] OneDrive upload exclusion policy disabled"
        return
    }

    let shell = (powershell-command)

    if ($shell | is-empty) {
        print "[warn] PowerShell not found; OneDrive policy was not checked"
        return
    }

    let helper = ($TOOLS_ROOT | path join "scripts" "windows" "set-onedrive-ignore-upload-policy.ps1")
    let patterns = ($TOOLS_ROOT | path join "defaults" "onedrive-ignore-upload-patterns.txt")

    let base_args = [
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        ($helper | into string)
        "-PatternsFile"
        ($patterns | into string)
    ]

    let args = if $check {
        $base_args | append "-CheckOnly"
    } else {
        $base_args
    }

    let resolved_args = $args
    let result = (run-command $shell $resolved_args)
    let exit_code = ($result.exit_code? | default 1)
    print-result "OneDrive upload exclusion policy" $result

    match $exit_code {
        0 => {
            return
        }

        10 => {
            print "[--] OneDrive upload exclusion policy is not fully applied"
            return
        }

        11 => {
            print "[warn] OneDrive exclusions require an elevated Windows terminal"
            print "[info] Re-run `nu scripts/setup-onedrive-ignore-upload.nu` as Administrator"
            return
        }

        _ => {
            error make { msg: (command-failure-message "OneDrive policy helper" $result) }
        }
    }
}
