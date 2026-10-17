@echo off
rem Piki Optimizer - installazione / setup
cd /d "%~dp0"
if not exist "%~dp0app\Setup.ps1" (
    echo Estrai TUTTO lo zip prima di installare. / Extract the WHOLE zip first.
    pause
    exit /b 1
)
start "" /min "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0app\Setup.ps1"
exit /b 0
