# Install / update the RPool binary from its public GitHub releases.
#
# Source of truth: https://github.com/Kim-WooJong/RPool/releases (public, no
# token). The binary is installed to ~/.cargo/bin, which resolve-rpool-executable
# finds directly (no PATH edit) and which is machine-local — never the
# cloud-synced Initial-setup checkout. No background/auto update: this runs only
# when invoked. Downloads are checksum-verified against SHA256SUMS.txt before
# anything on disk is replaced.
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
const SUBPROCESS = path self ./subprocess.nu
const CONSOLE = path self ./console.nu
const TEXT_CASE = path self ./text-case.nu
use $CORE [nu-home error-message]
use $SAFETY [state-root checked private-directory]
use $SUBPROCESS [run-command]
use $CONSOLE [print-status print-warn print-key-value]
use $TEXT_CASE [text-lower]

const OWNER_REPO = "Kim-WooJong/RPool"
def api-base [] { "https://api.github.com/repos/" + $OWNER_REPO }
def dl-base [] { "https://github.com/" + $OWNER_REPO + "/releases/download" }
def ua-headers [] { ["User-Agent" "initial-setup-rpool-install" "Accept" "application/vnd.github+json"] }

# --- pure helpers (unit-testable) ---

# Choose the release asset for an OS/arch, or error for an unsupported platform.
export def select-asset [os: string arch: string] {
    let a = (match $arch { "aarch64" => "arm64", "arm64" => "arm64", "x86_64" => "x86_64", "amd64" => "x86_64", _ => "" })
    let plat = (match $os {
        "macos" => (if $a in ["arm64" "x86_64"] { "macos-" + $a } else { "" }),
        "linux" => (if $a == "x86_64" { "linux-x86_64" } else { "" }),
        "windows" => (if $a == "x86_64" { "windows-x86_64" } else { "" }),
        _ => ""
    })
    if ($plat | is-empty) {
        error make {msg: ("RPool has no prebuilt release for this platform (" + $os + "/" + $arch + "). Supported: macOS arm64/x86_64, Linux x86_64, Windows x86_64.")}
    }
    let win = ($os == "windows")
    {platform: $plat ext: (if $win { "zip" } else { "tar.gz" }) exe: (if $win { "rpool.exe" } else { "rpool" }) gui: (if $win { "rpool-gui.exe" } else { "rpool-gui" })}
}

export def asset-filename [tag: string platform: string ext: string] { "rpool-" + $tag + "-" + $platform + "." + $ext }
export def version-from-tag [tag: string] { $tag | str replace --regex '^v' '' }

# SHA-256 hex for one asset from a SHA256SUMS.txt body ("<hash>  <name>").
export def sha-for [sums_text: string asset: string] {
    let rows = ($sums_text | lines | each {|l| $l | str trim } | where {|l| not ($l | is-empty) }
        | each {|l| $l | parse --regex '^(?<hash>[0-9a-fA-F]{64})\s+\*?(?<name>.+)$' } | flatten
        | where {|r| ($r.name | str trim) == $asset })
    if ($rows | is-empty) { error make {msg: ("SHA256SUMS.txt has no entry for " + $asset)} }
    ($rows | first | get hash | text-lower)
}

# Verify an archive against a SHA256SUMS body; error (changing nothing) on
# mismatch or a missing entry. Returns the verified hash.
export def assert-archive-checksum [archive: path sums_text: string asset: string] {
    let expected = (sha-for $sums_text $asset)
    let actual = (open --raw $archive | hash sha256)
    if $actual != $expected {
        error make {msg: ("Checksum mismatch for " + $asset + " (expected " + $expected + ", got " + $actual + "). Nothing was installed.")}
    }
    $actual
}

# --- runtime ---

def target-platform [] { select-asset $nu.os-info.name $nu.os-info.arch }
export def install-dir [] { (nu-home) | path join ".cargo" "bin" }

def gh-message [err: any url: string] {
    let m = ($err.msg? | default ($err | into string))
    if ($m | str contains "403") or ($m | str contains "rate limit") {
        "GitHub refused the request, likely the anonymous rate limit (60/hour): " + $url + ". Wait and retry later."
    } else {
        "Network request to GitHub failed: " + $url + " (" + $m + ")"
    }
}

