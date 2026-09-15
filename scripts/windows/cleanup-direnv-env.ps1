param()

$ErrorActionPreference = 'Stop'

$appData = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::ApplicationData
)
$localAppData = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData
)

$managedDefaults = [ordered]@{
    DIRENV_CONFIG  = (Join-Path $appData 'direnv\config')
    XDG_CACHE_HOME = (Join-Path $localAppData 'direnv\cache')
    XDG_DATA_HOME  = (Join-Path $localAppData 'direnv\data')
}

$results = @()

foreach ($name in $managedDefaults.Keys) {
    $expected = $managedDefaults[$name]
    $current = [Environment]::GetEnvironmentVariable($name, 'User')

    $removed = $false
    $action = 'not-set'

    if (-not [string]::IsNullOrWhiteSpace($current)) {
        if (
            [string]::Equals(
                $current,
                $expected,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            # Remove only values that exactly match defaults written by
            # Initial-setup v0.8.2-v0.8.5.
            [Environment]::SetEnvironmentVariable($name, $null, 'User')
            $removed = $true
            $action = 'removed-old-managed-value'
        }
        else {
            # Preserve anything that may have been set by the user or
            # another application.
            $action = 'preserved-custom-value'
        }
    }

    $results += [ordered]@{
        name = $name
        expected = $expected
        previous = $current
        action = $action
        removed = $removed
    }
}

[ordered]@{
    variables = $results
} | ConvertTo-Json -Depth 4 -Compress
