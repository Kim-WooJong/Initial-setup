# Three providers:
# directory = an existing cloud-client-synchronized folder (legacy default)
# local     = an explicit filesystem/NAS revision store
# rclone    = an explicit configured rclone revision store
# rclone has no universal compare-and-swap; pre/post checks are optimistic only.
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
use $CORE [machine-context nu-home error-message]
use $SAFETY [state-root checked atomic-record tree-files tree-manifest manifest-hash verify-tree disjoint-paths validate-relative private-directory lock-acquire lock-release]

export def provider-config-path [] { (state-root) | path join "sync-provider.nuon" }
export def provider-state-path [] { (state-root) | path join "provider-state.nuon" }
export def payload-roots [] { [".chezmoiroot" "home" "vscode" "toolchains" "secrets" ".dotfiles-sync-meta.nuon"] }

export def load-provider [] {
    let file = (provider-config-path)
    let config = if ($file | path exists) { open --raw $file | from nuon } else { {version: 1 kind: "directory" remote: ""} }
    if ($config.version? | default 0) != 1 or not ($config.kind in ["directory" "local" "rclone"]) { error make { msg: "Unsupported sync provider configuration." } }
    let ctx = (machine-context)
    let root = ($ctx.data_root | path expand)
    if $config.kind == "local" {
        let remote = ($config.remote | path expand)
        disjoint-paths $root $remote
        disjoint-paths $ctx.tools_root $remote
        disjoint-paths (state-root) $remote
        return ($config | upsert remote ($remote | into string) | upsert data_root ($root | into string))
    }
    if $config.kind == "rclone" {
        if not ($config.remote =~ '^[a-zA-Z0-9][a-zA-Z0-9_. -]*:.+') or ($config.remote =~ '[\x00-\x1f]') {
            error make { msg: "Use a named rclone remote and dedicated subdirectory, e.g. proton:Initial-setup-store." }
        }
    }
    $config | upsert data_root ($root | into string)
}

export def provider-id [config: record] {
    [$config.kind $config.remote $config.data_root] | to json --raw | hash sha256
}

export def workspace-manifest [root: path] {
    mut rows = []
    for name in (payload-roots) {
        let source = ($root | path join $name)
        if not ($source | path exists) { continue }
        let kind = ($source | path type)
        if $kind == "dir" {
            let subtree = (tree-manifest $source | each {|row| {path: ($name + "/" + $row.path) sha256: $row.sha256} })
            $rows = ($rows | append $subtree)
        } else if $kind == "file" {
            $rows = ($rows | append {path: $name sha256: (open --raw $source | hash sha256)})
        } else { error make { msg: "Symlink/special-file source roots are not supported." } }
    }
    $rows | sort-by path
}

export def workspace-hash [root: path] { manifest-hash (workspace-manifest $root) }

export def audit-export [root: path] {
    let selector = ($root | path join ".chezmoiroot")
    if ($selector | path exists) {
        if (open --raw $selector | str trim) != "home" { error make {msg: "This project only permits home as the chezmoi source subdirectory."} }
    }
    if ($root | path join "rclone" "rclone.conf" | path exists) {
        error make { msg: "Legacy plaintext rclone.conf found. Run dotvault migrate-rclone --remove-legacy before publishing." }
    }
    for row in (workspace-manifest $root) {
        let rel = $row.path
        if ($rel =~ '(^|/)(identity\.txt|id_rsa|id_ed25519|rclone\.conf)$') {
            error make { msg: "A known secret/private-key filename is present in the plain sync payload." }
        }
        let file = ($root | path join $rel)
        if ($rel | str starts-with "secrets/") {
            if not ($rel =~ '^secrets/[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}\.age$') { error make { msg: "Only named .age ciphertext files are allowed in secrets/." } }
            if not (open --raw $file | into binary | bytes starts-with ("age-encryption.org/v1\n" | into binary)) {
                error make {msg: "A .age file lacks the binary age header. Plaintext disguised by its extension is not published."}
            }
        } else {
            let text = (try { open --raw $file | into string } catch { "" })
            if ($text | str contains "PRIVATE KEY-----") or ($text | str contains "AGE-SECRET-KEY-") {
                error make { msg: "Private key material is present in the plain sync payload." }
            }
        }
    }
}

export def new-transfer-dir [] {
    let root = ((state-root) | path join "transfers" (random uuid))
    private-directory $root
    $root
}

export def copy-workspace [source: path destination: path] {
    mkdir $destination
    let before = (workspace-manifest $source)
    for row in $before {
        let out = ($destination | path join $row.path)
        mkdir ($out | path dirname)
        cp ($source | path join $row.path) $out
    }
    verify-tree $destination $before | ignore
    if (workspace-manifest $source) != $before { error make { msg: "Private source changed while preparing its snapshot." } }
    $before
}

