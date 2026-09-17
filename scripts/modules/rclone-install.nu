const PROCESS_OUTPUT = path self ./process-output.nu
use $PROCESS_OUTPUT [output-text]
# rclone is a setup dependency, separate from optional configuration capture.
# Install only through an existing package manager. Never fetch/run shell scripts,
# change remote credentials, install mount drivers, or upgrade a working binary.
const CORE = path self ./core.nu
use $CORE [nu-home]

# Pure selector: usable from offline regression tests on every host OS.
export def rclone-install-plan [os: string commands: list is_root: bool] {
    if $os == "windows" and "winget" in $commands {
        return {
            manager: "winget" supported: true reason: ""
            steps: [
                {kind: "winget-state" program: "winget" args: [] label: "Check Rclone.Rclone registration"}
                {kind: "command" program: "winget" args: ["install" "--id" "Rclone.Rclone" "--exact" "--source" "winget" "--no-upgrade" "--accept-package-agreements" "--accept-source-agreements"] label: "Install rclone with WinGet"}
            ]
        }
    }
    if $os == "macos" and "brew" in $commands {
        return {
            manager: "brew" supported: true reason: ""
            steps: [{kind: "command" program: "brew" args: ["install" "rclone"] label: "Install rclone with Homebrew"}]
        }
    }
    if $os == "linux" {
        let managers = (["apt-get" "dnf" "pacman" "zypper" "apk"] | where {|name| $name in $commands })
        if not ($managers | is-empty) {
            let manager = ($managers | first)
            if not $is_root and not ("sudo" in $commands) {
                return {manager: $manager supported: false reason: "rclone is missing; root privileges or sudo are required for the available Linux package manager." steps: []}
            }
            let operations = (match $manager {
                "apt-get" => { [["update"] ["install" "-y" "rclone"]] }
                "dnf" => { [["install" "-y" "rclone"]] }
                "pacman" => { [["-S" "--needed" "--noconfirm" "rclone"]] }
                "zypper" => { [["--non-interactive" "install" "rclone"]] }
                "apk" => { [["add" "--no-cache" "rclone"]] }
            })
            let steps = ($operations | each {|args|
                {
                    kind: "command"
                    program: (if $is_root { $manager } else { "sudo" })
                    args: (if $is_root { $args } else { [$manager] | append $args })
                    label: (if $args == ["update"] { "Refresh apt package index" } else { "Install rclone with " + $manager })
                }
            })
            return {manager: $manager supported: true reason: "" steps: $steps}
        }
    }
    let reason = (match $os {
        "windows" => { "rclone is missing and WinGet is unavailable. Install/repair Microsoft App Installer, or install rclone manually, then rerun setup." }
        "macos" => { "rclone is missing and Homebrew is unavailable. Run bootstrap.sh, prepare Homebrew, or install the official rclone binary, then rerun setup." }
        "linux" => { "rclone is missing. Supported package managers: apt-get, dnf, pacman, zypper, apk. Install rclone manually on this distribution, then rerun setup." }
        _ => { "Automatic rclone installation is not supported on this OS. Install rclone manually and put it on PATH." }
    })
    {manager: "" supported: false reason: $reason steps: []}
}

# Preserve process PATH precedence; do not replace custom paths with registry data.
export def merge-rclone-path [current: list extra: list] {
    $current | append ($extra | where {|entry| not ($entry | str trim | is-empty) }) | uniq
}

def registered-windows-path [] {
    # Never consult the real registry from an isolated test HOME.
    if ($env.INITIAL_SETUP_TEST_MODE? | default "") == "1" { return [] }
    let shells = (["pwsh" "powershell"] | where {|name| not (which ("^" + $name) | is-empty) })
    if ($shells | is-empty) { return [] }
    let shell = ($shells | first)
    let script = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); $paths = @(); foreach ($scope in @("Machine", "User")) { $value = [Environment]::GetEnvironmentVariable("Path", $scope); if ($value) { foreach ($part in ($value -split ";")) { if ($part) { $paths += [Environment]::ExpandEnvironmentVariables($part) } } } }; ConvertTo-Json -Compress -InputObject @($paths)'
    let result = (try { do { ^$shell -NoLogo -NoProfile -NonInteractive -Command $script } | complete } catch { {exit_code: 1 stdout: ""} })
    if $result.exit_code != 0 { return [] }
    try { $result.stdout | from json } catch { [] }
}

export def --env refresh-rclone-path [] {
    let raw = ($env.PATH? | default [])
    let current = (if ($raw | describe) == "string" { $raw | split row (if $nu.os-info.name == "windows" { ";" } else { ":" }) } else { $raw })
    let home = (nu-home)
    let known = (match $nu.os-info.name {
        "windows" => {
            let local = ($env.LOCALAPPDATA? | default ($home | path join "AppData" "Local"))
            let program_files = ($env.ProgramFiles? | default "C:\\Program Files")
            [($local | path join "Microsoft" "WinGet" "Links") ($program_files | path join "WinGet" "Links")]
        }
        "macos" => {
            let prefix = ($env.HOMEBREW_PREFIX? | default "/opt/homebrew")
            [($prefix | path join "bin") ($prefix | path join "opt" "rclone" "bin") "/opt/homebrew/bin" "/usr/local/bin" "/usr/local/opt/rclone/bin" ($home | path join ".local" "bin")]
        }
        _ => { [($home | path join ".local" "bin") "/usr/local/bin" "/usr/bin" "/bin"] }
    })
    let registered = (if $nu.os-info.name == "windows" { registered-windows-path } else { [] })
    let extra = ($registered | append $known | where {|entry|
        not ($entry | str trim | is-empty) and ($entry | path exists) and (($entry | path type) == "dir")
    })
    $env.PATH = (merge-rclone-path $current $extra)
}

