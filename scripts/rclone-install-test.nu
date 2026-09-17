#!/usr/bin/env nu
# Offline dependency regressions. Every installer execution is a mock callback;
# no package manager, rclone remote, sudo, or host credential is invoked.
const MODULE = path self ./modules/rclone-install.nu
use $MODULE [rclone-install-plan perform-rclone-install merge-rclone-path check-rclone-winget-state]

def expect [condition: bool message: string] {
    if not $condition { error make {msg: ("FAILED: " + $message)} }
    print ("[pass] " + $message)
}

def expect-error [action: closure text: string] {
    let err = (try { do $action | ignore; null } catch {|e| $e })
    expect ($err != null) ("Rejected: " + $text)
    expect (($err.msg? | default "") | str contains $text) ("Diagnostic: " + $text)
}

def selector-tests [] {
    let win = (rclone-install-plan "windows" ["winget"] false)
    expect ($win.supported and $win.manager == "winget") "Windows selects WinGet"
    expect (($win.steps | first | get kind) == "winget-state") "WinGet registration is checked before installation"
    let win_args = ($win.steps | last | get args)
    expect (("Rclone.Rclone" in $win_args) and ("--exact" in $win_args) and ("--no-upgrade" in $win_args)) "WinGet uses an exact ID and forbids upgrades"
    let mac = (rclone-install-plan "macos" ["brew"] false)
    expect (($mac.steps | first | get args) == ["install" "rclone"]) "macOS selects the Homebrew formula"
    for row in [
        {manager: "apt-get" args: ["install" "-y" "rclone"] count: 2}
        {manager: "dnf" args: ["install" "-y" "rclone"] count: 1}
        {manager: "pacman" args: ["-S" "--needed" "--noconfirm" "rclone"] count: 1}
        {manager: "zypper" args: ["--non-interactive" "install" "rclone"] count: 1}
        {manager: "apk" args: ["add" "--no-cache" "rclone"] count: 1}
    ] {
        let normal = (rclone-install-plan "linux" [$row.manager "sudo"] false)
        let step = ($normal.steps | last)
        expect ($step.program == "sudo" and $step.args == ([$row.manager] | append $row.args)) ("Non-root command: " + $row.manager)
        expect (($normal.steps | length) == $row.count) ("Step count: " + $row.manager)
        let root_plan = (rclone-install-plan "linux" [$row.manager] true)
        expect (($root_plan.steps | last | get program) == $row.manager) ("Root needs no sudo: " + $row.manager)
    }
    let apt = (rclone-install-plan "linux" ["apt-get" "sudo"] false)
    expect (($apt.steps | first | get args) == ["apt-get" "update"]) "APT refreshes its package index before first installation"
    let no_sudo = (rclone-install-plan "linux" ["apt-get"] false)
    expect (not $no_sudo.supported) "Missing sudo blocks a non-root system install"
    for os in ["windows" "macos" "linux" "freebsd"] {
        let unavailable = (rclone-install-plan $os [] false)
        expect (not $unavailable.supported) ("No installer fallback for unsupported/missing manager: " + $os)
    }
    let merged = (merge-rclone-path ["C:\\custom bin" "C:\\Windows"] ["" "C:\\Windows" "C:\\Program Files\\WinGet\\Links"])
    expect ($merged == ["C:\\custom bin" "C:\\Windows" "C:\\Program Files\\WinGet\\Links"]) "PATH precedence, spaces and deduplication are preserved"
    for code in [-1978335212 2316632084] {
        expect (check-rclone-winget-state $code "localized no-match message") "Signed/unsigned no-applications HRESULT is recognized"
    }
    expect-error {|| check-rclone-winget-state 0 "Rclone Rclone.Rclone 1.70.0 winget" } "already installed"
    expect-error {|| check-rclone-winget-state 1 "Rclone.Rclone network failure" } "Could not determine"
    expect-error {|| check-rclone-winget-state 0 "unrecognized table" } "Could not determine"
}

def lifecycle-tests [sandbox: path] {
    let missing = {found: false ready: false path: "" version: ""}
    let present = {found: true ready: true path: "fixture/rclone" version: "rclone v1.70.0"}
    let broken = {found: true ready: false path: "fixture/rclone" version: ""}
    let cannot_run = {|step| error make {msg: "A read-only/present path invoked an installer"} }
    let plan = (rclone-install-plan "linux" ["apt-get"] true)
    let unsupported = (rclone-install-plan "linux" [] false)

    let ready = (perform-rclone-install $unsupported $cannot_run {|| $present })
    expect ($ready.state == "present") "Existing working rclone skips installation even without a package manager"
    let preview = (perform-rclone-install $plan $cannot_run {|| $missing } --dry-run)
    expect ($preview.state == "planned") "Dry-run never invokes the executor"
    let blocked_preview = (perform-rclone-install $unsupported $cannot_run {|| $missing } --dry-run)
    expect (not $blocked_preview.supported) "Dry-run explains missing package manager without installing"
    expect-error {|| perform-rclone-install $plan $cannot_run {|| $missing } --check } "not available"
    expect-error {|| perform-rclone-install $plan $cannot_run {|| $broken } } "will not be replaced"
    expect-error {|| perform-rclone-install $unsupported $cannot_run {|| $missing } } "Supported package managers"

    let marker = ($sandbox | path join "installed.fixture")
    let trace = ($sandbox | path join "steps.nuon")
    [] | to nuon | save $trace
    let probe = {|| if ($marker | path exists) { $present } else { $missing } }
    let execute = {|step|
        let old = (open $trace)
        $old | append $step.label | to nuon | save --force $trace
        if ("rclone" in $step.args) { "fixture-only" | save --force $marker }
        {exit_code: 0 stderr: ""}
    }
    let installed = (perform-rclone-install $plan $execute $probe)
    expect ($installed.state == "installed") "Missing -> package installation -> successful version probe"
    expect ((open $trace | length) == 2) "Both APT steps run exactly once"
    let again = (perform-rclone-install $plan $cannot_run $probe)
    expect ($again.state == "present") "Second invocation is idempotent"

    rm $marker
    [] | to nuon | save --force $trace
    let failing = {|step|
        let old = (open $trace)
        $old | append $step.label | to nuon | save --force $trace
        {exit_code: 42 stderr: "injected-download-failure"}
    }
    expect-error {|| perform-rclone-install $plan $failing {|| $missing } } "injected-download-failure"
    expect ((open $trace | length) == 1) "Failed index update stops before installation (no fallback)"
    let no_binary = {|step| {exit_code: 0 stderr: ""} }
    expect-error {|| perform-rclone-install $plan $no_binary {|| $missing } } "still failed or rclone is not on PATH"
    print "[pass] Package-manager success alone is not an installation success"
}

def main [--keep] {
    selector-tests
    let base = ($env.TEMP? | default ($env.TMPDIR? | default "/tmp") | path expand)
    let sandbox = ($base | path join ("initial-setup-rclone-test-" + (random uuid)))
    mkdir $sandbox
    try {
        lifecycle-tests $sandbox
        if $keep { print ("[kept] " + ($sandbox | into string)) } else { rm --recursive --force $sandbox }
    } catch {|err|
        print ("[kept] Failed mocked installer test: " + ($sandbox | into string))
        error make {msg: $err.msg}
    }
    print "[ok] rclone installer mocked regressions passed; no real package manager was invoked."
}