def http-json [url: string] {
    try { http get --headers (ua-headers) $url } catch {|err| error make {msg: (gh-message $err $url)} }
}

def download-to [url: string dest: path] {
    try { http get --headers (ua-headers) --raw $url | save --force --raw $dest } catch {|err| error make {msg: (gh-message $err $url)} }
}

# Resolve the requested version (default: latest) to a concrete tag that exists.
export def resolve-tag [requested: string] {
    if ($requested | str trim | is-empty) {
        let tag = (http-json ((api-base) + "/releases/latest") | get tag_name)
        if ($tag | is-empty) { error make {msg: "GitHub returned no latest release tag for RPool."} }
        $tag
    } else {
        let tag = (if ($requested | str starts-with "v") { $requested } else { "v" + $requested })
        if not ($tag =~ '^v[0-9]+\.[0-9]+\.[0-9]+$') { error make {msg: ("Invalid --version: " + $requested + ". Use vX.Y.Z.")} }
        http-json ((api-base) + "/releases/tags/" + $tag) | ignore
        $tag
    }
}

# Version string reported by an installed rpool executable, or null.
export def installed-version [exe_path: path] {
    if not ($exe_path | path exists) or (($exe_path | path type) != "file") { return null }
    let r = (run-command ($exe_path | into string) ["--version"])
    if not $r.ok { return null }
    let parsed = ($r.stdout | lines | each {|l| $l | parse --regex 'rpool\s+(?<v>[0-9][0-9A-Za-z.\-]*)' } | flatten)
    if ($parsed | is-empty) { null } else { ($parsed | first | get v) }
}

def rpool-running [] {
    if $nu.os-info.name == "windows" { return false }
    if (which pgrep | is-empty) { return false }
    let names = ["rpool" "rpool-gui"]
    ($names | any {|n| let r = (run-command "pgrep" ["-x" $n]); $r.ok and not (($r.stdout | str trim) | is-empty) })
}

def extract-archive [archive: path dest: path ext: string] {
    mkdir $dest
    if $ext == "zip" {
        if $nu.os-info.name == "windows" {
            checked "powershell.exe" ["-NoProfile" "-NonInteractive" "-Command" ("Expand-Archive -LiteralPath " + ($archive | into string | to nuon) + " -DestinationPath " + ($dest | into string | to nuon) + " -Force")] "Extract RPool archive" | ignore
        } else {
            if (which unzip | is-empty) { error make {msg: "unzip is required to extract the RPool archive."} }
            checked "unzip" ["-q" "-o" ($archive | into string) "-d" ($dest | into string)] "Extract RPool archive" | ignore
        }
    } else {
        checked "tar" ["-xzf" ($archive | into string) "-C" ($dest | into string)] "Extract RPool archive" | ignore
    }
}

# Locate a binary by basename within the extracted tree (top folder first).
def find-binary [root: path inner: string name: string] {
    let direct = ($root | path join $inner | path join $name)
    if ($direct | path exists) { return $direct }
    let hits = (try { ls ($root | path join "**" $name) | get name } catch { [] })
    if ($hits | is-empty) { null } else { $hits | first }
}

# Atomically place one binary into the install dir, backing up any existing one.
def place-binary [src: path dest: path] {
    let parent = ($dest | path dirname)
    mkdir $parent
    if ($dest | path exists) {
        cp --force $dest (($dest | into string) + ".prev")
    }
    let tmp = (($dest | into string) + ".new-" + (random uuid))
    cp $src $tmp
    if $nu.os-info.name != "windows" { checked "chmod" ["+x" $tmp] "Mark RPool executable" | ignore }
    try {
        mv --force $tmp $dest
    } catch {|err|
        if ($tmp | path exists) { rm --force $tmp }
        error make {msg: (error-message $err ("Could not replace " + ($dest | into string) + ". If RPool is running or a drive is mounted, unmount it first (dotrpool/rpool mount ... then unmount), then retry."))}
    }
    # macOS: remove the quarantine attribute so the unsigned binary can run.
    if $nu.os-info.name == "macos" {
        run-command "xattr" ["-dr" "com.apple.quarantine" ($dest | into string)] | ignore
    }
}

