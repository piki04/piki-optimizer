# Piki Optimizer 2.0 - "Misura": real before/after numbers instead of a score.
# Everything here is READ-ONLY (the disk test writes and deletes one temporary file in %TEMP%).

function Get-VxBootTime {
    # Windows boot performance (event 100 of Diagnostics-Performance): total, main path and post-boot, in ms
    try {
        $e = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop)[0]
        return (ConvertFrom-VxBootEvent $e.ToXml() $e.TimeCreated)
    } catch { return $null }
}

function ConvertFrom-VxBootEvent {
    param([string]$Xml, $When)
    try {
        $doc = [xml]$Xml
        $d = @{}
        foreach ($n in @($doc.Event.EventData.Data)) { $d[[string]$n.Name] = [string]$n.'#text' }
        $total = [int64]$d['BootTime']
        if ($total -le 0) { return $null }
        return @{ total = $total; main = [int64]$d['MainPathBootTime']; post = [int64]$d['BootPostBootTime']; when = $(if ($When) { ([datetime]$When).ToString('yyyy-MM-dd HH:mm') } else { '' }) }
    } catch { return $null }
}

function Measure-VxIdleCpu {
    # average total CPU % over $Seconds, plus the 5 busiest processes
    param([int]$Seconds = 10)
    [void][VeloxPC.Native]::CpuUsage()
    $samples = @()
    for ($i = 0; $i -lt $Seconds; $i++) { Start-Sleep -Milliseconds 1000; $samples += [VeloxPC.Native]::CpuUsage() }
    $avg = ($samples | Measure-Object -Average).Average
    $top = @()
    try { $top = @([VeloxPC.Native]::SnapshotProcesses(1000) | Where-Object { $_.Id -ne $PID -and $_.Name -ne 'Idle' } | Sort-Object Cpu -Descending | Select-Object -First 5 | ForEach-Object { @{ name = $_.Name; cpu = [math]::Round($_.Cpu, 1) } }) } catch { }
    return @{ avg = [math]::Round($avg, 1); top = $top }
}

function Measure-VxPing {
    # 20 pings to 1.1.1.1: average and jitter in ms, loss in %
    try {
        $pr = New-Object VeloxPC.PingRunner -ArgumentList (, [string[]]@('1.1.1.1'))
        $pr.Start(20, 150)
        $t0 = [DateTime]::Now
        while ($pr.Running -and ([DateTime]::Now - $t0).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 200 }
        $st = [VeloxPC.PingRunner]::Stats($pr.Snapshot(0))
        if ($st[5] -le 0) { return $null }
        return @{ avg = [math]::Round($st[0], 1); jitter = [math]::Round($st[3], 1); loss = [math]::Round($st[4], 1) }
    } catch { return $null }
}

function New-VxMeasureSnapshot {
    # One full read-only measurement. Takes about 20-25 seconds.
    param($Hw, $Sync, [switch]$NoPing)
    $step = { param($it, $en, $p) if ($Sync) { $Sync.Step = L @{ it = $it; en = $en }; $Sync.Pct = $p } }
    $s = [ordered]@{ time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); ver = 1 }
    & $step 'Leggo il tempo di avvio...' 'Reading the boot time...' 5
    $s.boot = Get-VxBootTime
    & $step 'Conto le app all''avvio...' 'Counting startup apps...' 12
    try {
        $st = @(Get-VxStartupItems | Where-Object { $_.Enabled })
        $s.startup = @{ count = $st.Count; high = @($st | Where-Object { $_.Impact -eq 'high' }).Count; medium = @($st | Where-Object { $_.Impact -eq 'medium' }).Count }
    } catch { $s.startup = $null }
    & $step 'Misuro il processore a riposo (10 s)...' 'Measuring the idle processor (10 s)...' 20
    $s.cpu = Measure-VxIdleCpu 10
    $m = [VeloxPC.Native]::Memory()
    $s.ram = @{ usedGB = [math]::Round(($m[1] - $m[2]) / 1GB, 2); totalGB = [math]::Round($m[1] / 1GB, 1); pct = [int]$m[0] }
    try { $s.procs = @(Get-Process -ErrorAction Stop).Count } catch { $s.procs = 0 }
    & $step 'Controllo lo spazio libero...' 'Checking free space...' 62
    try {
        $sd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
        $s.disk = @{ freeGB = [math]::Round([int64]$sd.FreeSpace / 1GB, 1); sizeGB = [math]::Round([int64]$sd.Size / 1GB); freePct = [int](100 * [int64]$sd.FreeSpace / [math]::Max(1, [int64]$sd.Size)) }
    } catch { $s.disk = $null }
    & $step 'Velocità del processore (3 s)...' 'Processor speed (3 s)...' 70
    try { $s.cpuScore = [math]::Round([VeloxPC.Extra]::CpuBench(3000) / 1000, 1) } catch { $s.cpuScore = $null }
    & $step 'Velocità del disco (4 KB casuali)...' 'Disk speed (4 KB random)...' 80
    try { $r = [VeloxPC.Extra]::DiskRandomRead($env:TEMP, 64, 2500); $s.diskRead = $(if ($r -gt 0) { [math]::Round($r, 1) } else { $null }) } catch { $s.diskRead = $null }
    if (-not $NoPing) { & $step 'Misuro il ping...' 'Measuring ping...' 90; $s.ping = Measure-VxPing }
    & $step 'Fatto' 'Done' 100
    return $s
}

