@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Launch-ConfigTrial.ps1" -Mode SelectTrial
pause
