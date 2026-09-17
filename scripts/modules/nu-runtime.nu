# Cargo runtime gate. This module intentionally has no project imports: old seed
# interpreters must parse it before setup/sync implementation modules are loaded.
# All version conversions below run at execution time, never in a const selector.

export def runtime-version [value: string] {
    let clean = ($value | str trim)
    if not ($clean =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        error make {msg: "NU_VERSION_INVALID: expected stable major.minor.patch."}
    }
    $clean | split row "." | each {|part| $part | into int }
}

export def runtime-version-compare [actual: string required: string] {
    let a = (runtime-version $actual)
    let b = (runtime-version $required)
    for index in [0 1 2] {
        if ($a | get $index) > ($b | get $index) { return 1 }
        if ($a | get $index) < ($b | get $index) { return (-1) }
    }
    0
}

# Sparse crates.io index: select the newest stable, non-yanked `nu` numerically.
# Never let Cargo's MSRV fallback silently select an older package as "latest".
export def runtime-release [index: string] {
    mut best: any = null
    for line in ($index | lines | where {|line| not ($line | str trim | is-empty) }) {
        let row = ($line | from json)
        if ($row.name? | default "") != "nu" { error make {msg: "NU_INDEX_INVALID: unexpected crate."} }
        let version = ($row.vers? | default "")
        if ($row.yanked? | default true) or not ($version =~ '^[0-9]+\.[0-9]+\.[0-9]+$') { continue }
        runtime-version $version | ignore
        if not (($row.cksum? | default "") =~ '^[a-f0-9]{64}$') { error make {msg: "NU_INDEX_INVALID: crate checksum is missing."} }
        let required = ($row.rust_version? | default "")
        if not ($required | is-empty) and not ($required =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$') {
            error make {msg: "NU_INDEX_INVALID: unsupported Rust requirement."}
        }
        if $best == null {
            $best = {version: $version checksum: $row.cksum rust_version: $required}
        } else if (runtime-version-compare $version $best.version) > 0 {
            $best = {version: $version checksum: $row.cksum rust_version: $required}
        }
    }
    if $best == null { error make {msg: "NU_INDEX_INVALID: no non-yanked stable release."} }
    if (runtime-version-compare $best.version "0.109.1") < 0 { error make {msg: "NU_INDEX_INVALID: registry result is below the supported runtime minimum."} }
    $best
}

export def runtime-latest [] {
    try {
        let index = (http get --raw --max-time 30sec --headers [User-Agent Initial-setup/0.14] "https://index.crates.io/2/nu")
        let text = if ($index | describe) == "binary" { $index | decode utf-8 } else { $index }
        runtime-release $text
    } catch {|err|
        print --stderr "[nushell] crates.io latest-stable check failed. No setup/sync will start; check TLS, network or proxy configuration."
        error make {msg: ($err.msg? | default "NU_REGISTRY_CHECK_FAILED")}
    }
}

export def runtime-fixture-mode [] {
    ($env.INITIAL_SETUP_TEST_MODE? | default "") == "1" and not (($env.INITIAL_SETUP_HOME_OVERRIDE? | default "") | is-empty)
}

export def runtime-home [] {
    if (runtime-fixture-mode) { return ($env.INITIAL_SETUP_HOME_OVERRIDE | path expand) }
    let home = ($env.USERPROFILE? | default ($env.HOME? | default ""))
    if ($home | is-empty) { error make {msg: "NU_RUNTIME_HOME: no user home is available."} }
    $home | path expand
}

export def runtime-cargo-home [] {
    if (runtime-fixture-mode) { return ((runtime-home) | path join ".cargo") }
    ($env.CARGO_HOME? | default ((runtime-home) | path join ".cargo")) | path expand
}

export def runtime-root [] { (runtime-cargo-home) | path join "initial-setup" "nu" }

def runtime-bin-name [] { if $nu.os-info.name == "windows" { "nu.exe" } else { "nu" } }

# This marker is a child-invocation optimization, NOT an authorization mechanism.
# Only a runtime prepared/selected by the bootstrap or runtime gate may reuse the session marker.
export def runtime-session-valid [] {
    let provider = ($env.INITIAL_SETUP_NU_SESSION_PROVIDER? | default "")
    (
        ($provider in ["cargo-v1" "release-v1" "current-v1"]) and
        ($env.INITIAL_SETUP_NU_SESSION_EXE? | default "") == ($nu.current-exe | into string) and
        ($env.INITIAL_SETUP_NU_SESSION_VERSION? | default "") == (version).version
    )
}

