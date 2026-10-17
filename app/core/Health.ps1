# VeloxPC - PC health check-up (first launch + on demand)

function New-VxFinding {
    param([string]$Cat, [string]$Sev, $Title, $Detail, [string]$Action = '', $ActionLabel = $null)
    $lbl = ''
    if ($Action) {
        if ($ActionLabel) { $lbl = L $ActionLabel } else { $lbl = L @{ it = 'Risolvi'; en = 'Fix' } }
    }
    return @{ cat = $Cat; sev = $Sev; title = (L $Title); detail = (L $Detail); action = $Action; actionLabel = $lbl }
}

function Get-VxEvents {
    param([hashtable]$Filter, [int]$Max = 500)
    try { return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Max -ErrorAction Stop) } catch { return @() }
}

$script:VxWinSupport = @{
    19041 = '2021-12-14'; 19042 = '2022-05-10'; 19043 = '2022-12-13'; 19044 = '2023-06-13'; 19045 = '2025-10-14'
    22000 = '2023-10-10'; 22621 = '2024-10-08'; 22631 = '2025-11-11'; 26100 = '2026-10-13'; 26200 = '2027-10-12'
}

function Invoke-VxHealthCheck {
    param($Hw, $Sync)
    $f = New-Object System.Collections.ArrayList
    $step = { param($t, $p) if ($Sync) { $Sync.Step = $t; $Sync.Pct = $p } }
    $since30 = (Get-Date).AddDays(-30)
    $since7 = (Get-Date).AddDays(-7)

    # ======================= DISKS
    & $step (L @{ it = 'Controllo la salute dei dischi...'; en = 'Checking disk health...' }) 8
    $diskProblems = 0
    foreach ($d in $Hw.Disks) {
        $name = $d.Name
        if ($d.Health -and $d.Health -ne 'Healthy') {
            $diskProblems++
            [void]$f.Add((New-VxFinding 'disk' 'crit' @{ it = "Disco in pericolo: $name"; en = "Disk at risk: $name" } @{ it = "Windows segnala lo stato '$($d.Health)'. Fai SUBITO un backup dei tuoi file importanti: il disco potrebbe guastarsi."; en = "Windows reports status '$($d.Health)'. Back up your important files NOW: the disk may fail." } 'fix:chkdsk' @{ it = 'Controlla e ripara'; en = 'Check and repair' }))
        }
        if ($d.Wear -ge 90) {
            $diskProblems++
            [void]$f.Add((New-VxFinding 'disk' 'crit' @{ it = "SSD quasi esaurito: $name ($($d.Wear)% usura)"; en = "SSD almost worn out: $name ($($d.Wear)% wear)" } @{ it = 'Ha consumato quasi tutti i cicli di scrittura. Fai un backup e pianifica la sostituzione.'; en = 'It has used almost all its write cycles. Back up and plan a replacement.' }))
        } elseif ($d.Wear -ge 70) {
            $diskProblems++
            [void]$f.Add((New-VxFinding 'disk' 'warn' @{ it = "SSD usurato: $name ($($d.Wear)%)"; en = "SSD wearing out: $name ($($d.Wear)%)" } @{ it = 'Funziona, ma tieni dei backup aggiornati.'; en = 'It works, but keep backups up to date.' }))
        }
        if ($d.ReadErrors -gt 0) {
            $diskProblems++
            [void]$f.Add((New-VxFinding 'disk' 'warn' @{ it = "Errori di lettura su $name"; en = "Read errors on $name" } @{ it = "$($d.ReadErrors) errori non corretti registrati dal disco. Tieni d'occhio il disco e fai backup."; en = "$($d.ReadErrors) uncorrected errors logged by the disk. Keep an eye on it and back up." } 'fix:chkdsk' @{ it = 'Controlla e ripara'; en = 'Check and repair' }))
        }
        if ($d.Temperature -ge 70) {
            [void]$f.Add((New-VxFinding 'thermal' 'warn' @{ it = "Disco caldo: $name ($($d.Temperature) °C)"; en = "Hot disk: $name ($($d.Temperature) °C)" } @{ it = 'Gli SSD NVMe rallentano sopra i 70-80 °C. Un dissipatore per M.2 o più flusso d''aria risolve.'; en = 'NVMe SSDs slow down above 70-80 °C. An M.2 heatsink or more airflow fixes it.' }))
        }
    }
    try {
        $pred = @(Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop | Where-Object { $_.PredictFailure })
        if ($pred.Count -gt 0) {
            $diskProblems++
            [void]$f.Add((New-VxFinding 'disk' 'crit' @{ it = 'Il controllo SMART prevede un guasto del disco'; en = 'SMART predicts a disk failure' } @{ it = 'Fai subito un backup dei tuoi dati.'; en = 'Back up your data right away.' }))
        }
    } catch { }
    $diskEvt = @(Get-VxEvents @{ LogName = 'System'; ProviderName = @('disk', 'Ntfs', 'stornvme', 'storahci', 'iaStorAC', 'iaStorVD'); StartTime = $since30 } | Where-Object { @(7, 11, 51, 55, 98, 129, 153) -contains $_.Id })
    if ($diskEvt.Count -ge 3) {
        $diskProblems++
        [void]$f.Add((New-VxFinding 'disk' 'warn' @{ it = "$($diskEvt.Count) errori del disco negli ultimi 30 giorni"; en = "$($diskEvt.Count) disk errors in the last 30 days" } @{ it = 'Possibili cause: cavo SATA allentato, disco che invecchia o driver del controller. Controlla i collegamenti e fai backup.'; en = 'Possible causes: loose SATA cable, ageing disk or controller driver. Check connections and back up.' } 'fix:chkdsk' @{ it = 'Controlla e ripara'; en = 'Check and repair' }))
    }
    if ($diskProblems -eq 0 -and $Hw.Disks.Count -gt 0) {
        [void]$f.Add((New-VxFinding 'disk' 'ok' @{ it = 'Dischi in salute'; en = 'Disks are healthy' } @{ it = (($Hw.Disks | ForEach-Object { "$($_.Name) ($($_.Media))" }) -join ', '); en = (($Hw.Disks | ForEach-Object { "$($_.Name) ($($_.Media))" }) -join ', ') }))
    }

    # free space
    $spaceOk = $true
    foreach ($v in $Hw.Volumes) {
        $freeGB = [math]::Round($v.FreeBytes / 1GB, 1)
        $isSys = ($v.Letter -eq $env:SystemDrive)
        if (($isSys -and $freeGB -lt 15) -or $v.FreePct -lt 8) {
            $spaceOk = $false
            [void]$f.Add((New-VxFinding 'disk' $(if ($isSys -and $freeGB -lt 8) { 'crit' } else { 'warn' }) @{ it = "Poco spazio su $($v.Letter) ($freeGB GB liberi)"; en = "Low space on $($v.Letter) ($freeGB GB free)" } @{ it = 'Con il disco quasi pieno Windows e i giochi rallentano e gli aggiornamenti falliscono. Libera almeno il 15%.'; en = 'With a nearly full drive Windows and games slow down and updates fail. Free at least 15%.' } 'goto:cleanup' @{ it = 'Pulisci'; en = 'Clean up' }))
        }
    }
    if ($spaceOk) { [void]$f.Add((New-VxFinding 'disk' 'ok' @{ it = 'Spazio libero sufficiente'; en = 'Enough free space' } @{ it = 'Tutti i dischi hanno spazio libero.'; en = 'All drives have free space.' })) }
    if (-not $Hw.SystemOnSSD) {
        [void]$f.Add((New-VxFinding 'perf' 'warn' @{ it = 'Windows è installato su un disco meccanico (HDD)'; en = 'Windows is installed on a hard drive (HDD)' } @{ it = 'È il collo di bottiglia più grande che esista: un SSD rende avvio, programmi e caricamenti 5-10 volte più rapidi. È l''aggiornamento migliore che puoi fare.'; en = 'It is the biggest bottleneck there is: an SSD makes boot, apps and loading 5-10x faster. It is the best upgrade you can make.' }))
    }
    try {
        $trim = (& fsutil behavior query DisableDeleteNotify 2>$null) -join ' '
        if ($trim -match 'NTFS\s+DisableDeleteNotify\s*=\s*1') {
            [void]$f.Add((New-VxFinding 'perf' 'warn' @{ it = 'TRIM disattivato'; en = 'TRIM is disabled' } @{ it = 'Senza TRIM gli SSD rallentano nel tempo e si usurano di più.'; en = 'Without TRIM SSDs slow down over time and wear faster.' } 'fix:trim' @{ it = 'Attiva TRIM'; en = 'Enable TRIM' }))
        }
    } catch { }

    # ======================= STABILITY
    & $step (L @{ it = 'Cerco schermate blu e crash...'; en = 'Looking for blue screens and crashes...' }) 22
    $bsod = @(Get-VxEvents @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since30 })
    $kp = @(Get-VxEvents @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since30 })
    $whea = @(Get-VxEvents @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since30 })
    $wheaFatal = @($whea | Where-Object { $_.Level -le 2 })
    if ($bsod.Count -gt 0) {
        $last = $bsod[0].TimeCreated.ToString('dd/MM HH:mm')
        [void]$f.Add((New-VxFinding 'stability' 'crit' @{ it = "$($bsod.Count) schermate blu negli ultimi 30 giorni"; en = "$($bsod.Count) blue screens in the last 30 days" } @{ it = "L'ultima il $last. Cause tipiche: RAM con XMP/EXPO instabile, overclock, driver della scheda video o un disco difettoso."; en = "Last one on $last. Typical causes: unstable XMP/EXPO RAM, overclocking, graphics driver or a faulty disk." } 'fix:memtest' @{ it = 'Test della RAM'; en = 'Test RAM' }))
    }
    if ($kp.Count -gt 0 -and $bsod.Count -eq 0) {
        [void]$f.Add((New-VxFinding 'stability' 'warn' @{ it = "$($kp.Count) spegnimenti improvvisi negli ultimi 30 giorni"; en = "$($kp.Count) unexpected shutdowns in the last 30 days" } @{ it = 'Il PC si è spento senza chiudere Windows. Se non hai staccato tu la corrente: alimentatore, temperature o overclock instabile.'; en = 'The PC turned off without shutting down Windows. If you did not pull the plug: power supply, temperatures or unstable overclock.' } 'fix:memtest' @{ it = 'Test della RAM'; en = 'Test RAM' }))
    }
    if ($wheaFatal.Count -gt 0) {
        [void]$f.Add((New-VxFinding 'stability' 'crit' @{ it = "$($wheaFatal.Count) errori hardware gravi (WHEA)"; en = "$($wheaFatal.Count) serious hardware errors (WHEA)" } @{ it = 'La CPU o la RAM hanno segnalato errori. Nel 90% dei casi è un overclock, un undervolt o un profilo XMP/EXPO troppo spinto: prova a riportarli a default nel BIOS.'; en = 'The CPU or RAM reported errors. 90% of the time it is an overclock, undervolt or an aggressive XMP/EXPO profile: try reverting them to default in the BIOS.' } 'fix:bios' @{ it = 'Apri il BIOS'; en = 'Open BIOS' }))
    } elseif ($whea.Count -ge 5) {
        [void]$f.Add((New-VxFinding 'stability' 'warn' @{ it = "$($whea.Count) errori hardware corretti (WHEA)"; en = "$($whea.Count) corrected hardware errors (WHEA)" } @{ it = 'Windows li ha corretti, ma indicano instabilità (spesso PCIe o RAM). Se hai scatti o crash, controlla overclock/XMP e aggiorna il BIOS.'; en = 'Windows corrected them, but they point to instability (often PCIe or RAM). If you get stutters or crashes, check overclock/XMP and update the BIOS.' } 'fix:bios' @{ it = 'Apri il BIOS'; en = 'Open BIOS' }))
    }
    if ($bsod.Count -eq 0 -and $kp.Count -eq 0 -and $wheaFatal.Count -eq 0) {
        [void]$f.Add((New-VxFinding 'stability' 'ok' @{ it = 'Nessuna schermata blu o crash di sistema'; en = 'No blue screens or system crashes' } @{ it = 'Negli ultimi 30 giorni il sistema è stato stabile.'; en = 'The system has been stable for the last 30 days.' }))
    }
    $appCrash = @(Get-VxEvents @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = $since7 })
    if ($appCrash.Count -ge 3) {
        $top = @($appCrash | ForEach-Object { try { [string]$_.Properties[0].Value } catch { '' } } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 3)
        $list = ($top | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ', '
        [void]$f.Add((New-VxFinding 'stability' 'info' @{ it = 'Programmi che si sono chiusi da soli questa settimana'; en = 'Apps that crashed this week' } @{ it = "$list. Se uno è un gioco o After Effects, aggiorna il programma e i driver della scheda video."; en = "$list. If one is a game or After Effects, update it and your graphics driver." }))
    }

    # ======================= WINDOWS
    & $step (L @{ it = 'Controllo Windows e aggiornamenti...'; en = 'Checking Windows and updates...' }) 38
    $build = [int]$Hw.OS.Build
    $eos = $null
    if ($script:VxWinSupport.ContainsKey($build)) { $eos = [datetime]::ParseExact($script:VxWinSupport[$build], 'yyyy-MM-dd', $null) }
    $ent = ([string]$Hw.OS.Edition -match 'Enterprise|Education')
    if (-not $Hw.OS.IsWin11) {
        [void]$f.Add((New-VxFinding 'system' 'crit' @{ it = 'Windows 10 non riceve più aggiornamenti di sicurezza'; en = 'Windows 10 no longer gets security updates' } @{ it = 'Il supporto è finito il 14 ottobre 2025. Passa a Windows 11 (gratis se il PC è compatibile) oppure attiva gli Aggiornamenti di sicurezza estesi (ESU).'; en = 'Support ended on 14 October 2025. Move to Windows 11 (free if the PC is compatible) or enable Extended Security Updates (ESU).' } 'open:windowsupdate' @{ it = 'Apri Windows Update'; en = 'Open Windows Update' }))
    } elseif ($eos -and -not $ent -and (Get-Date) -gt $eos) {
        [void]$f.Add((New-VxFinding 'system' 'warn' @{ it = "La tua versione di Windows 11 ($($Hw.OS.DisplayVersion)) non è più supportata"; en = "Your Windows 11 version ($($Hw.OS.DisplayVersion)) is no longer supported" } @{ it = 'Installa l''ultimo aggiornamento di funzionalità da Windows Update per continuare a ricevere patch di sicurezza.'; en = 'Install the latest feature update from Windows Update to keep receiving security patches.' } 'open:windowsupdate' @{ it = 'Apri Windows Update'; en = 'Open Windows Update' }))
    } else {
        [void]$f.Add((New-VxFinding 'system' 'ok' @{ it = "$($Hw.OS.Name) $($Hw.OS.DisplayVersion) supportato"; en = "$($Hw.OS.Name) $($Hw.OS.DisplayVersion) is supported" } @{ it = "Build $build.$($Hw.OS.Ubr)"; en = "Build $build.$($Hw.OS.Ubr)" }))
    }
    try {
        $hf = @(Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1)
        if ($hf.Count -gt 0 -and $hf[0].InstalledOn -lt (Get-Date).AddDays(-60)) {
            $days = [int]((Get-Date) - $hf[0].InstalledOn).TotalDays
            [void]$f.Add((New-VxFinding 'system' 'warn' @{ it = "Nessun aggiornamento da $days giorni"; en = "No updates for $days days" } @{ it = 'Gli aggiornamenti correggono falle di sicurezza e bug di prestazioni. Controlla Windows Update.'; en = 'Updates fix security holes and performance bugs. Check Windows Update.' } 'open:windowsupdate' @{ it = 'Apri Windows Update'; en = 'Open Windows Update' } 'fix:wuscan' @{ it = 'Aggiorna ora'; en = 'Update now' }))
        }
    } catch { }
    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        [void]$f.Add((New-VxFinding 'system' 'warn' @{ it = 'Riavvio in sospeso'; en = 'Restart pending' } @{ it = 'Windows ha installato aggiornamenti che si completano solo riavviando.'; en = 'Windows installed updates that only finish after a restart.' } 'restart' @{ it = 'Riavvia ora'; en = 'Restart now' }))
    }
    if ($Hw.OS.LastBoot) {
        $up = (Get-Date) - $Hw.OS.LastBoot
        if ($up.TotalDays -ge 7) {
            [void]$f.Add((New-VxFinding 'system' 'info' @{ it = "PC acceso da $([int]$up.TotalDays) giorni senza riavvio"; en = "PC running for $([int]$up.TotalDays) days without a restart" } @{ it = 'Un riavvio ogni tanto libera la memoria e applica gli aggiornamenti. Con l''avvio rapido attivo, "Arresta" non conta come riavvio.'; en = 'An occasional restart frees memory and applies updates. With Fast Startup on, "Shut down" does not count as a restart.' } 'restart' @{ it = 'Riavvia ora'; en = 'Restart now' }))
        }
    }
    & $step (L @{ it = 'Verifico l''integrità dei file di Windows...'; en = 'Verifying Windows file integrity...' }) 46
    try {
        $img = Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop
        if ([string]$img.ImageHealthState -ne 'Healthy') {
            [void]$f.Add((New-VxFinding 'system' 'crit' @{ it = 'File di Windows danneggiati'; en = 'Damaged Windows files' } @{ it = 'Alcuni componenti di Windows risultano corrotti: possono causare crash e lentezza. La riparazione automatica (DISM + SFC) richiede 10-20 minuti.'; en = 'Some Windows components are corrupted: they can cause crashes and slowness. Automatic repair (DISM + SFC) takes 10-20 minutes.' } 'fix:repair' @{ it = 'Ripara Windows'; en = 'Repair Windows' }))
        } else {
            [void]$f.Add((New-VxFinding 'system' 'ok' @{ it = 'File di Windows integri'; en = 'Windows files are intact' } @{ it = 'Nessuna corruzione rilevata.'; en = 'No corruption detected.' }))
        }
    } catch { }

    # ======================= DRIVERS
    & $step (L @{ it = 'Controllo i driver...'; en = 'Checking drivers...' }) 56
    try {
        $bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -and @(0, 22, 24, 45) -notcontains [int]$_.ConfigManagerErrorCode })
        if ($bad.Count -gt 0) {
            $names = (@($bad | Select-Object -First 4 | ForEach-Object { if ($_.Name) { $_.Name } else { $_.DeviceID } }) -join ', ')
            [void]$f.Add((New-VxFinding 'drivers' 'warn' @{ it = "$($bad.Count) dispositivi con problemi di driver"; en = "$($bad.Count) devices with driver problems" } @{ it = "$names. Installa i driver dal sito del produttore della scheda madre/portatile."; en = "$names. Install drivers from your motherboard/laptop maker's website." } 'fix:drivers' @{ it = 'Installa driver'; en = 'Install drivers' }))
        } else {
            [void]$f.Add((New-VxFinding 'drivers' 'ok' @{ it = 'Tutti i dispositivi funzionano'; en = 'All devices are working' } @{ it = 'Nessun driver mancante o in errore.'; en = 'No missing or failing drivers.' }))
        }
    } catch { }
    if ($Hw.BasicDisplayOnly) {
        [void]$f.Add((New-VxFinding 'drivers' 'crit' @{ it = 'Manca il driver della scheda video'; en = 'Graphics driver is missing' } @{ it = 'Windows sta usando un driver di base: niente accelerazione 3D. Installa il driver NVIDIA/AMD/Intel.'; en = 'Windows is using a basic driver: no 3D acceleration. Install the NVIDIA/AMD/Intel driver.' } 'open:gpudriver' @{ it = 'Scarica driver'; en = 'Get driver' }))
    }
    foreach ($g in @($Hw.GPUs | Where-Object { -not $_.Integrated })) {
        if ($g.DriverDate -and $g.DriverDate -lt (Get-Date).AddDays(-180)) {
            $age = [int](((Get-Date) - $g.DriverDate).TotalDays / 30)
            [void]$f.Add((New-VxFinding 'drivers' 'warn' @{ it = "Driver della scheda video vecchio di $age mesi"; en = "Graphics driver is $age months old" } @{ it = "$($g.Name): i driver nuovi portano FPS in più e correzioni per i giochi recenti."; en = "$($g.Name): new drivers bring extra FPS and fixes for recent games." } "open:gpudriver" @{ it = 'Scarica driver'; en = 'Get driver' }))
        }
    }

    # ======================= SECURITY
    & $step (L @{ it = 'Controllo antivirus e firewall...'; en = 'Checking antivirus and firewall...' }) 66
    $avOk = $false; $avNames = @()
    try {
        foreach ($av in @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)) {
            $hex = '{0:x6}' -f [int]$av.productState
            $on = @('10', '11') -contains $hex.Substring(2, 2)
            if ($on) { $avOk = $true; $avNames += [string]$av.displayName }
        }
    } catch { $avOk = $true }
    if (-not $avOk) {
        [void]$f.Add((New-VxFinding 'security' 'crit' @{ it = 'Nessun antivirus attivo'; en = 'No active antivirus' } @{ it = 'Il PC non è protetto. Riattiva Microsoft Defender: è gratuito e leggerissimo.'; en = 'The PC is unprotected. Turn Microsoft Defender back on: it is free and very light.' } 'open:security' @{ it = 'Apri Sicurezza'; en = 'Open Security' }))
    } else {
        $sigOld = $false
        try { $mp = Get-MpComputerStatus -ErrorAction Stop; if ($mp.AntivirusEnabled -and $mp.AntivirusSignatureAge -gt 7) { $sigOld = $true } } catch { }
        if ($sigOld) { [void]$f.Add((New-VxFinding 'security' 'warn' @{ it = 'Definizioni antivirus non aggiornate'; en = 'Antivirus definitions out of date' } @{ it = 'Defender non si aggiorna da più di 7 giorni.'; en = 'Defender has not updated for more than 7 days.' } 'fix:defsig' @{ it = 'Aggiorna ora'; en = 'Update now' })) }
        else { [void]$f.Add((New-VxFinding 'security' 'ok' @{ it = 'Antivirus attivo'; en = 'Antivirus active' } @{ it = (($avNames | Select-Object -Unique) -join ', '); en = (($avNames | Select-Object -Unique) -join ', ') })) }
    }
    try {
        $offProfiles = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled })
        if ($offProfiles.Count -gt 0) {
            [void]$f.Add((New-VxFinding 'security' 'warn' @{ it = 'Firewall disattivato'; en = 'Firewall is off' } @{ it = 'Il firewall non rallenta i giochi né alza il ping: tenerlo spento ti espone solo ad attacchi.'; en = 'The firewall does not slow games or raise ping: keeping it off only exposes you to attacks.' } 'fix:firewall' @{ it = 'Riattiva'; en = 'Turn on' }))
        }
    } catch { }
    $wu = Get-VxSvcStart 'wuauserv'
    if ($wu -and $wu.start -eq 4) {
        [void]$f.Add((New-VxFinding 'security' 'crit' @{ it = 'Windows Update è stato disattivato'; en = 'Windows Update has been disabled' } @{ it = 'Probabilmente da un altro "ottimizzatore". Senza aggiornamenti il PC resta vulnerabile e perdi correzioni ai driver e ai giochi.'; en = 'Probably by another "optimizer". Without updates the PC stays vulnerable and you miss driver and game fixes.' } 'fix:wu' @{ it = 'Riattiva'; en = 'Re-enable' }))
    }
    try {
        if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop).EnableLUA -eq 0) {
            [void]$f.Add((New-VxFinding 'security' 'warn' @{ it = 'Controllo account utente (UAC) disattivato'; en = 'User Account Control (UAC) is off' } @{ it = 'Qualsiasi programma può modificare il sistema senza chiedertelo.'; en = 'Any program can change the system without asking you.' } 'fix:uac' @{ it = 'Riattiva'; en = 'Turn on' }))
        }
    } catch { }
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        if (-not $sb) { [void]$f.Add((New-VxFinding 'security' 'info' @{ it = 'Secure Boot disattivato'; en = 'Secure Boot is off' } @{ it = 'Alcuni giochi con anti-cheat (es. Valorant, Battlefield 6, Call of Duty) lo richiedono. Si attiva dal BIOS.'; en = 'Some anti-cheat games (e.g. Valorant, Battlefield 6, Call of Duty) require it. Enable it in the BIOS.' } 'fix:bios' @{ it = 'Apri il BIOS'; en = 'Open BIOS' })) }
    } catch { }

    # ======================= TEMPERATURES / THROTTLING
    & $step (L @{ it = 'Controllo temperature e prestazioni CPU...'; en = 'Checking temperatures and CPU throttling...' }) 74
    $thr = @(Get-VxEvents @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = $since7 })
    if ($thr.Count -gt 0) {
        [void]$f.Add((New-VxFinding 'thermal' 'warn' @{ it = 'La CPU è stata rallentata dal firmware'; en = 'The CPU was slowed down by firmware' } @{ it = "Successo $($thr.Count) volte in 7 giorni: di solito surriscaldamento o limiti di alimentazione. Pulisci la polvere, controlla la pasta termica e le ventole."; en = "Happened $($thr.Count) times in 7 days: usually overheating or power limits. Clean dust, check thermal paste and fans." }))
    }
    $smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (Test-Path -LiteralPath $smi) {
        try {
            $out = (& $smi --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
            if ($out) {
                $parts = $out.Split(',')
                $temp = [int]$parts[0].Trim(); $util = [int]$parts[1].Trim()
                if ($temp -ge 85) { [void]$f.Add((New-VxFinding 'thermal' 'crit' @{ it = "Scheda video molto calda: $temp °C"; en = "Graphics card very hot: $temp °C" } @{ it = 'Sopra gli 83-85 °C le NVIDIA abbassano la frequenza. Pulisci le ventole e migliora il flusso d''aria del case.'; en = 'Above 83-85 °C NVIDIA cards lower their clocks. Clean the fans and improve case airflow.' })) }
                elseif ($temp -ge 70 -and $util -lt 20) { [void]$f.Add((New-VxFinding 'thermal' 'warn' @{ it = "Scheda video calda a riposo: $temp °C"; en = "Graphics card hot at idle: $temp °C" } @{ it = 'A PC fermo dovrebbe stare sotto i 55 °C: probabilmente ventole sporche o flusso d''aria scarso.'; en = 'At idle it should be below 55 °C: probably dirty fans or poor airflow.' })) }
                else { [void]$f.Add((New-VxFinding 'thermal' 'ok' @{ it = "Temperatura scheda video: $temp °C"; en = "Graphics card temperature: $temp °C" } @{ it = 'Nella norma.'; en = 'Normal.' })) }
            }
        } catch { }
    }
    if ($thr.Count -eq 0) { [void]$f.Add((New-VxFinding 'thermal' 'ok' @{ it = 'Nessun rallentamento termico della CPU'; en = 'No CPU thermal throttling' } @{ it = 'Negli ultimi 7 giorni la CPU ha lavorato a piena velocità.'; en = 'The CPU ran at full speed for the last 7 days.' })) }

    # ======================= MEMORY / CONFIG
    & $step (L @{ it = 'Controllo RAM e configurazione...'; en = 'Checking RAM and configuration...' }) 82
    $mem = [VeloxPC.Native]::Memory()
    if ($mem[0] -ge 85) {
        [void]$f.Add((New-VxFinding 'memory' 'warn' @{ it = "RAM quasi piena ($([int]$mem[0])%)"; en = "RAM almost full ($([int]$mem[0])%)" } @{ it = 'Troppi programmi aperti o in background: il PC usa il disco al posto della RAM e rallenta.'; en = 'Too many apps open or in the background: the PC uses the disk instead of RAM and slows down.' } 'goto:processes' @{ it = 'Riduci processi'; en = 'Reduce processes' }))
    }
    try {
        $pfu = @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop)
        $auto = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).AutomaticManagedPagefile
        if ($pfu.Count -eq 0 -and -not $auto) {
            [void]$f.Add((New-VxFinding 'memory' 'crit' @{ it = 'File di paging disattivato'; en = 'Page file disabled' } @{ it = 'Alcune guide lo consigliano, ma è sbagliato: giochi e After Effects possono chiudersi all''improvviso quando la RAM finisce.'; en = 'Some guides recommend it, but it is wrong: games and After Effects can suddenly crash when RAM runs out.' } 'fix:pagefile' @{ it = 'Riattiva'; en = 'Re-enable' }))
        }
    } catch { }
    if ($Hw.RAM.SingleChannel -and $Hw.RAM.Modules -eq 1) {
        [void]$f.Add((New-VxFinding 'memory' 'warn' @{ it = 'RAM in single channel (1 solo modulo)'; en = 'RAM in single channel (only 1 stick)' } @{ it = 'Con un solo banco la memoria va a metà velocità: nei giochi si perdono anche il 20-30% di FPS minimi. Aggiungi un secondo modulo identico.'; en = 'With one stick memory runs at half bandwidth: games can lose 20-30% of minimum FPS. Add a second identical stick.' }))
    }
    if ($Hw.RAM.XmpProbablyOff -and $Hw.RAM.KitMTs -gt 0) {
        [void]$f.Add((New-VxFinding 'memory' 'warn' @{ it = "La tua RAM è da $($Hw.RAM.KitMTs) MT/s ma va a $($Hw.RAM.SpeedMTs)"; en = "Your RAM is rated $($Hw.RAM.KitMTs) MT/s but runs at $($Hw.RAM.SpeedMTs)" } @{ it = 'Il profilo EXPO/XMP è spento: attivalo nel BIOS (di solito tasto CANC all''avvio, voce "EXPO" o "XMP"). Più banda e meno latenza della RAM: FPS minimi più alti, soprattutto nei giochi competitivi.'; en = 'The EXPO/XMP profile is off: enable it in the BIOS (usually DEL at boot, "EXPO" or "XMP" option). More RAM bandwidth and lower latency: higher minimum FPS, especially in competitive games.' } 'fix:bios' @{ it = 'Apri il BIOS'; en = 'Open BIOS' }))
    } elseif ($Hw.RAM.XmpProbablyOff) {
        [void]$f.Add((New-VxFinding 'memory' 'warn' @{ it = "RAM a $($Hw.RAM.SpeedMTs) MT/s: probabilmente XMP/EXPO è spento"; en = "RAM at $($Hw.RAM.SpeedMTs) MT/s: XMP/EXPO is probably off" } @{ it = 'Le RAM gaming vanno attivate nel BIOS (profilo XMP per Intel, EXPO/DOCP per AMD), altrimenti restano alla velocità minima. Guadagno tipico: 5-15% di FPS.'; en = 'Gaming RAM must be enabled in the BIOS (XMP profile for Intel, EXPO/DOCP for AMD), otherwise it stays at base speed. Typical gain: 5-15% FPS.' } 'fix:bios' @{ it = 'Apri il BIOS'; en = 'Open BIOS' }))
    }
    foreach ($dsp in $Hw.Displays) {
        if ($dsp.MaxHz -gt $dsp.CurrentHz + 5) {
            [void]$f.Add((New-VxFinding 'perf' 'warn' @{ it = "Schermo a $($dsp.CurrentHz) Hz ma ne supporta $($dsp.MaxHz)"; en = "Screen at $($dsp.CurrentHz) Hz but it supports $($dsp.MaxHz)" } @{ it = 'Stai vedendo meno fotogrammi di quelli che il monitor può mostrare: più Hz = movimento più fluido e meno ritardo.'; en = 'You are seeing fewer frames than the monitor can show: more Hz = smoother motion and less delay.' } ("fix:refresh|" + $dsp.Device + "|" + $dsp.MaxHz) @{ it = "Imposta $($dsp.MaxHz) Hz"; en = "Set $($dsp.MaxHz) Hz" }))
        }
    }
    if ($Hw.PowerScheme -and $Hw.PowerScheme.guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a' -and -not $Hw.IsLaptop) {
        [void]$f.Add((New-VxFinding 'perf' 'warn' @{ it = 'Piano energetico "Risparmio di energia" attivo'; en = '"Power saver" plan is active' } @{ it = 'Su un PC fisso limita inutilmente CPU e scheda video.'; en = 'On a desktop it needlessly limits the CPU and graphics card.' } 'fix:powerplan' @{ it = 'Correggi'; en = 'Fix' }))
    }
    try {
        $gm = Get-VxRegState 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
        if ($gm.existed -and [int]$gm.value -eq 0) {
            [void]$f.Add((New-VxFinding 'perf' 'info' @{ it = 'Modalità Gioco disattivata'; en = 'Game Mode is off' } @{ it = 'Attivala per dare priorità ai giochi.'; en = 'Turn it on to prioritise games.' } 'fix:gamemode' @{ it = 'Attiva'; en = 'Turn on' }))
        }
    } catch { }
    try {
        $st = @(Get-VxStartupItems | Where-Object { $_.Enabled })
        if ($st.Count -ge 10) {
            [void]$f.Add((New-VxFinding 'perf' 'warn' @{ it = "$($st.Count) programmi partono all'accensione"; en = "$($st.Count) programs start at boot" } @{ it = 'Rallentano l''avvio e restano in background a consumare RAM e CPU.'; en = 'They slow down boot and stay in the background eating RAM and CPU.' } 'goto:processes' @{ it = 'Gestisci'; en = 'Manage' }))
        }
    } catch { }

    # ======================= NETWORK
    & $step (L @{ it = 'Test veloce della connessione...'; en = 'Quick connection test...' }) 90
    $n = $Hw.Network
    if (-not $n) {
        [void]$f.Add((New-VxFinding 'network' 'crit' @{ it = 'Nessuna connessione a Internet'; en = 'No Internet connection' } @{ it = 'Nessuna scheda di rete collegata a un router.'; en = 'No network adapter connected to a router.' }))
    } else {
        $hosts = @(); if ($n.Gateway) { $hosts += [string]$n.Gateway }; $hosts += '1.1.1.1'
        $pr = New-Object VeloxPC.PingRunner -ArgumentList (, [string[]]$hosts)
        $pr.Start(8, 150)
        $waited = 0
        while ($pr.Running -and $waited -lt 15000) { Start-Sleep -Milliseconds 200; $waited += 200 }
        $netOk = $true
        for ($i = 0; $i -lt $hosts.Count; $i++) {
            $s = [VeloxPC.PingRunner]::Stats($pr.Snapshot($i))
            $isRouter = ($n.Gateway -and $hosts[$i] -eq [string]$n.Gateway)
            if ($s[4] -gt 0) {
                $netOk = $false
                [void]$f.Add((New-VxFinding 'network' 'warn' $(if ($isRouter) { @{ it = "Pacchetti persi verso il router ($([int]$s[4])%)"; en = "Packet loss to the router ($([int]$s[4])%)" } } else { @{ it = "Pacchetti persi verso Internet ($([int]$s[4])%)"; en = "Packet loss to the Internet ($([int]$s[4])%)" } }) $(if ($n.IsWifi -and $isRouter) { @{ it = 'Il Wi-Fi sta perdendo dati: avvicinati al router, usa i 5 GHz o meglio un cavo.'; en = 'Wi-Fi is dropping data: get closer to the router, use 5 GHz or better a cable.' } } else { @{ it = 'Perdere pacchetti causa lag e "teletrasporti" nei giochi. Fai il test completo nella sezione Rete.'; en = 'Packet loss causes lag and rubber-banding in games. Run the full test in the Network section.' } }) 'goto:network' @{ it = 'Test completo'; en = 'Full test' }))
            } elseif ($isRouter -and $s[0] -gt 8) {
                $netOk = $false
                [void]$f.Add((New-VxFinding 'network' 'warn' @{ it = "Ping verso il router alto: $([int]$s[0]) ms"; en = "High ping to the router: $([int]$s[0]) ms" } @{ it = 'Dovrebbe essere 1-3 ms. Di solito è colpa del Wi-Fi o di un router sovraccarico.'; en = 'It should be 1-3 ms. Usually Wi-Fi or an overloaded router is to blame.' } 'goto:network' @{ it = 'Ottimizza rete'; en = 'Optimize network' }))
            }
        }
        if ($n.IsWifi) { [void]$f.Add((New-VxFinding 'network' 'info' @{ it = 'Connesso in Wi-Fi'; en = 'Connected via Wi-Fi' } @{ it = 'Per il ping più basso e stabile possibile usa un cavo Ethernet.'; en = 'For the lowest, steadiest ping use an Ethernet cable.' })) }
        elseif ($n.LinkBps -gt 0 -and $n.LinkBps -le 100000000) { [void]$f.Add((New-VxFinding 'network' 'warn' @{ it = "Cavo di rete a soli $($n.LinkSpeed)"; en = "Network cable at only $($n.LinkSpeed)" } @{ it = 'Probabile cavo vecchio o danneggiato: usa un Cat5e/Cat6.'; en = 'Likely an old or damaged cable: use Cat5e/Cat6.' })) }
        if ($netOk) { [void]$f.Add((New-VxFinding 'network' 'ok' @{ it = 'Connessione stabile'; en = 'Stable connection' } @{ it = 'Nessuna perdita di pacchetti.'; en = 'No packet loss.' })) }
    }

    # ======================= BATTERY
    if ($Hw.HasBattery -and $Hw.IsLaptop) {
        try {
            $full = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop)[0].FullChargedCapacity
            $design = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop)[0].DesignedCapacity
            if ($design -gt 0 -and $full -gt 0) {
                $healthPct = [int](100 * $full / $design)
                if ($healthPct -lt 70) { [void]$f.Add((New-VxFinding 'battery' 'warn' @{ it = "Batteria usurata: $healthPct% della capacità originale"; en = "Worn battery: $healthPct% of original capacity" } @{ it = 'Dura molto meno di quando era nuova. Valuta la sostituzione.'; en = 'It lasts much less than when new. Consider a replacement.' })) }
                else { [void]$f.Add((New-VxFinding 'battery' 'ok' @{ it = "Batteria in buono stato ($healthPct%)"; en = "Battery in good shape ($healthPct%)" } @{ it = 'Capacità rispetto a quando era nuova.'; en = 'Capacity compared to new.' })) }
            }
        } catch { }
    }

    & $step (L @{ it = 'Fatto!'; en = 'Done!' }) 100
    $crit = @($f | Where-Object { $_.sev -eq 'crit' }).Count
    $warn = @($f | Where-Object { $_.sev -eq 'warn' }).Count
    $score = [math]::Max(5, 100 - 18 * $crit - 6 * $warn)
    return @{ time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); score = $score; crit = $crit; warn = $warn; findings = @($f.ToArray()) }
}

