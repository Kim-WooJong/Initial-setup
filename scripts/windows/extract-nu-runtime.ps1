param([Parameter(Mandatory=$true)][string]$Archive,
      [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
# Only a verified official archive is passed here. No system installation or
# execution-policy preference is changed. Do not overwrite a running binary.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = $null
try {
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    $entries = @($zip.Entries | Where-Object { $_.Name -ceq 'nu.exe' })
    if ($entries.Count -ne 1) { throw 'Expected exactly one nu.exe in the archive.' }
    $entry = $entries[0]
    if ($entry.FullName -match '(^/|\\|(^|/)\.\.(/|$)|:)') { throw 'Unsafe archive entry path.' }
    if ($entry.Length -le 0) { throw 'Empty runtime executable.' }
    $source = $entry.Open()
    try {
        $output = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $source.CopyTo($output); $output.Flush() } finally { $output.Dispose() }
    } finally { $source.Dispose() }
} catch {
    [Console]::Error.WriteLine(('NU_EXTRACT_FAILED: ' + $_.Exception.Message))
    exit 1
} finally { if ($null -ne $zip) { $zip.Dispose() } }
exit 0