def runtime-command [name: string] {
    let file = if $nu.os-info.name == "windows" { $name + ".exe" } else { $name }
    let local = ((runtime-cargo-home) | path join "bin" $file)
    if ($local | path exists) { return $local }
    let found = (which $name | where type == "external")
    if ($found | is-empty) { return null }
    $found | first | get path
}

# The build uses an explicit stable toolchain when rustup is present; no default,
# override file, user's project toolchain or Rust lock file is rewritten.
def runtime-compiler [release: record] {
    let rustup = (runtime-command "rustup")
    let cargo = (runtime-command "cargo")
    let rustc = (runtime-command "rustc")
    let command = if $rustup != null {
        print --stderr "[nushell] Preparing the stable Rust toolchain for the new Cargo build."
        ^$rustup toolchain install stable --profile minimal | ignore
        if ($env.LAST_EXIT_CODE | default 1) != 0 { error make {msg: "NU_RUST_UPDATE_FAILED: Rust update failed; current Nushell is retained."} }
        {program: $rustup prefix: ["run" "stable" "cargo"] rustc: $rustup rustc_args: ["run" "stable" "rustc"]}
    } else {
        if $cargo == null or $rustc == null { error make {msg: "NU_CARGO_MISSING: install Rust/Cargo or run native bootstrap first. No synchronization started."} }
        {program: $cargo prefix: [] rustc: $rustc rustc_args: []}
    }
    let program = $command.rustc
    let args = ($command.rustc_args | append "-vV")
    let result = (do { ^$program ...$args } | complete)
    if $result.exit_code != 0 or ($result.stdout | describe) != "string" { error make {msg: "NU_RUST_INVALID: cannot run the selected Rust compiler."} }
    let versions = ($result.stdout | lines | parse --regex '^release: (?P<value>\S+)$')
    let hosts = ($result.stdout | lines | parse --regex '^host: (?P<value>[a-zA-Z0-9_-]+)$')
    if ($versions | length) != 1 or ($hosts | length) != 1 { error make {msg: "NU_RUST_INVALID: missing compiler version/host."} }
    let actual = $versions.0.value
    runtime-version $actual | ignore
    if not ($release.rust_version | is-empty) {
        let required = if ($release.rust_version | split row "." | length) == 2 { $release.rust_version + ".0" } else { $release.rust_version }
        if (runtime-version-compare $actual $required) < 0 { error make {msg: ("NU_RUST_TOO_OLD: selected nu requires Rust " + $required + "; found " + $actual + ". Update Rust; no older nu will be substituted.")} }
    }
    $command | upsert host $hosts.0.value
}

export def runtime-build-args [release: record destination: path host: string] {
    runtime-version $release.version | ignore
    if not ($host =~ '^[a-zA-Z0-9_-]+$') { error make {msg: "NU_RUST_INVALID: invalid host."} }
    ["install" "nu" "--locked" "--version" $release.version "--bin" "nu" "--registry" "crates-io" "--root" ($destination | into string) "--target" $host]
}

export def runtime-probe [exe: path expected: string] {
    let result = (do { ^$exe --version } | complete)
    if $result.exit_code != 0 or ($result.stdout | describe) != "string" or ($result.stdout | str trim) != $expected {
        error make {msg: "NU_RUNTIME_VERIFY_FAILED: executable did not report the selected stable version."}
    }
    let probe = (do { ^$exe --no-config-file -c '"AbC" | str length' } | complete)
    if $probe.exit_code != 0 or ($probe.stdout | describe) != "string" or ($probe.stdout | str trim) != "3" {
        error make {msg: "NU_RUNTIME_VERIFY_FAILED: selected executable cannot run an isolated command."}
    }
}

# Cargo tracks --root installations separately; require that this installation
# was recorded as the crates.io `nu` package, not as a downloaded GitHub archive.
def runtime-tracked [directory: path expected: string] {
    let file = ($directory | path join ".crates2.json")
    if not ($file | path exists) { return false }
    let tracked = (open --raw $file | from json)
    $tracked.installs | columns | any {|key|
        (
            ($key | str starts-with ("nu " + $expected + " (registry+")) and
            (($key | str contains "github.com/rust-lang/crates.io-index") or ($key | str contains "index.crates.io"))
        )
    }
}

