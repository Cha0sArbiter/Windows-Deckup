@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Manage-NormalBootTrial.ps1" -Mode Keep
pause
