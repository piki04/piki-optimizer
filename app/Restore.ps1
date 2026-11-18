# Piki Optimizer - "Ripristina come prima" standalone
# Runs from "Ripristina Piki.cmd" even when the app itself does not open.
# It puts back exactly the original values Piki saved in data\backup.json
# (registry, services, power plan and settings, network, startup apps...).
param([switch]$Yes)
$ErrorActionPreference = 'Continue'
$AppDir = $PSScriptRoot
$Root = Split-Path -Parent $AppDir
$it = ((Get-Culture).TwoLetterISOLanguageName -eq 'it')
function Tx([string]$i, [string]$e) { if ($it) { $i } else { $e } }
function Say([string]$i, [string]$e, [string]$Color = 'Gray') { Write-Host (Tx $i $e) -ForegroundColor $Color }

# ---- administrator rights (registry under HKLM, services, power plans)
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $a = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Yes) { $a += ' -Yes' }
    try { Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $a } catch { Say 'Servono i permessi di amministratore.' 'Administrator rights are needed.' 'Red'; Read-Host (Tx 'Premi INVIO per chiudere' 'Press ENTER to close') | Out-Null }
    exit
}

$Host.UI.RawUI.WindowTitle = 'Piki Optimizer - ' + (Tx 'Ripristina come prima' 'Restore as before')
Write-Host ''
Say '  PIKI OPTIMIZER - RIPRISTINA COME PRIMA' '  PIKI OPTIMIZER - RESTORE AS BEFORE' 'Cyan'
Write-Host ''

# ---- read the saved original values
$data = Join-Path $Root 'data'
$backup = $null; $used = $null
foreach ($name in @('backup.json', 'backup.prev.json')) {
    $f = Join-Path $data $name
    if (-not (Test-Path -LiteralPath $f)) { continue }
    try {
        $obj = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
        if ($obj -and $obj.entries) { $backup = $obj; $used = $f; break }
    } catch { Say "  $name non leggibile, provo la copia precedente..." "  $name unreadable, trying the previous copy..." 'Yellow' }
}
$ids = @()
if ($backup) { $ids = @($backup.entries.PSObject.Properties | ForEach-Object { $_.Name }) }
if ($ids.Count -eq 0) {
    Say '  Nessuna modifica di Piki da annullare: il PC è già com''era prima.' '  No Piki changes to undo: the PC is already as it was.' 'Green'
    Write-Host ''
    Read-Host (Tx '  Premi INVIO per chiudere' '  Press ENTER to close') | Out-Null
    exit
}
Say "  Trovate $($ids.Count) modifiche salvate in $used" "  Found $($ids.Count) saved changes in $used"
foreach ($id in $ids) { Write-Host ('   - ' + [string]$backup.entries.$id.title) }
Write-Host ''
if (-not $Yes) {
    $ans = Read-Host (Tx '  Riportare tutto com''era prima? (S/N)' '  Put everything back as it was? (Y/N)')
    if ($ans -notmatch '^(s|si|sì|y|yes)$') { Say '  Annullato: non ho cambiato nulla.' '  Cancelled: nothing was changed.' 'Yellow'; Start-Sleep 2; exit }
}

# ---- close Piki first, so it does not rewrite the backup while we restore
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
    if ([string]$p.CommandLine -like '*VeloxPC.ps1*' -and $p.ProcessId -ne $PID) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
}
# safety copy of what we are about to restore; if only the previous copy was readable, it becomes the backup again
try { Copy-Item -LiteralPath $used -Destination (Join-Path $data ('backup.before-restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')) -Force } catch { }
if ((Split-Path -Leaf $used) -ne 'backup.json') { try { Copy-Item -LiteralPath $used -Destination (Join-Path $data 'backup.json') -Force } catch { } }

