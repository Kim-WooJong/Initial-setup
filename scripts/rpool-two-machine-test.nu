#!/usr/bin/env nu
# Two-machine RPool sync e2e: sandbox HOMEs A and B share one directory-provider
# private source. Uses the real rpool (0.7+), age, age-keygen, chezmoi and
# rclone found on PATH; skips when any is missing. Synthetic passwords only.
# Covers: artifact publish, crypt-password-only change detection with
# rclone.conf sync disabled, B pull (crypt password + rpool settings + chezmoi).
const TOOLS = path self ..

def ok [c: bool m: string] {
    if not $c { error make {msg: ("[e2e] FAIL: " + $m)} }
    print $"[pass] ($m)"
}

def machine-env [sb: path name: string] {
    let home = ($sb | path join $name "home")
    {
        INITIAL_SETUP_TEST_MODE: "1"
        INITIAL_SETUP_HOME_OVERRIDE: $home
        HOME: $home
        USERPROFILE: $home
        XDG_CONFIG_HOME: ($home | path join ".config")
        XDG_DATA_HOME: ($home | path join ".local" "share")
        XDG_STATE_HOME: ($home | path join ".local" "state")
        XDG_CACHE_HOME: ($home | path join ".cache")
        RCLONE_CONFIG: ($sb | path join $name "rclone.conf")
        PATH: $env.PATH
    }
}

# Runs a script inside the machine env; returns complete record.
def on [sb: path name: string script: string ...args: string] {
    with-env (machine-env $sb $name) {
        do { ^$nu.current-exe --no-config-file ($TOOLS | path join "scripts" $script) ...$args } | complete
    }
}

def show [r: record label: string] {
    if $r.exit_code != 0 {
        print $"---- ($label) stdout"; print $r.stdout; print $"---- ($label) stderr"; print $r.stderr
    }
    $r
}

def rclone-conf [password: string token: string = "t1"] {
    $"[store]\ntype = local\n\n[gd]\ntype = drive\ntoken = {\"access_token\":\"($token)\"}\n\n[sec]\ntype = crypt\nremote = store:/tmp/rpool-e2e-data\npassword = ($password)\n"
}

def verify [sb: path name: string] { shim-call $sb $name "dotctl verify --json" }
def verify-ok [r: record] { $r.exit_code == 0 and (try { ($r.stdout | from json).ok } catch { false }) }

def obscure [plain: string] { ^rclone obscure $plain | str trim }

def setup-machine [sb: path name: string private: path identity_src: any rclone_sync: bool] {
    let env_rec = (machine-env $sb $name)
    let state = ($env_rec.HOME | path join ".config" "dotfiles")
    mkdir $state $env_rec.XDG_DATA_HOME $env_rec.XDG_STATE_HOME $env_rec.XDG_CACHE_HOME
    {
        app_version: "e2e"
        schema_version: 5
        data_root: ($private | into string)
        tools_root: ($TOOLS | into string)
        machine: { name: $name profile: "minimal" install_gui_apps: false }
        sync: { enabled: false interval_minutes: 1 auto_push: false auto_pull: false conflict_policy: "stop" stability_delay_seconds: 0 prune_extras: false }
        maintenance: { snapshots_enabled: false snapshot_keep: 2 log_keep_lines: 100 }
        features: { neovim: false fonts: false cli_tools: false vscode: false wezterm: false starship: false rust: false julia: false git_config: true ssh_config: false rclone_config: $rclone_sync onedrive_ignore_uploads: false }
    } | to nuon | save --force ($state | path join "config.nuon")
    if $name == "A" { $"# ($name) gitconfig\n" | save --force ($env_rec.HOME | path join ".gitconfig") }
    let r = (show (on $sb $name "refresh-commands.nu") $"($name) refresh-commands")
    if $r.exit_code != 0 { error make {msg: $"[e2e] ($name) command shim install failed"} }
    if $identity_src != null {
        mkdir ($state | path join "age")
        cp $identity_src ($state | path join "age" "identity.txt")
    }
}

