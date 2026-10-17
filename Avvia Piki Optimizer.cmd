@echo off
rem ============================================================
rem  Piki Optimizer - avvio / launcher
rem  Avvia l'app come amministratore, senza finestre nere.
rem ============================================================
setlocal
cd /d "%~dp0"
if not exist "%~dp0app\VeloxPC.ps1" (
    echo.
    echo  File mancanti: estrai TUTTO lo zip in una cartella prima di avviare Piki Optimizer.
    echo  Missing files: extract the WHOLE zip into a folder before starting Piki Optimizer.
    echo.
    pause
    exit /b 1
)
start "" /min "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0app\VeloxPC.ps1"
exit /b 0
