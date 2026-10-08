@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stage-Package.ps1"
if errorlevel 1 echo Preparation failed. Save the error and recovery logs before restarting.
pause
