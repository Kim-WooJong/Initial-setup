# ============================================================
# Initial-setup Nushell convenience commands.
# ============================================================

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
    let config_file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    if not ($config_file | path exists) {
        error make {
            msg: ("Dotfiles machine config not found: " + ($config_file | into string))
        }
    }

    open $config_file
}

def data-root [] {
    let config = (machine-context)
    $config.data_root | path expand
}

def tools-root [] {
    let config = (machine-context)
    $config.tools_root | path expand
}

def tool-script [name: string] {
    let script = (tools-root | path join "scripts" $name)
    if not ($script | path exists) or ($script | path type) != "file" {
        error make {msg: ("TOOL_SCRIPT_MISSING: " + ($script | into string) + "\nThe checkout may have moved or the archive may be incomplete. Run scripts/refresh-commands.nu from the new complete checkout; do not rerun setup just to repair this path.")}
    }
    $script
}

def fingerprint [kind: string] {
    let script = (tool-script "sync-fingerprint.nu")
    let args = [
        $script
        "--kind"
        $kind
    ]

    ^$nu.current-exe --no-config-file ...$args | str trim
}

def edit-file [target: path] {
    mkdir ($target | path dirname)

    if not ($target | path exists) {
        "" | save $target
    }

    ^nvim $target
}

# This module is copied into the local Nushell configuration by setup/refresh.
# Put the implementation in a checkout script so later bug fixes are not frozen
# in the copied command module. Default editing never publishes implicitly.
def edit-managed-target [target: path --push --path] {
    if $path { return ($target | path expand --no-symlink) }
    let script = (tool-script "edit-managed.nu")
    if not ($script | path exists) {
        error make {msg: "edit-managed.nu is missing from tools_root. Run scripts/refresh-commands.nu from the updated checkout and restart Nushell."}
    }
    let exe = $nu.current-exe
    mut args = ["--no-config-file" $script ($target | into string)]
    if $push { $args = ($args | append "--push") }
    ^$exe ...$args
    let code = ($env.LAST_EXIT_CODE | default 1)
    if $code != 0 { error make {msg: "Managed editor command did not complete; see the preceding diagnostic. Any local edit is preserved."} }
}

export def dotstatus [] {
    let context = (machine-context)
    let state_file = ((nu-home) | path join ".config" "dotfiles" "sync-state.nuon")
    let conflict_file = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")

    print "Automatic Sync"
    print "────────────────────────────────"
    print ("Machine       : " + $context.machine.name)
    print ("Profile       : " + $context.machine.profile)
    print ("Enabled       : " + ($context.sync.enabled | into string))
    print ("Interval      : " + ($context.sync.interval_minutes | into string) + " minute(s)")
    print ("Auto push     : " + ($context.sync.auto_push | into string))
    print ("Auto pull     : " + ($context.sync.auto_pull | into string))
    print ("Conflict mode : " + $context.sync.conflict_policy)

    if ($state_file | path exists) {
        let state = (open $state_file)
        let local_now = (fingerprint "local")
        let cloud_now = (fingerprint "cloud")
        let local_status = (if $local_now == $state.local_hash { "clean" } else { "changed" })
        let cloud_status = (if $cloud_now == $state.cloud_hash { "clean" } else { "changed" })

        print ("Last sync     : " + ($state.last_sync? | default "unknown"))
        print ("Last writer   : " + ($state.last_writer? | default "unknown"))
        print ("Writer time   : " + ($state.last_write_time? | default "unknown"))
        print ("Last action   : " + ($state.last_action? | default "unknown"))
        print ("Local         : " + $local_status)
        print ("Cloud         : " + $cloud_status)
    } else {
        print "Last sync     : not initialized"
        print "Last writer   : unknown"
        print "Local         : unknown"
        print "Cloud         : unknown"
    }

    if ($conflict_file | path exists) {
        print "Conflict      : YES"
        print ("Details       : " + ($conflict_file | into string))
    } else {
        print "Conflict      : none"
    }

    print ""
    print ("Private data  : " + (data-root | into string))
    print ""
    print "chezmoi status:"

    let args = [
        "--source"
        (data-root | into string)
        "status"
    ]

    ^chezmoi ...$args
}

export def dotdiff [] {
    let root = (data-root)

    let args = [
        "--source"
        ($root | into string)
        "diff"
    ]

    ^chezmoi ...$args
}

export def dotpush [] {
    let exe = $nu.current-exe
    ^$exe --no-config-file (tool-script "sync-up.nu")
}

