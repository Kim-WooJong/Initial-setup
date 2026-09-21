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
const SUBPROCESS_MODULE = path self ./scripts/modules/subprocess.nu
const NUSHELL_CONFIG_MODULE = path self ./scripts/nushell-config-dir.nu

use $SUBPROCESS_MODULE [run-command command-failure-message]
use $NUSHELL_CONFIG_MODULE [ensure-nushell-config-dir]

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
    let exe = ($nu.current-exe | into string)
    let child_args = (["--no-config-file" ($script | into string)] | append $args)
    let result = (run-command $exe $child_args --live)
    if not $result.ok {
        error make {msg: (command-failure-message ("Nushell child script " + ($script | into string)) $result)}
    }
}

# Interactive orchestrators must own the terminal directly. Capturing the whole
# process hides Nushell `input` prompts behind tee/complete pipelines.
def interactive-child [script: path args: list] {
    if not ($script | path exists) or ($script | path type) != "file" {
        error make {msg: ("INCOMPLETE_RELEASE: missing " + ($script | into string) + "\nExtract the complete project into a new directory.")}
    }
    let exe = ($nu.current-exe | into string)
    print ("[setup] Transferring interactive terminal to " + ($script | path basename))
    exec $exe --no-config-file $script ...$args
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
    let bash_exe = ($bash | first | get path | into string)
    print "[setup] Transferring interactive terminal to bootstrap.sh"
    exec $bash_exe $bootstrap ...$args
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
    let shell_exe = ($shell | into string)
    print "[setup] Transferring interactive terminal to bootstrap.ps1"
    exec $shell_exe ...$args
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

    # setup autoload directories and XDG_CONFIG_HOME on Windows. This is a one-time setup step that
    # may require a relaunch of the shell to take effect. If the config directory is already set up, this will be a no-op.
    let config_state = (ensure-nushell-config-dir)

    if $config_state.relaunch_required {
        print ''
        print '[nushell] XDG_CONFIG_HOME was changed.'
        print '[nushell] Restarting Nushell so the new config directory is active...'
        print ''

        $env.XDG_CONFIG_HOME = $config_state.xdg_config_home

        # 여기서는 현재 setup.nu가 setup-main.nu에 전달하려던
        # 동일한 arguments를 다시 setup.nu에 전달해야 합니다.
        let setup_script = ($ROOT | path join "setup.nu")
        exec $nu.current-exe --no-config-file $setup_script ...$args
    }

    # Preserve the original direct setup behavior once the host is ready. Do not
    # force an online Nushell update merely because setup was invoked.
    interactive-child ($ROOT | path join "setup-main.nu") $args
}
