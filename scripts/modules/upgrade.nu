const PROCESS_OUTPUT = path self ./process-output.nu
use $PROCESS_OUTPUT [output-text]
const TEXT_CASE = path self ./text-case.nu
use $TEXT_CASE [text-lower]
# A validation sandbox isolates configuration paths; it is NOT a security
# sandbox. Only run candidate code authenticated by a trusted manifest digest
# or an explicitly pinned Git commit.
const SAFETY = path self ./safety.nu
const CORE = path self ./core.nu
use $SAFETY [state-root checked atomic-record tree-files validate-relative private-directory]
use $CORE [error-message]

export def release-files [root: path] {
    mut result = []
    for row in (ls --all $root | sort-by name) {
        if ($row.name | path basename) == ".git" { continue }
        if $row.type == "file" { $result = ($result | append $row.name) } else if $row.type == "dir" {
            $result = ($result | append (tree-files $row.name))
        } else { error make { msg: "Release trees must not contain symlinks or special files." } }
    }
    $result
}

export def release-entries [root: path] {
    release-files $root | where {|file| ($file | path relative-to $root | into string) != "RELEASE-MANIFEST.json" } | each {|file|
        {path: ($file | path relative-to $root | into string | str replace --all '\' '/') sha256: (open --raw $file | hash sha256)}
    } | sort-by path
}

export def write-release-manifest [root: path] {
    let version = (open --raw ($root | path join "VERSION") | into string | str trim)
    let manifest = {format: 1 version: $version files: (release-entries $root)}
    let file = ($root | path join "RELEASE-MANIFEST.json")
    $manifest | to json | save --force $file
    open --raw $file | hash sha256
}

export def verify-release [root: path expected_digest: string] {
    if not ($root | path exists) { error make { msg: "Candidate directory is missing." } }
    let file = ($root | path join "RELEASE-MANIFEST.json")
    if not ($file | path exists) { error make { msg: "Release manifest missing. Unmanifested releases cannot be installed by the safe updater." } }
    if not ($expected_digest | is-empty) {
        if not ($expected_digest =~ '^[a-fA-F0-9]{64}$') or ((open --raw $file | hash sha256) != ($expected_digest | text-lower)) {
            error make { msg: "Release manifest SHA-256 does not match the trusted digest." }
        }
    }
    let manifest = (open --raw $file | from json)
    if ($manifest.format? | default 0) != 1 { error make { msg: "Unsupported release manifest format." } }
    let version = (open --raw ($root | path join "VERSION") | into string | str trim)
    if not ($version =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') or $version != $manifest.version { error make { msg: "Updater requires a matching stable major.minor.patch manifest." } }
    for row in $manifest.files {
        validate-relative $row.path | ignore
        if ($row.path | str starts-with ".git/") or ($row.path | str starts-with ".github/") or $row.path == "RELEASE-MANIFEST.json" {
            error make { msg: "Forbidden path in release manifest." }
        }
        if not ($row.sha256 =~ '^[a-f0-9]{64}$') { error make { msg: "Invalid release file digest." } }
    }
    if (release-entries $root) != ($manifest.files | sort-by path) { error make { msg: "Release file inventory or SHA-256 checks failed; no installed files were replaced." } }
    $manifest
}

export def copy-release [source: path destination: path] {
    mkdir $destination
    for file in (release-files $source) {
        let out = ($destination | path join ($file | path relative-to $source))
        mkdir ($out | path dirname)
        cp $file $out
    }
}

export def validate-candidate [root: path run_dir: path] {
    let sandbox = ($run_dir | path join "validation-home")
    private-directory $sandbox
    let config = ($sandbox | path join "config")
    let data = ($sandbox | path join "data")
    let state = ($sandbox | path join "state")
    mkdir $config $data $state
    with-env {
        INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: ($sandbox | into string)
        HOME: ($sandbox | into string) USERPROFILE: ($sandbox | into string)
        APPDATA: ($sandbox | path join "AppData" "Roaming") LOCALAPPDATA: ($sandbox | path join "AppData" "Local")
        XDG_CACHE_HOME: ($sandbox | path join ".cache")
        XDG_CONFIG_HOME: ($config | into string) XDG_DATA_HOME: ($data | into string) XDG_STATE_HOME: ($state | into string)
    } {
        for args in [
            ["--no-config-file" ($root | path join "scripts" "validate-project.nu")]
            ["--no-config-file" ($root | path join "scripts" "self-test.nu") "--sandbox"]
            ["--no-config-file" ($root | path join "scripts" "security-self-test.nu")]
        ] {
            let nu_exe = $nu.current-exe
            let result = (do { ^$nu_exe ...$args } | complete)
            let logfile = ($run_dir | path join "validation.log")
            let text = ("=== " + ($args.1 | path basename) + " ===\n" + ($result.stdout | output-text) + "\n" + ($result.stderr | output-text) + "\n")
            if ($logfile | path exists) { $text | save --append $logfile } else { $text | save $logfile }
            if $result.exit_code != 0 {
                error make {msg: ("Candidate validation failed. Isolated test diagnostics: " + ($logfile | into string))}
            }
        }
    }
}

export def promote-files [installed: path candidate: path old: record new: record] {
    let previous_paths = ($old.files | get path | append "RELEASE-MANIFEST.json")
    let new_paths = ($new.files | get path | append "RELEASE-MANIFEST.json")
    for rel in $new_paths {
        let dest = ($installed | path join $rel)
        mkdir ($dest | path dirname)
        let tmp = (($dest | into string) + ".update-" + (random uuid))
        try {
            cp ($candidate | path join $rel) $tmp
            mv --force $tmp $dest
        } catch {|err|
            if ($tmp | path exists) { rm --force $tmp }
            error make {msg: (error-message $err "Upgrade helper failed.")}
        }
    }
    for rel in $previous_paths {
        if not ($rel in $new_paths) {
            let dest = ($installed | path join $rel)
            if ($dest | path exists) { rm --force $dest }
        }
    }
}

export def rollback-files [installed: path previous: path candidate: path] {
    let old = (verify-release $previous "")
    let new = (verify-release $candidate "")
    let paths = ($old.files | get path | append ($new.files | get path) | append "RELEASE-MANIFEST.json" | uniq)
    # Do not erase an edit made by a user/editor after promotion started.
    for rel in $paths {
        let dest = ($installed | path join $rel)
        if not ($dest | path exists) { continue }
        let hash = (open --raw $dest | hash sha256)
        mut allowed = []
        for root in [$previous $candidate] {
            let file = ($root | path join $rel)
            if ($file | path exists) { $allowed = ($allowed | append (open --raw $file | hash sha256)) }
        }
        if not ($hash in $allowed) { error make { msg: "Rollback stopped to preserve a post-update local edit. Previous release is retained in the upgrade directory." } }
    }
    promote-files $installed $previous $new $old
    verify-release $installed "" | ignore
}