function Invoke-VxToolProgress {
    # runs a console tool and turns its "NN.N%" output into real progress
    param([string]$Exe, [string]$Arguments, $Sync, [int]$From, [int]$To, [string]$Label)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot "System32\$Exe"
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    if ($Exe -eq 'sfc.exe') { $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode }
    $p = [System.Diagnostics.Process]::Start($psi)
    $buf = New-Object char[] 512
    $tail = ''
    if ($Sync) { $Sync.Step = "$Label (0%)"; $Sync.Pct = $From }
    while (($n = $p.StandardOutput.Read($buf, 0, $buf.Length)) -gt 0) {
        $tail = ($tail + (New-Object string($buf, 0, $n)))
        if ($tail.Length -gt 400) { $tail = $tail.Substring($tail.Length - 400) }
        $m = [regex]::Matches(($tail -replace "`0", ''), '(\d{1,3})(?:[.,]\d)?\s*%')
        if ($m.Count -gt 0 -and $Sync) {
            $v = [math]::Min(100, [int]$m[$m.Count - 1].Groups[1].Value)
            $Sync.Pct = [int]($From + ($To - $From) * $v / 100)
            $Sync.Step = "$Label ($v%)"
        }
    }
    $p.WaitForExit()
    return $p.ExitCode
}

