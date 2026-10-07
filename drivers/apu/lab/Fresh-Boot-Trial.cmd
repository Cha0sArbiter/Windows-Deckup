@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Launch-Driver.ps1" -Mode SelectForRestart
if errorlevel 1 (
    echo The administrator helper did not start. Windows has not selected the fresh-boot trial.
    pause
    exit /b 1
)
echo The helper is preparing the driver. Wait for TrialNeedsRestart in installation-state.json before restarting Windows.
pause
