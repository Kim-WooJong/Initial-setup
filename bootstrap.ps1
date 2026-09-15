[CmdletBinding()]
param(
    [ValidateSet("auto", "initial", "existing")]
    [string]$Mode = "auto",

    [string]$DataDir = "",

    [ValidateSet("", "workstation", "laptop", "server", "minimal")]
    [string]$Profile = "",

    [switch]$NoAutoSync,

    [switch]$DryRun,

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

    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"

    if (Test-Path $wingetLinks) {
        $env:Path = "$wingetLinks;$env:Path"
    }
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

function Install-Nushell {
    if (Test-Command "nu") {
        Write-Host "[ok] nu already available"
        return
    }

    if (Test-WingetPackageState -Mode "installed" -PackageId "Nushell.Nushell") {
        Refresh-ProcessPath

        if (Test-Command "nu") {
            Write-Host "[ok] Nushell package already installed; PATH refreshed"
            return
        }

        $candidate = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\nu.exe"

        if (Test-Path $candidate) {
            $script:NuExecutable = $candidate
            Write-Host "[ok] Nushell package already installed; using WinGet link"
            return
        }

        throw "Nushell is already installed, but nu.exe is not visible. Restart the terminal or repair PATH; bootstrap will not reinstall the same package."
    }

    # Nushell's official Windows documentation recommends:
    # winget install nushell --scope user
    $args = @(
        "install",
        "nushell",
        "--scope", "user",
        "--source", "winget",
        "--accept-package-agreements",
        "--accept-source-agreements"
    )

    [void](Invoke-Winget "Install Nushell" $args)

    if (-not (Test-Command "nu")) {
        $candidate = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\nu.exe"

        if (Test-Path $candidate) {
            $script:NuExecutable = $candidate
            return
        }

        throw "Nushell installation finished, but nu.exe could not be located. Open a new terminal and rerun bootstrap.ps1."
    }
}

function Resolve-NuExecutable {
    if ($script:NuExecutable) {
        return $script:NuExecutable
    }

    $command = Get-Command "nu" -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
    }

    $candidate = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\nu.exe"

    if (Test-Path $candidate) {
        return $candidate
    }

    throw "nu.exe could not be located."
}

Write-Section "Initial-setup bootstrap"

if (-not (Test-Command "winget")) {
    throw "winget is required. Install or update Microsoft App Installer, then rerun this script."
}

Refresh-ProcessPath

Write-Section "Installing core prerequisites"

Install-WingetId -Command "git" -PackageId "Git.Git" -Required
Install-Nushell
Install-WingetId -Command "nvim" -PackageId "Neovim.Neovim" -Required
Install-WingetId -Command "chezmoi" -PackageId "twpayne.chezmoi" -Required

if (-not $SkipVSCode) {
    Install-WingetId -Command "code" -PackageId "Microsoft.VisualStudioCode"
}

Refresh-ProcessPath

$nu = Resolve-NuExecutable
$setup = Join-Path $RepoRoot "setup.nu"

Write-Section "Starting Nushell setup"

$nuArgs = @(
    $setup,
    "--mode", $Mode
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

& $nu @nuArgs
$setupExitCode = $LASTEXITCODE

if ($setupExitCode -ne 0) {
    throw "setup.nu exited with code $setupExitCode."
}

Write-Section "Bootstrap complete"
Write-Host "Open a new terminal after setup so newly installed programs are visible in PATH."
