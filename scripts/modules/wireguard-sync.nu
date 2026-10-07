# Opt-in device-scoped encrypted WireGuard disk-config synchronization.
# Privileged helpers own native stores. Nothing here starts/stops a tunnel.
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
const VAULT = path self ./vault.nu
use $CORE [machine-context]
use $SAFETY [state-root private-directory private-file checked atomic-record disjoint-paths]
use $VAULT [load-vault]

export def load-wireguard-policy [] {
    let path = ((state-root) | path join "wireguard.nuon")
    if not ($path | path exists) { return {enabled: false} }
    let policy = (open $path)
    if ($policy.enabled? | default false) == false { return {enabled: false} }
    if ($policy.schema_version? | default 0) != 1 { error make {msg: "Unsupported WireGuard policy schema."} }
    if not (($policy.device_id? | default "") =~ '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,40}$') {
        error make {msg: "WireGuard requires an explicit stable device_id (letters, digits, underscore or hyphen; maximum 41 characters)."}
    }
    let backend = ($policy.backend? | default "")
    let expected = if $nu.os-info.name == "windows" { "windows-dpapi" } else if $nu.os-info.name == "linux" { "linux-wg-quick" } else { "unsupported" }
    if $backend != $expected or $expected == "unsupported" { error make {msg: "WireGuard backend does not match this platform. Only Windows DPAPI and Linux wg-quick stores are supported."} }
    let names = ($policy.tunnels? | default [])
    if ($names | is-empty) or ($names | length) > 128 { error make {msg: "WireGuard policy must explicitly allowlist 1–128 tunnel names."} }
    for name in $names {
        if not ($name =~ '^[a-zA-Z0-9_=+.-]{1,15}$') or $name in ["." ".."] { error make {msg: "Invalid WireGuard tunnel name (portable names must be 1–15 characters)."} }
    }
    if ($names | uniq | length) != ($names | length) { error make {msg: "WireGuard tunnel names must be unique."} }
    $policy
}

def stage-directory [] {
    let root = ((state-root) | path join "wireguard-staging" (random uuid))
    disjoint-paths $root ((machine-context).data_root | path expand)
    private-directory $root
    $root
}

def cleanup-stage [stage: path] { if ($stage | path exists) { rm --recursive --force $stage } }

def helper-call [policy: record action: string stage: path bundle: path --baseline: record = {}] {
    let request = ($stage | path join ((random uuid) + "-request.json"))
    let response = ($stage | path join ((random uuid) + "-response.json"))
    {schema_version: 1 device_id: $policy.device_id tunnels: $policy.tunnels bundle_path: ($bundle | into string) baseline: $baseline} | to json | save $request
    private-file $request
    try {
        if $policy.backend == "linux-wg-quick" {
            let helper = "/usr/local/libexec/initial-setup-wireguard-helper"
            # Never elevate a helper from the checkout or a user-selected path.
            for target in ["/usr/local" "/usr/local/libexec" $helper] {
                let metadata = (with-env {LC_ALL: "C"} { checked "stat" ["-c" "%u:%a:%F" $target] "Verify installed WireGuard helper" } | str trim)
                if not ($metadata =~ '^0:(700|750|755):(regular file|directory)$') { error make {msg: "WireGuard helper must be installed root-owned with protected parent directories."} }
            }
            checked "sudo" ["-n" $helper $action "--request" $request "--response" $response] "WireGuard privileged operation" | ignore
        } else {
            let helper = ($env.ProgramFiles | path join "InitialSetup" "WireGuardSync" "wireguard-sync-helper.exe")
            checked $helper [$action "--request" $request "--response" $response] "WireGuard privileged operation" | ignore
        }
        let result = (open $response)
        if ($result.ok? | default false) != true { error make {msg: "WireGuard helper did not confirm success."} }
        $result
    } catch {
        # Deliberately do not forward raw helper/JSON errors: configs contain keys.
        error make {msg: "WireGuard helper operation failed. Check installation, privilege policy, protected paths and tunnel compatibility. No secret diagnostic output is shown."}
    }
}

