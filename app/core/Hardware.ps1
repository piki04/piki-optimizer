# VeloxPC - hardware detection

function Get-VxCim {
    param([string]$Class, [string]$Namespace = 'root/cimv2', [string]$Filter)
    try {
        if ($Filter) { return @(Get-CimInstance -Namespace $Namespace -ClassName $Class -Filter $Filter -ErrorAction Stop -OperationTimeoutSec 15) }
        return @(Get-CimInstance -Namespace $Namespace -ClassName $Class -ErrorAction Stop -OperationTimeoutSec 15)
    } catch { return @() }
}

function Get-VxGpuMemory {
    # Win32_VideoController.AdapterRAM is capped at 4 GB, so read the real VRAM from the driver key
    $map = @{}
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    try {
        Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if ($p -and $p.DriverDesc) {
                $mem = 0
                $q = $p.'HardwareInformation.qwMemorySize'
                if ($q) { $mem = [int64]$q }
                else {
                    $m = $p.'HardwareInformation.MemorySize'
                    if ($m -is [byte[]] -and $m.Length -ge 4) { $mem = [int64][BitConverter]::ToUInt32($m, 0) }
                    elseif ($m) { $mem = [int64]$m }
                }
                if ($mem -gt 0 -and (-not $map.ContainsKey($p.DriverDesc) -or $map[$p.DriverDesc] -lt $mem)) { $map[$p.DriverDesc] = $mem }
            }
        }
    } catch { }
    return $map
}

function Get-VxNvidiaVersion {
    param([string]$DriverVersion)
    # 32.0.15.6094 -> 560.94
    $d = ($DriverVersion -replace '[^0-9]', '')
    if ($d.Length -lt 5) { return '' }
    $last = $d.Substring($d.Length - 5)
    return ('{0}.{1}' -f [int]$last.Substring(0, 3), $last.Substring(3))
}