def rpool-cfg-dir [sb: path name: string] {
    let home = ($sb | path join $name "home")
    if $nu.os-info.name == "macos" { $home | path join "Library" "Application Support" "rpool" } else { $home | path join ".config" "rpool" }
}

# The real user path: the installed command shim's dotpush/dotpull (no flags).
def shim-call [sb: path name: string command: string] {
    let shim = ($sb | path join $name "home" ".config" "nushell" "modules" "dotfiles.nu")
    with-env (machine-env $sb $name) {
        do { ^$nu.current-exe --no-config-file -c ("use " + ($shim | to nuon) + " *\n" + $command) } | complete
    }
}
def dotpush [sb: path name: string label: string] { show (shim-call $sb $name "dotpush") $label }
def dotpull [sb: path name: string label: string] { show (shim-call $sb $name "dotpull") $label }
def roots [sb: path name: string] { open --raw ((rpool-cfg-dir $sb $name) | path join "remote_roots.json") }

# rclone_sync=false: B already has the crypt remote (stale password) and only
# the rpool artifact carries the password. rclone_sync=true: B starts without
# any rclone.conf and receives it through the encrypted rclone vault entry.
def scenario [rclone_sync: bool keep: bool] {
    let tag = if $rclone_sync { "rclone-sync" } else { "rpool-only" }
    print $"== scenario ($tag)"
    let sb = (($env.TMPDIR? | default "/tmp") | path join ("rpool-two-machine-" + (random uuid)))
    let private = ($sb | path join "private")
    mkdir $sb $private
    let pw1 = (obscure "e2e-password-one")

    # ---- machine A ----
    setup-machine $sb "A" $private null $rclone_sync
    rclone-conf $pw1 | save --force ($sb | path join "A" "rclone.conf")
    let r = (show (on $sb "A" "init-private-data.nu") "A init-private-data")
    ok ($r.exit_code == 0) "A private source initialized"
    "# seeded gitconfig\n" | save --force ($private | path join "home" "dot_gitconfig")
    let r = (show (on $sb "A" "secret-vault.nu" "init") "A vault init")
    ok ($r.exit_code == 0) "A vault initialized"
    with-env (machine-env $sb "A") { ^rpool remote-root set store /tmp/rpool-e2e-data | complete | ignore }
    ok ((rpool-cfg-dir $sb "A") | path join "remote_roots.json" | path exists) "A has active rpool settings"

    let rev = (with-env (machine-env $sb "A") { use ($TOOLS | path join "scripts" "modules" "sync-provider.nu") [load-provider provider-head]; (provider-head (load-provider)).revision })
    let r = (show (on $sb "A" "backend-control.nu" "acknowledge" "--expected" $rev) "A acknowledge")
    ok ($r.exit_code == 0) "A baseline acknowledged"
    ok ((dotpush $sb "A" "A push 1").exit_code == 0) "A dotpush 1 succeeded"
    ok (($private | path join "rpool" "config" "portable-config.json") | path exists) "artifact config published"
    ok (($private | path join "rpool" "secrets" "rclone.age") | path exists) "crypt secrets published"
    if $rclone_sync { ok (($private | path join "secrets" "rclone.age") | path exists) "encrypted rclone.conf published" }
    let secret1 = (open --raw ($private | path join "rpool" "secrets" "rclone.age") | hash sha256)

    # ---- password-only change ----
    let fp_before = (on $sb "A" "sync-fingerprint.nu" "--kind" "local" | get stdout | str trim)
    let pw2 = (obscure "e2e-password-two")
    rclone-conf $pw2 | save --force ($sb | path join "A" "rclone.conf")
    let fp_after = (on $sb "A" "sync-fingerprint.nu" "--kind" "local" | get stdout | str trim)
    ok (($fp_before | str length) == 64 and $fp_before != $fp_after) "password-only change alters local fingerprint"
    let unpublished = (verify $sb "A")
    let report = (try { $unpublished.stdout | from json } catch { {} })
    ok ($unpublished.exit_code != 0 and ($report.rpool?.secrets? == "differ")) "dotctl verify reports unpublished crypt password change"
    if $rclone_sync { ok (($report.rclone?.changed? | default [] | where crypt | get name) == ["sec"]) "dotctl verify names the changed crypt remote" }
    ok ((dotpush $sb "A" "A push 2").exit_code == 0) "A dotpush 2 succeeded"
    ok ((open --raw ($private | path join "rpool" "secrets" "rclone.age") | hash sha256) != $secret1) "push 2 republished crypt secrets"
    let fp_again = (on $sb "A" "sync-fingerprint.nu" "--kind" "local" | get stdout | str trim)
    ok ($fp_again == $fp_after) "fingerprint stable without changes"

    # ---- machine B (fresh) dotpull ----
    let identity = ($sb | path join "A" "home" ".config" "dotfiles" "age" "identity.txt")
    setup-machine $sb "B" $private $identity $rclone_sync
    if not $rclone_sync { rclone-conf (obscure "b-stale-password") | save --force ($sb | path join "B" "rclone.conf") }
    let recipient = (^age-keygen -y $identity | str trim)
    let r = (show (on $sb "B" "secret-vault.nu" "init" "--recipient" $recipient) "B vault init")
    ok ($r.exit_code == 0) "B vault initialized with shared identity"
    ok ((dotpull $sb "B" "B pull").exit_code == 0) "B dotpull succeeded"
    let b_conf = (open --raw ($sb | path join "B" "rclone.conf"))
    ok ($b_conf | str contains $"password = ($pw2)") "B crypt password matches A"
    if $rclone_sync { ok ($b_conf | str contains "[store]") "B rclone.conf restored with all remotes" }
    ok ((roots $sb "B") == (roots $sb "A")) "B rpool settings equal A"
    ok ((open --raw ($sb | path join "B" "home" ".gitconfig")) | str contains "A gitconfig") "B chezmoi apply delivered A files"
    ok ((dotpull $sb "B" "B pull again").exit_code == 0) "B repeated dotpull is a no-op success"
    let bv = (verify $sb "B")
    if not (verify-ok $bv) { print $bv.stdout; print $bv.stderr }
    ok (verify-ok $bv) "dotctl verify on B reports rclone and rpool in sync"
    let human = (shim-call $sb "B" "dotctl verify")
    ok (not (($bv.stdout + $bv.stderr + $human.stdout + $human.stderr) | str contains $pw2)) "dotctl verify output contains no secret values"
    print ($human.stdout | ansi strip)

    # ---- reverse direction: B edits rpool + crypt password, A pulls ----
    with-env (machine-env $sb "B") { ^rpool remote-root set store /tmp/rpool-e2e-other | complete | ignore }
    let pw3 = (obscure "e2e-password-three")
    open --raw ($sb | path join "B" "rclone.conf") | str replace $"password = ($pw2)" $"password = ($pw3)" | save --force ($sb | path join "B" "rclone.conf")
    ok ((dotpush $sb "B" "B push").exit_code == 0) "B dotpush succeeded"
    ok ((dotpull $sb "A" "A pull").exit_code == 0) "A dotpull succeeded"
    ok ((roots $sb "A") | str contains "rpool-e2e-other") "A received B rpool settings"
    ok ((open --raw ($sb | path join "A" "rclone.conf")) | str contains $"password = ($pw3)") "A received B crypt password"
    ok ((dotpush $sb "A" "A push after pull").exit_code == 0) "A dotpush after pull has no conflict"
    ok (verify-ok (verify $sb "A")) "dotctl verify on A reports in sync after round trip"

    # Wrong key on B: identity no longer matches the vault recipient.
    let b_identity = ($sb | path join "B" "home" ".config" "dotfiles" "age" "identity.txt")
    let saved_identity = (open --raw $b_identity)
    let other = ($sb | path join "other-identity.txt")
    ^age-keygen -o $other err> /dev/null
    cp --force $other $b_identity
    let wrong = (verify $sb "B")
    let wr = (try { $wrong.stdout | from json } catch { {} })
    ok ($wrong.exit_code != 0 and $wr.keys?.status? == "mismatch") "dotctl verify detects identity/recipient mismatch"
    ok ($wr.rpool?.secrets? in ["decrypt-failed" "decrypt-failed-local"]) "Undecryptable crypt passwords are not reported as different"
    if $rclone_sync { ok ($wr.rclone?.status? == "decrypt-failed") "Undecryptable rclone copy is reported as decrypt-failed" }
    let readiness = (shim-call $sb "B" "dotctl config rclone")
    ok (($readiness.stdout | ansi strip) | str contains "MISMATCH") "rclone readiness shows the key mismatch"
    if $rclone_sync {
        # The user's case: keep B's new key, rekey the vault to it, re-push.
        let preview = (shim-call $sb "B" "dotvault rekey")
        ok ($preview.exit_code == 0 and (open --raw ($sb | path join "B" "home" ".config" "dotfiles" "vault.nuon") | str contains (^age-keygen -y $other | str trim) | not $in)) "dotvault rekey preview changes nothing"
        ok ((show (shim-call $sb "B" "dotvault rekey --execute") "B rekey").exit_code == 0) "dotvault rekey --execute sets this identity as recipient"
        ok ((dotpush $sb "B" "B push after rekey").exit_code == 0) "dotpush after rekey succeeds"
        let after = (verify $sb "B")
        if not (verify-ok $after) { print $after.stdout }
        ok (verify-ok $after) "After rekey + dotpush, B verifies rclone and rpool"
        let a_old = (try { (verify $sb "A").stdout | from json } catch { {} })
        ok ($a_old.rclone?.status? == "decrypt-failed" and ($a_old.rclone?.detail? | default "" | str contains "different key")) "A with the old key cannot decrypt and is told to copy the new identity"
        cp --force $other ($sb | path join "A" "home" ".config" "dotfiles" "age" "identity.txt")
        let a_rec = (^age-keygen -y $other | str trim)
        open --raw ($sb | path join "A" "home" ".config" "dotfiles" "vault.nuon") | from nuon | upsert recipients [$a_rec] | to nuon | save --force ($sb | path join "A" "home" ".config" "dotfiles" "vault.nuon")
        let a_new = (verify $sb "A")
        if not (verify-ok $a_new) { print $a_new.stdout }
        ok (verify-ok $a_new) "A verifies after receiving the new identity"
    } else {
        $saved_identity | save --force --raw $b_identity
        ok (verify-ok (verify $sb "B")) "Restoring the matching identity makes verify pass again"
    }
    if $rclone_sync {
        open --raw ($sb | path join "A" "rclone.conf") | str replace '"access_token":"t1"' '"access_token":"t2"' | save --force ($sb | path join "A" "rclone.conf")
        let tv = (verify $sb "A")
        ok ($tv.exit_code == 0 and (($tv.stdout | from json).rclone.status == "token-refresh")) "OAuth token-only change is reported as normal refresh"
    }

    if $keep { print $"[info] sandbox kept: ($sb)" } else { rm --recursive --force $sb }
}

def main [--keep] {
    if $nu.os-info.name == "windows" { print "[skip] POSIX sandbox paths only."; return }
    let missing = (["rpool" "rclone" "age" "age-keygen" "chezmoi"] | where {|t| which $t | where type == "external" | is-empty })
    if not ($missing | is-empty) { print $"[skip] rpool two-machine e2e needs: ($missing | str join ', ')"; return }
    scenario false $keep
    scenario true $keep
    print "[ok] rpool two-machine e2e passed"
}
