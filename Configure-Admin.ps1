param([string]$Email,[switch]$RequireVerification)
$ErrorActionPreference='Stop'
if(-not $Email){$Email=Read-Host 'Enter your existing account email'}
$Email=$Email.Trim().ToLowerInvariant()
if($Email -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$'){throw 'Invalid email.'}
$properties=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'android\local.properties')
$line=$properties | Where-Object {$_.StartsWith('flutter.sdk=')} | Select-Object -First 1
if(-not $line){throw 'Prepare Flutter dependencies first.'}
$dart=Join-Path ($line.Substring(12).Replace('\\','\')) 'bin\cache\dart-sdk\bin\dart.exe'
Push-Location (Join-Path $PSScriptRoot 'backend')
try {
  $toolArgs=@('run','tool/configure_admin.dart',$Email)
  if($RequireVerification){$toolArgs+='--require-verification'}
  & $dart @toolArgs
  if($LASTEXITCODE -ne 0){throw 'Admin configuration failed.'}
} finally {Pop-Location}