function Save-VxMeasureSnapshot {
    # bench.json: first snapshot = baseline ("before"); every new one becomes "latest" (history keeps 10)
    param($Snap, [switch]$AsBaseline)
    $b = ConvertTo-VxHashtable (Read-VxJson 'bench.json' $null)
    if (-not $b) { $b = @{} }
    if ($AsBaseline -or -not $b.baseline) { $b.baseline = $Snap }
    $b.latest = $Snap
    $hist = @(@($b.history) | Where-Object { $_ }) + @($Snap)
    if ($hist.Count -gt 10) { $hist = $hist[($hist.Count - 10)..($hist.Count - 1)] }
    $b.history = $hist
    $b.pendingAfterReboot = ''
    Write-VxJson 'bench.json' $b
    return $b
}

function Set-VxMeasureAfterReboot {
    # after optimizing: measure again automatically after the next restart (boot time needs a reboot)
    $b = ConvertTo-VxHashtable (Read-VxJson 'bench.json' $null)
    if (-not $b -or -not $b.baseline) { return }
    $b.pendingAfterReboot = (Get-Date -Format 'o')
    Write-VxJson 'bench.json' $b
}

function Test-VxMeasureDue {
    param($LastBoot)
    $b = ConvertTo-VxHashtable (Read-VxJson 'bench.json' $null)
    if (-not $b -or -not $b.pendingAfterReboot) { return $false }
    try { return ([datetime]$LastBoot -gt [datetime]::Parse([string]$b.pendingAfterReboot)) } catch { return $false }
}

function Get-VxMeasureDeltas {
    # list of @{ key; before; after; unit; better('lower'|'higher'); delta; good } for the cards
    param($Before, $After)
    $rows = @()
    $add = {
        param($k, $b, $a, $unit, $better)
        if ($null -eq $a) { return }
        $d = $null; $good = $null
        if ($null -ne $b) {
            $d = [double]$a - [double]$b
            if ([math]::Abs($d) -lt 0.0001) { $good = $null } elseif ($better -eq 'lower') { $good = ($d -lt 0) } else { $good = ($d -gt 0) }
        }
        $script:VxDeltaRows += @{ key = $k; before = $b; after = $a; unit = $unit; better = $better; delta = $d; good = $good }
    }
    $script:VxDeltaRows = @()
    $g = { param($o, [string[]]$p) $x = $o; foreach ($n in $p) { if ($null -eq $x) { return $null }; $x = $x[$n] }; return $x }
    & $add 'boot' $(if ($Before) { $v = & $g $Before @('boot', 'total'); if ($null -ne $v) { [math]::Round($v / 1000, 1) } }) $(if ($After) { $v = & $g $After @('boot', 'total'); if ($null -ne $v) { [math]::Round($v / 1000, 1) } }) 's' 'lower'
    & $add 'startup' (& $g $Before @('startup', 'count')) (& $g $After @('startup', 'count')) '' 'lower'
    & $add 'ram' (& $g $Before @('ram', 'usedGB')) (& $g $After @('ram', 'usedGB')) 'GB' 'lower'
    & $add 'cpu' (& $g $Before @('cpu', 'avg')) (& $g $After @('cpu', 'avg')) '%' 'lower'
    & $add 'procs' (& $g $Before @('procs')) (& $g $After @('procs')) '' 'lower'
    & $add 'disk' (& $g $Before @('disk', 'freeGB')) (& $g $After @('disk', 'freeGB')) 'GB' 'higher'
    & $add 'diskread' (& $g $Before @('diskRead')) (& $g $After @('diskRead')) 'MB/s' 'higher'
    & $add 'cpuscore' (& $g $Before @('cpuScore')) (& $g $After @('cpuScore')) '' 'higher'
    & $add 'ping' (& $g $Before @('ping', 'avg')) (& $g $After @('ping', 'avg')) 'ms' 'lower'
    & $add 'jitter' (& $g $Before @('ping', 'jitter')) (& $g $After @('ping', 'jitter')) 'ms' 'lower'
    return $script:VxDeltaRows
}

