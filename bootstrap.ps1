[CmdletBinding()]
param(
    [ValidateSet("auto", "initial", "existing")]
    [string]$Mode = "auto",

    [string]$DataDir = "",

    [ValidateSet("", "workstation", "laptop", "server", "minimal")]
    [string]$Profile = "",

    [ValidateSet("ask", "push-local", "pull-private", "review", "backup-private", "preview", "keep-local", "keep-private")]
    [string]$ConfigPolicy = "ask",

    [switch]$NoAutoSync,

    [switch]$DryRun,

    [switch]$Resume,

    [string]$RunId = "",

    [switch]$Validate,

    [switch]$SkipVSCode
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Section {
    param([string]$Title)

    Write-Host ""
    Write-Host "============================================================"
    Write-Host " $Title"
    Write-Host "============================================================"
    Write-Host ""
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($machinePath -and $userPath) {
        $env:Path = "$machinePath;$userPath"
    }
    elseif ($machinePath) {
        $env:Path = $machinePath
    }
    elseif ($userPath) {
        $env:Path = $userPath
    }

    if ($script:NuExecutable -and (Test-Path -LiteralPath $script:NuExecutable -PathType Leaf)) {
        $env:PATH = (Split-Path -Parent $script:NuExecutable) + [IO.Path]::PathSeparator + $env:PATH
    }
    $cargoBin = Join-Path $(if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE ".cargo" }) "bin"
    $env:PATH = $cargoBin + [IO.Path]::PathSeparator + $env:PATH
    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"

    if (Test-Path $wingetLinks) {
        $env:Path = "$wingetLinks;$env:Path"
    }
    if ($script:NuExecutable) { $env:PATH = (Split-Path -Parent $script:NuExecutable) + [IO.Path]::PathSeparator + $env:PATH }
}

