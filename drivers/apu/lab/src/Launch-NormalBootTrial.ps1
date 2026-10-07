param([ValidateSet('Prepare','Recover')][string]$Mode='Prepare')
$ErrorActionPreference='Stop'
$worker=Join-Path $PSScriptRoot 'Manage-NormalBootTrial.ps1'
$arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Mode '+$Mode
$process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru
Write-Output "Started normal-boot $Mode helper $($process.Id). Results are written beneath normal-boot\."