export def runtime-cache [root: path release: record] {
    let file = ($root | path join "current.json")
    if not ($file | path exists) { return null }
    let saved = (open --raw $file | from json)
    if ($saved.format? | default 0) != 2 or ($saved.provider? | default "") != "cargo" {
        error make {msg: "NU_CACHE_INVALID: this is not a Cargo runtime receipt; no files were replaced."}
    }
    runtime-version ($saved.version? | default "") | ignore
    if (runtime-version-compare $saved.version $release.version) > 0 {
        error make {msg: "NU_REGISTRY_BEHIND: installed Cargo runtime is newer than the registry result. Automatic downgrade refused; check registry/network state."}
    }
    if $saved.version != $release.version { return null }
    if ($saved.crate_sha256? | default "") != $release.checksum {
        error make {msg: "NU_CACHE_CHANGED: crate checksum differs from the Cargo receipt; refusing a silent same-version replacement."}
    }
    let directory = ($saved.directory? | default "")
    if not ($directory =~ '^build-[a-f0-9-]{32,36}$') { error make {msg: "NU_CACHE_INVALID: unsafe installation path."} }
    let install = ($root | path join "versions" $directory)
    let exe = ($install | path join "bin" (runtime-bin-name))
    if not ($exe | path exists) { return null }
    if ($exe | path type) != "file" or (open --raw $exe | hash sha256) != ($saved.binary_sha256? | default "") {
        error make {msg: "NU_CACHE_CHANGED: executable differs from its local receipt; refusing to execute it."}
    }
    if not (runtime-tracked $install $release.version) { error make {msg: "NU_CACHE_INVALID: Cargo installation record is missing."} }
    $exe
}

def runtime-record [root: path directory: path release: record] {
    let exe = ($directory | path join "bin" (runtime-bin-name))
    if not (runtime-tracked $directory $release.version) { error make {msg: "NU_CARGO_RECORD_MISSING: Cargo did not record the selected nu installation."} }
    runtime-probe $exe $release.version
    let receipt = {
        format: 2 provider: "cargo" registry: "crates-io" version: $release.version
        directory: ($directory | path basename) crate_sha256: $release.checksum
        binary_sha256: (open --raw $exe | hash sha256)
    }
    let temp = ($root | path join ("receipt-" + (random uuid) + ".json"))
    $receipt | to json | save $temp
    mv --force $temp ($root | path join "current.json")
    $exe
}

export def runtime-install [release: record] {
    let root = (runtime-root)
    let cached = (runtime-cache $root $release)
    if $cached != null { runtime-probe $cached $release.version; return $cached }
    # A native bootstrap may have just compiled the seed in this managed root.
    # Adopt that verified Cargo installation instead of compiling the same nu twice.
    let seed_root = ($nu.current-exe | path dirname | path dirname)
    if (
        ($seed_root | path dirname) == ($root | path join "versions") and
        (($seed_root | path basename) =~ '^build-[a-f0-9-]{32,36}$') and (version).version == $release.version
    ) {
        return (runtime-record $root $seed_root $release)
    }
    let compiler = (runtime-compiler $release)
    let directory = ($root | path join "versions" ("build-" + (random uuid)))
    mkdir $directory
    let args = ($compiler.prefix | append (runtime-build-args $release $directory $compiler.host))
    let program = $compiler.program
    print --stderr ("[nushell] Cargo building nu " + $release.version + ". Existing running binaries are not replaced.")
    let result = (try {
        # One shared build cache lets Cargo use its own OS-backed build locks.
        # There is no extra, age-deleted operation/provider lock in this updater.
        with-env {CARGO_TARGET_DIR: ($root | path join "target") RUSTUP_TOOLCHAIN: "stable"} {
            ^$program ...$args | ignore
            let code = ($env.LAST_EXIT_CODE | default 1)
            if $code != 0 { error make {msg: "NU_CARGO_BUILD_FAILED: see Cargo diagnostics above. Install native build prerequisites; the previous runtime and configuration were not replaced."} }
        }
        let exe = (runtime-record $root $directory $release)
        {ok: true exe: $exe}
    } catch {|err| {ok: false message: ($err.msg? | default "NU_CARGO_BUILD_FAILED")} })
    if not $result.ok {
        print --stderr ("[nushell] Incomplete build retained for inspection: " + ($directory | into string))
        error make {msg: $result.message}
    }
    print --stderr ("[nushell] Cargo runtime ready: " + ($result.exe | into string))
    $result.exe
}