function Test-Command {
    param([string]$Command)

    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-WingetPackageState {
    param(
        [ValidateSet("installed", "upgrade-available")]
        [string]$Mode,

        [string]$PackageId,

        [string]$Source = "winget"
    )

    $arguments = @(
        "list",
        "--id", $PackageId,
        "--exact",
        "--accept-source-agreements",
        "--disable-interactivity"
    )

    if ($Source) {
        $arguments += @("--source", $Source)
    }

    if ($Mode -eq "upgrade-available") {
        $arguments += "--upgrade-available"
    }

    try {
        $output = (& winget @arguments 2>&1 | Out-String)
        $escapedId = [regex]::Escape($PackageId)
        $pattern = "(?im)(^|\s)$escapedId(\s|$)"
        return [regex]::IsMatch($output, $pattern)
    }
    catch {
        return $false
    }
}

function Invoke-Winget {
    param(
        [string]$Label,
        [string[]]$Arguments
    )

    Write-Host "[run] $Label"
    Write-Host ""

    & winget @Arguments | Out-Host
    $exitCode = $LASTEXITCODE

    Refresh-ProcessPath

    if ($exitCode -ne 0) {
        Write-Warning "$Label returned exit code $exitCode."
    }

    return $exitCode
}

function Install-WingetId {
    param(
        [string]$Command,
        [string]$PackageId,
        [switch]$Required
    )

    if (Test-Command $Command) {
        Write-Host "[ok] $Command already available"
        return
    }

    if (Test-WingetPackageState -Mode "installed" -PackageId $PackageId) {
        Refresh-ProcessPath

        if (Test-Command $Command) {
            Write-Host "[ok] $PackageId already installed; PATH refreshed"
            return
        }

        if ($Required) {
            throw "$PackageId is already installed, but '$Command' is not visible in PATH. Restart the terminal or repair PATH; bootstrap will not reinstall the same package."
        }

        Write-Warning "$PackageId is already installed, but '$Command' is not visible in PATH. Skipping reinstall."
        return
    }

    $args = @(
        "install",
        "--id", $PackageId,
        "--exact",
        "--source", "winget",
        "--accept-package-agreements",
        "--accept-source-agreements"
    )

    [void](Invoke-Winget "Install $PackageId" $args)

    if (-not (Test-Command $Command)) {
        if ($Required) {
            throw "Required command '$Command' is still unavailable after installing $PackageId."
        }

        Write-Warning "$Command is still unavailable. Continuing."
    }
}

function Ensure-Cargo {
    if (-not $env:CARGO_HOME) { $env:CARGO_HOME = Join-Path $env:USERPROFILE '.cargo' }
    $env:PATH = (Join-Path $env:CARGO_HOME 'bin') + [IO.Path]::PathSeparator + $env:PATH
    if (Test-Command 'rustup') { return }
    if ((Test-Command 'cargo') -and (Test-Command 'rustc')) { return }
    Install-WingetId -Command 'rustup' -PackageId 'Rustlang.Rustup' -Required
    $env:PATH = (Join-Path $env:CARGO_HOME 'bin') + [IO.Path]::PathSeparator + $env:PATH
    if (-not (Test-Command 'rustup')) { throw 'Rustup/Cargo could not be installed; no setup will start.' }
}


function Get-CompatibleNu {
    $cmd = Get-Command nu -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    try {
        $raw = (& $cmd.Source --version).Trim()
        if ($LASTEXITCODE -ne 0) { return $null }
        $parsed = [version]$raw
        if ($parsed -ge [version]'0.109.1') { return $cmd.Source }
    } catch { return $null }
    return $null
}

function Resolve-NuExecutable {
    if ($script:NuExecutable) { return $script:NuExecutable }
    throw 'A compatible Nushell runtime has not been prepared.'
}

$previousRuntimeExe = $env:INITIAL_SETUP_NU_SESSION_EXE
$previousRuntimeVersion = $env:INITIAL_SETUP_NU_SESSION_VERSION
$previousRuntimeProvider = $env:INITIAL_SETUP_NU_SESSION_PROVIDER
try {
Write-Section "Initial-setup bootstrap"

Refresh-ProcessPath
if (-not $DryRun -and $ConfigPolicy -ne 'preview') {
    if (-not (Test-Command 'winget')) { throw 'winget is required to prepare missing native prerequisites.' }
    Install-WingetId -Command 'git' -PackageId 'Git.Git' -Required
}
$compatibleNu = Get-CompatibleNu
if ($compatibleNu) {
    Write-Section 'Using compatible existing Nushell'
    $script:NuExecutable = $compatibleNu
    $runtimeVersion = (& $script:NuExecutable --version).Trim()
    $env:INITIAL_SETUP_NU_SESSION_PROVIDER = 'current-v1'
} else {
    Write-Section 'Preparing Nushell with Cargo'
    if ($DryRun -or $ConfigPolicy -eq 'preview') { throw 'A compatible Nushell (>=0.109.1) is required for a read-only preview; bootstrap will not install toolchains in dry-run mode.' }
    Ensure-Cargo
    $helper = Join-Path $RepoRoot 'scripts\windows\prepare-nu-cargo.ps1'
    $nativeArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $helper)
    if ($DryRun -or $ConfigPolicy -eq 'preview') { $nativeArgs += '-Check' }
    $savedNativePreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $runtimePath = @(& powershell.exe @nativeArgs)
        $runtimeStatus = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedNativePreference }
    if ($runtimeStatus -ne 0 -or $runtimePath.Count -ne 1) { throw 'Cargo runtime preparation failed; no setup/sync started.' }
    $script:NuExecutable = ([string]$runtimePath[0]).Trim()
    if (-not (Test-Path -LiteralPath $script:NuExecutable -PathType Leaf)) { throw "Prepared Nushell executable is missing." }
    $runtimeVersion = (& $script:NuExecutable --version).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Prepared Nushell does not run." }
    $env:INITIAL_SETUP_NU_SESSION_PROVIDER = 'cargo-v1'
}
$env:INITIAL_SETUP_NU_SESSION_EXE = $script:NuExecutable
$env:INITIAL_SETUP_NU_SESSION_VERSION = $runtimeVersion
$env:PATH = (Split-Path -Parent $script:NuExecutable) + [IO.Path]::PathSeparator + $env:PATH
if (-not $DryRun -and $ConfigPolicy -ne 'preview') {
Install-WingetId -Command "nvim" -PackageId "Neovim.Neovim" -Required
Install-WingetId -Command "chezmoi" -PackageId "twpayne.chezmoi" -Required

if (-not $SkipVSCode) {
    Install-WingetId -Command "code" -PackageId "Microsoft.VisualStudioCode"
}

}

Refresh-ProcessPath

$nu = Resolve-NuExecutable
$setup = Join-Path $RepoRoot "setup.nu"

Write-Section "Starting Nushell setup"

$nuArgs = @(
    $setup,
    "--mode", $Mode,
    "--config-policy", $ConfigPolicy
)

if ($DataDir) {
    $nuArgs += @("--data-dir", $DataDir)
}

if ($Profile) {
    $nuArgs += @("--profile", $Profile)
}

if ($NoAutoSync) {
    $nuArgs += "--no-auto-sync"
}

if ($DryRun) {
    $nuArgs += "--dry-run"
}

if ($Resume) {
    $nuArgs += "--resume"
}

if ($RunId) {
    $nuArgs += @("--run-id", $RunId)
}

if ($Validate) {
    $nuArgs += "--validate"
}

$env:PATH = (Split-Path -Parent $nu) + [IO.Path]::PathSeparator + $env:PATH
& $nu --no-config-file @nuArgs
$setupExitCode = $LASTEXITCODE

if ($setupExitCode -ne 0) {
    throw "setup.nu exited with code $setupExitCode."
}

Write-Section "Bootstrap complete"
Write-Host ("Nushell runtime: " + $script:NuExecutable)
Write-Host "Launch this executable or configure your terminal profile to use it. Existing system Nu is unchanged."

} finally {
    # Do not let a completed interactive bootstrap authorize unrelated future runs.
    $env:INITIAL_SETUP_NU_SESSION_EXE = $previousRuntimeExe
    $env:INITIAL_SETUP_NU_SESSION_VERSION = $previousRuntimeVersion
    $env:INITIAL_SETUP_NU_SESSION_PROVIDER = $previousRuntimeProvider
}
