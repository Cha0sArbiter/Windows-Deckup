@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Launch-NormalBootTrial.ps1" -Mode Recover
pause
