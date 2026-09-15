param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('installed', 'upgrade-available')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$PackageId,

    [string]$Source = 'winget'
)

$ErrorActionPreference = 'Stop'

try {
    $arguments = @(
        'list',
        '--id', $PackageId,
        '--exact',
        '--accept-source-agreements',
        '--disable-interactivity'
    )

    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $arguments += @('--source', $Source)
    }

    if ($Mode -eq 'upgrade-available') {
        $arguments += '--upgrade-available'
    }

    $output = (& winget @arguments 2>&1 | Out-String)
    $escapedId = [regex]::Escape($PackageId)
    $pattern = "(?im)(^|\s)$escapedId(\s|$)"

    if ([regex]::IsMatch($output, $pattern)) {
        exit 0
    }

    exit 10
}
catch {
    exit 2
}
