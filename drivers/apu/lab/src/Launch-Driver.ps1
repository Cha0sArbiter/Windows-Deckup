param([ValidateSet('Prepare','Activate','SelectForRestart','Rollback')][string]$Mode='Prepare')
$ErrorActionPreference='Stop'
$workerPath=Join-Path $PSScriptRoot 'Apply-Driver.ps1'
$powershellPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$workerArguments='-NoProfile -ExecutionPolicy Bypass -File "'+$workerPath+'" -Mode '+$Mode
$process=Start-Process -FilePath $powershellPath -ArgumentList $workerArguments -Verb RunAs -WindowStyle Hidden -PassThru
$projectRoot=Split-Path -Parent $PSScriptRoot
[PSCustomObject]@{Mode=$Mode; ProcessId=$process.Id; StartedAt=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot 'launcher-state.json')
Write-Output "Started Windows administrator helper, process $($process.Id). Results will be written to installation-state.json and logs."
