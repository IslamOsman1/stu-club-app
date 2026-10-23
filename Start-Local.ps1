$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$backendRoot = Join-Path $projectRoot 'backend'
$runRoot = Join-Path $backendRoot 'run'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$properties = Get-Content -LiteralPath (Join-Path $projectRoot 'android\local.properties')
$flutterLine = $properties | Where-Object { $_.StartsWith('flutter.sdk=') } | Select-Object -First 1
$sdkLine = $properties | Where-Object { $_.StartsWith('sdk.dir=') } | Select-Object -First 1
if (-not $flutterLine -or -not $sdkLine) { throw 'Run flutter pub get or flutter doctor to prepare android/local.properties.' }
$flutterRoot = $flutterLine.Substring(12).Replace('\\','\')
$sdkRoot = $sdkLine.Substring(8).Replace('\\','\')
$dartExe = Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
$adbExe = Join-Path $sdkRoot 'platform-tools\adb.exe'
try {
    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -TimeoutSec 2
} catch { $health = $null }
if (-not $health.ok) {
    Push-Location $backendRoot
    try { & $dartExe pub get; if ($LASTEXITCODE -ne 0) { throw 'Dependency setup failed.' } } finally { Pop-Location }
    $env:STU_HOST = '127.0.0.1'
    $env:PORT = '8080'
    $process = Start-Process -FilePath $dartExe -ArgumentList @('run','bin/server.dart') -WorkingDirectory $backendRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runRoot 'server.log') -RedirectStandardError (Join-Path $runRoot 'error.log')
    $process.Id | Set-Content -LiteralPath (Join-Path $runRoot 'server.pid')
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -TimeoutSec 1; if ($health.ok) { $ready = $true; break } } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw 'Server did not start. See backend/run/error.log.' }
}
& $adbExe start-server
$devices = & $adbExe devices
foreach ($line in $devices) {
    if ($line -match '^(\S+)\s+device$') { & $adbExe -s $Matches[1] reverse tcp:8080 tcp:8080 }
}
Write-Host 'STU Club server is ready at http://127.0.0.1:8080. Connect an Android device, install the APK and create an account.'

