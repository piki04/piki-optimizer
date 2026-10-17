# VeloxPC - Adobe After Effects optimization

$script:VxAeCache = $null

function Get-VxAdobeApps {
    if ($script:VxAeCache) { return $script:VxAeCache }
    $roots = @()
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramW6432})) { if ($pf -and (Test-Path -LiteralPath (Join-Path $pf 'Adobe'))) { $roots += (Join-Path $pf 'Adobe') } }
    # custom install locations from the uninstall registry
    foreach ($u in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($e in @(Get-ItemProperty $u -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Adobe After Effects|Adobe Media Encoder|Adobe Premiere Pro' -and $_.InstallLocation })) {
            $parent = Split-Path -Parent ([string]$e.InstallLocation).TrimEnd('\')
            if ($parent -and (Test-Path -LiteralPath $parent)) { $roots += $parent }
        }
    }
    $roots = @($roots | Select-Object -Unique)
    $ae = @(); $ame = @(); $pr = @()
    foreach ($r in $roots) {
        foreach ($d in @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue)) {
            if ($d.Name -match '^Adobe After Effects') {
                $exe = Join-Path $d.FullName 'Support Files\AfterFX.exe'
                if (Test-Path -LiteralPath $exe) {
                    $ver = ''
                    try { $ver = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).ProductVersion } catch { }
                    $ae += [pscustomobject]@{ Name = $d.Name; Exe = $exe; Aerender = (Join-Path $d.FullName 'Support Files\aerender.exe'); Dir = $d.FullName; Version = $ver }
                }
            } elseif ($d.Name -match '^Adobe Media Encoder') {
                $exe = Join-Path $d.FullName 'Adobe Media Encoder.exe'
                if (Test-Path -LiteralPath $exe) { $ame += [pscustomobject]@{ Name = $d.Name; Exe = $exe } }
            } elseif ($d.Name -match '^Adobe Premiere Pro') {
                $exe = Join-Path $d.FullName 'Adobe Premiere Pro.exe'
                if (Test-Path -LiteralPath $exe) { $pr += [pscustomobject]@{ Name = $d.Name; Exe = $exe } }
            }
        }
    }
    $script:VxAeCache = [pscustomobject]@{
        AE = @($ae | Sort-Object Name -Descending)
        AME = @($ame | Sort-Object Name -Descending)
        PR = @($pr | Sort-Object Name -Descending)
        Installed = ($ae.Count -gt 0)
    }
    return $script:VxAeCache
}

function Get-VxAdobeExes {
    $a = Get-VxAdobeApps
    $list = @()
    foreach ($x in $a.AE) { $list += $x.Exe; if (Test-Path -LiteralPath $x.Aerender) { $list += $x.Aerender } }
    foreach ($x in $a.AME) { $list += $x.Exe }
    foreach ($x in $a.PR) { $list += $x.Exe }
    return @($list | Select-Object -Unique)
}

function Get-VxBestCacheDrive {
    param($Hw)
    $best = $null; $bestScore = -1
    foreach ($v in $Hw.Volumes) {
        $disk = @($Hw.Disks | Where-Object { $_.Number -eq $v.DiskNumber }) | Select-Object -First 1
        if (-not $disk -or $disk.Media -ne 'SSD' -or $disk.Bus -eq 'USB') { continue }
        $freeGB = [math]::Floor($v.FreeBytes / 1GB)
        if ($freeGB -lt 20) { continue }
        $score = [math]::Min($freeGB, 500) / 10
        if ($disk.Bus -eq 'NVMe') { $score += 40 }
        if (-not $disk.IsSystem -and $freeGB -ge 100) { $score += 25 }
        if ($score -gt $bestScore) { $bestScore = $score; $best = [pscustomobject]@{ Letter = $v.Letter; FreeGB = $freeGB; Bus = $disk.Bus; IsSystem = $disk.IsSystem; DiskName = $disk.Name } }
    }
    return $best
}