export def rclone-probe [] {
    let matches = (which "^rclone" | where type == external)
    if ($matches | is-empty) { return {found: false ready: false path: "" version: ""} }
    let exe = ($matches | first | get path)
    let result = (try { do { ^$exe version } | complete } catch { {exit_code: 1 stdout: ""} })
    let versions = ($result.stdout | lines | where {|line| $line | str starts-with "rclone v" })
    let version = (if ($versions | is-empty) { "" } else { $versions | first | str trim })
    {found: true ready: ($result.exit_code == 0 and not ($version | is-empty)) path: ($exe | into string) version: $version}
}

# All policy decisions are shared with tests; tests supply non-installing callbacks.
export def perform-rclone-install [plan: record execute: closure probe: closure --dry-run --check] {
    let before = (do $probe)
    if $before.ready {
        return {state: "present" path: $before.path version: $before.version manager: ""}
    }
    if $before.found {
        error make {msg: ("rclone exists at " + $before.path + " but `rclone version` failed. Repair this installation/PATH first; it will not be replaced automatically.")}
    }
    if $check {
        error make {msg: "rclone is not available. Run `nu --no-config-file scripts/install-rclone.nu` to install it."}
    }
    if $dry_run {
        return {state: "planned" path: "" version: "" manager: $plan.manager supported: $plan.supported reason: $plan.reason steps: $plan.steps}
    }
    if not $plan.supported { error make {msg: $plan.reason} }
    for step in $plan.steps {
        let result = (do $execute $step)
        if $result.exit_code != 0 {
            error make {msg: ($step.label + " failed (exit " + ($result.exit_code | into string) + "). " + ($result.stderr? | output-text))}
        }
    }
    let after = (do $probe)
    if not $after.ready {
        error make {msg: "The package manager finished, but `rclone version` still failed or rclone is not on PATH. Restart the terminal or repair PATH, then rerun setup. Cloud configuration was not changed by this installer."}
    }
    {state: "installed" path: $after.path version: $after.version manager: $plan.manager}
}

# Native WinGet HRESULT, accepting both signed and unsigned process representations.
# APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND = 0x8A150014. No text match alone
# may convert a repository/network/authentication error into "not installed".
export def check-rclone-winget-state [code: int output: string] {
    if $code in [-1978335212 2316632084] { return true }
    if $code == 0 and ($output =~ '(?m)(^|\s)Rclone\.Rclone(\s|$)') {
        error make {msg: "Rclone.Rclone is already installed but rclone is not usable after PATH refresh. Restart the terminal or repair the WinGet link; refusing to reinstall/upgrade it."}
    }
    error make {msg: ("Could not determine Rclone.Rclone installation state (WinGet exit " + ($code | into string) + "). Repair WinGet/App Installer and retry; refusing a blind reinstall.")}
}

def execute-install-step [step: record] {
    # The production executor cannot install software from test sandboxes.
    if ($env.INITIAL_SETUP_TEST_MODE? | default "") == "1" {
        error make {msg: "Package installation is disabled in INITIAL_SETUP_TEST_MODE. Use --dry-run or the mocked rclone-install-test.nu."}
    }
    print ("[run] " + $step.label)
    if $step.kind == "winget-state" {
        let result = (do { ^winget list --id Rclone.Rclone --exact --source winget --accept-source-agreements --disable-interactivity } | complete)
        check-rclone-winget-state $result.exit_code (($result.stdout | output-text) + ($result.stderr | output-text)) | ignore
        return {exit_code: 0 stderr: ""}
    }
    let program = $step.program
    let args = $step.args
    # Capture the native exit code explicitly. In a terminal sudo can still use
    # its controlling TTY; package output is shown when the command completes.
    let result = (do { ^$program ...$args } | complete)
    if not ($result.stdout | is-empty) { print ($result.stdout | output-text) }
    if not ($result.stderr | is-empty) { print --stderr ($result.stderr | output-text) }
    {exit_code: $result.exit_code stderr: "See the package manager output above. No other manager or unverified download was tried."}
}

export def --env ensure-rclone [--dry-run --check] {
    if $dry_run and $check { error make {msg: "Use --dry-run or --check, not both."} }
    refresh-rclone-path
    let candidates = ["winget" "brew" "apt-get" "dnf" "pacman" "zypper" "apk" "sudo"]
    let commands = ($candidates | where {|name| not (which ("^" + $name) | is-empty) })
    let is_root = (if $nu.os-info.name == "linux" and not (which "^id" | is-empty) {
        let result = (do { ^id -u } | complete)
        $result.exit_code == 0 and ($result.stdout | str trim) == "0"
    } else { false })
    let plan = (rclone-install-plan $nu.os-info.name $commands $is_root)
    let outcome = (perform-rclone-install $plan {|step| execute-install-step $step } {||
        # A child installer/closure cannot refresh its parent process environment.
        refresh-rclone-path
        rclone-probe
    } --dry-run=$dry_run --check=$check)
    # Export refreshed PATH into this caller, too (setup refreshes after its child).
    refresh-rclone-path
    $outcome
}
