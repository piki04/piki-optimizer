# VeloxPC - safe disk cleanup

$script:VxCleanItems = @(
    @{ Id = 'temp'; Risk = 'safe'; Default = $true; Scheduled = $true; MinAgeHours = 24
        Title = @{ it = 'File temporanei'; en = 'Temporary files' }
        Desc = @{ it = 'File lasciati da installazioni e programmi, solo quelli più vecchi di un giorno. I file ancora in uso vengono saltati.'; en = 'Files left behind by installers and apps, only those older than one day. Files still in use are skipped.' }
        Paths = { @($env:TEMP, (Join-Path $env:windir 'Temp')) } },
    @{ Id = 'wucache'; Risk = 'safe'; Default = $true
        Title = @{ it = 'Cache di Windows Update'; en = 'Windows Update cache' }
        Desc = @{ it = 'Aggiornamenti già installati che Windows tiene da parte.'; en = 'Already-installed updates Windows keeps around.' }
        Paths = { @((Join-Path $env:windir 'SoftwareDistribution\Download')) }
        Pre = { & net stop wuauserv 2>&1 | Out-Null; & net stop bits 2>&1 | Out-Null }
        Post = { & net start bits 2>&1 | Out-Null; & net start wuauserv 2>&1 | Out-Null } },
    @{ Id = 'delivopt'; Risk = 'safe'; Default = $true; Scheduled = $true
        Title = @{ it = 'Cache Ottimizzazione recapito'; en = 'Delivery Optimization cache' }
        Desc = @{ it = 'Pezzi di aggiornamenti condivisi con altri PC.'; en = 'Update pieces shared with other PCs.' }
        Paths = { @((Join-Path $env:windir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache')) }
        Clean = { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { } } },
    @{ Id = 'dumps'; Risk = 'safe'; Default = $true
        Title = @{ it = 'Report errori e dump'; en = 'Error reports and dumps' }
        Desc = @{ it = 'Rapporti di crash già inviati e file di dump. Se stai indagando su schermate blu, tienili.'; en = 'Already-sent crash reports and dump files. Keep them if you are investigating blue screens.' }
        Paths = { @((Join-Path $env:LOCALAPPDATA 'CrashDumps'), (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'), (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'), (Join-Path $env:windir 'LiveKernelReports'), (Join-Path $env:windir 'Minidump')) } },
    @{ Id = 'adobe'; Risk = 'safe'; Default = $true
        Title = @{ it = 'Cache media Adobe'; en = 'Adobe media cache' }
        Desc = @{ it = 'File di anteprima audio/video di After Effects e Premiere: vengono ricreati quando servono. Saltato se Adobe è aperto.'; en = 'After Effects and Premiere audio/video preview files: recreated when needed. Skipped if Adobe is open.' }
        Paths = { @(Get-VxMediaCacheDirs) }
        Skip = { Test-VxProcessRunning @('AfterFX', 'Adobe Premiere Pro', 'Adobe Media Encoder', 'aerender') } },
    @{ Id = 'gpudriver'; Risk = 'safe'; Default = $true; Scheduled = $true
        Title = @{ it = 'Installer vecchi dei driver video'; en = 'Old graphics driver installers' }
        Desc = @{ it = 'File di installazione dei driver NVIDIA e AMD già installati: spesso diversi GB. Il driver in uso non viene toccato.'; en = 'Setup files of already-installed NVIDIA and AMD drivers: often several GB. The driver in use is not touched.' }
        Paths = { @((Join-Path $env:SystemDrive 'NVIDIA'), (Join-Path $env:SystemDrive 'AMD'), (Join-Path $env:ProgramData 'NVIDIA Corporation\Downloader')) } },
    @{ Id = 'winlogs'; Risk = 'safe'; Default = $true; Scheduled = $true
        Title = @{ it = 'Log di Windows'; en = 'Windows logs' }
        Desc = @{ it = 'Registri di installazione e manutenzione di Windows già chiusi. Quelli in uso vengono saltati.'; en = 'Windows setup and servicing logs that are already closed. Logs in use are skipped.' }
        Paths = { @((Join-Path $env:windir 'Logs\CBS'), (Join-Path $env:windir 'Logs\DISM'), (Join-Path $env:windir 'Logs\MoSetup'), (Join-Path $env:windir 'Logs\WindowsUpdate')) } },
    @{ Id = 'thumbs'; Risk = 'safe'; Default = $false
        Title = @{ it = 'Anteprime delle immagini'; en = 'Image thumbnails' }
        Desc = @{ it = 'Le miniature di foto e video in Esplora file. Utile se mostrano immagini sbagliate; vengono ricreate quando apri le cartelle.'; en = 'Photo and video thumbnails in File Explorer. Useful if they show the wrong image; they are recreated when you open folders.' }
        Paths = { @((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer')) }
        Clean = { Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') -Filter 'thumbcache_*.db' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue } },
    @{ Id = 'appcache'; Risk = 'caution'; Default = $false
        Title = @{ it = 'Cache di Discord, Steam e Teams'; en = 'Discord, Steam and Teams caches' }
        Desc = @{ it = 'Immagini e file temporanei salvati da queste app: vengono riscaricati quando servono. Account e chat NON vengono toccati. Saltato se l''app è aperta.'; en = 'Images and temporary files saved by these apps: downloaded again when needed. Accounts and chats are NOT touched. Skipped if the app is open.' }
        Paths = {
            $out = @()
            if (-not (Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)) { foreach ($n in @('Cache', 'Code Cache', 'GPUCache')) { $out += (Join-Path $env:APPDATA "discord\$n") } }
            if (-not (Get-Process -Name 'steamwebhelper', 'steam' -ErrorAction SilentlyContinue)) { $out += (Join-Path $env:LOCALAPPDATA 'Steam\htmlcache') }
            if (-not (Get-Process -Name 'ms-teams', 'Teams' -ErrorAction SilentlyContinue)) { $out += (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\Default\Cache') }
            $out
        } },
    @{ Id = 'aedisk'; Risk = 'safe'; Default = $false
        Title = @{ it = 'Cache disco di After Effects'; en = 'After Effects disk cache' }
        Desc = @{ it = 'Le anteprime già calcolate salvate da After Effects nella cartella creata da Piki: vengono ricalcolate quando servono. Saltato se After Effects è aperto.'; en = 'Previews already rendered by After Effects in the folder Piki created: recalculated when needed. Skipped if After Effects is open.' }
        Paths = { @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.Root 'VeloxPC Cache\After Effects Disk Cache' } | Where-Object { Test-Path -LiteralPath $_ }) }
        Skip = { Test-VxProcessRunning @('AfterFX', 'aerender', 'Adobe Media Encoder') } },
    @{ Id = 'browser'; Risk = 'caution'; Default = $false
        Title = @{ it = 'Cache dei browser'; en = 'Browser caches' }
        Desc = @{ it = 'Immagini e file dei siti salvati da Chrome, Edge e Brave. Password e accessi NON vengono toccati. Saltato se il browser è aperto.'; en = 'Site images and files saved by Chrome, Edge and Brave. Passwords and logins are NOT touched. Skipped if the browser is open.' }
        Paths = {
            $out = @()
            foreach ($b in @(@{ R = 'Google\Chrome\User Data'; P = 'chrome' }, @{ R = 'Microsoft\Edge\User Data'; P = 'msedge' }, @{ R = 'BraveSoftware\Brave-Browser\User Data'; P = 'brave' })) {
                if (Get-Process -Name $b.P -ErrorAction SilentlyContinue) { continue }
                $root = Join-Path $env:LOCALAPPDATA $b.R
                if (-not (Test-Path -LiteralPath $root)) { continue }
                foreach ($prof in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
                    $out += (Join-Path $prof.FullName 'Cache'); $out += (Join-Path $prof.FullName 'Code Cache'); $out += (Join-Path $prof.FullName 'GPUCache')
                }
            }
            $out
        } },
    @{ Id = 'shader'; Risk = 'caution'; Default = $false
        Title = @{ it = 'Cache shader della scheda video'; en = 'Graphics shader cache' }
        Desc = @{ it = 'Utile SOLO se un gioco scatta dopo un aggiornamento dei driver. Dopo la pulizia i giochi ricompilano gli shader e i primi minuti possono scattare.'; en = 'ONLY useful if a game stutters after a driver update. Afterwards games recompile shaders and the first minutes may stutter.' }
        Paths = { @((Join-Path $env:LOCALAPPDATA 'D3DSCache'), (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'), (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'), (Join-Path $env:LOCALAPPDATA 'AMD\DxCache'), (Join-Path $env:LOCALAPPDATA 'AMD\DxcCache'), (Join-Path $env:LOCALAPPDATA 'AMD\VkCache'), (Join-Path ($env:LOCALAPPDATA + 'Low') 'NVIDIA\PerDriverVersion\DXCache'), (Join-Path ($env:LOCALAPPDATA + 'Low') 'Intel\ShaderCache')) } },
    @{ Id = 'recycle'; Risk = 'caution'; Default = $false
        Title = @{ it = 'Cestino'; en = 'Recycle Bin' }
        Desc = @{ it = 'Svuota il cestino di tutti i dischi. Non si può annullare.'; en = 'Empties the recycle bin on all drives. Cannot be undone.' }
        Paths = { @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.Root '$Recycle.Bin' }) }
        Clean = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } }
)

function Get-VxCleanSizes {
    $res = @{}
    foreach ($c in $script:VxCleanItems) {
        $total = [int64]0
        try {
            foreach ($p in @(& $c.Paths)) {
                if (-not $p) { continue }
                if ($c.MinAgeHours) { $total += [VeloxPC.Native]::OldSize($p, [double]$c.MinAgeHours) }
                else { $total += ([VeloxPC.Native]::DirSize($p))[0] }
            }
        } catch { }
        $res[$c.Id] = $total
    }
    return $res
}

# A folder whose CONTENTS may be deleted: never a drive root, the user profile, a user folder (Desktop, Documents,
# Downloads, Pictures, Videos, Music, OneDrive), Windows or Program Files, nor a folder that contains one of them.
# Guards against a broken TEMP variable (e.g. TEMP=C:\ or TEMP=%USERPROFILE%) emptying user files.
function Test-VxCleanPathSafe {
    param([string]$Path)
    try {
        if (-not $Path) { return $false }
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $root = [IO.Path]::GetPathRoot($full)
        if (-not $root -or $full.Length -le $root.TrimEnd('\').Length) { return $false }
        $prot = @($env:USERPROFILE, $env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, $env:OneDrive)
        foreach ($sf in @('Desktop', 'MyDocuments', 'MyPictures', 'MyVideos', 'MyMusic')) { try { $prot += [Environment]::GetFolderPath($sf) } catch { } }
        try { $prot += [string](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}' } catch { }
        if ($env:USERPROFILE) { $prot += (Join-Path $env:USERPROFILE 'Downloads') }
        foreach ($p in $prot) {
            if (-not $p) { continue }
            $pf = ([IO.Path]::GetFullPath([string]$p)).TrimEnd('\')
            if ($pf -ieq $full -or $pf.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        return $true
    } catch { return $false }
}

function Invoke-VxClean {
    param([string[]]$Ids)
    $freed = [int64]0
    foreach ($c in $script:VxCleanItems) {
        if (-not ($Ids -contains $c.Id)) { continue }
        if ($script:VxDryRun) { Add-VxDryRecord ("clean: " + (L $c.Title)); continue }
        try {
            if ($c.Skip -and (& $c.Skip)) { continue }
            $before = [int64]0
            # Winstep (Nexus dock) files are never touched
            $paths = @(& $c.Paths | Where-Object { $_ -and ([string]$_ -notmatch '(?i)\\Winstep') })
            if ($c.Clean) {
                foreach ($p in $paths) { if ($p) { $before += ([VeloxPC.Native]::DirSize($p))[0] } }
                & $c.Clean
                $after = [int64]0
                foreach ($p in $paths) { if ($p) { $after += ([VeloxPC.Native]::DirSize($p))[0] } }
                $freed += [math]::Max([int64]0, [int64]($before - $after))
            } else {
                $paths = @($paths | Where-Object { if (Test-VxCleanPathSafe $_) { $true } else { Write-VxLog "Clean $($c.Id): refused unsafe folder $_" 'WARN'; $false } })
                if ($c.Pre) { & $c.Pre }
                # Post (e.g. Windows Update and BITS started again) runs even if a deletion throws
                try {
                    foreach ($p in $paths) {
                        if ($c.MinAgeHours) { $freed += [VeloxPC.Native]::DeleteOlderThan($p, [double]$c.MinAgeHours) }
                        else { $freed += [VeloxPC.Native]::DeleteContents($p, '*') }
                    }
                } finally { if ($c.Post) { & $c.Post } }
            }
        } catch { Write-VxLog "Clean $($c.Id): $($_.Exception.Message)" 'WARN' }
    }
    Write-VxLog "Cleanup freed $freed bytes"
    return $freed
}

# Minidumps are kept by default when the check-up found blue screens (they are what a technician needs)
function Get-VxCleanDefault {
    param($Item, $Health)
    if ($Item.Id -eq 'dumps' -and $Health) {
        foreach ($fd in @($Health.findings)) { if ($fd.cat -eq 'stability' -and $fd.sev -eq 'crit') { return $false } }
    }
    return [bool]$Item.Default
}

# ---------------------------------------------------------------- scheduled cleaning
# A weekly or monthly Windows task, only when the PC is idle and on mains power, only the "Scheduled" items.
# It is saved like every other change (backup entry 'cleantask'), so Ripristino can remove it.
$script:VxCleanTaskName = 'PikiOptimizer Clean'
function Get-VxCleanTaskInfo {
    try {
        $t = Get-ScheduledTask -TaskName $script:VxCleanTaskName -ErrorAction Stop
        $i = Get-ScheduledTaskInfo -TaskName $script:VxCleanTaskName -ErrorAction SilentlyContinue
        return @{ exists = $true; next = $(if ($i -and $i.NextRunTime) { $i.NextRunTime.ToString('yyyy-MM-dd HH:mm') } else { '' }); last = $(if ($i -and $i.LastRunTime -and $i.LastRunTime.Year -gt 2000) { $i.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { '' }) }
    } catch { return @{ exists = $false; next = ''; last = '' } }
}

function Register-VxCleanTask {
    param([ValidateSet('weekly', 'monthly')][string]$Frequency, [string]$ScriptPath)
    if ($script:VxDryRun) { Add-VxDryRecord "scheduled task '$($script:VxCleanTaskName)' ($Frequency)"; return $true }
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $act = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -ScheduledClean"
    if ($Frequency -eq 'weekly') { $trg = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '12:00' }
    else { $trg = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At '12:00' }
    $set = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration ([TimeSpan]::FromMinutes(10)) -IdleWaitTimeout ([TimeSpan]::FromHours(4)) -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::FromMinutes(30)) -Priority 8
    $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $existed = [bool](Get-ScheduledTask -TaskName $script:VxCleanTaskName -ErrorAction SilentlyContinue)
    Register-ScheduledTask -TaskName $script:VxCleanTaskName -Action $act -Trigger $trg -Settings $set -Principal $prn -Force -ErrorAction Stop | Out-Null
    if (-not $existed) {
        Start-VxTx -Id 'cleantask' -Title (L @{ it = 'Pulizia programmata'; en = 'Scheduled cleaning' })
        Add-VxCustomUndo 'schedtask|clean' @{ kind = 'schedtask'; name = $script:VxCleanTaskName }
        Complete-VxTx
    }
    Write-VxLog "Scheduled cleaning: $Frequency"
    return $true
}

function Unregister-VxCleanTask {
    if (Test-VxBackupEntry 'cleantask') { [void](Undo-VxEntry 'cleantask') }
    else { Unregister-ScheduledTask -TaskName $script:VxCleanTaskName -Confirm:$false -ErrorAction SilentlyContinue }
}

function Invoke-VxScheduledClean {
    # runs from the task: below normal priority, safe items only, result kept for the app
    try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal' } catch { }
    $ids = [string[]]@($script:VxCleanItems | Where-Object { $_.Scheduled } | ForEach-Object { $_.Id })
    $freed = Invoke-VxClean $ids
    try { Write-VxJson 'cleanlast.json' @{ time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); freed = [int64]$freed } } catch { }
    return $freed
}