export def dotpull [
    --prune
    --force
    --backup
    --source-only
    --discard-source
] {
    let script = (tool-script "sync-down.nu")

    if $backup {
        ^$nu.current-exe --no-config-file (tool-script "backup-local-config.nu") --label "before-private-pull"

        let backup_exit = ($env.LAST_EXIT_CODE | default 0)
        if $backup_exit != 0 {
            error make { msg: "Local backup failed; private pull was not started." }
        }
    }

    mut args = [$script]

    if $prune {
        $args = ($args | append "--prune")
    }
    if $source_only { $args = ($args | append "--source-only") }
    if $discard_source { $args = ($args | append "--discard-source") }

    if $force or $backup {
        $args = ($args | append "--force")
    }

    ^$nu.current-exe --no-config-file ...$args
}

export def dotresolve [--policy] {
    let script = (tool-script "resolve-config.nu")
    if $policy {
        ^$nu.current-exe --no-config-file $script --policy
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

export def dotsync [] {
    ^$nu.current-exe --no-config-file (tool-script "auto-sync.nu")
}

export def dotsnapshot [
    --label: string = "manual"
] {
    let args = [
        (tool-script "create-snapshot.nu")
        "--label"
        $label
    ]

    ^$nu.current-exe --no-config-file ...$args
}

export def dotrollback [
    --list
    --snapshot: string = ""
] {
    let script = (tool-script "rollback.nu")

    if $list {
        ^$nu.current-exe --no-config-file $script --list
        return
    }

    if ($snapshot | is-empty) {
        ^$nu.current-exe --no-config-file $script
    } else {
        ^$nu.current-exe --no-config-file $script --snapshot $snapshot
    }
}

export def dotversion [] {
    ^$nu.current-exe --no-config-file (tool-script "version-info.nu")
}

export def dotrepo [] {
    ^$nu.current-exe --no-config-file (tool-script "repo-status.nu")
}

export def dotrelease [
    mode: string
    requested: string = ""
    --push
    --no-tag
] {
    let script = (tool-script "release.nu")
    mut args = [$script $mode]

    if not ($requested | is-empty) {
        $args = ($args | append $requested)
    }

    if $push {
        $args = ($args | append "--push")
    }

    if $no_tag {
        $args = ($args | append "--no-tag")
    }

    ^$nu.current-exe --no-config-file ...$args
}

export def dotcleanup [
    --force
] {
    let script = (tool-script "cleanup-direnv.nu")

    if $force {
        ^$nu.current-exe --no-config-file $script --force
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

export def dotaudit [] {
    ^$nu.current-exe --no-config-file (tool-script "audit.nu")
}

export def dotstate [] {
    ^$nu.current-exe --no-config-file (tool-script "capture-tool-state.nu")
}

export def dotmigrate [--check] {
    let script = (tool-script "migrate-config.nu")

    if $check {
        ^$nu.current-exe --no-config-file $script --check
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

export def dotchecklist [] {
    ^$nu.current-exe --no-config-file (tool-script "post-setup-checklist.nu")
}

export def dotcapture [] {
    ^$nu.current-exe --no-config-file (tool-script "capture-tool-state.nu")
    if ($env.LAST_EXIT_CODE | default 1) != 0 {
        error make {msg: "CAPTURE_FAILED: synchronization was not started; review the capture error above."}
    }
    ^$nu.current-exe --no-config-file (tool-script "sync-up.nu")
    if ($env.LAST_EXIT_CODE | default 1) != 0 {
        error make {msg: "CAPTURE_SYNC_FAILED: local capture remains, but synchronization did not complete."}
    }
}

export def dotrestoreenv [] {
    ^$nu.current-exe --no-config-file (tool-script "restore-work-environment.nu")
}

export def dotdoctor [
    --fix
] {
    let script = (tool-script "doctor.nu")

    if $fix {
        ^$nu.current-exe --no-config-file $script --fix
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

export def dotupdate [
    --repo
    --tools
    --config
    --all
] {
    let script = (tool-script "update.nu")
    mut args = [$script]

    if $repo {
        $args = ($args | append "--repo")
    }

    if $tools {
        $args = ($args | append "--tools")
    }

    if $config {
        $args = ($args | append "--config")
    }

    if $all {
        $args = ($args | append "--all")
    }

    ^$nu.current-exe --no-config-file ...$args
}

export def dotreport [
    --save
] {
    let script = (tool-script "report.nu")

    if $save {
        ^$nu.current-exe --no-config-file $script --save
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

export def dotlog [
    --lines: int = 50
    --clear
] {
    let file = ((nu-home) | path join ".config" "dotfiles" "logs" "sync.log")

    if $clear {
        if ($file | path exists) {
            "" | save --force $file
        }

        print "[ok] Sync log cleared"
        return
    }

    if not ($file | path exists) {
        print "No sync log."
        return
    }

    let content = (open --raw $file | lines)
    let count = ($content | length)
    let start = (if $count > $lines { $count - $lines } else { 0 })

    $content
    | skip $start
    | str join (char nl)
    | print
}

export def dotconfig [] {
    edit-file ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    print ""
    print "[info] Run `nu setup.nu` after changing profile, scheduler interval, or feature switches."
}

export def dotonedrive [
    --apply
] {
    let script = (tool-script "setup-onedrive-ignore-upload.nu")

    if $apply {
        ^$nu.current-exe --no-config-file $script
    } else {
        ^$nu.current-exe --no-config-file $script --check
    }
}

export def dotrclone [
    --capture
    --restore
] {
    if $capture and $restore {
        error make { msg: "Use either --capture or --restore, not both." }
    }

    if $capture {
        ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") capture rclone
        return
    }

    if $restore {
        ^$nu.current-exe --no-config-file (tool-script "secret-vault.nu") restore rclone
        return
    }

    if (which rclone | is-empty) {
        print "rclone: not installed"
        return
    }

    print "Local rclone config:"
    ^rclone config file
    print ""
    print ("Encrypted copy: " + ((data-root) | path join "secrets" "rclone.age" | into string))
}

export def dotlocal [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "local.nu")

    if not ($file | path exists) {
        ^$nu.current-exe --no-config-file (tool-script "setup-machine-local.nu")
    }

    edit-file $file
}

export def dotsecrets [] {
    edit-file ($nu.data-dir | path join "vendor" "autoload" "dotfiles-secrets.nu")
}

export def dotgitids [
    --edit
    --apply
] {
    let script = (tool-script "setup-git-identities.nu")

    if $edit {
        if $apply {
            ^$nu.current-exe --no-config-file $script --edit --apply
        } else {
            ^$nu.current-exe --no-config-file $script --edit
        }
        return
    }

    if $apply {
        ^$nu.current-exe --no-config-file $script --apply
    } else {
        ^$nu.current-exe --no-config-file $script --check
    }
}

export def dotsshkeys [
    --generate
] {
    let script = (tool-script "setup-ssh-keys.nu")

    if $generate {
        ^$nu.current-exe --no-config-file $script --generate
    } else {
        ^$nu.current-exe --no-config-file $script --check
    }
}

export def dotgitlocal [] {
    edit-file ((nu-home) | path join ".gitconfig.local")
}

export def dotsshlocal [] {
    edit-file ((nu-home) | path join ".ssh" "config.local")
}

export def dotnvim [--push --path] {
    edit-managed-target ((nu-home) | path join ".config" "nvim") --push=$push --path=$path
}

export def dotnu [--push --path] {
    edit-managed-target ((nu-home) | path join ".config" "nushell" "config.nu") --push=$push --path=$path
}

export def dotenv [--push --path] {
    edit-managed-target ((nu-home) | path join ".config" "nushell" "env.nu") --push=$push --path=$path
}

export def dotwezterm [--push --path] {
    edit-managed-target ((nu-home) | path join ".config" "wezterm" "wezterm.lua") --push=$push --path=$path
}

export def dotstarship [--push --path] {
    edit-managed-target ((nu-home) | path join ".config" "starship.toml") --push=$push --path=$path
}



export def dotrun [
    --list
    --status
    --logs
    --resume
    --rollback
    --run-id: string = ""
] {
    let script = (tool-script "run-control.nu")
    mut args = [$script]

    if $list { $args = ($args | append "--list") }
    if $status { $args = ($args | append "--status") }
    if $logs { $args = ($args | append "--logs") }
    if $resume { $args = ($args | append "--resume") }
    if $rollback { $args = ($args | append "--rollback") }
    if not ($run_id | is-empty) {
        $args = ($args | append "--run-id")
        $args = ($args | append $run_id)
    }

    ^$nu.current-exe --no-config-file ...$args
}

export def dotvalidate [] {
    ^$nu.current-exe --no-config-file (tool-script "validate-project.nu")
}

export def dottest [
    --sandbox
    --keep
] {
    let script = (tool-script "self-test.nu")
    mut args = [$script]

    if $sandbox {
        $args = ($args | append "--sandbox")
    }

    if $keep {
        $args = ($args | append "--keep")
    }

    ^$nu.current-exe --no-config-file ...$args
}

export def dotpreflight [
    --diff
] {
    let script = (tool-script "preflight.nu")

    if $diff {
        ^$nu.current-exe --no-config-file $script --diff
    } else {
        ^$nu.current-exe --no-config-file $script
    }
}

export def dotlocalbackup [
    --label: string = "manual"
] {
    let script = (tool-script "backup-local-config.nu")
    ^$nu.current-exe --no-config-file $script --label $label
}

export def dotlocalrestore [
    --list
    --backup: string = ""
    --force
] {
    let script = (tool-script "backup-local-config.nu")

    if $list {
        ^$nu.current-exe --no-config-file $script --list
        return
    }

    mut args = [$script]

    if ($backup | is-empty) {
        $args = ($args | append "--restore-latest")
    } else {
        $args = ($args | append "--restore")
        $args = ($args | append $backup)
    }

    if $force {
        $args = ($args | append "--force")
    }

    ^$nu.current-exe --no-config-file ...$args
}

export def newproj [
    kind: string
    name: string
    --path: string = ""
] {
    let args = [
        (tool-script "new-project.nu")
        $kind
        $name
        "--path"
        $path
    ]

    ^$nu.current-exe --no-config-file ...$args
}

export def dotdata [] {
    ^nvim (data-root)
}

export def dottools [] {
    ^nvim (tools-root)
}

export def dotplan [--direction: string = "none" --no-save] {
    let script = (tool-script "plan.nu")
    mut args = [$script "--direction" $direction]
    if $no_save { $args = ($args | append "--no-save") }
    ^$nu.current-exe --no-config-file ...$args
}

export def dotapply [--plan: string = "" --yes] {
    let script = (tool-script "apply-plan.nu")
    mut args = [$script]
    if not ($plan | is-empty) {
        $args = ($args | append "--plan")
        $args = ($args | append $plan)
    }
    if $yes { $args = ($args | append "--yes") }
    ^$nu.current-exe --no-config-file ...$args
}

export def dotverify [--plan: string = ""] {
    let script = (tool-script "verify-plan.nu")
    if ($plan | is-empty) { ^$nu.current-exe --no-config-file $script } else { ^$nu.current-exe --no-config-file $script --plan $plan }
}

export def dottoolchain [--status --apply --lock-current] {
    let script = (tool-script "toolchain-state.nu")
    if $lock_current { ^$nu.current-exe --no-config-file $script --lock-current } else if $apply { ^$nu.current-exe --no-config-file $script --apply } else { ^$nu.current-exe --no-config-file $script --status }
}

export def dotmergecfg [--check --force] {
    let script = (tool-script "setup-merge-tool.nu")
    if $check { ^$nu.current-exe --no-config-file $script --check } else if $force { ^$nu.current-exe --no-config-file $script --force } else { ^$nu.current-exe --no-config-file $script }
}

# Arguments are forwarded as a list; no shell expansion/evaluation is used.
export def --wrapped dotvault [...args: string] { let exe = $nu.current-exe; ^$exe --no-config-file (tool-script "secret-vault.nu") ...$args }
export def --wrapped dotbackend [...args: string] { let exe = $nu.current-exe; ^$exe --no-config-file (tool-script "backend-control.nu") ...$args }
export def --wrapped dotupgrade [...args: string] { ^$nu.current-exe --no-config-file (tool-script "safe-upgrade.nu") ...$args }

export def --wrapped dotsecuritytest [...args: string] { ^$nu.current-exe --no-config-file (tool-script "security-self-test.nu") ...$args }

# Verify/update the managed runtime without synchronizing settings.
export def dotnuupdate [--check --shell] {
    if $check and $shell { error make {msg: "Choose --check or --shell."} }
    let exe = $nu.current-exe
    let script = (tool-script "update-nushell.nu")
    if $check { ^$exe --no-config-file $script --check } else if $shell { ^$exe --no-config-file $script --shell } else { ^$exe --no-config-file $script }
}

# Explicit cloud-mirror -> local-workspace import. Native Nu records on success.
export def --wrapped dotcloud [action: string = "help" ...args: string] {
    let exe = $nu.current-exe
    let script = (tool-script "cloud-wins.nu")
    if $action == "help" or "--help" in $args {
        ^$exe --no-config-file $script $action ...$args
        return
    }
    let result = (do { ^$exe --no-config-file $script $action ...$args } | complete)
    let diagnostic = (try { $result.stderr | into string } catch { "Unable to decode child diagnostic." })
    if not ($diagnostic | is-empty) { print --stderr $diagnostic }
    if $result.exit_code != 0 { error make {msg: "dotcloud failed; see the preceding diagnostic. No success is assumed."} }
    $result.stdout | into string | from json
}
