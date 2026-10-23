param(
    [string]$Device,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$FlutterArgs
)
$ErrorActionPreference = 'Stop'
$propertiesPath = Join-Path $PSScriptRoot 'android\local.properties'
if (-not (Test-Path -LiteralPath $propertiesPath)) {
    throw 'Run flutter pub get first to prepare android/local.properties.'
}
$flutterLine = Get-Content -LiteralPath $propertiesPath | Where-Object { $_.StartsWith('flutter.sdk=') } | Select-Object -First 1
if (-not $flutterLine) { throw 'flutter.sdk is missing from android/local.properties.' }
$flutterRoot = $flutterLine.Substring(12).Replace('\\','\')
$flutterCommand = Join-Path $flutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterCommand)) { throw 'The configured Flutter SDK was not found.' }
Push-Location $PSScriptRoot
try {
    & (Join-Path $PSScriptRoot 'Start-Local.ps1')
    if (-not $?) { throw 'The local server could not be prepared.' }
    $runArguments = @('run', '--no-dds')
    if ($Device) { $runArguments += @('-d', $Device) }
    if ($FlutterArgs) { $runArguments += $FlutterArgs }
    # This SDK's DDS connection fails locally; direct VM service still supports hot reload.
    & $flutterCommand @runArguments
    $runExitCode = $LASTEXITCODE
} finally { Pop-Location }
exit $runExitCode