def canonical-bundle [path: path policy: record --complete] {
    if (ls $path | first | get size) > 4mb { error make {msg: "WireGuard bundle exceeds the 4 MB limit."} }
    let bundle = (try { open $path } catch { error make {msg: "WireGuard bundle is not valid JSON."} })
    if ($bundle.schema_version? | default 0) != 1 or ($bundle.device_id? | default "") != $policy.device_id {
        error make {msg: "WireGuard bundle schema or device identity does not match the local policy."}
    }
    let rows = ($bundle.tunnels? | default [])
    mut names = []
    for row in $rows {
        let name = ($row.name? | default "")
        if not ($name in $policy.tunnels) or $name in $names { error make {msg: "WireGuard bundle has unexpected or duplicate tunnel names."} }
        if (($row.config? | describe) != "string") { error make {msg: "WireGuard bundle has invalid configuration content."} }
        $names = ($names | append $name)
    }
    if $complete and (($names | sort) != ($policy.tunnels | sort)) { error make {msg: "WireGuard capture is incomplete; every allowlisted tunnel must exist before publication."} }
    {schema_version: 1 device_id: $policy.device_id tunnels: ($rows | sort-by name | each {|row| {name: $row.name config: $row.config}})}
}

def bundle-hash [bundle: record] { $bundle | to json --raw | hash sha256 }
def state-path [] { (state-root) | path join "wireguard-sync-state.nuon" }
def read-state [] { if ((state-path) | path exists) { open (state-path) } else { {} } }
def write-state [policy: record plaintext_hash: string ciphertext_hash: string] {
    atomic-record (state-path) {schema_version: 1 device_id: $policy.device_id plaintext_sha256: $plaintext_hash ciphertext_sha256: $ciphertext_hash}
    private-file (state-path)
}
def cipher-name [policy: record] { "wireguard-" + $policy.device_id + ".age" }

export def wireguard-local-hash [] {
    let policy = (load-wireguard-policy)
    if not $policy.enabled { return "DISABLED" }
    let stage = (stage-directory)
    try {
        let bundle = ($stage | path join "capture.json")
        helper-call $policy "capture" $stage $bundle | ignore
        let hash = (bundle-hash (canonical-bundle $bundle $policy))
        cleanup-stage $stage
        $hash
    } catch {
        cleanup-stage $stage
        error make {msg: "Could not fingerprint protected WireGuard configuration; synchronization stopped."}
    }
}

export def capture-wireguard [source_root: path] {
    let policy = (load-wireguard-policy)
    if not $policy.enabled { return }
    disjoint-paths ((state-root) | path join "wireguard-staging") $source_root
    let stage = (stage-directory)
    try {
        let bundle_path = ($stage | path join "capture.json")
        helper-call $policy "capture" $stage $bundle_path | ignore
        let bundle = (canonical-bundle $bundle_path $policy --complete)
        let hash = (bundle-hash $bundle)
        let target = ($source_root | path join "secrets" (cipher-name $policy))
        let previous = (read-state)
        let encrypted_hash = if ($target | path exists) { open --raw $target | hash sha256 } else { "" }
        if $hash != ($previous.plaintext_sha256? | default "") or $encrypted_hash != ($previous.ciphertext_sha256? | default "") or $encrypted_hash == "" {
            let vault = (load-vault)
            let ciphertext = ($stage | path join "capture.age")
            mut args = ["--encrypt" "--output" $ciphertext]
            for recipient in $vault.recipients { $args = ($args | append ["--recipient" $recipient]) }
            checked "age" ($args | append $bundle_path) "Encrypt WireGuard configuration" | ignore
            mkdir ($target | path dirname)
            # Copy to a sibling first, then atomically replace the ciphertext.
            let candidate = (($target | into string) + ".tmp-" + (random uuid))
            cp $ciphertext $candidate
            mv --force $candidate $target
        }
        write-state $policy $hash (open --raw $target | hash sha256)
        cleanup-stage $stage
    } catch {
        cleanup-stage $stage
        error make {msg: "Encrypted WireGuard capture failed; no plaintext was published."}
    }
}

export def discard-prepared-wireguard [prepared: record] {
    if ($prepared.status? | default "") == "prepared" { cleanup-stage $prepared.stage_dir }
}