export def remote-location [config: record rel: string] {
    if $config.kind == "local" { $config.remote | path join $rel } else { ($config.remote | str trim --right --char '/') + "/" + $rel }
}

export def provider-probe [config: record] {
    if $config.kind == "directory" {
        if not ($config.data_root | path exists) { error make { msg: "Private data directory is unavailable." } }
        return
    }
    if $config.kind == "local" {
        if not ($config.remote | path exists) { error make { msg: "Local revision store does not exist. Run dotbackend init." } }
    } else {
        checked "rclone" ["lsjson" $config.remote "--max-depth" "1"] "Probe rclone store" | ignore
    }
}

export def provider-init [config: record] {
    if $config.kind == "local" { mkdir $config.remote } else if $config.kind == "rclone" {
        checked "rclone" ["mkdir" $config.remote] "Create dedicated revision store" | ignore
    } else { provider-probe $config }
}

export def provider-head [config: record] {
    provider-probe $config
    if $config.kind == "directory" {
        let entries = (workspace-manifest $config.data_root)
        let hash = (manifest-hash $entries)
        return {revision: $hash tree_hash: $hash empty: ($entries | is-empty)}
    }
    let head_location = (remote-location $config "HEAD.nuon")
    let exists = if $config.kind == "local" { $head_location | path exists } else {
        let listing = (checked "rclone" ["lsjson" $config.remote "--files-only" "--max-depth" "1"] "Read remote index" | from json)
        $listing | any {|row| $row.Name == "HEAD.nuon" }
    }
    if not $exists { return {revision: "" tree_hash: "" empty: true} }
    let head = if $config.kind == "local" { open --raw $head_location | from nuon } else {
        checked "rclone" ["cat" $head_location] "Read remote HEAD" | from nuon
    }
    if ($head.version? | default 0) != 1 or not ($head.revision =~ '^[a-f0-9-]{36}$') or not ($head.tree_hash =~ '^[a-f0-9]{64}$') {
        error make { msg: "Invalid remote HEAD; refusing to treat it as an empty store." }
    }
    $head | upsert empty false
}

export def load-provider-state [config: record] {
    let file = (provider-state-path)
    if not ($file | path exists) { return null }
    let state = (open --raw $file | from nuon)
    if ($state.provider_id? | default "") != (provider-id $config) { return null }
    $state
}

export def record-provider-state [config: record head: record] {
    atomic-record (provider-state-path) {
        version: 1 provider_id: (provider-id $config) revision: $head.revision
        tree_hash: $head.tree_hash source_hash: (workspace-hash $config.data_root)
        observed_at: (date now | format date "%+")
    }
}

export def assert-expected-head [config: record] {
    let head = (provider-head $config)
    let state = (load-provider-state $config)
    if $state == null {
        if not $head.empty { error make { msg: "No trusted baseline exists. Pull first, or inspect dotbackend status and explicitly acknowledge its revision." } }
    } else if $state.revision != $head.revision or $state.tree_hash != $head.tree_hash {
        error make { msg: "Private source changed since this machine last synchronized. Push stopped before capture/upload; run dotbackend status and reconcile first." }
    }
    $head
}

export def assert-same-head [config: record expected: record] {
    let current = (provider-head $config)
    if $current.revision != $expected.revision or $current.tree_hash != $expected.tree_hash {
        error make { msg: "Remote changed during the operation. HEAD was not intentionally advanced; staged data is retained." }
    }
}

export def provider-local-lock-path [config: record] {
    let id = (provider-id $config)
    (state-root) | path join "locks" ("provider-" + $id + ".lock")
}

export def legacy-directory-lock-path [config: record] {
    if $config.kind != "directory" { return null }
    $config.data_root | path join ".initial-setup-write.lock"
}

export def remote-lock [config: record] {
    if $config.kind == "local" {
        # A true shared filesystem/NAS can provide an atomic cooperative lock
        # visible to every machine using that same filesystem.
        return (lock-acquire ($config.remote | path join ".initial-setup-write.lock"))
    }
    if $config.kind == "directory" {
        # No second local provider lock is needed: every directory-provider
        # writer already holds the machine-wide operation.lock. Cross-machine
        # conflicts are handled by revision/tree fingerprint checks.
        return null
    }
    # Object-store/rclone backends use optimistic revision checks, not a fake lock.
    null
}

export def release-remote-lock [lock: any] { if $lock != null { lock-release $lock } }

