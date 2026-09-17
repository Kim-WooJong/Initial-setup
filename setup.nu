#!/usr/bin/env nu
# Canonical Initial-setup entry point.
# Run from the project root with: nu setup.nu
#
# A compatible, prepared machine goes directly to setup-main.nu.
# If the current Nushell or core native prerequisites are not ready, this file
# delegates once to the platform bootstrap, which prepares them and re-enters
# this same setup.nu entry point.

const ROOT = path self .
const MIN_RUNTIME = "0.109.1"

def version-at-least [actual: string required: string] {
    if not ($actual =~ '^[0-9]+\.[0-9]+\.[0-9]+$') { return false }
    if not ($required =~ '^[0-9]+\.[0-9]+\.[0-9]+$') { return false }
    let a = ($actual | split row "." | each {|x| $x | into int })
    let b = ($required | split row "." | each {|x| $x | into int })
    for i in [0 1 2] {
        if ($a | get $i) > ($b | get $i) { return true }
        if ($a | get $i) < ($b | get $i) { return false }
    }
    true
}

def has-command [name: string] {
    not (which $name | where type == "external" | is-empty)
}

def child [script: path args: list] {
    if not ($script | path exists) or ($script | path type) != "file" {
        error make {msg: ("INCOMPLETE_RELEASE: missing " + ($script | into string) + "\nExtract the complete project into a new directory.")}
    }
    let exe = $nu.current-exe
    ^$exe --no-config-file $script ...$args
    let code = ($env.LAST_EXIT_CODE | default 1)
    if $code != 0 { exit $code }
}

def common-args [mode: string data_dir: string profile: string config_policy: string run_id: string no_auto_sync: bool dry_run: bool resume: bool validate: bool] {
    mut args = ["--mode" $mode "--data-dir" $data_dir "--profile" $profile "--config-policy" $config_policy "--run-id" $run_id]
    if $no_auto_sync { $args = ($args | append "--no-auto-sync") }
    if $dry_run { $args = ($args | append "--dry-run") }
    if $resume { $args = ($args | append "--resume") }
    if $validate { $args = ($args | append "--validate") }
    $args
}

def native-ready [non_mutating: bool] {
    let runtime_ok = (version-at-least (version).version $MIN_RUNTIME)
    if not $runtime_ok { return false }
    if $non_mutating { return true }
    (has-command "git") and (has-command "chezmoi")
}

def bootstrap-posix [args: list] {
    let bootstrap = ($ROOT | path join "bootstrap.sh")
    if not ($bootstrap | path exists) { error make {msg: "INCOMPLETE_RELEASE: bootstrap.sh is missing."} }
    let bash = (which bash | where type == "external")
    if ($bash | is-empty) {
        error make {msg: "BOOTSTRAP_UNAVAILABLE: bash is required to run bootstrap.sh. Install bash, then run `bash bootstrap.sh`."}
    }
    let bash_exe = ($bash | first | get path)
    ^$bash_exe $bootstrap ...$args
    let code = ($env.LAST_EXIT_CODE | default 1)
    if $code != 0 { exit $code }
}

def bootstrap-windows [mode: string data_dir: string profile: string config_policy: string run_id: string no_auto_sync: bool dry_run: bool resume: bool validate: bool] {
    let bootstrap = ($ROOT | path join "bootstrap.ps1")
    if not ($bootstrap | path exists) { error make {msg: "INCOMPLETE_RELEASE: bootstrap.ps1 is missing."} }
    let candidates = (which pwsh | where type == "external")
    let shell = if ($candidates | is-empty) {
        let legacy = (which powershell.exe | where type == "external")
        if ($legacy | is-empty) { error make {msg: "BOOTSTRAP_UNAVAILABLE: PowerShell was not found."} }
        $legacy | first | get path
    } else { $candidates | first | get path }
    mut args = ["-NoProfile" "-ExecutionPolicy" "Bypass" "-File" ($bootstrap | into string) "-Mode" $mode "-ConfigPolicy" $config_policy]
    if not ($data_dir | is-empty) { $args = ($args | append ["-DataDir" $data_dir]) }
    if not ($profile | is-empty) { $args = ($args | append ["-Profile" $profile]) }
    if $no_auto_sync { $args = ($args | append "-NoAutoSync") }
    if $dry_run { $args = ($args | append "-DryRun") }
    if $resume { $args = ($args | append "-Resume") }
    if not ($run_id | is-empty) { $args = ($args | append ["-RunId" $run_id]) }
    if $validate { $args = ($args | append "-Validate") }
    ^$shell ...$args
    let code = ($env.LAST_EXIT_CODE | default 1)
    if $code != 0 { exit $code }
}

def main [
    --mode: string = "auto"
    --data-dir: string = ""
    --profile: string = ""
    --config-policy: string = "ask"
    --no-auto-sync
    --dry-run
    --resume
    --run-id: string = ""
    --validate
    --diagnose
    --check
] {
    if $diagnose and $check { error make {msg: "Choose --diagnose or --check."} }
    let preflight = ($ROOT | path join "scripts" "diagnose-project.nu")
    if $diagnose {
        child $preflight ["--root" ($ROOT | into string) "--manifest"]
        return
    }
    if $check {
        child ($ROOT | path join "verify.nu") []
        return
    }

    # Normal setup only blocks on files that are required to start safely.
    # Release-manifest drift is reviewed explicitly by --diagnose/--check instead
    # of forcing setup into a no-change mode before the user can review config diffs.
    child $preflight ["--root" ($ROOT | into string) "--quiet"]

    let args = (common-args $mode $data_dir $profile $config_policy $run_id $no_auto_sync $dry_run $resume $validate)
    let non_mutating = ($dry_run or $config_policy == "preview")
    if not (native-ready $non_mutating) {
        print --stderr ("[setup] Preparing prerequisites for `nu setup.nu` (Nu >= " + $MIN_RUNTIME + ", git, chezmoi).")
        if $nu.os-info.name == "windows" {
            bootstrap-windows $mode $data_dir $profile $config_policy $run_id $no_auto_sync $dry_run $resume $validate
        } else if $nu.os-info.name in ["linux" "macos"] {
            bootstrap-posix $args
        } else {
            error make {msg: ("Unsupported operating system: " + $nu.os-info.name)}
        }
        return
    }

    # Preserve the original direct setup behavior once the host is ready. Do not
    # force an online Nushell update merely because setup was invoked.
    child ($ROOT | path join "setup-main.nu") $args
}
