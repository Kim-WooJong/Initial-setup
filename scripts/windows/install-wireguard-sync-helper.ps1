[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9_-]{0,40}\z')][string]$DeviceId,
    [Parameter(Mandatory = $true)][string[]]$TunnelNames,
    [Parameter(Mandatory = $true)][string]$CallerSid
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this installer from an elevated PowerShell console.'
}
$caller = [Security.Principal.SecurityIdentifier]::new($CallerSid)
$system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$admins = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
if ($caller -eq $system -or $caller -eq $admins) { throw 'CallerSid must identify the ordinary sync user.' }
if ($TunnelNames.Count -lt 1 -or $TunnelNames.Count -gt 128) { throw 'Specify 1 to 128 tunnels.' }
foreach ($name in $TunnelNames) {
    if ($name -notmatch '\A[A-Za-z0-9_=+.-]{1,15}\z' -or $name -in @('.', '..')) { throw 'Invalid tunnel name.' }
}
if (@($TunnelNames | Sort-Object -Unique).Count -ne $TunnelNames.Count) { throw 'Duplicate tunnel names.' }
$serviceName = 'InitialSetupWireGuardSync'
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
    throw 'Helper service already exists. This installer refuses an implicit privileged service replacement.'
}
# Known-folder lookup, not a caller-controlled ProgramFiles environment variable.
$programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$root = Join-Path $programFiles 'InitialSetup\WireGuardSync'
function Assert-NoReparse([string]$path) {
    $part = [IO.Path]::GetFullPath($path)
    while ($part) {
        if (Test-Path -LiteralPath $part) {
            if ((Get-Item -Force -LiteralPath $part).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse paths are not permitted.' }
        }
        $part = [IO.Path]::GetDirectoryName($part)
    }
}
Assert-NoReparse $root
if (Test-Path -LiteralPath $root) { throw 'Install directory already exists; refusing to trust existing contents.' }
$parent = Split-Path $root -Parent
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
# Verify parent cannot be replaced by the sync user or another unprivileged SID.
$parentAcl = Get-Acl -LiteralPath $parent
if ($parentAcl.Owner -notin @('NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators')) {
    $ownerSid = $parentAcl.GetOwner([Security.Principal.SecurityIdentifier])
    if ($ownerSid -ne $system -and $ownerSid -ne $admins) { throw 'Installation parent must be owned by SYSTEM or Administrators.' }
}
$writeRights = [Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
foreach ($rule in $parentAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
    if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $writeRights) -ne 0 -and $rule.IdentityReference -ne $system -and $rule.IdentityReference -ne $admins -and $rule.IdentityReference.Value -ne 'S-1-3-0') {
        throw 'Installation parent grants unprivileged write access.'
    }
}
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$acl.SetOwner($admins)
$inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
foreach ($sid in @($system, $admins)) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', $inherit, 'None', 'Allow'))
}
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($caller, 'ReadAndExecute', $inherit, 'None', 'Allow'))
[IO.Directory]::CreateDirectory($root, $acl) | Out-Null
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\tools\wireguard-helper\WireGuardSync.cs'))
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Reviewed helper source is missing.' }
Assert-NoReparse $source
$compiler = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '64-bit .NET Framework compiler is required.' }
$exe = Join-Path $root 'wireguard-sync-helper.exe'
& $compiler /nologo /target:exe /platform:x64 /optimize+ /reference:System.ServiceProcess.dll /reference:System.Web.Extensions.dll "/out:$exe" $source
if ($LASTEXITCODE -ne 0) { throw 'Helper compilation failed; no service was installed.' }
$policy = @{ schema_version = 1; device_id = $DeviceId; caller_sid = $CallerSid; tunnels = @($TunnelNames) }
[IO.File]::WriteAllText((Join-Path $root 'policy.json'), ($policy | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
# New-Service without credentials runs as LocalSystem.
New-Service -Name $serviceName -DisplayName 'Initial Setup WireGuard Sync' -BinaryPathName ('"' + $exe + '" service') -StartupType Automatic | Out-Null
Start-Service -Name $serviceName
if ((Get-Service -Name $serviceName).Status -ne 'Running') { throw 'Service failed to start.' }
Write-Output 'WireGuard helper installed. No tunnel services were changed.'
