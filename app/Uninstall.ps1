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

# Changes still saved (the user said No, or the undo step was refused): the original values (data\backup.json) would be
# deleted with the app folder and could never be put back. Keep a small "restore kit" outside the app folder instead.
$kit = $null
if ($true) {
    try {
        $bf = Join-Path $Dest 'data\backup.json'
        $bj = if (Test-Path -LiteralPath $bf) { [System.IO.File]::ReadAllText($bf, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } else { $null }
        if ($bj -and $bj.entries -and @($bj.entries.PSObject.Properties).Count -gt 0) {
            $kit = Join-Path $env:LOCALAPPDATA 'PikiOptimizer-Ripristino'
            foreach ($d in @("$kit\app\core", "$kit\data")) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
            Copy-Item -LiteralPath (Join-Path $Dest 'app\Restore.ps1') -Destination "$kit\app" -Force -ErrorAction Stop
            Copy-Item -LiteralPath (Join-Path $Dest 'app\core\Common.ps1') -Destination "$kit\app\core" -Force -ErrorAction Stop
            Copy-Item -LiteralPath (Join-Path $Dest 'app\core\Native.cs') -Destination "$kit\app\core" -Force -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath (Join-Path $Dest 'Ripristina Piki.cmd') -Destination $kit -Force -ErrorAction Stop
            foreach ($n in @('backup.json', 'backup.prev.json')) { $s = Join-Path $Dest "data\$n"; if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination "$kit\data" -Force } }
        }
    } catch { $kit = $null }
}

foreach ($f in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
    Remove-Item -LiteralPath (Join-Path $f 'Piki Optimizer.lnk') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $f 'Ripristina Piki Optimizer.lnk') -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PikiOptimizer' -Recurse -Force -ErrorAction SilentlyContinue
$msg = Tx 'Piki Optimizer è stato disinstallato.' 'Piki Optimizer has been uninstalled.'
if ($kit) { $msg += "`n`n" + (Tx "Le impostazioni originali di Windows sono salvate qui: se un giorno vuoi rimettere tutto com'era, apri `"Ripristina Piki.cmd`" in:`n$kit" "Your original Windows settings are kept here: to put everything back one day, open `"Ripristina Piki.cmd`" in:`n$kit") }
[System.Windows.MessageBox]::Show($msg, 'Piki Optimizer') | Out-Null
Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q `"$Dest`"" -WindowStyle Hidden