function Invoke-VxHealthFix {
    # Runs an automatic fix from a finding. Returns a message.
    param([string]$Action, $Hw, $Sync)
    switch -Regex ($Action) {
        '^fix:wu$' {
            Set-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv' -Name Start -Value 3 -Type DWord -ErrorAction SilentlyContinue
            Start-Service wuauserv -ErrorAction SilentlyContinue
            return (L @{ it = 'Windows Update riattivato.'; en = 'Windows Update re-enabled.' })
        }
        '^fix:chkdsk$' {
            $out = @()
            foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.FileSystemType -in @('NTFS', 'ReFS') })) {
                $l = [string]$v.DriveLetter
                if ($Sync) { $Sync.Step = (L @{ it = "Controllo il disco $($l):"; en = "Checking drive $($l):" }) }
                $r = [string](Repair-Volume -DriveLetter $l -Scan -ErrorAction SilentlyContinue)
                if ($r -and $r -ne 'NoErrorsFound') {
                    $r2 = [string](Repair-Volume -DriveLetter $l -SpotFix -ErrorAction SilentlyContinue)
                    $out += "$($l): $r2"
                } else { $out += "$($l): OK" }
            }
            return ((L @{ it = 'Controllo dischi completato: '; en = 'Disk check finished: ' }) + ($out -join ', ') + (L @{ it = '. Se un disco esterno continua a dare errori, copia i tuoi file e sostituiscilo.'; en = '. If an external disk keeps showing errors, copy your files and replace it.' }))
        }
        '^fix:memtest$' {
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\MdSched.exe')
            return (L @{ it = 'Ho aperto la Diagnostica memoria di Windows: scegli "Riavvia ora e verifica". Se trova errori, il colpevole è la RAM o il profilo EXPO/XMP.'; en = 'Windows Memory Diagnostic is open: choose "Restart now and check". If it finds errors, the RAM or the EXPO/XMP profile is to blame.' })
        }
        '^fix:wuscan$' {
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\UsoClient.exe') -ArgumentList 'StartInteractiveScan' -WindowStyle Hidden -ErrorAction SilentlyContinue
            Start-Process 'ms-settings:windowsupdate'
            return (L @{ it = 'Ricerca aggiornamenti avviata in Windows Update.'; en = 'Windows Update scan started.' })
        }
        '^fix:drivers$' {
            & pnputil.exe /scan-devices 2>&1 | Out-Null
            Start-Process 'ms-settings:windowsupdate-optionalupdates'
            return (L @{ it = 'Ho rianalizzato i dispositivi e aperto "Aggiornamenti facoltativi": installa i driver che trovi lì.'; en = 'Devices rescanned and "Optional updates" opened: install the drivers listed there.' })
        }
        '^fix:defsig$' {
            Update-MpSignature -ErrorAction SilentlyContinue
            return (L @{ it = 'Antivirus aggiornato.'; en = 'Antivirus updated.' })
        }
        '^fix:uac$' {
            Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1 -Type DWord
            return (L @{ it = 'Controllo account riattivato. Riavvia il PC.'; en = 'User Account Control turned on. Restart the PC.' })
        }
        '^fix:trim$' { & fsutil behavior set DisableDeleteNotify 0 2>&1 | Out-Null; return (L @{ it = 'TRIM attivato.'; en = 'TRIM enabled.' }) }
        '^fix:firewall$' { Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled True -ErrorAction SilentlyContinue; return (L @{ it = 'Firewall riattivato.'; en = 'Firewall turned on.' }) }
        '^fix:pagefile$' {
            $cs = Get-CimInstance Win32_ComputerSystem
            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
            return (L @{ it = 'File di paging riattivato (gestito da Windows). Riavvia il PC.'; en = 'Page file re-enabled (managed by Windows). Restart the PC.' })
        }
        '^fix:refresh\|(.+)\|(\d+)$' {
            $dev = $Matches[1]; $hz = [int]$Matches[2]
            $cur = @([VeloxPC.Native]::GetDisplays() | Where-Object { $_.Device -eq $dev }) | Select-Object -First 1
            Start-VxTx -Id ("display:" + $dev) -Title ((L @{ it = 'Frequenza schermo '; en = 'Screen refresh rate ' }) + "$hz Hz")
            if ($cur) { Add-VxCustomUndo "display|$dev" @{ kind = 'display'; device = $dev; hz = $cur.CurrentHz } }
            $r = [VeloxPC.Native]::SetRefreshRate($dev, $hz)
            Complete-VxTx
            if ($r -eq 0) { return (L @{ it = "Schermo impostato a $hz Hz."; en = "Screen set to $hz Hz." }) }
            [void](Undo-VxEntry ("display:" + $dev))
            return (L @{ it = "Il monitor non ha accettato $hz Hz con questo cavo/porta (codice $r). Prova un cavo DisplayPort o HDMI 2.1."; en = "The monitor did not accept $hz Hz with this cable/port (code $r). Try a DisplayPort or HDMI 2.1 cable." })
        }
        '^fix:gamemode$' { $t = Find-VxTweak 'gamemode'; [void](Invoke-VxTweak $t $Hw); return (L @{ it = 'Modalità Gioco attivata.'; en = 'Game Mode turned on.' }) }
        '^fix:powerplan$' { $t = Find-VxTweak 'powerplan'; [void](Invoke-VxTweak $t $Hw); return (L @{ it = 'Piano energetico prestazioni attivato.'; en = 'Performance power plan enabled.' }) }
        '^fix:repair$' {
            Write-VxLog 'Repair: DISM RestoreHealth'
            Invoke-VxToolProgress 'DISM.exe' '/Online /Cleanup-Image /RestoreHealth' $Sync 0 60 (L @{ it = 'Passo 1 di 2 - DISM ripara i componenti'; en = 'Step 1 of 2 - DISM repairs components' })
            Write-VxLog 'Repair: SFC'
            Invoke-VxToolProgress 'sfc.exe' '/scannow' $Sync 60 100 (L @{ it = 'Passo 2 di 2 - SFC controlla i file di sistema'; en = 'Step 2 of 2 - SFC checks system files' })
            return (L @{ it = 'Riparazione completata. Riavvia il PC.'; en = 'Repair finished. Restart the PC.' })
        }
    }
    return ''
}
