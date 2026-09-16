param(
    [Parameter(Mandatory = $true)]
    [string]$PatternsFile,

    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

$PolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreListFromGPO"

if (-not (Test-Path -LiteralPath $PatternsFile)) {
    Write-Error "Pattern file not found: $PatternsFile"
    exit 2
}

$Patterns = @(
    Get-Content -LiteralPath $PatternsFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }
)

if ($Patterns.Count -eq 0) {
    Write-Error "No OneDrive exclusion patterns were found."
    exit 2
}

$Current = $null
if (Test-Path -LiteralPath $PolicyPath) {
    $Current = Get-ItemProperty -LiteralPath $PolicyPath
}

$AllMatch = $true

for ($Index = 0; $Index -lt $Patterns.Count; $Index++) {
    $Name = [string]($Index + 1)
    $Desired = $Patterns[$Index]
    $Actual = $null

    if ($null -ne $Current) {
        $Property = $Current.PSObject.Properties[$Name]
        if ($null -ne $Property) {
            $Actual = [string]$Property.Value
        }
    }

    if ($Actual -ne $Desired) {
        $AllMatch = $false
    }

    Write-Host ("{0} = {1}" -f $Name, $Desired)
}

if ($AllMatch) {
    Write-Host "[ok] OneDrive upload exclusion policy is already current."
    exit 0
}

if ($CheckOnly) {
    Write-Host "[--] OneDrive upload exclusion policy needs to be applied."
    exit 10
}

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
$IsAdministrator = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdministrator) {
    Write-Warning "Administrator rights are required to write the OneDrive HKLM policy."
    exit 11
}

New-Item -Path $PolicyPath -Force | Out-Null

for ($Index = 0; $Index -lt $Patterns.Count; $Index++) {
    $Name = [string]($Index + 1)
    $Desired = $Patterns[$Index]

    New-ItemProperty `
        -LiteralPath $PolicyPath `
        -Name $Name `
        -PropertyType String `
        -Value $Desired `
        -Force | Out-Null
}

$Verified = Get-ItemProperty -LiteralPath $PolicyPath

for ($Index = 0; $Index -lt $Patterns.Count; $Index++) {
    $Name = [string]($Index + 1)
    $Desired = $Patterns[$Index]
    $Actual = [string]$Verified.PSObject.Properties[$Name].Value

    if ($Actual -ne $Desired) {
        Write-Error ("Registry verification failed for value {0}." -f $Name)
        exit 2
    }
}

Write-Host "[ok] OneDrive upload exclusion policy applied."
Write-Host "[info] Existing policy values outside the managed indices were preserved."
Write-Host "[info] Restart OneDrive.exe for the changed policy to take effect."
exit 0
