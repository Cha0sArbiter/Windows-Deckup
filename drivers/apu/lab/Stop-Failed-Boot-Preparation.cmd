@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$worker=Join-Path '%~dp0' 'src\Stop-FailedNormalBootPreparation.ps1'; Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File '+[char]34+$worker+[char]34)"
pause
