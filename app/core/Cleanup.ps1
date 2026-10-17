# VeloxPC - safe disk cleanup

$script:VxCleanItems = @(
    @{ Id = 'temp'; Risk = 'safe'; Default = $true
        Title = @{ it = 'File temporanei'; en = 'Temporary files' }
        Desc = @{ it = 'File lasciati da installazioni e programmi. I file ancora in uso vengono saltati.'; en = 'Files left behind by installers and apps. Files still in use are skipped.' }
        Paths = { @($env:TEMP, (Join-Path $env:windir 'Temp')) } },
    @{ Id = 'wucache'; Risk = 'safe'; Default = $true
        Title = @{ it = 'Cache di Windows Update'; en = 'Windows Update cache' }
        Desc = @{ it = 'Aggiornamenti già installati che Windows tiene da parte.'; en = 'Already-installed updates Windows keeps around.' }
        Paths = { @((Join-Path $env:windir 'SoftwareDistribution\Download')) }
        Pre = { & net stop wuauserv 2>&1 | Out-Null; & net stop bits 2>&1 | Out-Null }
        Post = { & net start bits 2>&1 | Out-Null; & net start wuauserv 2>&1 | Out-Null } },
    @{ Id = 'delivopt'; Risk = 'safe'; Default = $true
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
        try { foreach ($p in @(& $c.Paths)) { if ($p) { $total += ([VeloxPC.Native]::DirSize($p))[0] } } } catch { }
        $res[$c.Id] = $total
    }
    return $res
}

function Invoke-VxClean {
    param([string[]]$Ids)
    $freed = [int64]0
    foreach ($c in $script:VxCleanItems) {
        if (-not ($Ids -contains $c.Id)) { continue }
        try {
            if ($c.Skip -and (& $c.Skip)) { continue }
            $before = [int64]0
            $paths = @(& $c.Paths)
            if ($c.Clean) {
                foreach ($p in $paths) { if ($p) { $before += ([VeloxPC.Native]::DirSize($p))[0] } }
                & $c.Clean
                $after = [int64]0
                foreach ($p in $paths) { if ($p) { $after += ([VeloxPC.Native]::DirSize($p))[0] } }
                $freed += [math]::Max(0, $before - $after)
            } else {
                if ($c.Pre) { & $c.Pre }
                foreach ($p in $paths) { if ($p) { $freed += [VeloxPC.Native]::DeleteContents($p, '*') } }
                if ($c.Post) { & $c.Post }
            }
        } catch { Write-VxLog "Clean $($c.Id): $($_.Exception.Message)" 'WARN' }
    }
    Write-VxLog "Cleanup freed $freed bytes"
    return $freed
}