# Compare installed vs target without changing anything.
export def rpool-install-check [requested: string] {
    let plat = (target-platform)
    let tag = (resolve-tag $requested)
    let target = (version-from-tag $tag)
    let dest = ((install-dir) | path join $plat.exe)
    let current = (installed-version $dest)
    {platform: $plat.platform target_version: $target installed_version: $current install_path: ($dest | into string) up_to_date: ($current == $target)}
}

export def install-rpool [requested: string --check] {
    let plat = (target-platform)
    print-status "info" "rpool" ("Platform: " + $plat.platform)
    let tag = (resolve-tag $requested)
    let target = (version-from-tag $tag)
    let dest_dir = (install-dir)
    let exe_dest = ($dest_dir | path join $plat.exe)
    let current = (installed-version $exe_dest)
    print-key-value "Installed version" ($current | default "none")
    print-key-value "Target version   " $target

    if $current == $target {
        print-status "ok" "rpool" ("RPool " + $target + " is already installed at " + ($exe_dest | into string) + "; nothing to do.")
        return {status: "up-to-date" version: $target path: ($exe_dest | into string)}
    }
    if $check {
        print-status "info" "rpool" ("Update available: " + ($current | default "none") + " -> " + $target + ". Run `rpool-install` to install it.")
        return {status: "update-available" installed: $current target: $target}
    }
    if (rpool-running) {
        error make {msg: "RPool appears to be running (rpool/rpool-gui process found). Unmount/stop it first, then retry so its executable is not replaced while in use."}
    }

    let asset = (asset-filename $tag $plat.platform $plat.ext)
    let stage = ((state-root) | path join "rpool-install" (random uuid))
    let result = (try {
        private-directory $stage
        let archive = ($stage | path join $asset)
        print-status "info" "rpool" ("Downloading " + $asset + " ...")
        download-to ((dl-base) + "/" + $tag + "/" + $asset) $archive
        let sums = (try { http get --headers (ua-headers) --raw ((dl-base) + "/" + $tag + "/SHA256SUMS.txt") } catch {|err| error make {msg: (gh-message $err "SHA256SUMS.txt")} })
        assert-archive-checksum $archive ($sums | decode utf-8) $asset | ignore
        print-status "ok" "rpool" "Checksum verified."
        let unpacked = ($stage | path join "unpacked")
        extract-archive $archive $unpacked $plat.ext
        let inner = ("rpool-" + $tag + "-" + $plat.platform)
        let exe_src = (find-binary $unpacked $inner $plat.exe)
        if $exe_src == null { error make {msg: ("The RPool archive did not contain " + $plat.exe + ".")} }
        place-binary $exe_src $exe_dest
        # rpool-gui is optional and slated for removal; install it if present.
        let gui_src = (find-binary $unpacked $inner $plat.gui)
        if $gui_src != null { place-binary $gui_src ($dest_dir | path join $plat.gui) }

        let got = (installed-version $exe_dest)
        if $got != $target {
            let prev = (($exe_dest | into string) + ".prev")
            if ($prev | path exists) { cp --force $prev $exe_dest }
            error make {msg: ("Installed RPool reports version " + ($got | default "unknown") + ", expected " + $target + ". Previous binary was restored.")}
        }
        {status: "installed" version: $target path: ($exe_dest | into string) gui: ($gui_src != null)}
    } catch {|err| {status: null error: ($err.msg? | default "RPool install failed." | into string)} })

    if ($stage | path exists) { try { rm --recursive --force $stage } catch { } }
    # An error value also describes as a record, so detect success by `status`.
    if (($result.status? | default null) == null) {
        error make {msg: ($result.error? | default "RPool install failed." | into string)}
    }

    print-status "ok" "rpool" ("Installed RPool " + $target + " -> " + ($result.path))
    if (which rclone | is-empty) {
        print-warn "rclone was not found. RPool needs rclone at runtime; install it (dotctl config rclone / your package manager)."
    }
    if $nu.os-info.name == "windows" {
        print-status "info" "rpool" "Windows native drives need WinFsp; without it RPool falls back to WebDAV. Install WinFsp separately if you want native mounts."
    }
    $result
}
