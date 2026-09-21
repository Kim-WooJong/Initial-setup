#!/usr/bin/env nu
const ROOT = path self ..
const RECONCILE = path self ./modules/setup-reconcile.nu
const PROVIDER = path self ./modules/sync-provider.nu
const SAFETY = path self ./modules/safety.nu
const SUBPROCESS = path self ./modules/subprocess.nu
use $RECONCILE [setup-head-changed choose-changed-source preserve-reviewed-source]
use $PROVIDER [provider-head record-provider-state load-provider-state assert-expected-head provider-state-path workspace-manifest]
use $SAFETY [state-root]
use $SUBPROCESS [run-command]

def check [ok: bool message: string] { if not $ok { error make {msg: $message} } }

def main [--interactive --choose: string = ""] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("setup-reconcile-test-" + (random uuid)))
    let home = ($base | path join "home")
    let source = ($base | path join "private")
    mkdir $home ($source | path join "home")
    $env.INITIAL_SETUP_TEST_MODE = "1"
    $env.INITIAL_SETUP_HOME_OVERRIDE = ($home | into string)
    $env.HOME = ($home | into string)
    $env.USERPROFILE = ($home | into string)
    $env.APPDATA = ($home | path join "AppData" "Roaming")
    $env.LOCALAPPDATA = ($home | path join "AppData" "Local")
    $env.XDG_CONFIG_HOME = ($home | path join ".config")
    $env.XDG_DATA_HOME = ($home | path join ".local" "share")
    $env.XDG_STATE_HOME = ($home | path join ".local" "state")
    $env.INITIAL_SETUP_PROVIDER_STATE_SCOPE = ""
    $env.INITIAL_SETUP_OPERATION_TOKEN = ""
    mkdir (state-root) $env.APPDATA $env.LOCALAPPDATA
    {data_root: $source tools_root: ($ROOT | into string) maintenance: {snapshots_enabled: false snapshot_keep: 1}} | to nuon | save ((state-root) | path join "config.nuon")
    "local configuration" | save ($home | path join ".gitconfig")
    "home" | save ($source | path join ".chezmoiroot")
    "old private configuration" | save ($source | path join "home" "dot_gitconfig")
    let config = {version: 1 kind: "directory" remote: "" data_root: $source}
    let original = (provider-head $config)
    record-provider-state $config $original
    let baseline = (open --raw (provider-state-path))
    check (not (setup-head-changed (load-provider-state $config) $original)) "Equal heads must not prompt"
    check (not (setup-head-changed null $original)) "First setup must retain its existing policy"
    "new private configuration" | save --force ($source | path join "home" "dot_gitconfig")
    let reviewed = (provider-head $config)
    let state = (load-provider-state $config)
    check (setup-head-changed $state $reviewed) "Changed source must be reviewed"
    check (try { assert-expected-head $config | ignore; false } catch { true }) "Background push must still reject a stale baseline"

    if not ($choose | is-empty) {
        let policy = (choose-changed-source $config $state $reviewed {|| print "[test] Review callback displayed; source unchanged." })
        check ($policy == $choose) "Menu returned the wrong synchronization policy"
        check ((open --raw (provider-state-path)) == $baseline) "Choosing must not acknowledge the baseline"
        print ("[pass] Interactive choice: " + $policy)
        return
    }
    if $interactive {
        # Exercise the real entrypoint with isolated state. Only cancel/Ctrl+C here.
        ^$nu.current-exe --no-config-file ($ROOT | path join "setup.nu") --data-dir $source
        let code = $env.LAST_EXIT_CODE
        check ($code in [0 130]) "Interactive cancel returned an unexpected status"
        check ((open --raw (provider-state-path)) == $baseline) "Cancel changed the baseline"
        check ((provider-head $config) == $reviewed) "Cancel changed private files"
        check ((open --raw ($home | path join ".gitconfig")) == "local configuration") "Cancel changed local files"
        check (not (((state-root) | path join "operation.lock") | path exists)) "Cancel leaked the operation lock"
        print ("[pass] Real setup cancellation, unchanged files/baseline, released lock; exit " + ($code | into string))
        return
    }
    let attempt = (run-command ($nu.current-exe | into string) ["--no-config-file" ($ROOT | path join "setup.nu" | into string) "--data-dir" ($source | into string)])
    check (not $attempt.ok) "Captured setup must not prompt or accept a stale head"
    check (($attempt.stderr + $attempt.stdout) | str contains "interactive terminal") "Captured setup must explain how to reconcile"
    check ((open --raw (provider-state-path)) == $baseline) "Rejected setup changed the baseline"
    let recovery = (preserve-reviewed-source $config $reviewed "fixture-run")
    check ((workspace-manifest $recovery) == (workspace-manifest $source)) "Recovery differs from reviewed source"
    check ((open --raw (provider-state-path)) == $baseline) "Recovery must not reset the baseline"
    check (($recovery | path join "reconciliation.nuon") | path exists) "Recovery metadata missing"
    "changed again" | save --force ($source | path join "home" "dot_gitconfig")
    check (try { preserve-reviewed-source $config $reviewed "fixture-run" | ignore; false } catch { true }) "A later source change must invalidate approval"
    check ((open --raw ($recovery | path join "home" "dot_gitconfig")) == "new private configuration") "Recovery copy was not retained"
    check ((open --raw (provider-state-path)) == $baseline) "Failed reconciliation changed the baseline"
    print "[pass] Setup reconciliation: captured input rejected, background guard retained, verified recovery with snapshots disabled, stale approval rejected."
    print ("[test] Isolated fixture retained at: " + ($base | into string))
}