export def prepare-wireguard-restore [source_root: path --discard-local] {
    let policy = (load-wireguard-policy)
    if not $policy.enabled { return {status: "disabled"} }
    let ciphertext = ($source_root | path join "secrets" (cipher-name $policy))
    if not ($ciphertext | path exists) { return {status: "missing"} }
    if (ls $ciphertext | first | get size) > 5mb { error make {msg: "Encrypted WireGuard bundle exceeds the size limit."} }
    disjoint-paths ((state-root) | path join "wireguard-staging") $source_root
    let stage = (stage-directory)
    try {
        let vault = (load-vault)
        let hash = (open --raw $ciphertext | hash sha256)
        let bundle_path = ($stage | path join "incoming.json")
        checked "age" ["--decrypt" "--identity" ($vault.identity | path expand) "--output" $bundle_path $ciphertext] "Authenticate WireGuard configuration" | ignore
        private-file $bundle_path
        let incoming = (canonical-bundle $bundle_path $policy --complete)
        let incoming_hash = (bundle-hash $incoming)
        if (open --raw $ciphertext | hash sha256) != $hash { error make {msg: "WireGuard ciphertext changed during authentication."} }
        let local_path = ($stage | path join "local.json")
        let captured = (helper-call $policy "capture" $stage $local_path)
        let local = (canonical-bundle $local_path $policy)
        let local_hash = (bundle-hash $local)
        if $incoming_hash == $local_hash {
            write-state $policy $incoming_hash $hash
            cleanup-stage $stage
            return {status: "current"}
        }
        let state = (read-state)
        if not $discard_local and not ($local.tunnels | is-empty) and ($local_hash != ($state.plaintext_sha256? | default "") or ($state.device_id? | default "") != $policy.device_id) {
            error make {msg: "WIREGUARD_LOCAL_CONFLICT"}
        }
        let validation = (helper-call $policy "validate" $stage $bundle_path)
        if ($captured.baseline? | default null) == null or $captured.baseline != $validation.baseline { error make {msg: "WireGuard local configuration changed during preflight."} }
        {status: "prepared" stage_dir: $stage policy: $policy bundle_path: $bundle_path plaintext_sha256: $incoming_hash ciphertext: $ciphertext ciphertext_sha256: $hash baseline: $validation.baseline local_sha256: $local_hash}
    } catch {|err|
        cleanup-stage $stage
        if ($err.msg? | default "") == "WIREGUARD_LOCAL_CONFLICT" { error make {msg: "Local WireGuard configs differ from the last synchronized baseline (or no baseline exists). Review them; use --discard-local only to explicitly replace them."} }
        error make {msg: "Incoming WireGuard configuration could not be authenticated or validated. Check device policy, age identity, helper readiness and inactive compatible tunnels. No WireGuard configuration was changed."}
    }
}

export def commit-prepared-wireguard [prepared: record] {
    if ($prepared.status? | default "") != "prepared" { return null }
    try {
        let policy = (load-wireguard-policy)
        if $policy != $prepared.policy { error make {msg: "WireGuard policy changed after preflight."} }
        if (open --raw $prepared.ciphertext | hash sha256) != $prepared.ciphertext_sha256 { error make {msg: "WireGuard ciphertext changed after preflight."} }
        if (bundle-hash (canonical-bundle $prepared.bundle_path $policy --complete)) != $prepared.plaintext_sha256 { error make {msg: "Prepared WireGuard plaintext changed after preflight."} }
        let result = (helper-call $policy "restore" $prepared.stage_dir $prepared.bundle_path --baseline $prepared.baseline)
        let verify_path = ($prepared.stage_dir | path join "verified.json")
        helper-call $policy "capture" $prepared.stage_dir $verify_path | ignore
        if (bundle-hash (canonical-bundle $verify_path $policy --complete)) != $prepared.plaintext_sha256 { error make {msg: "WireGuard committed configuration did not match prepared plaintext."} }
        write-state $policy $prepared.plaintext_sha256 $prepared.ciphertext_sha256
        discard-prepared-wireguard $prepared
        {changed: true recovery: ($result.recovery? | default "")}
    } catch {
        discard-prepared-wireguard $prepared
        error make {msg: "WireGuard restore did not complete verification. Inspect the protected native-store recovery backup before retrying; no tunnels were activated."}
    }
}
