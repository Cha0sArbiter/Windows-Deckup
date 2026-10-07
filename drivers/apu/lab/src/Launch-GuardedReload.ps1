param([ValidateSet('Prepare','Start')][string]$Mode='Start')
$ErrorActionPreference='Stop'
$worker=Join-Path $PSScriptRoot 'Manage-GuardedReload.ps1'
$arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Mode '+$Mode
$process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru
Write-Output "Started guarded reload helper $($process.Id). Mode: $Mode."
