#!/usr/bin/env nu
# Regression tests use an isolated HOME and a filesystem-only rclone remote.
# No user/cloud credentials are read. Missing optional binaries are SKIP unless
# --require-age / --require-rclone is supplied (the release gate supplies both).
const ROOT = path self ..
const SAFETY = path self ./modules/safety.nu
const PROVIDER = path self ./modules/sync-provider.nu
const VAULT = path self ./modules/vault.nu
const UPGRADE = path self ./modules/upgrade.nu
use $SAFETY *
use $PROVIDER *
use $VAULT *
use $UPGRADE *

def expect [condition: bool label: string] {
    if not $condition { error make {msg: ("FAILED: " + $label)} }
    print ("[pass] " + $label)
}

def rejects [label: string action: closure] {
    let rejected = (try { do $action | ignore; false } catch { true })
    expect $rejected $label
}

def fixture-release [root: path version: string content: string] {
    mkdir $root
    ($version + "\n") | save ($root | path join "VERSION")
    $content | save ($root | path join "tool.nu")
    write-release-manifest $root | ignore
}

def test-suite [sandbox: path require_age: bool require_rclone: bool] {
    let home = ($sandbox | path join "home")
    let workspace = ($sandbox | path join "workspace")
    mkdir $workspace
    let cfg = ((state-root) | path join "config.nuon")
    atomic-record $cfg {
        app_version: "security-self-test" schema_version: 5
        data_root: ($workspace | into string) tools_root: ($ROOT | into string)
        machine: {name: "sandbox" profile: "minimal" install_gui_apps: false}
        features: {rust: false julia: false vscode: false rclone_config: false}
        maintenance: {snapshots_enabled: false snapshot_keep: 2 log_keep_lines: 100}
        sync: {enabled: false auto_push: false auto_pull: false prune_extras: false}
    }
    expect ((state-root) == ($home | path join ".config" "dotfiles")) "Guarded HOME isolation"

    let first_lock = (operation-lock)
    rejects "Second writer cannot acquire the local lock" { operation-lock }
    lock-release {path: $first_lock.path token: "not-the-owner"}
    expect ($first_lock.path | path exists) "A different token cannot release a lock"
    lock-release $first_lock
    let reacquired = (operation-lock)
    lock-release $reacquired
    print "[pass] Lock can be reacquired after its owner releases it"

    for invalid in ["../escape" "/absolute" "home/../escape" 'home\escape' "C:/escape" "home//empty" "home/CON.txt" "home/trailing."] {
        rejects ("Unsafe manifest path: " + $invalid) { validate-relative $invalid }
    }
    rejects "Nested source/store paths are rejected" { disjoint-paths $workspace ($workspace | path join "store") }
    disjoint-paths $workspace ($sandbox | path join "store")

    mkdir ($workspace | path join "home")
    "first" | save ($workspace | path join "home" "dot_example")
    "hidden" | save ($workspace | path join "home" ".hidden-fixture")
    let inventory = (workspace-manifest $workspace)
    expect (($inventory | length) == 2) "Hidden files participate in the snapshot hash"
    let copy = ($sandbox | path join "copy")
    copy-workspace $workspace $copy | ignore
    verify-tree $copy $inventory | ignore
    "tampered" | save --force ($copy | path join "home" "dot_example")
    rejects "Content tampering is rejected before install" { verify-tree $copy $inventory }
    rejects "Case-colliding remote paths are rejected" {
        verify-tree $copy [{path: "HOME/a" sha256: ("a" | hash sha256)} {path: "home/A" sha256: ("a" | hash sha256)}]
    }
    if $nu.os-info.name != "windows" {
        let link_tree = ($sandbox | path join "links")
        mkdir $link_tree
        checked "ln" ["-s" ($workspace | into string) ($link_tree | path join "outside")] "Create link fixture" | ignore
        rejects "Symlinks cannot enter transfer manifests" { tree-manifest $link_tree }
    } else { print "[skip] Symlink creation fixture requires Unix ln; Windows path guards are still tested." }

    let directory = {version: 1 kind: "directory" remote: "" data_root: ($workspace | into string)}
    rejects "Existing source without a baseline cannot be pushed" { assert-expected-head $directory }
    record-provider-state $directory (provider-head $directory)
    assert-expected-head $directory | ignore
    let directory_lock = (remote-lock $directory)
    expect ($directory_lock == null) "Directory/cloud provider relies on operation.lock instead of a redundant provider lock"
    expect (not (($workspace | path join ".initial-setup-write.lock") | path exists)) "Directory/cloud provider never creates a lock inside the synced tree"
    "remote edit" | save --force ($workspace | path join "home" "dot_example")
    rejects "Another mirror edit invalidates the saved baseline" { assert-expected-head $directory }

    let store = {version: 1 kind: "local" remote: ($sandbox | path join "revision store") data_root: ($workspace | into string)}
    provider-init $store
    let empty = (provider-head $store)
    expect $empty.empty "New revision store is empty"
    let remote_lock = (remote-lock $store)
    rejects "Cooperating filesystem writers share an exclusive lock" { remote-lock $store }
    let head1 = (publish-revision $store $empty)
    release-remote-lock $remote_lock
    record-provider-state $store $head1
    let fetched = (fetch-revision $store $head1 ($sandbox | path join "download-1"))
    expect ((workspace-manifest $fetched) == (workspace-manifest $workspace)) "Local revision round trip preserves all files"
    "second revision" | save --force ($workspace | path join "home" "dot_example")
    let head2 = (publish-revision $store $head1)
    rejects "An old machine baseline cannot publish over a new HEAD" { assert-expected-head $store }
    rejects "Mid-operation HEAD change aborts publish" { publish-revision $store $head1 }
    expect ((provider-head $store).revision == $head2.revision) "Rejected publish leaves HEAD unchanged"
    expect (($store.remote | path join "revisions" $head1.revision "manifest.nuon") | path exists) "Earlier immutable revision is retained"
    "corrupt remote bytes" | save --force ($store.remote | path join "revisions" $head2.revision "data" "home" "dot_example")
    rejects "Downloaded corruption does not reach the workspace" { fetch-revision $store $head2 ($sandbox | path join "corrupt-download") }
    expect ((open --raw ($workspace | path join "home" "dot_example")) == "second revision") "Corrupt download leaves the working source untouched"

    mkdir ($workspace | path join "rclone")
    "[fixture]\ntype = local\n" | save ($workspace | path join "rclone" "rclone.conf")
    rejects "Legacy plaintext credentials block publication" { audit-export $workspace }
    rm ($workspace | path join "rclone" "rclone.conf")
    # A marker is assembled to avoid including real private keys in the repository.
    ("-----BEGIN " + "PRIVATE KEY-----") | save ($workspace | path join "home" "dot_renamed_key")
    rejects "Renamed private-key material is rejected" { audit-export $workspace }
    rm ($workspace | path join "home" "dot_renamed_key")

    mkdir ($workspace | path join "secrets")
    "not encrypted" | save ($workspace | path join "secrets" "pretend.age")
    rejects "An age extension without a binary age header is not ciphertext" { audit-export $workspace }
    rm ($workspace | path join "secrets" "pretend.age")
    "../outside" | save ($workspace | path join ".chezmoiroot")
    rejects "Remote source subdirectory cannot escape home" { audit-export $workspace }
    rm ($workspace | path join ".chezmoiroot")

    let previous = ($sandbox | path join "release-old")
    let candidate = ($sandbox | path join "release-new")
    let installed = ($sandbox | path join "installed")
    fixture-release $previous "0.12.32" "# previous\n"
    fixture-release $candidate "0.13.0" "# candidate\n"
    let digest = (open --raw ($candidate | path join "RELEASE-MANIFEST.json") | hash sha256)
    let old = (verify-release $previous "")
    let new = (verify-release $candidate $digest)
    rejects "Wrong trusted manifest digest blocks an update" { verify-release $candidate ("wrong" | hash sha256) }
    copy-release $previous $installed
    promote-files $installed $candidate $old $new
    expect ((verify-release $installed "").version == "0.13.0") "File promotion installs the validated inventory"
    rollback-files $installed $previous $candidate
    expect ((verify-release $installed "").version == "0.12.32") "File fallback restores the previous inventory"
    promote-files $installed $candidate $old $new
    "user edit after promotion" | save --force ($installed | path join "tool.nu")
    rejects "Rollback preserves a later user edit" { rollback-files $installed $previous $candidate }
    expect ((open --raw ($installed | path join "tool.nu")) == "user edit after promotion") "User-edited file was not erased"
    "tampered candidate" | save --force ($candidate | path join "tool.nu")
    rejects "Candidate contents must match the trusted manifest" { verify-release $candidate $digest }

    let have_age = (not (which age | is-empty) and not (which age-keygen | is-empty))
    if $require_age and not $have_age { error make {msg: "age and age-keygen are required by this release gate."} }
    if $have_age {
        initialize-vault ""
        let secret = ($home | path join "example-token.txt")
        let plaintext = "fixture-token-not-a-real-credential\n"
        $plaintext | save $secret
        let policy = ((load-vault) | upsert entries [{name: "fixture" local: ($secret | into string) auto_capture: false auto_restore: false}])
        atomic-record (vault-config-path) $policy
        capture-secret "fixture"
        let cipher = (ciphertext-path "fixture")
        expect ((open --raw $cipher | hash sha256) != ($plaintext | hash sha256)) "age ciphertext differs from plaintext"
        rm $secret
        restore-secret "fixture" false
        expect ((open --raw $secret) == $plaintext) "age authenticated round trip"
        rejects "Existing secret is not overwritten without --force" { restore-secret "fixture" false }
        "damaged ciphertext" | save --force $cipher
        rejects "Corrupt ciphertext cannot replace an existing secret" { restore-secret "fixture" true }
        expect ((open --raw $secret) == $plaintext) "Failed decryption preserves the existing secret"
        rm $cipher
        let key = ($home | path join ".ssh" "custom-private-name")
        mkdir ($key | path dirname)
        "not a real private key" | save $key
        atomic-record (vault-config-path) ($policy | upsert entries [{name: "ssh" local: ($key | into string) auto_capture: false auto_restore: false}])
        rejects "All SSH key paths, including nonstandard names, are excluded" { capture-secret "ssh" }
        # Legacy removal is explicit and must pass decrypt/hash verification.
        let local_rclone = ($home | path join "rclone-test.conf")
        "[fixture]\ntype = local\n" | save $local_rclone
        cp $local_rclone ($workspace | path join "rclone" "rclone.conf")
        atomic-record (vault-config-path) ($policy | upsert entries [{name: "rclone" local: ($local_rclone | into string) auto_capture: false auto_restore: false}])
        migrate-rclone-secret false
        expect (($workspace | path join "rclone" "rclone.conf") | path exists) "Migration without removal retains active plaintext"
        migrate-rclone-secret true
        expect (not (($workspace | path join "rclone" "rclone.conf") | path exists)) "Explicit verified migration removes active plaintext"
    } else { print "[skip] age round trip, decryption rejection, and migration require age + age-keygen." }

    let have_rclone = (not (which rclone | is-empty))
    if $require_rclone and not $have_rclone { error make {msg: "rclone is required by this release gate."} }
    if $have_rclone {
        # RCLONE_CONFIG is set to a fresh file containing type=local ONLY.
        let remote = ("fixture:" + (($sandbox | path join "rclone store") | into string | str replace --all '\' '/'))
        let rclone = {version: 1 kind: "rclone" remote: $remote data_root: ($workspace | into string)}
        provider-init $rclone
        let before = (provider-head $rclone)
        let after = (publish-revision $rclone $before)
        let copy = (fetch-revision $rclone $after ($sandbox | path join "rclone-download"))
        expect ((workspace-manifest $copy) == (workspace-manifest $workspace)) "rclone filesystem backend verified upload/download round trip"
        rejects "rclone stale expected HEAD rejects a second publish" { publish-revision $rclone $before }
    } else { print "[skip] rclone transport round trip requires rclone (no live cloud is tested)." }
}

def main [--require-age --require-rclone --keep] {
    let base = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand)
    let sandbox = ($base | path join ("initial-setup-security-" + (random uuid)))
    private-directory $sandbox
    let home = ($sandbox | path join "home")
    mkdir $home
    let rclone_config = ($sandbox | path join "rclone.conf")
    "[fixture]\ntype = local\n" | save $rclone_config
    try {
        with-env {
            INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($home | into string)
            HOME: ($home | into string) USERPROFILE: ($home | into string)
            APPDATA: ($home | path join "AppData" "Roaming") LOCALAPPDATA: ($home | path join "AppData" "Local")
            XDG_CACHE_HOME: ($home | path join ".cache")
            XDG_CONFIG_HOME: ($home | path join ".config") XDG_DATA_HOME: ($home | path join ".local" "share") XDG_STATE_HOME: ($home | path join ".local" "state")
            RCLONE_CONFIG: ($rclone_config | into string)
        } {
            test-suite $sandbox $require_age $require_rclone
        }
        if $keep { print ("[kept] " + ($sandbox | into string)) } else { rm --recursive --force $sandbox }
        print "[ok] All available security tests passed; explicit skips above were NOT executed."
    } catch {|err|
        if $keep { print ("[kept] Failed-test sandbox: " + ($sandbox | into string)) } else { rm --recursive --force $sandbox }
        error make {msg: $err.msg}
    }
}