function Get-VxHardware {
    param([switch]$Quick, $Sync)
    $hw = [ordered]@{}
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $step = {
        param($it, $en, $pct)
        if ($Sync) { $Sync.Step = L @{ it = $it; en = $en }; $Sync.Pct = $pct }
        Write-VxLog ("hw: {0} ({1} ms)" -f $en, $sw.ElapsedMilliseconds)
    }
    & $step 'Leggo il sistema...' 'Reading the system...' 5

    # ---------------- system / OS
    $cs = Get-VxCim Win32_ComputerSystem | Select-Object -First 1
    $os = Get-VxCim Win32_OperatingSystem | Select-Object -First 1
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $build = 0; if ($os) { $build = [int]$os.BuildNumber }
    $osName = if ($os) { [string]$os.Caption } else { 'Windows' }
    if ($build -ge 22000 -and $osName -match 'Windows 10') { $osName = $osName -replace 'Windows 10', 'Windows 11' }
    $hw.OS = [pscustomobject]@{
        Name = ($osName -replace 'Microsoft ', '').Trim()
        Build = $build
        Ubr = if ($cv -and $null -ne $cv.UBR) { [int]$cv.UBR } else { 0 }
        DisplayVersion = if ($cv -and $cv.DisplayVersion) { [string]$cv.DisplayVersion } elseif ($cv) { [string]$cv.ReleaseId } else { '' }
        Edition = if ($cv) { [string]$cv.EditionID } else { '' }
        IsWin11 = ($build -ge 22000)
        LastBoot = if ($os) { $os.LastBootUpTime } else { $null }
        InstallDate = if ($os) { $os.InstallDate } else { $null }
        Arch = if ($os) { [string]$os.OSArchitecture } else { '' }
    }
    $hw.ComputerName = $env:COMPUTERNAME
    $hw.Model = if ($cs) { ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim() } else { '' }
    if ($hw.Model -match 'To Be Filled|System manufacturer|System Product Name|Default string') { $hw.Model = '' }

    # ---------------- chassis / laptop
    $enc = Get-VxCim Win32_SystemEnclosure | Select-Object -First 1
    $bat = Get-VxCim Win32_Battery
    $laptopTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    $isLaptop = $false
    if ($enc -and $enc.ChassisTypes) { foreach ($t in $enc.ChassisTypes) { if ($laptopTypes -contains [int]$t) { $isLaptop = $true } } }
    if (-not $isLaptop -and $cs -and $cs.PCSystemType -eq 2) { $isLaptop = $true }
    $hw.IsLaptop = $isLaptop
    $hw.HasBattery = ($bat.Count -gt 0)
    $hw.OnBattery = $false
    if ($bat.Count -gt 0) { $hw.OnBattery = ([int]$bat[0].BatteryStatus -eq 1) }

    & $step 'Riconosco il processore...' 'Detecting the processor...' 15
    # ---------------- CPU
    $cpu = Get-VxCim Win32_Processor | Select-Object -First 1
    $cpuName = if ($cpu) { ([string]$cpu.Name -replace '\s+', ' ').Trim() } else { 'CPU' }
    $vendor = 'Other'
    if ($cpu) { if ($cpu.Manufacturer -match 'Intel') { $vendor = 'Intel' } elseif ($cpu.Manufacturer -match 'AMD') { $vendor = 'AMD' } }
    $cpuCount = (Get-VxCim Win32_Processor).Count
    $hw.CPU = [pscustomobject]@{
        Name = $cpuName
        Vendor = $vendor
        Cores = if ($cpu) { [int]$cpu.NumberOfCores * [math]::Max(1, $cpuCount) } else { 0 }
        Threads = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors * [math]::Max(1, $cpuCount) } else { [Environment]::ProcessorCount }
        MaxMHz = if ($cpu) { [int]$cpu.MaxClockSpeed } else { 0 }
        IsX3DDual = ($cpuName -match '(7900|7950|9900|9950)X3D')
        IsX3D = ($cpuName -match 'X3D')
        IsHybrid = ($cpuName -match 'i[3579]-1[2-4]\d{3}' -or $cpuName -match 'Core\(TM\) Ultra|Core Ultra')
    }

    & $step 'Riconosco la scheda video...' 'Detecting the graphics card...' 25
    # ---------------- GPU(s)
    $vram = Get-VxGpuMemory
    $gpus = @()
    foreach ($g in (Get-VxCim Win32_VideoController)) {
        $pnp = [string]$g.PNPDeviceID
        if ($pnp -notmatch '^PCI\\') { continue }   # skip virtual / remote adapters
        $gv = 'Other'
        if ($g.Name -match 'NVIDIA|GeForce|Quadro|RTX') { $gv = 'NVIDIA' } elseif ($g.Name -match 'AMD|Radeon') { $gv = 'AMD' } elseif ($g.Name -match 'Intel') { $gv = 'Intel' }
        $mem = 0
        if ($vram.ContainsKey([string]$g.Name)) { $mem = $vram[[string]$g.Name] } elseif ($g.AdapterRAM) { $mem = [int64][uint32]$g.AdapterRAM }
        $integrated = ($gv -eq 'Intel' -and $g.Name -notmatch 'Arc A\d|Arc B\d') -or ($gv -eq 'AMD' -and $g.Name -match 'Radeon\(TM\) Graphics|Vega \d+ Graphics|Radeon Graphics$|780M|760M|890M|880M|680M|660M|610M')
        if ($mem -gt 0 -and $mem -lt 1GB -and $gv -ne 'Other') { $integrated = $true }
        $drvDate = $null
        try { if ($g.DriverDate) { $drvDate = [datetime]$g.DriverDate } } catch { }
        $gpus += [pscustomobject]@{
            Name = ([string]$g.Name).Trim()
            Vendor = $gv
            VramBytes = $mem
            DriverVersion = [string]$g.DriverVersion
            NvidiaVersion = if ($gv -eq 'NVIDIA') { Get-VxNvidiaVersion ([string]$g.DriverVersion) } else { '' }
            DriverDate = $drvDate
            Integrated = [bool]$integrated
            Status = [string]$g.Status
            ErrorCode = [int]$g.ConfigManagerErrorCode
        }
    }
    $hw.GPUs = @($gpus | Sort-Object @{ Expression = { if ($_.Integrated) { 1 } else { 0 } } }, @{ Expression = { $_.VramBytes }; Descending = $true })
    $hw.GPU = if ($hw.GPUs.Count -gt 0) { $hw.GPUs[0] } else { $null }
    $hw.HasDedicatedGpu = (@($hw.GPUs | Where-Object { -not $_.Integrated }).Count -gt 0)
    $hw.HybridGraphics = ($hw.HasDedicatedGpu -and @($hw.GPUs | Where-Object { $_.Integrated }).Count -gt 0)
    $hw.BasicDisplayOnly = ($hw.GPUs.Count -eq 0 -and @(Get-VxCim Win32_VideoController | Where-Object { $_.Name -match 'Basic Display|Microsoft Basic' }).Count -gt 0)

    & $step 'Controllo la RAM...' 'Checking RAM...' 35
    # ---------------- RAM
    $mods = Get-VxCim Win32_PhysicalMemory
    $arr = Get-VxCim Win32_PhysicalMemoryArray | Select-Object -First 1
    $totalRam = if ($cs) { [int64]$cs.TotalPhysicalMemory } else { 0 }
    $ramType = ''
    $speed = 0; $configured = 0
    if ($mods.Count -gt 0) {
        $m0 = $mods[0]
        switch ([int]$m0.SMBIOSMemoryType) { 24 { $ramType = 'DDR3' } 26 { $ramType = 'DDR4' } 34 { $ramType = 'DDR5' } 30 { $ramType = 'LPDDR4' } 35 { $ramType = 'LPDDR5' } default { $ramType = '' } }
        $speed = [int]$m0.Speed
        $configured = [int]$m0.ConfiguredClockSpeed
        if ($configured -eq 0) { $configured = $speed }
    }
    $installed = [int64]0; foreach ($m in $mods) { $installed += [int64]$m.Capacity }
    if ($installed -eq 0) { $installed = $totalRam }
    # rated (XMP/EXPO) speed read from the part number, e.g. F5-6000J3040G32GX2, CMK64GX5M2B6000C30, KF560C36
    $kitMTs = 0
    $pn = if ($mods.Count -gt 0) { ([string]$mods[0].PartNumber).Trim() } else { '' }
    if ($pn -match 'KF([45])(\d{2})C') { $kitMTs = [int]$Matches[2] * 100 }
    elseif ($pn -match '(?<!\d)(2666|2933|3000|3200|3466|3600|3733|4000|4400|4800|5200|5600|6000|6200|6400|6600|6800|7000|7200|7600|8000|8200|8400)(?!\d)') { $kitMTs = [int]$Matches[1] }
    elseif ($pn -match 'G(3[26]|4[048]|5[26]|6[04])C') { $kitMTs = [int]$Matches[1] * 100 }
    $jedecLike = $false
    if ($kitMTs -gt 0 -and $configured -gt 0) { $jedecLike = ($kitMTs -ge $configured + 400) }
    else {
        if ($ramType -eq 'DDR4' -and $configured -gt 0 -and $configured -le 2666) { $jedecLike = $true }
        if ($ramType -eq 'DDR5' -and $configured -gt 0 -and $configured -le 4800) { $jedecLike = $true }
    }
    $hw.RAM = [pscustomobject]@{
        TotalBytes = $installed
        UsableBytes = $totalRam
        GB = [math]::Round($installed / 1GB)
        Modules = $mods.Count
        Slots = if ($arr) { [int]$arr.MemoryDevices } else { 0 }
        Type = $ramType
        SpeedMTs = $configured
        RatedMTs = $speed
        Manufacturer = if ($mods.Count -gt 0) { ([string]$mods[0].Manufacturer).Trim() } else { '' }
        PartNumber = if ($mods.Count -gt 0) { ([string]$mods[0].PartNumber).Trim() } else { '' }
        KitMTs = $kitMTs
        SingleChannel = ($mods.Count -eq 1)
        XmpProbablyOff = ($jedecLike -and -not $isLaptop)
    }

    & $step 'Analizzo i dischi...' 'Analysing disks...' 45
    # ---------------- storage
    $disks = @()
    $sysDiskNumber = -1
    try { $sysDiskNumber = (Get-Partition -DriveLetter ($env:SystemDrive.Substring(0, 1)) -ErrorAction Stop | Get-Disk -ErrorAction Stop).Number } catch { }
    # disks Windows really sees right now (empty card readers, unplugged or "ghost" drives are left out)
    $present = $null
    try { $present = @(Get-Disk -ErrorAction Stop | Where-Object { [int64]$_.Size -gt 0 } | ForEach-Object { [int]$_.Number }) } catch { }
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
            if ([int64]$d.Size -le 0) { continue }
            if (([string]($d.OperationalStatus -join ',')) -match 'Lost Communication|Detached|No Media|Not Present|Removed') { continue }
            if ($present -and $present.Count -gt 0 -and ($present -notcontains [int]$d.DeviceId)) { continue }
            $rel = $null
            if (-not $Quick) { try { $rel = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { } }
            $media = [string]$d.MediaType
            $bus = [string]$d.BusType
            if ($media -eq 'Unspecified' -and $bus -eq 'NVMe') { $media = 'SSD' }
            $disks += [pscustomobject]@{
                Number = [int]$d.DeviceId
                Name = ([string]$d.FriendlyName).Trim()
                Media = $media
                Bus = $bus
                SizeBytes = [int64]$d.Size
                Health = [string]$d.HealthStatus
                Operational = ([string]($d.OperationalStatus -join ','))
                IsSystem = ([int]$d.DeviceId -eq $sysDiskNumber)
                Temperature = if ($rel) { [int]$rel.Temperature } else { 0 }
                Wear = if ($rel) { [int]$rel.Wear } else { 0 }
                ReadErrors = if ($rel -and $rel.ReadErrorsUncorrected) { [int64]$rel.ReadErrorsUncorrected } else { 0 }
                PowerOnHours = if ($rel -and $rel.PowerOnHours) { [int64]$rel.PowerOnHours } else { 0 }
            }
        }
    } catch { }
    $hw.Disks = @($disks)
    $vols = @()
    foreach ($v in (Get-VxCim Win32_LogicalDisk -Filter 'DriveType=3')) {
        $diskNo = -1
        try { $diskNo = (Get-Partition -DriveLetter ([string]$v.DeviceID).Substring(0, 1) -ErrorAction Stop | Select-Object -First 1).DiskNumber } catch { }
        $vols += [pscustomobject]@{
            Letter = [string]$v.DeviceID
            Label = [string]$v.VolumeName
            SizeBytes = [int64]$v.Size
            FreeBytes = [int64]$v.FreeSpace
            FreePct = if ([int64]$v.Size -gt 0) { [math]::Round(100 * [int64]$v.FreeSpace / [int64]$v.Size) } else { 0 }
            DiskNumber = [int]$diskNo
        }
    }
    $hw.Volumes = @($vols)
    $sysDisk = @($disks | Where-Object { $_.IsSystem }) | Select-Object -First 1
    $hw.SystemOnSSD = if ($sysDisk) { $sysDisk.Media -eq 'SSD' } else { $true }
    $hw.SystemDiskBus = if ($sysDisk) { $sysDisk.Bus } else { '' }

    & $step 'Leggo scheda madre e schermi...' 'Reading motherboard and screens...' 65
    # ---------------- board / BIOS
    $bb = Get-VxCim Win32_BaseBoard | Select-Object -First 1
    $bios = Get-VxCim Win32_BIOS | Select-Object -First 1
    $hw.Board = [pscustomobject]@{
        Name = if ($bb) { ('{0} {1}' -f $bb.Manufacturer, $bb.Product).Trim() } else { '' }
        Bios = if ($bios) { [string]$bios.SMBIOSBIOSVersion } else { '' }
        BiosDate = if ($bios -and $bios.ReleaseDate) { ([datetime]$bios.ReleaseDate).ToString('MM/yyyy') } else { '' }
    }

    # ---------------- displays
    $hw.Displays = @()
    try { $hw.Displays = @([VeloxPC.Native]::GetDisplays()) } catch { }
    # real monitor names (EDID) instead of "Generic PnP Monitor"
    try {
        $names = @{}
        foreach ($m in @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction Stop -OperationTimeoutSec 10)) {
            $code = ([string]$m.InstanceName -split '\\')[1]
            $nm = (($m.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join '').Trim()
            if ($code -and $nm) { $names[$code.ToUpper()] = $nm }
        }
        foreach ($d in $hw.Displays) {
            $code = ([string]$d.MonitorId -split '\\')[1]
            if ($code -and $names.ContainsKey($code.ToUpper())) { $d.Monitor = $names[$code.ToUpper()] }
        }
    } catch { }

    & $step 'Controllo la rete...' 'Checking the network...' 75
    # ---------------- network
    $nets = @()
    try {
        foreach ($c in @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })) {
            $a = $c.NetAdapter
            $wifi = ([string]$a.MediaType -match '802\.11' -or [string]$a.PhysicalMediaType -match '802\.11|Wireless' -or [string]$a.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11')
            $nets += [pscustomobject]@{
                Name = [string]$c.InterfaceAlias
                Description = [string]$a.InterfaceDescription
                IfIndex = [int]$c.InterfaceIndex
                IsWifi = [bool]$wifi
                LinkSpeed = [string]$a.LinkSpeed
                LinkBps = [int64]$a.ReceiveLinkSpeed
                IPv4 = (@($c.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', ')
                Gateway = (@($c.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) | Select-Object -First 1)
                Dns = @($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ', '
                Virtual = [bool]($a.Virtual)
            }
        }
    } catch { }
    $hw.Networks = @($nets | Sort-Object @{ Expression = { if ($_.Virtual) { 1 } else { 0 } } })
    $hw.Network = if ($hw.Networks.Count -gt 0) { $hw.Networks[0] } else { $null }

    # ---------------- power
    $hw.PowerScheme = Get-VxActiveScheme

    & $step 'Controllo stampanti, Bluetooth e app...' 'Checking printers, Bluetooth and apps...' 85
    # ---------------- usage context (used to protect services the user needs)
    $ctx = [ordered]@{}
    try {
        $printers = @(Get-CimInstance Win32_Printer -ErrorAction Stop | Where-Object { $_.Name -notmatch 'PDF|XPS|OneNote|Fax|Send To|AnyDesk|Snagit' })
        $ctx.HasPrinter = ($printers.Count -gt 0)
    } catch { $ctx.HasPrinter = $false }
    $pnp = @()
    try { $pnp = @(Get-PnpDevice -PresentOnly -ErrorAction Stop) } catch { }
    $ctx.HasBluetooth = (@($pnp | Where-Object { $_.Class -eq 'Bluetooth' }).Count -gt 0)
    $ctx.HasBiometric = (@($pnp | Where-Object { $_.Class -eq 'Biometric' }).Count -gt 0)
    $ctx.HasScanner = (@($pnp | Where-Object { $_.Class -eq 'Image' }).Count -gt 0)
    $ctx.HasSmartCard = (@($pnp | Where-Object { $_.Class -eq 'SmartCardReader' }).Count -gt 0)
    $ctx.HasTouch = (@($pnp | Where-Object { $_.FriendlyName -match 'touch screen|Touchscreen' }).Count -gt 0)
    $ctx.HasXbox = $false
    try { $ctx.HasXbox = (@(Get-AppxPackage -Name 'Microsoft.GamingApp' -ErrorAction Stop).Count -gt 0) -or (@(Get-AppxPackage -Name 'Microsoft.XboxApp' -ErrorAction Stop).Count -gt 0) } catch { }
    $ctx.UsesRdp = $false
    try { $ctx.UsesRdp = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop).fDenyTSConnections -eq 0) } catch { }
    $ctx.IsInsider = (Test-Path 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability') -and [bool]((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability' -ErrorAction SilentlyContinue).BranchName)
    $ctx.HasHyperV = $false
    try { $ctx.HasHyperV = [bool](Get-Service -Name vmms -ErrorAction Stop) } catch { }
    $hw.Ctx = [pscustomobject]$ctx
    & $step 'Fatto' 'Done' 100

    return [pscustomobject]$hw
}
