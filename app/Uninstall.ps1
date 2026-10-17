# Piki Optimizer - uninstaller
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName PresentationFramework
$it = ((Get-Culture).TwoLetterISOLanguageName -eq 'it')
function Tx($i, $e) { if ($it) { $i } else { $e } }
$Dest = Split-Path -Parent $PSScriptRoot
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

$r = [System.Windows.MessageBox]::Show((Tx "Vuoi disinstallare Piki Optimizer?" "Uninstall Piki Optimizer?"), 'Piki Optimizer', 'YesNo', 'Question')
if ($r -ne 'Yes') { return }
$undo = [System.Windows.MessageBox]::Show((Tx "Vuoi anche riportare Windows com'era prima (annulla tutte le ottimizzazioni)?" "Also put Windows back as it was (undo all optimizations)?"), 'Piki Optimizer', 'YesNo', 'Question')

foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
    if ([string]$p.CommandLine -like '*VeloxPC.ps1*') { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
}
# undo changes + remove the autostart task (needs admin)
$args2 = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Dest\app\VeloxPC.ps1`" -Cleanup"
if ($undo -eq 'Yes') { $args2 += ' -UndoAll' }
try { Start-Process -FilePath $psExe -Verb RunAs -WindowStyle Hidden -ArgumentList $args2 -Wait } catch { }

foreach ($f in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
    Remove-Item -LiteralPath (Join-Path $f 'Piki Optimizer.lnk') -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PikiOptimizer' -Recurse -Force -ErrorAction SilentlyContinue
[System.Windows.MessageBox]::Show((Tx 'Piki Optimizer è stato disinstallato.' 'Piki Optimizer has been uninstalled.'), 'Piki Optimizer') | Out-Null
Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$Dest`"" -WindowStyle Hidden
