@echo off
rem ============================================================
rem  Piki Optimizer - Ripristina come prima / Restore as before
rem  Rimette i valori originali salvati da Piki (data\backup.json).
rem  Funziona anche se l'app non si apre.
rem ============================================================
setlocal
cd /d "%~dp0"
if not exist "%~dp0app\Restore.ps1" (
    echo.
    echo  File mancante: app\Restore.ps1
    echo.
    pause
    exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\Restore.ps1"
exit /b 0
