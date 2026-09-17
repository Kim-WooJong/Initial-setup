param([Parameter(Mandatory=$true)][string]$Path,
      [Parameter(Mandatory=$true)][string]$Token)
$ErrorActionPreference = 'Stop'
# Encode helper-owned diagnostics as UTF-8 without changing the console code
# page. Script-load/policy errors can occur before this runs; the Nu consumer
# must still accept binary stderr. Failure to set the writer is non-fatal.
try {
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $errorWriter = [System.IO.StreamWriter]::new([Console]::OpenStandardError(), $utf8)
    $errorWriter.AutoFlush = $true
    [Console]::SetError($errorWriter)
} catch {
    # Retain PowerShell's existing error stream; never bypass execution policy.
}
# Match the POSIX helper: 0 acquired, 17 file already exists, 74 I/O error.
# Do not change execution policy, silently retry, or delete an existing lock.
$stream = $null
$created = $false
try {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.PSIsContainer -or
            (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw 'The lock path is a directory or reparse point, not a regular lock file.'
        }
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $created = $true
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Token)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    } finally { $stream.Dispose(); $stream = $null }
    exit 0
} catch {
    $cause = $_.Exception.GetBaseException()
    $nativeCode = $cause.HResult -band 0xffff
    # ERROR_FILE_EXISTS (80) / ERROR_ALREADY_EXISTS (183). All other errors,
    # including access denied, disk full and write/flush failures, are NOT busy.
    if (-not $created -and $cause -is [System.IO.IOException] -and
        ($nativeCode -eq 80 -or $nativeCode -eq 183)) {
        [Console]::Error.WriteLine('INITIAL_SETUP_LOCK_EXISTS: existing lock path was not replaced')
        exit 17
    }
    $message = $cause.Message.Replace($Token, '<redacted-lock-token>')
    [Console]::Error.WriteLine(('INITIAL_SETUP_LOCK_IO: {0} (HRESULT {1}): {2}' -f
        $cause.GetType().FullName, $cause.HResult, $message))
    if ($created) {
        [Console]::Error.WriteLine('A partially written lock may remain; inspect it after stopping all writers.')
    }
    exit 74
}
