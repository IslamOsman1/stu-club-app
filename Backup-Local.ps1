$ErrorActionPreference='Stop'
$properties=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'android\local.properties')
$sdk=($properties | Where-Object { $_.StartsWith('flutter.sdk=') } | Select-Object -First 1).Substring(12).Replace('\\','\')
$dart=Join-Path $sdk 'bin\dart.bat'
& (Join-Path $PSScriptRoot 'Stop-Local.ps1')
Push-Location (Join-Path $PSScriptRoot 'backend')
try { & $dart run tool/backup.dart; if($LASTEXITCODE -ne 0){throw 'Backup failed'} }
finally { Pop-Location; & (Join-Path $PSScriptRoot 'Start-Local.ps1') }
