@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Launch-GuardedReload.ps1" -Mode Start
if errorlevel 1 pause
