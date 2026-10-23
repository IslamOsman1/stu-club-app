$ErrorActionPreference='Stop'
$pidFile=Join-Path $PSScriptRoot 'backend\run\server.pid'
if(Test-Path -LiteralPath $pidFile){
    $serverProcessId=[int](Get-Content -LiteralPath $pidFile)
    $rootProcess=Get-CimInstance Win32_Process -Filter "ProcessId = $serverProcessId" -ErrorAction SilentlyContinue
    if($rootProcess -and $rootProcess.Name -eq 'dart.exe' -and $rootProcess.CommandLine -match 'bin[\\/]server\.dart'){
        $children=Get-CimInstance Win32_Process -Filter "ParentProcessId = $serverProcessId" | Where-Object {$_.Name -eq 'dartvm.exe' -and $_.CommandLine -match 'bin[\\/]server\.dart'}
        foreach($child in $children){Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue}
        Stop-Process -Id $serverProcessId -ErrorAction SilentlyContinue
        Write-Host 'Local STU Club server stopped.'
    }
    Remove-Item -LiteralPath $pidFile
}
