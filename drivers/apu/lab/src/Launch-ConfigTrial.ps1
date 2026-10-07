param([ValidateSet('SelectTrial','RestorePrototype','Check')][string]$Mode='SelectTrial')
$ErrorActionPreference='Stop'
$worker=Join-Path $PSScriptRoot 'Apply-ConfigTrial.ps1'
$arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Mode '+$Mode
$process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru
Write-Output "Started configuration trial helper $($process.Id). Results are written to config-trial-state.json."
