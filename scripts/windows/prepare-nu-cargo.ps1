[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$oldPath = $env:PATH
$oldCargoHome = $env:CARGO_HOME
$oldTarget = $env:CARGO_TARGET_DIR
$oldExe = $env:INITIAL_SETUP_NU_SESSION_EXE
$oldVersion = $env:INITIAL_SETUP_NU_SESSION_VERSION
$oldProvider = $env:INITIAL_SETUP_NU_SESSION_PROVIDER

function Test-Seed([string]$Executable) {
    try {
        $text = [string](& $Executable --version)
        if ($LASTEXITCODE -ne 0 -or $text.Trim() -notmatch '^\d+\.\d+\.\d+$') { return $false }
        return ([version]$text.Trim() -ge [version]'0.106.1')
    } catch { return $false }
}

# Forward build stdout to stderr as well. This helper is launched in a child
# powershell.exe process; Out-Host would contaminate its one-line stdout protocol.
function Invoke-Build([string]$Program, [string[]]$Arguments, [string]$Label) {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Program @Arguments | ForEach-Object { [Console]::Error.WriteLine([string]$_) }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw ($Label + ' failed (exit ' + $code + '). Inspect native diagnostics; no sync started.') }
}

try {
    if (-not $env:CARGO_HOME) { $env:CARGO_HOME = Join-Path $env:USERPROFILE '.cargo' }
    $env:PATH = (Join-Path $env:CARGO_HOME 'bin') + [IO.Path]::PathSeparator + $env:PATH
    $env:INITIAL_SETUP_NU_SESSION_EXE = ''
    $env:INITIAL_SETUP_NU_SESSION_VERSION = ''
    $env:INITIAL_SETUP_NU_SESSION_PROVIDER = ''
    $seed = $null
    $command = Get-Command nu -CommandType Application -ErrorAction SilentlyContinue
    if ($command -and (Test-Seed $command.Source)) { $seed = $command.Source }
    $runtimeRoot = Join-Path $env:CARGO_HOME 'initial-setup\nu'
    $versions = Join-Path $runtimeRoot 'versions'
    $receipt = Join-Path $runtimeRoot 'current.json'
    if (-not $seed -and (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        $saved = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
        if ($saved.format -ne 2 -or $saved.provider -ne 'cargo' -or $saved.directory -notmatch '^build-[a-f0-9-]{32,36}$' -or $saved.binary_sha256 -notmatch '^[a-f0-9]{64}$') {
            throw 'NU_CACHE_INVALID: malformed Cargo receipt; no cached program was executed.'
        }
        $candidate = Join-Path (Join-Path $versions $saved.directory) 'bin\nu.exe'
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'NU_CACHE_INVALID: receipt binary is missing.' }
        $attributes = (Get-Item -LiteralPath $candidate -Force).Attributes
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'NU_CACHE_INVALID: binary is a reparse point.' }
        $digest = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($digest -ne $saved.binary_sha256) { throw 'NU_CACHE_CHANGED: refusing to execute modified Cargo Nu.' }
        if (Test-Seed $candidate) { $seed = $candidate }
    }
    if (-not $seed) {
        if ($Check) { throw 'NU_SEED_MISSING: check mode never installs. Run bootstrap first.' }
        $rustup = Get-Command rustup -CommandType Application -ErrorAction SilentlyContinue
        if ($rustup) {
            Invoke-Build -Program $rustup.Source -Arguments @('toolchain','install','stable','--profile','minimal') -Label 'Rust stable preparation'
            $builder = $rustup.Source
            $prefix = @('run', 'stable', 'cargo')
        } else {
            $cargo = Get-Command cargo -CommandType Application -ErrorAction SilentlyContinue
            $rustc = Get-Command rustc -CommandType Application -ErrorAction SilentlyContinue
            if (-not $cargo -or -not $rustc) { throw 'NU_CARGO_MISSING: install Rust/Cargo or run bootstrap.' }
            $builder = $cargo.Source
            $prefix = @()
        }
        $stage = Join-Path $versions ('build-' + [guid]::NewGuid().ToString())
        [void][IO.Directory]::CreateDirectory($stage)
        $env:CARGO_TARGET_DIR = Join-Path $runtimeRoot 'target'
        [Console]::Error.WriteLine('[nushell] No usable Nu seed. Cargo compiling an initial interpreter.')
        $arguments = $prefix + @('install', 'nu', '--locked', '--bin', 'nu', '--registry', 'crates-io', '--root', $stage)
        Invoke-Build -Program $builder -Arguments $arguments -Label ('Cargo Nu build; verify MSVC C++ Build Tools/Windows SDK. Staging: ' + $stage)
        $seed = Join-Path $stage 'bin\nu.exe'
        if (-not (Test-Seed $seed)) { throw 'NU_SEED_INVALID: built interpreter cannot start runtime gate.' }
    }
    $arguments = @('--no-config-file', (Join-Path $root 'scripts\runtime-launch.nu'), '--prepare')
    if ($Check) { $arguments += '--check' }
    # PowerShell 5 may surface native stderr as ErrorRecords. Only the exit code
    # determines success; ordinary Cargo/Nu progress must not be treated as failure.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $seed @arguments)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($code -ne 0 -or $output.Count -ne 1) { throw 'NU_CARGO_PREPARE_FAILED: no setup/sync was started.' }
    $exe = ([string]$output[0]).Trim()
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'NU_CARGO_PREPARE_FAILED: runtime executable is missing.' }
    Write-Output $exe
} finally {
    $env:PATH = $oldPath
    $env:CARGO_HOME = $oldCargoHome
    $env:CARGO_TARGET_DIR = $oldTarget
    $env:INITIAL_SETUP_NU_SESSION_EXE = $oldExe
    $env:INITIAL_SETUP_NU_SESSION_VERSION = $oldVersion
    $env:INITIAL_SETUP_NU_SESSION_PROVIDER = $oldProvider
}
