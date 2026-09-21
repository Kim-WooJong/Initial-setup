param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference = 'Stop'
try {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'A secret file/directory must not be a reparse point.'
    }
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($item.PSIsContainer) {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid, 'FullControl', $inherit, 'None', 'Allow')
    } else {
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid, 'FullControl', 'Allow')
    }
    # Build a fresh DACL rather than retaining unknown explicit grants.
    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetOwner($sid)
    $acl.AddAccessRule($rule)
    # Persist only the modified owner/DACL. Set-Acl may also request SACL
    # privileges on a previously protected directory. The .NET method avoids
    # that extra privilege and PowerShell-edition module autoload dependencies.
    $item.SetAccessControl($acl)
    exit 0
} catch {
    # Do not include paths, file contents, or credential values in error output.
    Write-Error 'Unable to apply the private owner-only ACL.'
    exit 1
}
