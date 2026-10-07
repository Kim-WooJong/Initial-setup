#!/usr/bin/env nu
# Command shim regression: commands installed once run from the checkout, so
# checkout edits apply without refresh; signature changes are reported.
# Works on a temporary copy of this checkout in an isolated HOME.
const ROOT = path self ..

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[command-shim-test] " + $message)} }
    print ("[pass] " + $message)
}

def call [home: path line: string] {
    let shim = ($home | path join ".config" "nushell" "modules" "dotfiles.nu")
    with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $home HOME: $home USERPROFILE: $home} {
        do { ^$nu.current-exe --no-config-file -c ("use " + ($shim | to nuon) + " *\n" + $line) } | complete
    }
}

def refresh [home: path checkout: path] {
    with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $home HOME: $home USERPROFILE: $home} {
        do { ^$nu.current-exe --no-config-file ($checkout | path join "scripts" "refresh-commands.nu") } | complete
    }
}

def tests [base: path] {
    let checkout = ($base | path join "checkout")
    let home = ($base | path join "home")
    mkdir $checkout ($home | path join ".config" "dotfiles")
    for entry in (ls --all $ROOT | where {|e| ($e.name | path basename) not-in [".git" "target"] }) {
        cp --recursive $entry.name $checkout
    }
    {schema_version: 5 tools_root: "old-checkout" data_root: ($base | path join "private")} | to nuon | save ($home | path join ".config" "dotfiles" "config.nuon")

    let r = (refresh $home $checkout)
    if $r.exit_code != 0 { print --stderr $r.stderr }
    check ($r.exit_code == 0) "refresh-commands installs the shim and binds tools_root"
    let shim_text = (open --raw ($home | path join ".config" "nushell" "modules" "dotfiles.nu"))
    check (not ($shim_text =~ '(?m)^\s*(use|source|source-env|overlay)\s')) "Installed shim imports no other module"

    let r = (call $home "dotversion")
    check ($r.exit_code == 0 and ($r.stdout | str contains "Initial-setup")) "Command runs through the shim"
    check (not ($r.stderr | str contains "[warn]")) "Fresh shim reports no staleness"

    # Body edit in the checkout: applies immediately, no refresh, no warning.
    let module = ($checkout | path join "scripts" "modules" "dotfiles.nu")
    let original = (open --raw $module)
    let marker = "export def dotversion [] {\n"
    check ($original | str contains $marker) "Fixture marker exists in dotfiles.nu"
    $original | str replace $marker ($marker + "    print \"edited-module-body\"\n") | save --force --raw $module
    let r = (call $home "dotversion")
    check ($r.exit_code == 0 and ($r.stdout | str contains "edited-module-body")) "Checkout module edit applies without refresh"
    check (not ($r.stderr | str contains "[warn]")) "Body-only edit does not mark the shim outdated"

    # New command: reported as outdated until refresh, then callable.
    ((open --raw $module) + "\n# Shim test command.\nexport def dotshimprobe [--times: int = 1] { print ('probe:' + ($times * 2 | into string)) }\n") | save --force --raw $module
    let r = (call $home "dotversion")
    check ($r.exit_code == 0 and ($r.stderr | str contains "refresh-commands.nu")) "Signature change prints a refresh hint"
    let r = (refresh $home $checkout)
    check ($r.exit_code == 0) "Refresh after a signature change succeeds"
    let r = (call $home "dotshimprobe --times 21")
    check ($r.exit_code == 0 and ($r.stdout | str contains "probe:42")) "New command with an int flag works after refresh"
    check (not ($r.stderr | str contains "[warn]")) "Refreshed shim reports no staleness"

    # Failures propagate; values are data, not code.
    let r = (call $home "dotshimprobe --nope")
    check ($r.exit_code != 0 and ($r.stderr | str contains "Unknown flag")) "Unknown flag fails with a clear message"
    let r = (call $home "dotshimprobe --times '1; exit 0'")
    check ($r.exit_code != 0 and ($r.stderr | str contains "expects an integer")) "Non-integer value is rejected, not evaluated"
    check ($shim_text | str contains '("--reload" in $args)') "dotpull --reload is handled in the user's shell"

    rm ($checkout | path join "scripts" "dotcmd.nu")
    let r = (call $home "dotversion")
    check ($r.exit_code != 0 and ($r.stderr | str contains "has no scripts/dotcmd.nu")) "Missing runner gives a checkout hint"
}

def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-shim-" + (random uuid)))
    mkdir $base
    try { tests $base } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
    print "[ok] Command shim regressions passed."
}
