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

# ---- Topaz Video AI / Topaz Video
$script:VxTopazCache = $null
function Get-VxTopazApps {
    if ($script:VxTopazCache) { return $script:VxTopazCache }
    $dirs = @()
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramW6432})) {
        if (-not $pf) { continue }
        $r = Join-Path $pf 'Topaz Labs LLC'
        if (Test-Path -LiteralPath $r) { $dirs += @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Topaz Video' } | ForEach-Object { $_.FullName }) }
    }
    foreach ($u in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($e in @(Get-ItemProperty $u -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^Topaz Video' -and $_.InstallLocation })) {
            $d = ([string]$e.InstallLocation).TrimEnd('\')
            if (Test-Path -LiteralPath $d) { $dirs += $d }
        }
    }
    $apps = @()
    foreach ($d in @($dirs | Select-Object -Unique)) {
        $exe = @(Get-ChildItem -LiteralPath $d -Filter 'Topaz Video*.exe' -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending) | Select-Object -First 1
        if (-not $exe) { continue }
        $ver = ''
        try { $ver = [string][System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe.FullName).ProductVersion } catch { }
        $major = 0
        if ($ver -match '^(\d+)') { $major = [int]$Matches[1] }
        # "Topaz Video AI" 3.x-7.x, then the renamed "Topaz Video" (cloud / Starlight models)
        $isNew = ($exe.BaseName -notmatch '\bAI\b') -and ((Split-Path -Leaf $d) -notmatch '\bAI\b')
        $gen = if ($isNew) { 'tv' } elseif ($major -gt 0 -and $major -le 4) { 'legacy' } else { 'v5' }
        $name = if ($isNew) { 'Topaz Video' } else { 'Topaz Video AI' }
        $ff = Join-Path $d 'ffmpeg.exe'
        $apps += [pscustomobject]@{ Name = $name; Version = $ver; Major = $major; Gen = $gen; Dir = $d; Exe = $exe.FullName; ExeName = $exe.Name; Ffmpeg = $(if (Test-Path -LiteralPath $ff) { $ff } else { $null }) }
    }
    $script:VxTopazCache = [pscustomobject]@{ Apps = @($apps | Sort-Object Major -Descending); Installed = ($apps.Count -gt 0) }
    return $script:VxTopazCache
}

function Get-VxTopazExes {
    $list = @()
    foreach ($a in (Get-VxTopazApps).Apps) { $list += $a.Exe; if ($a.Ffmpeg) { $list += $a.Ffmpeg } }
    return @($list | Select-Object -Unique)
}

function Get-VxTopazModelDirs {
    $list = @()
    foreach ($n in @('TVAI_MODEL_DIR', 'TVAI_MODEL_DATA_DIR')) {
        $v = [Environment]::GetEnvironmentVariable($n, 'Machine'); if (-not $v) { $v = [Environment]::GetEnvironmentVariable($n, 'User') }
        if ($v -and (Test-Path -LiteralPath $v)) { $list += $v.TrimEnd('\') }
    }
    foreach ($d in @('Topaz Video AI', 'Topaz Video')) { $p = Join-Path $env:ProgramData "Topaz Labs LLC\$d"; if (Test-Path -LiteralPath $p) { $list += $p } }
    return @($list | Select-Object -Unique)
}

function Get-VxTopazTweaks {
    $tz = Get-VxTopazApps
    if (-not $tz.Installed) { return @() }
    $a = $tz.Apps[0]
    $label = ("$($a.Name) $($a.Version)").Trim()
    return @(
        @{
            Id = 'topaz.boost'; Cat = 'ae'; Risk = 'safe'; Presets = @('creator')
            Title = @{ it = "Ottimizza $label"; en = "Optimize $label" }
            Desc = @{ it = "Su misura per la tua versione: $($a.Name) e il suo motore di render (ffmpeg) usano sempre la scheda video dedicata invece della grafica integrata, partono con priorità più alta e Windows non li rallenta quando sono in secondo piano durante un export lungo."; en = "Tailored to your version: $($a.Name) and its render engine (ffmpeg) always use the dedicated graphics card instead of integrated graphics, start with higher priority, and Windows does not slow them down in the background during a long export." }
            When = { param($hw) $hw.HasDedicatedGpu }
            Apply = {
                param($hw)
                foreach ($exe in (Get-VxTopazExes)) {
                    Set-VxReg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $exe 'String' 'GpuPreference=2;'
                    Add-VxCustomUndo "pthrottle|$exe" @{ kind = 'pthrottle'; path = $exe }
                    & powercfg /powerthrottling disable /path "$exe" 2>&1 | Out-Null
                }
                # above normal, not high: Topaz works mostly on the GPU and the PC must stay usable (After Effects, browser)
                foreach ($n in @((Get-VxTopazApps).Apps | ForEach-Object { $_.ExeName } | Select-Object -Unique)) { Set-VxReg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$n\PerfOptions" 'CpuPriorityClass' 'DWord' 6 }
            }
            Test = {
                param($hw)
                $exes = Get-VxTopazExes; if ($exes.Count -eq 0) { return $false }
                foreach ($exe in $exes) { if (-not (Test-VxRegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' $exe 'GpuPreference=2;')) { return $false } }
                foreach ($a in (Get-VxTopazApps).Apps) { if (-not (Test-VxRegValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$($a.ExeName)\PerfOptions" 'CpuPriorityClass' 6)) { return $false } }
                return $true
            }
        },
        @{
            Id = 'topaz.defender'; Cat = 'ae'; Risk = 'caution'; Presets = @('creator')
            Title = @{ it = "Antivirus più leggero sui modelli di $($a.Name)"; en = "Lighter antivirus on $($a.Name) models" }
            Desc = @{ it = 'Microsoft Defender smette di scansionare i modelli AI (file da diversi GB) e la cartella di anteprime di Topaz: i modelli si caricano prima e l''anteprima parte più in fretta.'; en = 'Microsoft Defender stops scanning the AI models (multi-GB files) and the Topaz preview folder: models load faster and previews start sooner.' }
            Warn = @{ it = 'Riguarda solo le cartelle dei modelli e della cache di Topaz.'; en = 'Only affects the Topaz model and cache folders.' }
            When = { param($hw) (@(Get-VxTopazModelDirs).Count -gt 0) -and $(try { [bool](Get-MpComputerStatus -ErrorAction Stop).AntivirusEnabled } catch { $false }) }
            Apply = {
                param($hw)
                $paths = @(Get-VxTopazModelDirs)
                $best = Get-VxBestCacheDrive $hw
                if ($best) { $paths += (Join-Path ($best.Letter + '\') 'VeloxPC Cache\Topaz Video') }
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

function Get-VxTopazReport {
    # recommended in-app settings for the installed Topaz version on this PC
    param($Hw)
    $tz = Get-VxTopazApps
    $rows = @(); $checks = @()
    if (-not $tz.Installed) { return @{ Rows = $rows; Checks = $checks } }
    $a = $tz.Apps[0]
    $pre = 'Topaz · '
    $ramGB = [int]$Hw.RAM.GB
    $gpu = $Hw.GPU
    $vgb = if ($gpu -and $gpu.VramBytes) { [math]::Round($gpu.VramBytes / 1GB) } else { 0 }
    $where = if ($a.Gen -eq 'legacy') { (L @{ it = 'Preferenze'; en = 'Preferences' }) } else { (L @{ it = 'File > Preferenze > Processing'; en = 'File > Preferences > Processing' }) }

    $proc = (L @{ it = 'La scheda video dedicata'; en = 'The dedicated graphics card' })
    if ($gpu -and -not $gpu.Integrated) { $proc = $gpu.Name }
    $hasIgpu = @($Hw.GPUs | Where-Object { $_.Integrated }).Count -gt 0
    $rows += @{ K = $pre + 'AI Processor'; V = $proc; H = ($where + ' > AI Processor. ' + $(if ($hasIgpu) { (L @{ it = 'Scegli questa e non "Auto": il tuo processore ha anche una grafica integrata, molto più lenta.'; en = 'Pick this one, not "Auto": your CPU also has integrated graphics, which is much slower.' }) } else { (L @{ it = 'Selezionala in modo esplicito.'; en = 'Select it explicitly.' }) })) }

    $mem = if ($ramGB -ge 64) { 80 } elseif ($ramGB -ge 32) { 70 } elseif ($ramGB -ge 16) { 60 } else { 50 }
    $rows += @{ K = $pre + 'Max Memory %'; V = "$mem %"; H = (L @{ it = "$where > Max Memory. Hai $ramGB GB. Se lavori insieme ad After Effects scendi a $([math]::Max(40, $mem - 20)) %, così non si contendono la RAM."; en = "$where > Max Memory. You have $ramGB GB. If you work alongside After Effects go down to $([math]::Max(40, $mem - 20)) % so they do not fight over RAM." }) }

    $maxp = if ($vgb -ge 16) { 3 } elseif ($vgb -ge 8) { 2 } else { 1 }
    if ($a.Gen -eq 'legacy') { $maxp = [math]::Min($maxp, 2) }
    $rows += @{ K = $pre + 'Max Processes'; V = "$maxp"; H = (L @{ it = "$where > Max Processes. Con $vgb GB di memoria video $maxp export in parallelo è il punto giusto: di più rallenta ognuno."; en = "$where > Max Processes. With $vgb GB of video memory, $maxp parallel exports is the sweet spot: more slows each one down." }) }

    if ($gpu -and $gpu.Vendor -eq 'NVIDIA') {
        $enc = if ($gpu.Name -match 'RTX\s*(40|50)\d\d') { 'H.265 NVENC (AV1 NVENC)' } else { 'H.265 NVENC' }
        $rows += @{ K = $pre + (L @{ it = 'Encoder video'; en = 'Video encoder' }); V = $enc; H = (L @{ it = 'Nelle impostazioni di export: l''encoder della scheda video libera la CPU e accorcia l''export.'; en = 'In the export settings: the graphics card encoder frees the CPU and shortens the export.' }) }
    }
    if ($a.Gen -ne 'legacy') {
        $rows += @{ K = $pre + 'Hardware Decoding'; V = (L @{ it = 'Attivo'; en = 'On' }); H = (L @{ it = "$where. Accelera la lettura di H.264, H.265 e AV1. Spegnilo solo se un video dà errori di decodifica."; en = "$where. Speeds up reading H.264, H.265 and AV1. Turn it off only if a video gives decode errors." }) }
    }
    $best = Get-VxBestCacheDrive $Hw
    if ($best) {
        $tp = Join-Path ($best.Letter + '\') 'VeloxPC Cache\Topaz Video'
        $rows += @{ K = $pre + (L @{ it = 'Cartella temporanea / anteprime'; en = 'Temporary / preview folder' }); V = $tp; H = (L @{ it = "Preferenze > Use Temporary Directory. Disco $($best.Letter) ($($best.Bus)) è il più veloce che hai."; en = "Preferences > Use Temporary Directory. Drive $($best.Letter) ($($best.Bus)) is your fastest." }); Copy = $true }
    }
    if ($a.Gen -eq 'tv') {
        $rows += @{ K = $pre + 'Live Render in Preview'; V = $(if ($vgb -ge 12) { (L @{ it = 'A piacere'; en = 'Your choice' }) } else { (L @{ it = 'Spento'; en = 'Off' }) }); H = (L @{ it = 'Preferenze > Advanced. Occupa la GPU anche mentre guardi l''anteprima: spegnilo se l''interfaccia scatta.'; en = 'Preferences > Advanced. Keeps the GPU busy while you watch the preview: turn it off if the interface stutters.' }) }
        $rows += @{ K = $pre + 'Cloud Processing'; V = (L @{ it = 'Solo se usi Starlight'; en = 'Only if you use Starlight' }); H = (L @{ it = 'Preferenze > Advanced. Se non usi i modelli Starlight puoi spegnerlo: niente connessioni in background.'; en = 'Preferences > Advanced. If you do not use Starlight models you can turn it off: no background connections.' }) }
    }
    if ($a.Gen -eq 'legacy') {
        $checks += @{ sev = 'info'; t = (L @{ it = "Hai $($a.Name) $($a.Version): le versioni 5 e successive sono molto più veloci sulle schede video recenti.";  en = "You have $($a.Name) $($a.Version): version 5 and later are much faster on recent graphics cards." }) }
    }
    $checks += @{ sev = 'ok'; t = ((L @{ it = 'Trovato: '; en = 'Found: ' }) + (($tz.Apps | ForEach-Object { ("$($_.Name) $($_.Version)").Trim() }) -join ', ')) }
    return @{ Rows = $rows; Checks = $checks }
}

function Get-VxAeTweaks {
    $apps = Get-VxAdobeApps
    if (-not $apps.Installed -and $apps.AME.Count -eq 0 -and $apps.PR.Count -eq 0) { return @(Get-VxTopazTweaks) }
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
    ) + @(Get-VxTopazTweaks)
}

function New-VxAeCacheFolders {
    param($Hw)
    $best = Get-VxBestCacheDrive $Hw
    if (-not $best) { return $null }
    $root = Join-Path ($best.Letter + '\') 'VeloxPC Cache'
    $disk = Join-Path $root 'After Effects Disk Cache'
    $media = Join-Path $root 'Media Cache'
    $dirs = @($root, $disk, $media)
    if ((Get-VxTopazApps).Installed) { $dirs += (Join-Path $root 'Topaz Video') }
    foreach ($d in $dirs) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
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
    try { $tzr = Get-VxTopazReport $Hw; $rows += @($tzr.Rows); $checks += @($tzr.Checks) } catch { }
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
