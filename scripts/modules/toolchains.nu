const PROCESS_OUTPUT = path self ./process-output.nu
use $PROCESS_OUTPUT [output-text]
# Toolchain desired-state lock and drift helpers.

const TOOLS_ROOT = path self ../..
const LOCK_FILE = path self ../../toolchains/lock.nuon

export def toolchain-lock-path [] { $LOCK_FILE }

export def load-toolchain-lock [] {
    if not ($LOCK_FILE | path exists) {
        error make { msg: ("Toolchain lock not found: " + ($LOCK_FILE | into string)) }
    }
    open $LOCK_FILE
}

# Split command output on whitespace, not natural-language punctuation.
# These pure parsers are also used by regression-test.nu; no installed tools
# are needed to test empty output, prereleases or named/default channels.
def whitespace-fields [value: string] {
    let trimmed = ($value | str trim)
    if ($trimmed | is-empty) { [] } else { $trimmed | split row --regex '\s+' }
}

export def parse-tool-version [program: string output: string] {
    let rows = ($output | lines | where {|line| not ($line | str trim | is-empty) })
    if ($rows | is-empty) { return "" }
    let fields = (whitespace-fields ($rows | first))
    let candidate = (
        if $program == "rustc" and ($fields | length) >= 2 and $fields.0 == "rustc" { $fields.1 }
        else if $program == "julia" and ($fields | length) >= 3 and $fields.0 == "julia" and $fields.1 == "version" { $fields.2 }
        else { "" }
    )
    if $candidate =~ '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$' { $candidate } else { "" }
}

export def parse-rust-channel [output: string] {
    let fields = (whitespace-fields $output)
    if ($fields | is-empty) { return "" }
    # Preserve dated nightly channels and exact versions; remove host triples.
    let parsed = ($fields.0 | parse --regex '^(?P<channel>(?:stable|beta|nightly)(?:-[0-9]{4}-[0-9]{2}-[0-9]{2})?|[0-9]+\.[0-9]+\.[0-9]+(?:-(?:beta|nightly|rc)[0-9.]*)?)(?:-|$)')
    if ($parsed | is-empty) { "" } else { $parsed.0.channel }
}

export def parse-julia-channel [output: string] {
    let parsed = ($output | lines | parse --regex '^\s*\*\s+(?P<channel>\S+)')
    if ($parsed | is-empty) { "" } else { $parsed.0.channel }
}

def command-output [program: string args: list] {
    if (which $program | is-empty) { return "" }
    let result = (do { ^$program ...$args } | complete)
    if $result.exit_code != 0 { return "" }
    $result.stdout? | default ""
}

export def current-toolchain-versions [] {
    {
        rust: (parse-tool-version "rustc" (command-output "rustc" ["--version"]))
        rust_channel: (parse-rust-channel (command-output "rustup" ["show" "active-toolchain"]))
        julia: (parse-tool-version "julia" (command-output "julia" ["--version"]))
        julia_channel: (parse-julia-channel (command-output "juliaup" ["status"]))
        nushell: ($env.NU_VERSION? | default "")
    }
}

def numeric-part [value: string index: int] {
    let pieces = ($value | split row ".")
    if $index >= ($pieces | length) { return 0 }
    let raw = ($pieces | get $index | split row "-" | first)
    try { $raw | into int } catch { 0 }
}

export def version-gte [actual: string required: string] {
    if ($actual | is-empty) { return false }
    let a0 = (numeric-part $actual 0)
    let r0 = (numeric-part $required 0)
    if $a0 != $r0 { return ($a0 > $r0) }
    let a1 = (numeric-part $actual 1)
    let r1 = (numeric-part $required 1)
    if $a1 != $r1 { return ($a1 > $r1) }
    (numeric-part $actual 2) >= (numeric-part $required 2)
}

def one-status [name: string spec: record actual: string active_channel: string = ""] {
    let mode = ($spec.mode? | default "exact")
    let desired = ($spec.value? | default "")
    let present = (not ($actual | is-empty))
    let ok = (
        if not $present { false }
        else if $mode == "minimum" { version-gte $actual $desired }
        else if $mode == "exact" { $actual == $desired }
        else if $mode == "channel" { (not ($active_channel | is-empty)) and $active_channel == $desired }
        else { false }
    )
    {
        name: $name
        mode: $mode
        desired: $desired
        actual: $actual
        channel: $active_channel
        status: (if not $present { "missing" } else if $ok { "ok" } else { "drift" })
    }
}

export def toolchain-status [] {
    let lock = (load-toolchain-lock)
    let current = (current-toolchain-versions)
    [
        (one-status "rust" ($lock.rust? | default {}) $current.rust $current.rust_channel)
        (one-status "julia" ($lock.julia? | default {}) $current.julia $current.julia_channel)
        (one-status "nushell" ($lock.nushell? | default {}) $current.nushell)
    ]
}

export def write-current-lock [] {
    let current = (current-toolchain-versions)
    let existing = (load-toolchain-lock)
    let rust_spec = (if ($current.rust | is-empty) { $existing.rust? | default { mode: "channel" value: "stable" } } else { { mode: "exact" value: $current.rust } })
    let julia_spec = (if ($current.julia | is-empty) { $existing.julia? | default { mode: "channel" value: "release" } } else { { mode: "exact" value: $current.julia } })
    let nu_spec = (if ($current.nushell | is-empty) { $existing.nushell? | default { mode: "minimum" value: "0.109.1" } } else { { mode: "exact" value: $current.nushell } })
    {
        version: 1
        rust: $rust_spec
        julia: $julia_spec
        nushell: $nu_spec
    } | to nuon | save --force $LOCK_FILE
    $LOCK_FILE
}

def require-toolchain-command [program: string args: list label: string] {
    let result = (do { ^$program ...$args } | complete)
    if $result.exit_code != 0 {
        let details = ($result.stderr? | output-text | str trim)
        error make { msg: ($label + " failed (exit " + ($result.exit_code | into string) + "). " + $details) }
    }
    let output = ($result.stdout? | output-text | str trim)
    if not ($output | is-empty) { print $output }
}

export def apply-toolchain-lock [] {
    let lock = (load-toolchain-lock)
    let statuses = (toolchain-status)
    let rust_status = ($statuses | where name == "rust" | first)
    let julia_status = ($statuses | where name == "julia" | first)

    # Missing optional managers are not installed here. Preserve profile policy.
    if $rust_status.status != "ok" and not (which rustup | is-empty) {
        let rust = ($lock.rust? | default {})
        let rust_mode = ($rust.mode? | default "channel")
        let rust_value = ($rust.value? | default "stable")
        if $rust_mode in ["channel" "exact"] {
            require-toolchain-command "rustup" ["toolchain" "install" $rust_value] "Install Rust toolchain"
            require-toolchain-command "rustup" ["default" $rust_value] "Set Rust default"
        }
    }

    if $julia_status.status != "ok" and not (which juliaup | is-empty) {
        let julia = ($lock.julia? | default {})
        let julia_mode = ($julia.mode? | default "channel")
        let julia_value = ($julia.value? | default "release")
        if $julia_mode in ["channel" "exact"] {
            require-toolchain-command "juliaup" ["add" $julia_value] "Install Julia channel"
            require-toolchain-command "juliaup" ["default" $julia_value] "Set Julia default"
        }
    }
}