function Get-VxMediaCacheDirs {
    return @((Join-Path $env:APPDATA 'Adobe\Common\Media Cache Files'), (Join-Path $env:APPDATA 'Adobe\Common\Media Cache'))
}

function Get-VxAeTweaks {
    $apps = Get-VxAdobeApps
    if (-not $apps.Installed -and $apps.AME.Count -eq 0 -and $apps.PR.Count -eq 0) { return @() }
    $exeNames = @('AfterFX.exe', 'aerender.exe', 'Adobe Media Encoder.exe', 'Adobe Premiere Pro.exe')
    $prio = @()
    foreach ($n in $exeNames) { $prio += , @("HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$n\PerfOptions", 'CpuPriorityClass', 'DWord', 3) }
    return @(
        @{
            Id = 'ae.priority'; Cat = 'ae'; Risk = 'safe'; Presets = @('creator')
            Title = @{ it = 'Priorità CPU alta per After Effects e Media Encoder'; en = 'High CPU priority for After Effects and Media Encoder' }
            Desc = @{ it = 'After Effects, il render da riga di comando (aerender), Media Encoder e Premiere partono sempre con priorità "Alta": anteprime e render più rapidi quando il PC fa anche altro.'; en = 'After Effects, command-line render (aerender), Media Encoder and Premiere always start with "High" priority: faster previews and renders while the PC does other things.' }
            Reg = $prio
        },
        @{
            Id = 'ae.gpu'; Cat = 'ae'; Risk = 'safe'; Presets = @('creator')
            Title = @{ it = 'Usa sempre la scheda video potente'; en = 'Always use the powerful graphics card' }
            Desc = @{ it = 'Forza After Effects, Media Encoder e Premiere a usare la GPU dedicata (e non quella integrata nel processore).'; en = 'Forces After Effects, Media Encoder and Premiere to use the dedicated GPU (not the one built into the CPU).' }
            When = { param($hw) $hw.HasDedicatedGpu }
            Apply = {
                param($hw)
                foreach ($exe in (Get-VxAdobeExes)) { Set-VxReg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $exe 'String' 'GpuPreference=2;' }
            }
            Test = {
                param($hw)
                $exes = Get-VxAdobeExes; if ($exes.Count -eq 0) { return $false }
                foreach ($exe in $exes) { if (-not (Test-VxRegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $exe 'GpuPreference=2;')) { return $false } }
                return $true
            }
        },
        @{
            Id = 'ae.throttle'; Cat = 'ae'; Risk = 'safe'; Presets = @('creator')
            Title = @{ it = 'Render senza rallentamenti di Windows'; en = 'Renders without Windows throttling' }
            Desc = @{ it = 'Windows non riduce mai la velocità di After Effects e Media Encoder, nemmeno quando sono in secondo piano durante un render lungo.'; en = 'Windows never slows down After Effects and Media Encoder, even when they are in the background during a long render.' }
            Apply = {
                param($hw)
                foreach ($exe in (Get-VxAdobeExes)) {
                    Add-VxCustomUndo "pthrottle|$exe" @{ kind = 'pthrottle'; path = $exe }
                    & powercfg /powerthrottling disable /path "$exe" 2>&1 | Out-Null
                }
            }
        },
        @{
            Id = 'ae.defender'; Cat = 'ae'; Risk = 'caution'; Presets = @('creator')
            Title = @{ it = 'Antivirus più leggero sulle cartelle cache'; en = 'Lighter antivirus on cache folders' }
            Desc = @{ it = 'Microsoft Defender smette di scansionare ogni file di cache che After Effects scrive e legge migliaia di volte al minuto. Anteprime e scrubbing molto più fluidi.'; en = 'Microsoft Defender stops scanning every cache file After Effects writes and reads thousands of times a minute. Much smoother previews and scrubbing.' }
            Warn = @{ it = 'Riguarda solo le cartelle cache (non i tuoi progetti né i download).'; en = 'Only affects cache folders (not your projects or downloads).' }
            When = { param($hw) try { [bool](Get-MpComputerStatus -ErrorAction Stop).AntivirusEnabled } catch { $false } }
            Apply = {
                param($hw)
                $paths = @(Get-VxMediaCacheDirs)
                $best = Get-VxBestCacheDrive $hw
                if ($best) { $paths += (Join-Path ($best.Letter + '\') 'VeloxPC Cache') }
                $existing = @()
                try { $existing = @((Get-MpPreference -ErrorAction Stop).ExclusionPath) } catch { }
                foreach ($p in $paths) {
                    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
                    if ($existing -contains $p) { continue }
                    Add-VxCustomUndo "defender|$p" @{ kind = 'defender'; type = 'path'; value = $p }
                    Add-MpPreference -ExclusionPath $p -ErrorAction Stop
                }
            }
        }
    )
}

function New-VxAeCacheFolders {
    param($Hw)
    $best = Get-VxBestCacheDrive $Hw
    if (-not $best) { return $null }
    $root = Join-Path ($best.Letter + '\') 'VeloxPC Cache'
    $disk = Join-Path $root 'After Effects Disk Cache'
    $media = Join-Path $root 'Media Cache'
    foreach ($d in @($root, $disk, $media)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
    return [pscustomobject]@{ Disk = $disk; Media = $media; Drive = $best }
}

function Get-VxFontCount {
    $n = 0
    try { $n += @(Get-ChildItem -LiteralPath (Join-Path $env:windir 'Fonts') -File -ErrorAction Stop).Count } catch { }
    try { $u = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'; if (Test-Path -LiteralPath $u) { $n += @(Get-ChildItem -LiteralPath $u -File).Count } } catch { }
    return $n
}

function Get-VxAeReport {
    # Plain-language recommended settings (rows) + checks (findings) for this PC
    param($Hw)
    $apps = Get-VxAdobeApps
    $rows = @(); $checks = @()
    $ramGB = [int]$Hw.RAM.GB
    $reserve = [math]::Max(4, [math]::Min(12, [math]::Round($ramGB * 0.15)))
    $gpu = $Hw.GPU
    $best = Get-VxBestCacheDrive $Hw
    $cacheSize = 50
    if ($best) { $cacheSize = [int][math]::Max(30, [math]::Min(300, [math]::Floor($best.FreeGB * 0.25 / 10) * 10)) }

    $gpuMode = (L @{ it = 'Solo software (CPU)'; en = 'Software only (CPU)' })
    if ($gpu -and $gpu.Vendor -eq 'NVIDIA') { $gpuMode = 'Mercury GPU Acceleration (CUDA)' }
    elseif ($gpu) { $gpuMode = 'Mercury GPU Acceleration (OpenCL)' }

    $rows += @{ K = (L @{ it = 'Accelerazione GPU'; en = 'GPU acceleration' }); V = $gpuMode; H = (L @{ it = 'File > Impostazioni progetto > Rendering video ed effetti'; en = 'File > Project Settings > Video Rendering and Effects' }) }
    $rows += @{ K = (L @{ it = 'RAM lasciata alle altre app'; en = 'RAM reserved for other apps' }); V = "$reserve GB"; H = (L @{ it = "Modifica > Preferenze > Memoria e prestazioni (hai $ramGB GB: il resto va ad After Effects)"; en = "Edit > Preferences > Memory & Performance (you have $ramGB GB: the rest goes to After Effects)" }) }
    if ($best) {
        $p = Join-Path ($best.Letter + '\') 'VeloxPC Cache\After Effects Disk Cache'
        $rows += @{ K = (L @{ it = 'Cartella cache disco'; en = 'Disk cache folder' }); V = $p; H = (L @{ it = "Modifica > Preferenze > Media e cache disco. Disco $($best.Letter) ($($best.Bus), $($best.FreeGB) GB liberi) è il più veloce che hai."; en = "Edit > Preferences > Media & Disk Cache. Drive $($best.Letter) ($($best.Bus), $($best.FreeGB) GB free) is your fastest." }); Copy = $true }
        $rows += @{ K = (L @{ it = 'Dimensione cache disco'; en = 'Disk cache size' }); V = "$cacheSize GB"; H = (L @{ it = 'Più è grande, meno After Effects deve ricalcolare le anteprime.'; en = 'The bigger it is, the less After Effects has to re-render previews.' }) }
        $mp = Join-Path ($best.Letter + '\') 'VeloxPC Cache\Media Cache'
        $rows += @{ K = (L @{ it = 'Cartella cache media'; en = 'Media cache folder' }); V = $mp; H = (L @{ it = 'Stessa schermata: imposta anche "Elimina file della cache più vecchi di 30 giorni".'; en = 'Same screen: also set "Delete cache files older than 30 days".' }); Copy = $true }
    }
    $rows += @{ K = (L @{ it = 'Rendering multi-frame'; en = 'Multi-Frame Rendering' }); V = (L @{ it = "Attivo (usa i tuoi $($Hw.CPU.Threads) thread)"; en = "On (uses your $($Hw.CPU.Threads) threads)" }); H = (L @{ it = 'Modifica > Preferenze > Memoria e prestazioni: lascialo attivo.'; en = 'Edit > Preferences > Memory & Performance: keep it on.' }) }
    $rows += @{ K = (L @{ it = 'Pannelli accelerati'; en = 'Accelerated panels' }); V = (L @{ it = 'Attivo'; en = 'On' }); H = (L @{ it = 'Preferenze > Aspetto > "Accelerazione hardware dei pannelli Composizione, Livello e Metraggio".'; en = 'Preferences > Appearance > "Hardware Accelerate Composition, Layer, and Footage Panels".' }) }
    $rows += @{ K = (L @{ it = 'Video H.264 / HEVC'; en = 'H.264 / HEVC footage' }); V = (L @{ it = 'Usa proxy o converti in ProRes 422'; en = 'Use proxies or convert to ProRes 422' }); H = (L @{ it = 'I file da telefono e OBS sono pesantissimi da scorrere. Clic destro sul metraggio > Crea proxy, oppure converti con Media Encoder.'; en = 'Phone and OBS files are very heavy to scrub. Right-click footage > Create Proxy, or convert with Media Encoder.' }) }
    if ($gpu -and $gpu.Vendor -eq 'NVIDIA') {
        $rows += @{ K = (L @{ it = 'Driver NVIDIA'; en = 'NVIDIA driver' }); V = "Studio Driver (ora: $($gpu.NvidiaVersion))"; H = (L @{ it = 'Adobe consiglia i driver "Studio": stessa velocità nei giochi, più stabili in After Effects. Si scaricano dall''app NVIDIA.'; en = 'Adobe recommends "Studio" drivers: same game speed, more stable in After Effects. Get them from the NVIDIA app.' }) }
    }

    # ---- checks
    if (-not $apps.Installed) {
        $checks += @{ sev = 'info'; t = (L @{ it = 'After Effects non è installato: le ottimizzazioni di sistema valgono comunque per qualsiasi programma di montaggio.'; en = 'After Effects is not installed: system optimizations still help any editing app.' }) }
    } else {
        $checks += @{ sev = 'ok'; t = ((L @{ it = 'Trovato: '; en = 'Found: ' }) + (($apps.AE | ForEach-Object { "$($_.Name) ($($_.Version))" }) -join ', ')) }
    }
    if ($ramGB -lt 16) { $checks += @{ sev = 'crit'; t = (L @{ it = "Hai $ramGB GB di RAM: After Effects ne vuole almeno 16, meglio 32. È l'aggiornamento che ti darà di più."; en = "You have $ramGB GB of RAM: After Effects wants at least 16, ideally 32. It is the upgrade that will help most." }) } }
    elseif ($ramGB -lt 32) { $checks += @{ sev = 'warn'; t = (L @{ it = "Hai $ramGB GB di RAM: va bene, ma con 32 GB o più le anteprime lunghe restano in memoria."; en = "You have $ramGB GB of RAM: fine, but with 32 GB or more long previews stay in memory." }) } }
    else { $checks += @{ sev = 'ok'; t = (L @{ it = "$ramGB GB di RAM: ottimo per After Effects."; en = "$ramGB GB of RAM: great for After Effects." }) } }
    if ($gpu) {
        $vgb = [math]::Round($gpu.VramBytes / 1GB)
        if ($gpu.Integrated) { $checks += @{ sev = 'warn'; t = (L @{ it = 'Stai usando una grafica integrata: molti effetti GPU saranno lenti.'; en = 'You are using integrated graphics: many GPU effects will be slow.' }) } }
        elseif ($vgb -gt 0 -and $vgb -lt 4) { $checks += @{ sev = 'warn'; t = (L @{ it = "La scheda video ha $vgb GB: Adobe consiglia almeno 4 GB."; en = "Your graphics card has $vgb GB: Adobe recommends at least 4 GB." }) } }
        else { $checks += @{ sev = 'ok'; t = ("$($gpu.Name)" + $(if ($vgb -gt 0) { " - $vgb GB" } else { '' })) } }
        if ($gpu.Vendor -eq 'NVIDIA' -and $gpu.NvidiaVersion) {
            try { if ([double]$gpu.NvidiaVersion -lt 522.25) { $checks += @{ sev = 'crit'; t = (L @{ it = 'Driver NVIDIA troppo vecchio per l''accelerazione CUDA (serve 522.25 o più recente).'; en = 'NVIDIA driver too old for CUDA acceleration (522.25 or newer needed).' }) } } } catch { }
        }
    }
    if (-not $best) { $checks += @{ sev = 'warn'; t = (L @{ it = 'Nessun SSD con spazio sufficiente per la cache: liberane un po'' o aggiungi un SSD NVMe dedicato.'; en = 'No SSD with enough space for the cache: free some up or add a dedicated NVMe SSD.' }) } }
    elseif ($best.IsSystem) { $checks += @{ sev = 'info'; t = (L @{ it = 'La cache andrà sul disco di Windows: funziona, ma un secondo SSD NVMe solo per la cache sarebbe ancora meglio.'; en = 'The cache will live on the Windows drive: it works, but a second NVMe SSD just for cache would be even better.' }) } }
    $pf = @()
    try { $pf = @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop) } catch { }
    if ($pf.Count -eq 0) { $checks += @{ sev = 'crit'; t = (L @{ it = 'Il file di paging è disattivato: After Effects può chiudersi da solo quando finisce la RAM. Riattivalo dal Check-up.'; en = 'The page file is disabled: After Effects can crash when RAM runs out. Re-enable it from the Check-up.' }) } }
    $fonts = Get-VxFontCount
    if ($fonts -gt 1500) { $checks += @{ sev = 'warn'; t = (L @{ it = "Hai $fonts font installati: rallentano l'avvio di After Effects. Disinstalla quelli che non usi."; en = "You have $fonts fonts installed: they slow down After Effects startup. Uninstall the ones you do not use." }) } }
    return @{ Rows = $rows; Checks = $checks; Apps = $apps; Best = $best }
}

function Get-VxMediaCacheSize {
    $t = [int64]0
    foreach ($d in (Get-VxMediaCacheDirs)) { $t += ([VeloxPC.Native]::DirSize($d))[0] }
    return $t
}

function Clear-VxMediaCache {
    if (Test-VxProcessRunning @('AfterFX', 'Adobe Premiere Pro', 'Adobe Media Encoder', 'aerender')) { return -1 }
    $freed = [int64]0
    foreach ($d in (Get-VxMediaCacheDirs)) { $freed += [VeloxPC.Native]::DeleteContents($d, '*') }
    Write-VxLog "Adobe media cache cleaned: $freed bytes"
    return $freed
}
