@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Manage-GuardedReload.ps1" -Mode Keep
pause