$ok = 0; $fail = 0; $full = $false
# an unfinished Game/Render session (crash): put the previous power plan back first
try {
    $sf = Join-Path $data 'session.json'
    if (Test-Path -LiteralPath $sf) {
        $ss = [System.IO.File]::ReadAllText($sf) | ConvertFrom-Json
        if ([string]$ss.prevScheme -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { & powercfg /setactive ([string]$ss.prevScheme) 2>&1 | Out-Null }
        Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue
    }
} catch { }
# ---- 1) full restore with the app's own code (covers every kind of change)
try {
    if (-not ('VeloxPC.Native' -as [type])) {
        $dll = @(Get-ChildItem -LiteralPath (Join-Path $data 'cache') -Filter 'VeloxNative_*.dll' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
        try { if ($dll) { Add-Type -Path $dll.FullName -ErrorAction Stop } } catch { }
        if (-not ('VeloxPC.Native' -as [type])) { try { Add-Type -TypeDefinition ([System.IO.File]::ReadAllText((Join-Path $AppDir 'core\Native.cs'))) -ErrorAction Stop } catch { } }
    }
    . (Join-Path $AppDir 'core\Common.ps1')
    Initialize-VxPaths $Root
    $script:VxLang = if ($it) { 'it' } else { 'en' }
    if (-not (Get-Command Undo-VxEntry -ErrorAction SilentlyContinue)) { throw 'Undo-VxEntry missing' }
    $full = $true
} catch { Say "  Modalità semplice ($($_.Exception.Message))" "  Simple mode ($($_.Exception.Message))" 'Yellow' }

if ($full) {
    foreach ($id in $ids) {
        try {
            if (Undo-VxEntry $id) { $ok++; Write-Host ('  OK  ' + [string]$backup.entries.$id.title) -ForegroundColor Green } else { $fail++ }
        } catch { $fail++; Write-Host ('  !!  ' + $id + ': ' + $_.Exception.Message) -ForegroundColor Red }
    }
    if ($script:VxNicRestart) {
        Say '  Riavvio la scheda di rete (qualche secondo senza Internet)...' '  Restarting the network adapter (a few seconds offline)...'
        try { Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Restart-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    }
} else {
    # ---- 2) simple restore: registry, services, power settings and plan (works without the rest of the app)
    $guid = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    foreach ($id in $ids) {
        $e = $backup.entries.$id
        $items = @($e.items)
        $bad = 0
        for ($i = $items.Count - 1; $i -ge 0; $i--) {
            $x = $items[$i]
            try {
                switch ([string]$x.kind) {
                    'reg' {
                        if ($x.existed) {
                            if (-not (Test-Path -LiteralPath $x.path)) { New-Item -Path $x.path -Force | Out-Null }
                            $v = $x.value
                            switch ([string]$x.type) {
                                'Binary' { $v = [Convert]::FromBase64String([string]$v) }
                                'MultiString' { $v = [string[]]@($v) }
                                'DWord' { $n = [int64]$v; if ($n -gt [int]::MaxValue) { $n = $n - 4294967296 }; $v = [int]$n }
                                'QWord' { $v = [int64]$v }
                            }
                            New-ItemProperty -LiteralPath $x.path -Name $x.name -PropertyType $x.type -Value $v -Force -ErrorAction Stop | Out-Null
                        } elseif (Test-Path -LiteralPath $x.path) {
                            Remove-ItemProperty -LiteralPath $x.path -Name $x.name -Force -ErrorAction SilentlyContinue
                        }
                    }
                    'svc' {
                        $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$($x.name)"
                        if (Test-Path -LiteralPath $p) {
                            Set-ItemProperty -LiteralPath $p -Name Start -Value ([int]$x.start) -Type DWord -ErrorAction Stop
                            if ([int]$x.delayed -eq 1) { Set-ItemProperty -LiteralPath $p -Name DelayedAutostart -Value 1 -Type DWord -ErrorAction SilentlyContinue }
                        }
                    }
                    'power' {
                        if ($x.scheme -match $guid -and $x.sub -match $guid -and $x.setting -match $guid) {
                            & powercfg /setacvalueindex $x.scheme $x.sub $x.setting ([int]$x.ac) 2>&1 | Out-Null
                            & powercfg /setdcvalueindex $x.scheme $x.sub $x.setting ([int]$x.dc) 2>&1 | Out-Null
                        }
                    }
                    'plan' {
                        if ($x.prev -match $guid) { & powercfg /setactive $x.prev 2>&1 | Out-Null }
                        if ($x.created -and $x.created -match $guid) { & powercfg /delete $x.created 2>&1 | Out-Null }
                    }
                    'pthrottle' { if ($x.path -and (Test-Path -LiteralPath $x.path)) { & powercfg /powerthrottling reset /path "$($x.path)" 2>&1 | Out-Null } }
                    'regfile' { if ($x.file -and [string]$x.file -like '*.reg' -and (Test-Path -LiteralPath $x.file)) { & reg.exe import ([string]$x.file) 2>&1 | Out-Null } }
                    'defender' {
                        try {
                            if ($x.type -eq 'path') { Remove-MpPreference -ExclusionPath ([string]$x.value) -ErrorAction Stop }
                            elseif ($x.type -eq 'process') { Remove-MpPreference -ExclusionProcess ([string]$x.value) -ErrorAction Stop }
                        } catch { }
                    }
                    'appx' {
                        if ([string]$x.path -like 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\*') {
                            Set-ItemProperty -LiteralPath $x.path -Name State -Value ([int]$x.state) -Type DWord -ErrorAction SilentlyContinue
                        }
                    }
                    'overlay' { if ([string]$x.prev -match $guid) { & powercfg /overlaysetactive ([string]$x.prev) 2>&1 | Out-Null } }
                    'mmagent' { if ($x.prev) { Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue } else { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue } }
                    'tcp' {
                        if (@('autotuninglevel', 'rss', 'ecncapability', 'timestamps', 'heuristics') -contains [string]$x.prop -and ([string]$x.value) -match '^[a-zA-Z]+$') {
                            if ($x.prop -eq 'heuristics') { & netsh int tcp set heuristics ([string]$x.value) 2>&1 | Out-Null }
                            else { & netsh int tcp set global "$($x.prop)=$($x.value)" 2>&1 | Out-Null }
                        }
                    }
                    'nic' { Set-NetAdapterAdvancedProperty -Name ([string]$x.adapter) -RegistryKeyword ([string]$x.keyword) -RegistryValue ([string]$x.value) -NoRestart -ErrorAction Stop; $script:VxNicRestart = $true }
                    'dns' {
                        if ($x.dhcp) { Set-DnsClientServerAddress -InterfaceIndex ([int]$x.ifIndex) -ResetServerAddresses -ErrorAction Stop }
                        else { Set-DnsClientServerAddress -InterfaceIndex ([int]$x.ifIndex) -ServerAddresses @($x.servers) -ErrorAction Stop }
                    }
                    'mouse' {
                        $mp = 'HKCU:\Control Panel\Mouse'
                        Set-ItemProperty -LiteralPath $mp -Name MouseSpeed -Value ([string][int]$x.accel) -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $mp -Name MouseThreshold1 -Value ([string][int]$x.t1) -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $mp -Name MouseThreshold2 -Value ([string][int]$x.t2) -ErrorAction SilentlyContinue
                    }
                    'kbd' {
                        $kp = 'HKCU:\Control Panel\Keyboard'
                        Set-ItemProperty -LiteralPath $kp -Name KeyboardDelay -Value ([string][int]$x.delay) -ErrorAction SilentlyContinue
                        Set-ItemProperty -LiteralPath $kp -Name KeyboardSpeed -Value ([string][int]$x.speed) -ErrorAction SilentlyContinue
                    }
                    'display' { $bad++ }   # needs the app (refresh rate is set through a Windows API); takes effect at the next sign-in anyway
                    'schedtask' { if ([string]$x.name -match '^PikiOptimizer( Clean)?$') { Unregister-ScheduledTask -TaskName ([string]$x.name) -Confirm:$false -ErrorAction SilentlyContinue } }
                    default { $bad++ }
                }
            } catch { $bad++ }
        }
        if ($bad -eq 0) { $ok++; Write-Host ('  OK  ' + [string]$e.title) -ForegroundColor Green }
        else { $fail++; Write-Host ('  ~~  ' + [string]$e.title + (Tx " ($bad voci da rifare dall'app)" " ($bad items to redo from the app)")) -ForegroundColor Yellow }
        if ($bad -eq 0) { $backup.entries.PSObject.Properties.Remove($id) }
    }
    if ($script:VxNicRestart) { try { Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Restart-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue } catch { } }
    try {
        $json = ConvertTo-Json -InputObject $backup -Depth 12
        [System.IO.File]::WriteAllText((Join-Path $data 'backup.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

Write-Host ''
Say "  Fatto: $ok modifiche annullate, $fail con problemi." "  Done: $ok changes undone, $fail with problems." $(if ($fail -eq 0) { 'Green' } else { 'Yellow' })
Say '  Riavvia il PC per completare il ripristino.' '  Restart the PC to complete the restore.' 'Cyan'
try { Add-Content -LiteralPath (Join-Path $data 'logs\veloxpc.log') -Value ("{0} [INFO] Ripristina Piki.cmd: {1} undone, {2} failed" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $ok, $fail) -Encoding UTF8 } catch { }
Write-Host ''
Read-Host (Tx '  Premi INVIO per chiudere' '  Press ENTER to close') | Out-Null