export def runtime-check [] {
    let release = (runtime-latest)
    let cached = (runtime-cache (runtime-root) $release)
    if $cached != null { runtime-probe $cached $release.version }
    let current_version = (version).version
    let current_compatible = ((runtime-version-compare $current_version "0.109.1") >= 0)
    let current_satisfies_latest = ($current_compatible and (runtime-version-compare $current_version $release.version) >= 0)
    {
        current: $current_version
        latest: $release.version
        provider: (if $cached != null { "cargo" } else if $current_satisfies_latest { "current" } else { "cargo" })
        registry: "crates-io"
        managed_executable: (if $cached == null { "" } else { $cached | into string })
        rust_required: $release.rust_version
        current_satisfies_latest: $current_satisfies_latest
        update_required: ($cached == null and not $current_satisfies_latest)
        release: $release
    }
}

export def runtime-ensure [--read-only] {
    if (runtime-fixture-mode) {
        print --stderr "[nushell:test] Isolated HOME: registry/build disabled."
        return {exe: $nu.current-exe version: (version).version checked: false provider: "current-v1"}
    }
    if (runtime-session-valid) {
        return {
            exe: $nu.current-exe
            version: (version).version
            checked: true
            provider: ($env.INITIAL_SETUP_NU_SESSION_PROVIDER? | default "current-v1")
        }
    }
    # Read-only work must remain possible during a registry outage. A present
    # but corrupt managed receipt is still an error: never hide tampering.
    if $read_only { return (runtime-background) }
    let status = (runtime-check)
    if $status.current_satisfies_latest {
        runtime-probe $nu.current-exe $status.current
        print --stderr ("[nushell] Current Nu " + $status.current + " satisfies latest checked stable " + $status.latest + "; no rebuild.")
        return {exe: $nu.current-exe version: $status.current checked: true provider: "current-v1"}
    }
    if not $status.update_required {
        print --stderr ("[nushell] Cargo nu " + $status.latest + " is current; no rebuild.")
        return {exe: $status.managed_executable version: $status.latest checked: true provider: "cargo-v1"}
    }
    {exe: (runtime-install $status.release) version: $status.latest checked: true provider: "cargo-v1"}
}

# Idle scheduler cycles do not query the registry or build. Actual sync is a fresh
# checked invocation. The previous GitHub-managed store is never read or deleted.
export def runtime-background [] {
    if (runtime-fixture-mode) { return {exe: $nu.current-exe version: (version).version checked: false} }
    let root = (runtime-root)
    let file = ($root | path join "current.json")
    if ($file | path exists) {
        let saved = (open --raw $file | from json)
        let release = {version: $saved.version checksum: $saved.crate_sha256}
        let exe = (runtime-cache $root $release)
        if $exe != null { runtime-probe $exe $release.version; return {exe: $exe version: $release.version checked: false provider: "cargo-v1"} }
    }
    if (runtime-version-compare (version).version "0.109.1") >= 0 {
        print --stderr "[nushell] Using the current compatible interpreter for read-only/recovery work. Latest registry version was not checked."
        return {exe: $nu.current-exe version: (version).version checked: false provider: "current-v1"}
    }
    error make {msg: "NU_RUNTIME_TOO_OLD: no prepared compatible runtime. Run scripts/update-nushell.nu --shell; no setup/sync has started."}
}

# Native argv forwarding and streaming output. Never capture this function's
# output as a result record; it terminates this process with the child's status.
export def runtime-execute [script: path args: list --read-only --background --preflight: string = ""] {
    let selected = if $background { runtime-background } else { runtime-ensure --read-only=$read_only }
    let path_items = if ($env.PATH | describe) == "string" {
        $env.PATH | split row (if $nu.os-info.name == "windows" { ";" } else { ":" })
    } else { $env.PATH }
    let exe = $selected.exe
    with-env {
        PATH: ([($exe | path dirname)] | append $path_items)
        INITIAL_SETUP_NU_SESSION_EXE: (if $selected.checked { $exe | into string } else { "" })
        INITIAL_SETUP_NU_SESSION_VERSION: (if $selected.checked { $selected.version } else { "" })
        INITIAL_SETUP_NU_SESSION_PROVIDER: (if $selected.checked { $selected.provider? | default "current-v1" } else { "" })
    } {
        if not ($preflight | is-empty) {
            if not ($preflight | path exists) { error make {msg: "PROJECT_PREFLIGHT_MISSING: restore the complete release."} }
            ^$exe --no-config-file $preflight
            let checked = ($env.LAST_EXIT_CODE | default 1)
            if $checked != 0 { exit $checked }
        }
        if not ($script | path exists) or ($script | path type) != "file" {
            error make {msg: ("SCRIPT_MISSING: " + ($script | into string) + "; check the checkout path and archive extraction.")}
        }
        ^$exe --no-config-file $script ...$args
        exit ($env.LAST_EXIT_CODE | default 1)
    }
}
