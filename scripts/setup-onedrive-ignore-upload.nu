#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    open $file
}

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
    let result = (
        do { ^$shell ...$resolved_args }
        | complete
    )

    let exit_code = $result.exit_code

    if not (($result.stdout? | default "") | is-empty) {
        print $result.stdout
    }

    if not (($result.stderr? | default "") | is-empty) {
        print $result.stderr
    }

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
            error make {
                msg: ("OneDrive policy helper failed with exit code " + ($exit_code | into string))
            }
        }
    }
}