# ---------------------------------------------------------------- shareable report (no user name, no paths)
function Get-VxReportText {
    param($Hw, $Health, $Bench, [string]$Version)
    $sb = New-Object System.Text.StringBuilder
    $line = { param($t) [void]$sb.AppendLine($t) }
    & $line "Piki Optimizer $Version - $(L @{ it = 'report del PC'; en = 'PC report' }) ($(Get-Date -Format 'yyyy-MM-dd'))"
    & $line '----------------------------------------'
    if ($Hw) {
        & $line "CPU: $($Hw.CPU.Name) ($($Hw.CPU.Cores)c/$($Hw.CPU.Threads)t)"
        if ($Hw.GPU) { & $line ("GPU: $($Hw.GPU.Name)" + $(if ($Hw.GPU.VramBytes -gt 0) { " $([math]::Round($Hw.GPU.VramBytes / 1GB)) GB" } else { '' }) + " - driver $($Hw.GPU.DriverVersion)") }
        & $line "RAM: $($Hw.RAM.GB) GB $($Hw.RAM.Type) $($Hw.RAM.SpeedMTs) MT/s, $($Hw.RAM.Modules) module(s)"
        foreach ($d in @($Hw.Disks)) { & $line ("Disk: $($d.Name) ($($d.Media) $($d.Bus), $([math]::Round($d.SizeBytes / 1GB)) GB)" + $(if ($d.IsSystem) { ' [Windows]' } else { '' })) }
        & $line "Windows: $($Hw.OS.Name) $($Hw.OS.DisplayVersion) build $($Hw.OS.Build).$($Hw.OS.Ubr)"
        if ($Hw.Board.Name) { & $line "Board: $($Hw.Board.Name) BIOS $($Hw.Board.Bios) ($($Hw.Board.BiosDate))" }
        & $line ("Type: " + $(if ($Hw.IsLaptop) { 'laptop' } else { 'desktop' }))
    }
    if ($Health) {
        & $line ''
        & $line "Check-up $($Health.time): $($Health.score)/100 ($($Health.crit) crit, $($Health.warn) warn)"
        foreach ($f in @($Health.findings | Where-Object { $_.sev -in @('crit', 'warn') })) { & $line ("  [$($f.sev)] " + $f.title) }
    }
    if ($Bench -and $Bench.latest) {
        & $line ''
        & $line (L @{ it = 'Misure (prima -> adesso):'; en = 'Measurements (before -> now):' })
        foreach ($r in (Get-VxMeasureDeltas $Bench.baseline $Bench.latest)) { & $line ("  {0}: {1} -> {2} {3}" -f $r.key, $(if ($null -ne $r.before) { $r.before } else { '-' }), $r.after, $r.unit) }
    }
    $txt = $sb.ToString()
    # never leak the user name or profile paths
    $txt = $txt -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%'
    if ($env:USERNAME) { $txt = $txt -replace [regex]::Escape($env:USERNAME), '<user>' }
    return $txt
}
