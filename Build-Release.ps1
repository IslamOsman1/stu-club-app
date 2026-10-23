param(
    [Parameter(Mandatory=$true)][string]$ApiUrl,
    [string]$FirebaseConfig,
    [switch]$CreateSigningKey
)
$ErrorActionPreference='Stop'
$apiUri=$null
if(-not [Uri]::TryCreate($ApiUrl,[UriKind]::Absolute,[ref]$apiUri) -or $apiUri.Scheme -ne 'https' -or $apiUri.Host.EndsWith('.example.org')){throw 'Provide the real HTTPS API address.'}
$keyProperties=Join-Path $PSScriptRoot 'android\key.properties'
if($CreateSigningKey){
    if(Test-Path -LiteralPath $keyProperties){throw 'Signing settings already exist; keep the existing key.'}
    $keyDir=Join-Path $PSScriptRoot '.signing'
    New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
    $keyPath=Join-Path $keyDir 'stuclub-upload.jks'
    if(Test-Path -LiteralPath $keyPath){throw 'Signing key already exists.'}
    $keyTool=Join-Path 'D:\android stdio\jbr' 'bin\keytool.exe'
    if(-not(Test-Path -LiteralPath $keyTool)){$keyTool=(Get-Command keytool -ErrorAction Stop).Source}
    $secretBytes=New-Object byte[] 32
    $generator=[Security.Cryptography.RandomNumberGenerator]::Create(); try{$generator.GetBytes($secretBytes)}finally{$generator.Dispose()}
    $env:STU_SIGN_PASSWORD=[Convert]::ToBase64String($secretBytes)
    try{
        & $keyTool -genkeypair -keystore $keyPath -alias stuclub-upload -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=StuClub Upload Key' -storepass:env STU_SIGN_PASSWORD -keypass:env STU_SIGN_PASSWORD
        if($LASTEXITCODE -ne 0){throw 'Signing key generation failed.'}
        $escapedPath=$keyPath.Replace('\','\\')
        [IO.File]::WriteAllText($keyProperties,"storeFile=$escapedPath`nstorePassword=$env:STU_SIGN_PASSWORD`nkeyAlias=stuclub-upload`nkeyPassword=$env:STU_SIGN_PASSWORD`n",[Text.UTF8Encoding]::new($false))
    }finally{Remove-Item Env:STU_SIGN_PASSWORD -ErrorAction SilentlyContinue}
}
if(-not(Test-Path -LiteralPath $keyProperties)){throw 'Prepare android/key.properties or run with -CreateSigningKey. Keep the signing key and settings private.'}
$flutter=(Get-Command flutter -ErrorAction Stop).Source
Push-Location $PSScriptRoot
try{
    $releaseArgs=@('build','appbundle','--release',"--dart-define=API_URL=$($ApiUrl.TrimEnd('/'))")
    if($FirebaseConfig){if(-not(Test-Path -LiteralPath $FirebaseConfig)){throw 'Firebase client configuration was not found.'};$releaseArgs+="--dart-define-from-file=$FirebaseConfig"}
    & $flutter @releaseArgs
    if($LASTEXITCODE -ne 0){throw 'Release build failed.'}
}finally{Pop-Location}