export def fetch-revision [config: record head: record destination: path] {
    if $head.empty { error make { msg: "Remote store has no published revision." } }
    mkdir $destination
    if $config.kind == "directory" {
        let entries = (copy-workspace $config.data_root ($destination | path join "data"))
        if (manifest-hash $entries) != $head.tree_hash { error make { msg: "Private source changed while fetching." } }
        return ($destination | path join "data")
    }
    let rel = ("revisions/" + $head.revision)
    let src = (remote-location $config $rel)
    if $config.kind == "local" {
        for file in (tree-files $src) {
            let out = ($destination | path join ($file | path relative-to $src))
            mkdir ($out | path dirname)
            cp $file $out
        }
    } else {
        checked "rclone" ["copy" $src $destination] "Download immutable revision" | ignore
    }
    let manifest_file = ($destination | path join "manifest.nuon")
    let manifest = (open --raw $manifest_file | from nuon)
    if ($manifest.version? | default 0) != 1 or $manifest.revision != $head.revision or (manifest-hash $manifest.files) != $head.tree_hash {
        error make { msg: "Revision manifest does not match remote HEAD." }
    }
    let data = ($destination | path join "data")
    verify-tree $data $manifest.files | ignore
    # The allowlist is enforced before any target is touched.
    for row in $manifest.files {
        let top = ($row.path | split row "/" | first)
        if not ($top in (payload-roots)) { error make { msg: "Remote payload contains an unmanaged source root." } }
    }
    audit-export $data
    assert-same-head $config $head
    $data
}

export def publish-revision [config: record expected: record] {
    audit-export $config.data_root
    if $config.kind == "directory" { return (provider-head $config) }
    let stage = (new-transfer-dir)
    let entries = (copy-workspace $config.data_root ($stage | path join "data"))
    let revision = (random uuid)
    let hash = (manifest-hash $entries)
    let manifest = {version: 1 revision: $revision files: $entries}
    atomic-record ($stage | path join "manifest.nuon") $manifest
    assert-same-head $config $expected
    let destination = (remote-location $config ("revisions/" + $revision))
    if $config.kind == "local" {
        if ($destination | path exists) { error make { msg: "Revision already exists; immutable data was not replaced." } }
        mkdir ($destination | path dirname)
        cp --recursive $stage $destination
        verify-tree ($destination | path join "data") $entries | ignore
    } else {
        checked "rclone" ["copy" $stage $destination "--immutable"] "Upload immutable revision" | ignore
        # --download avoids trusting weak/missing server hash support.
        checked "rclone" ["check" $stage $destination "--download"] "Verify uploaded revision" | ignore
    }
    assert-same-head $config $expected
    let head = {version: 1 revision: $revision parent: $expected.revision tree_hash: $hash created_at: (date now | format date "%+")}
    let headfile = ($stage | path join "new-head.nuon")
    atomic-record $headfile $head
    if $config.kind == "local" {
        atomic-record (remote-location $config "HEAD.nuon") $head
    } else {
        checked "rclone" ["copyto" $headfile (remote-location $config "HEAD.nuon")] "Publish verified HEAD" | ignore
    }
    let readback = (provider-head $config)
    if $readback.revision != $revision or $readback.tree_hash != $hash {
        error make { msg: "HEAD read-back differs. Concurrent write or delayed visibility detected; baseline was not advanced. The uploaded revision remains available." }
    }
    rm --recursive --force $stage
    $readback
}

export def install-workspace [config: record fetched: path] {
    let backup = (new-transfer-dir)
    copy-workspace $config.data_root ($backup | path join "data") | ignore
    let roots = (payload-roots)
    try {
        for name in $roots {
            let dest = ($config.data_root | path join $name)
            let src = ($fetched | path join $name)
            if ($dest | path exists) { rm --recursive --force $dest }
            if ($src | path exists) {
                mkdir ($dest | path dirname)
                if ($src | path type) == "dir" { cp --recursive $src $dest } else { cp $src $dest }
            }
        }
        if (workspace-manifest $config.data_root) != (workspace-manifest $fetched) { error make { msg: "Workspace verification failed." } }
    } catch {|err|
        # Restore only our allowlisted source roots. Never apply to live HOME.
        for name in $roots {
            let dest = ($config.data_root | path join $name)
            let old = ($backup | path join "data" $name)
            if ($dest | path exists) { rm --recursive --force $dest }
            if ($old | path exists) {
                if ($old | path type) == "dir" { cp --recursive $old $dest } else { cp $old $dest }
            }
        }
        error make { msg: ((error-message $err "Workspace update failed.") + " Workspace backup: " + ($backup | into string)) }
    }
    print ("[backup] Previous workspace: " + ($backup | into string))
}
