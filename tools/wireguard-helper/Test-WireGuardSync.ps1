# Windows-only, non-admin compile and pure validator tests. Never installs a
# service, calls DPAPI, opens the pipe, or accesses the WireGuard configuration.
$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('wireguard-helper-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $compiler = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $exe = Join-Path $temp 'wireguard-sync-helper.exe'
    & $compiler /nologo /target:exe /platform:x64 /reference:System.ServiceProcess.dll /reference:System.Web.Extensions.dll "/out:$exe" (Join-Path $PSScriptRoot 'WireGuardSync.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed.' }
    Add-Type -AssemblyName System.Web.Extensions
    $assembly = [Reflection.Assembly]::LoadFile($exe)
    $type = $assembly.GetType('WireGuardSync', $true)
    $flags = [Reflection.BindingFlags]'NonPublic,Static'
    $names = $type.GetMethod('Names', $flags)
    $bundle = $type.GetMethod('Bundle', $flags)
    $sameBaseline = $type.GetMethod('SameBaseline', $flags)
    $fingerprint = $type.GetMethod('Fingerprint', $flags)
    $description = $type.GetMethod('CheckDescription', $flags)
    $json = [Web.Script.Serialization.JavaScriptSerializer]::new()
    function Expect-Rejected([scriptblock]$operation) {
        $rejected = $false
        try { & $operation | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Invalid input unexpectedly accepted.' }
    }
    $valid = $json.DeserializeObject('{"schema_version":1,"tunnels":["home","office"]}')
    $actual = $names.Invoke($null, @($valid))
    if ($actual.Count -ne 2) { throw 'Valid names rejected.' }
    foreach ($inputJson in @('{"tunnels":["../home"]}', '{"tunnels":["home","HOME"]}', '{"tunnels":["a/b"]}', '{"tunnels":[]}', '{"tunnels":[".."]}', '{"tunnels":["sixteencharslongx"]}')) {
        $value = $json.DeserializeObject($inputJson)
        Expect-Rejected { $names.Invoke($null, @($value)) }
    }
    $validBundle = $json.DeserializeObject('{"schema_version":1,"device_id":"host","tunnels":[{"name":"home","config":"[Interface]\nPrivateKey = fixture\n"}]}')
    $arguments = [object[]]@($validBundle, 'host', [string[]]@('home'))
    $result = $bundle.Invoke($null, $arguments)
    if ($result.Count -ne 1) { throw 'Valid bundle rejected.' }
    Expect-Rejected { $bundle.Invoke($null, [object[]]@($validBundle, 'other-host', [string[]]@('home'))) }
    Expect-Rejected { $bundle.Invoke($null, [object[]]@($validBundle, 'host', [string[]]@('home','office'))) }
    Expect-Rejected { $bundle.Invoke($null, [object[]]@($validBundle, 'host', [string[]]@('unknown'))) }
    $description.Invoke($null, [object[]]@('home', 'home'))
    Expect-Rejected { $description.Invoke($null, [object[]]@('home', 'renamed')) }
    Expect-Rejected { $description.Invoke($null, [object[]]@('home', $null)) }
    $snapshot = $json.DeserializeObject('{"home":"missing","office":"abc"}')
    $sameBaseline.Invoke($null, [object[]]@($snapshot, $snapshot))
    foreach ($changed in @('{"home":"missing"}', '{"home":"missing","office":"changed"}', '{"home":"missing","office":"abc","extra":"missing"}', '{"home":"missing","office":123}')) {
        $other = $json.DeserializeObject($changed)
        Expect-Rejected { $sameBaseline.Invoke($null, [object[]]@($other, $snapshot)) }
    }
    $emptyHash = $fingerprint.Invoke($null, [object[]]@(,[byte[]]@()))
    if ($emptyHash -ne 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') { throw 'SHA-256 baseline mismatch.' }
    Write-Output 'Compile and pure validation tests passed; Windows service/pipe/DPAPI integration not exercised.'
} finally {
    # Assembly LoadFile may keep the EXE locked until this PowerShell exits.
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
