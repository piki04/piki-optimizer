# VeloxPC - shared core: paths, logging, settings, i18n, backup engine
# Windows PowerShell 5.1 compatible.

if (-not $script:VxRoot -and $PSScriptRoot) { $script:VxRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (-not $script:VxLang) { $script:VxLang = 'it' }

function Initialize-VxPaths {
    param([string]$Root)
    $script:VxRoot = $Root
    $script:VxData = Join-Path $Root 'data'
    $script:VxLogs = Join-Path $script:VxData 'logs'
    foreach ($d in @($script:VxData, $script:VxLogs)) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function L {
    # Picks the right language from a bilingual hashtable @{ it = '...'; en = '...' }
    param($Text)
    if ($null -eq $Text) { return '' }
    if ($Text -is [hashtable]) {
        if ($Text.ContainsKey($script:VxLang) -and $Text[$script:VxLang]) { return [string]$Text[$script:VxLang] }
        if ($Text.ContainsKey('en') -and $Text['en']) { return [string]$Text['en'] }
        if ($Text.ContainsKey('it')) { return [string]$Text['it'] }
        return ''
    }
    return [string]$Text
}

function Write-VxLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if (-not $script:VxLogs) { return }
        $line = '{0} [{1}] {2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message, [Environment]::NewLine
        $file = Join-Path $script:VxLogs 'veloxpc.log'
        for ($i = 0; $i -lt 5; $i++) {
            try { [System.IO.File]::AppendAllText($file, $line, [System.Text.Encoding]::UTF8); break } catch { Start-Sleep -Milliseconds 40 }
        }
    } catch { }
}

# ---------------------------------------------------------------- JSON storage
function Read-VxJson {
    param([string]$Name, $Default)
    $file = Join-Path $script:VxData $Name
    if (Test-Path -LiteralPath $file) {
        try {
            $raw = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
            if ($raw.Trim()) { return ($raw | ConvertFrom-Json) }
        } catch { Write-VxLog "Cannot read $Name : $($_.Exception.Message)" 'WARN' }
    }
    return $Default
}

function Write-VxJson {
    param([string]$Name, $Object)
    $file = Join-Path $script:VxData $Name
    $json = ConvertTo-Json -InputObject $Object -Depth 12
    $tmp = "$file.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $file -Force
}

function ConvertTo-VxHashtable {
    # Converts PSCustomObject (from ConvertFrom-Json) into nested hashtables / arrays
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) { $h[$k] = ConvertTo-VxHashtable $InputObject[$k] }
        return $h
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-VxHashtable $p.Value }
        return $h
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $list = New-Object System.Collections.ArrayList
        foreach ($i in $InputObject) { [void]$list.Add((ConvertTo-VxHashtable $i)) }
        return ,$list.ToArray()
    }
    return $InputObject
}

# ---------------------------------------------------------------- settings
function Get-VxSettings {
    $s = ConvertTo-VxHashtable (Read-VxJson 'settings.json' $null)
    if (-not $s) { $s = @{} }
    $defaults = @{ lang = ''; firstRunDone = $false; autoUpdate = $true; expert = $false; lastHealth = ''; profile = ''; logo = ''; bg = ''; bgLevel = 2; tray = $true; autostart = $false; glass = $true; shortcutDone = $false }
    foreach ($k in $defaults.Keys) { if (-not $s.ContainsKey($k)) { $s[$k] = $defaults[$k] } }
    return $s
}

function Save-VxSettings {
    param([hashtable]$Settings)
    Write-VxJson 'settings.json' $Settings
}

# ---------------------------------------------------------------- backup / undo engine
# Every change goes through Set-Vx* helpers. The first original value of each
# changed item is stored in data\backup.json under the tweak id, so the change
# can be undone at any time (even after updates or reboots).

$script:VxTx = $null

# Batch mode: while applying many changes, backup.json and history.json are read once,
# kept in memory and written once at the end (Stop-VxBatch), instead of once per change.
$script:VxBatch = $null
function Start-VxBatch { $script:VxBatch = @{ backup = $null; history = $null } }
function Stop-VxBatch {
    $bt = $script:VxBatch
    $script:VxBatch = $null
    if (-not $bt) { return }
    if ($bt.backup) { Write-VxJson 'backup.json' $bt.backup }
    if ($null -ne $bt.history) { Write-VxJson 'history.json' @($bt.history) }
}

function Get-VxBackup {
    if ($script:VxBatch -and $script:VxBatch.backup) { return $script:VxBatch.backup }
    $b = ConvertTo-VxHashtable (Read-VxJson 'backup.json' $null)
    if (-not $b) { $b = @{} }
    if (-not $b.ContainsKey('entries')) { $b['entries'] = @{} }
    if ($script:VxBatch) { $script:VxBatch.backup = $b }
    return $b
}

function Save-VxBackup {
    param([hashtable]$Backup)
    if ($script:VxBatch) { $script:VxBatch.backup = $Backup; return }
    Write-VxJson 'backup.json' $Backup
}

function Test-VxBackupEntry { param([string]$Id) $b = Get-VxBackup; return $b.entries.ContainsKey($Id) }

function Start-VxTx {
    param([string]$Id, [string]$Title)
    $script:VxTx = @{ Id = $Id; Title = $Title; Items = (New-Object System.Collections.ArrayList); Keys = @{} }
    $b = Get-VxBackup
    if ($b.entries.ContainsKey($Id)) {
        foreach ($it in @($b.entries[$Id].items)) { if ($it.key) { $script:VxTx.Keys[$it.key] = $true } }
    }
}

function Add-VxTxItem {
    param([hashtable]$Item)
    if (-not $script:VxTx) { return }
    if ($script:VxTx.Keys.ContainsKey($Item.key)) { return }   # keep the very first original value
    $script:VxTx.Keys[$Item.key] = $true
    [void]$script:VxTx.Items.Add($Item)
}

function Complete-VxTx {
    if (-not $script:VxTx) { return }
    $b = Get-VxBackup
    $id = $script:VxTx.Id
    if ($b.entries.ContainsKey($id)) {
        $e = $b.entries[$id]
        $items = @($e.items) + @($script:VxTx.Items.ToArray())
        $e.items = $items
    } else {
        $b.entries[$id] = @{ id = $id; title = $script:VxTx.Title; time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); items = @($script:VxTx.Items.ToArray()) }
    }
    Save-VxBackup $b
    Add-VxHistory -Id $id -Title $script:VxTx.Title -Action 'apply'
    $script:VxTx = $null
}

function Add-VxHistory {
    param([string]$Id, [string]$Title, [string]$Action)
    try {
        if ($script:VxBatch -and $null -ne $script:VxBatch.history) { $h = @($script:VxBatch.history) }
        else {
            $old = ConvertTo-VxHashtable (Read-VxJson 'history.json' $null)
            $h = @($old | Where-Object { $_ })
        }
        $h = @(@{ time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); id = $Id; title = $Title; action = $Action }) + $h
        if ($h.Count -gt 300) { $h = $h[0..299] }
        if ($script:VxBatch) { $script:VxBatch.history = $h; return }
        Write-VxJson 'history.json' $h
    } catch { }
}

# ---- registry
function ConvertTo-VxRegPath {
    param([string]$Path)
    return ($Path -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU:\\', 'HKEY_CURRENT_USER\')
}

function Get-VxRegState {
    param([string]$Path, [string]$Name)
    $state = @{ existed = $false; type = ''; value = $null; keyExisted = (Test-Path -LiteralPath $Path) }
    if ($state.keyExisted) {
        try {
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            $names = $key.GetValueNames()
            if ($names -contains $Name) {
                $state.existed = $true
                $state.type = $key.GetValueKind($Name).ToString()
                $v = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
                if ($v -is [byte[]]) { $v = [Convert]::ToBase64String($v); $state.type = 'Binary' }
                elseif ($v -is [string[]]) { $v = @($v) }
                $state.value = $v
            }
        } catch { }
    }
    return $state
}

function Set-VxReg {
    param([string]$Path, [string]$Name, [string]$Type, $Value)
    $prev = Get-VxRegState -Path $Path -Name $Name
    Add-VxTxItem @{ key = "reg|$Path|$Name"; kind = 'reg'; path = $Path; name = $Name; existed = $prev.existed; keyExisted = $prev.keyExisted; type = $prev.type; value = $prev.value }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Type -eq 'Binary' -and $Value -is [string]) { $Value = [Convert]::FromBase64String($Value) }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function Remove-VxReg {
    param([string]$Path, [string]$Name)
    $prev = Get-VxRegState -Path $Path -Name $Name
    if (-not $prev.existed) { return }
    Add-VxTxItem @{ key = "reg|$Path|$Name"; kind = 'reg'; path = $Path; name = $Name; existed = $true; keyExisted = $true; type = $prev.type; value = $prev.value }
    Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
}

function Test-VxRegValue {
    param([string]$Path, [string]$Name, $Value)
    $s = Get-VxRegState -Path $Path -Name $Name
    if (-not $s.existed) { return $false }
    if ($s.type -eq 'DWord' -or $s.type -eq 'QWord') { return ([int64]$s.value -eq [int64]$Value) }
    return ([string]$s.value -eq [string]$Value)
}

# ---- services
function Get-VxSvcStart {
    param([string]$Name)
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $k = Get-ItemProperty -LiteralPath $p -ErrorAction SilentlyContinue
    if ($null -eq $k.Start) { return $null }
    $delayed = 0
    if ($null -ne $k.DelayedAutostart) { $delayed = [int]$k.DelayedAutostart }
    return @{ start = [int]$k.Start; delayed = $delayed }
}

function Set-VxSvc {
    param([string]$Name, [ValidateSet('Automatic', 'Manual', 'Disabled')][string]$StartType)
    $prev = Get-VxSvcStart $Name
    if (-not $prev) { return $false }
    Add-VxTxItem @{ key = "svc|$Name"; kind = 'svc'; name = $Name; start = $prev.start; delayed = $prev.delayed }
    $map = @{ Automatic = 2; Manual = 3; Disabled = 4 }
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    try { Set-ItemProperty -LiteralPath $p -Name Start -Value $map[$StartType] -Type DWord -ErrorAction Stop }
    catch {
        try { Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop } catch { Write-VxLog "Service $Name : $($_.Exception.Message)" 'WARN'; return $false }
    }
    if ($StartType -eq 'Disabled') { & sc.exe stop $Name 2>&1 | Out-Null }
    return $true
}

# ---- power settings (powercfg)
function Get-VxActiveScheme {
    $out = (& powercfg /getactivescheme 2>$null) -join ' '
    if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        $name = ''
        if ($out -match '\(([^)]+)\)\s*$') { $name = $Matches[1] }
        return @{ guid = $Matches[1].ToLower(); name = $name }
    }
    return $null
}

function Get-VxPowerValue {
    param([string]$Scheme, [string]$Sub, [string]$Setting)
    $out = & powercfg /q $Scheme $Sub $Setting 2>$null
    $hex = @([regex]::Matches(($out -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -ge 2) {
        return @{ ac = [Convert]::ToInt32($hex[$hex.Count - 2], 16); dc = [Convert]::ToInt32($hex[$hex.Count - 1], 16) }
    }
    return $null
}

function Set-VxPower {
    param([string]$Sub, [string]$Setting, [int]$Ac, $Dc = $null)
    $scheme = Get-VxActiveScheme
    if (-not $scheme) { return }
    $prev = Get-VxPowerValue $scheme.guid $Sub $Setting
    if ($prev) {
        Add-VxTxItem @{ key = "power|$($scheme.guid)|$Setting"; kind = 'power'; scheme = $scheme.guid; sub = $Sub; setting = $Setting; ac = $prev.ac; dc = $prev.dc }
    }
    & powercfg /setacvalueindex $scheme.guid $Sub $Setting $Ac 2>&1 | Out-Null
    if ($null -ne $Dc) { & powercfg /setdcvalueindex $scheme.guid $Sub $Setting ([int]$Dc) 2>&1 | Out-Null }
    & powercfg /setactive $scheme.guid 2>&1 | Out-Null
}

# ---- generic custom items (fixed handlers, parameters only - no stored code)
function Add-VxCustomUndo {
    param([string]$Key, [hashtable]$Data)
    $Data['key'] = $Key
    Add-VxTxItem $Data
}

$script:VxGuidRx = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

function Restore-VxItem {
    param([hashtable]$It)
    switch ($It.kind) {
        'reg' {
            if ($It.existed) {
                if (-not (Test-Path -LiteralPath $It.path)) { New-Item -Path $It.path -Force | Out-Null }
                $val = $It.value
                if ($It.type -eq 'Binary') { $val = [Convert]::FromBase64String([string]$val) }
                elseif ($It.type -eq 'MultiString') { $val = [string[]]@($val) }
                elseif ($It.type -eq 'DWord') { $n = [int64]$It.value; if ($n -gt [int]::MaxValue) { $n = $n - 4294967296 }; $val = [int]$n }
                elseif ($It.type -eq 'QWord') { $val = [int64]$val }
                New-ItemProperty -LiteralPath $It.path -Name $It.name -PropertyType $It.type -Value $val -Force | Out-Null
            } else {
                if (Test-Path -LiteralPath $It.path) {
                    Remove-ItemProperty -LiteralPath $It.path -Name $It.name -Force -ErrorAction SilentlyContinue
                    if (-not $It.keyExisted) {
                        $k = Get-Item -LiteralPath $It.path -ErrorAction SilentlyContinue
                        if ($k -and $k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item -LiteralPath $It.path -Force -ErrorAction SilentlyContinue }
                    }
                }
            }
        }
        'svc' {
            $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$($It.name)"
            if (Test-Path -LiteralPath $p) {
                Set-ItemProperty -LiteralPath $p -Name Start -Value ([int]$It.start) -Type DWord -ErrorAction SilentlyContinue
                if ([int]$It.delayed -eq 1) { Set-ItemProperty -LiteralPath $p -Name DelayedAutostart -Value 1 -Type DWord -ErrorAction SilentlyContinue }
                if ([int]$It.start -eq 2) { Start-Service -Name $It.name -ErrorAction SilentlyContinue }
            }
        }
        'power' {
            if ($It.scheme -match $script:VxGuidRx -and $It.sub -match $script:VxGuidRx -and $It.setting -match $script:VxGuidRx) {
                & powercfg /setacvalueindex $It.scheme $It.sub $It.setting ([int]$It.ac) 2>&1 | Out-Null
                & powercfg /setdcvalueindex $It.scheme $It.sub $It.setting ([int]$It.dc) 2>&1 | Out-Null
                $cur = Get-VxActiveScheme
                if ($cur -and $cur.guid -eq $It.scheme) { & powercfg /setactive $It.scheme 2>&1 | Out-Null }
            }
        }
        'plan' {
            if ($It.prev -match $script:VxGuidRx) { & powercfg /setactive $It.prev 2>&1 | Out-Null }
            if ($It.created -and $It.created -match $script:VxGuidRx) { & powercfg /delete $It.created 2>&1 | Out-Null }
        }
        'overlay' {
            if ($It.prev -match $script:VxGuidRx) { & powercfg /overlaysetactive $It.prev 2>&1 | Out-Null }
        }
        'mmagent' {
            if ($It.prev) { Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue } else { Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue }
        }
        'tcp' {
            $allowed = @('autotuninglevel', 'rss', 'ecncapability', 'timestamps', 'heuristics')
            if ($allowed -contains $It.prop -and ([string]$It.value) -match '^[a-zA-Z]+$') {
                if ($It.prop -eq 'heuristics') { & netsh int tcp set heuristics ([string]$It.value) 2>&1 | Out-Null }
                else { & netsh int tcp set global "$($It.prop)=$($It.value)" 2>&1 | Out-Null }
            }
        }
        'nic' {
            try { Set-NetAdapterAdvancedProperty -Name $It.adapter -RegistryKeyword $It.keyword -RegistryValue ([string]$It.value) -NoRestart -ErrorAction Stop } catch { }
            $script:VxNicRestart = $true
        }
        'dns' {
            try {
                if ($It.dhcp) { Set-DnsClientServerAddress -InterfaceIndex ([int]$It.ifIndex) -ResetServerAddresses -ErrorAction Stop }
                else { Set-DnsClientServerAddress -InterfaceIndex ([int]$It.ifIndex) -ServerAddresses @($It.servers) -ErrorAction Stop }
                Clear-DnsClientCache -ErrorAction SilentlyContinue
            } catch { }
        }
        'display' {
            try { [void][VeloxPC.Native]::SetRefreshRate([string]$It.device, [int]$It.hz) } catch { }
        }
        'defender' {
            try {
                if ($It.type -eq 'path') { Remove-MpPreference -ExclusionPath ([string]$It.value) -ErrorAction Stop }
                elseif ($It.type -eq 'process') { Remove-MpPreference -ExclusionProcess ([string]$It.value) -ErrorAction Stop }
            } catch { }
        }
        'pthrottle' {
            if (Test-Path -LiteralPath $It.path) { & powercfg /powerthrottling reset /path "$($It.path)" 2>&1 | Out-Null }
        }
        'mouse' {
            try { [void][VeloxPC.Native]::SetMouse([int]$It.t1, [int]$It.t2, [int]$It.accel) } catch { }
        }
        'kbd' {
            try { [void][VeloxPC.Native]::Spi(0x0017, [uint32]$It.delay); [void][VeloxPC.Native]::Spi(0x000B, [uint32]$It.speed) } catch { }
        }
        'appx' {
            # Store app startup task state
            $p = [string]$It.path
            if ($p -like 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\*') {
                Set-ItemProperty -LiteralPath $p -Name State -Value ([int]$It.state) -Type DWord -ErrorAction SilentlyContinue
            }
        }
        default { Write-VxLog "Unknown backup item kind $($It.kind)" 'WARN' }
    }
}

function Undo-VxEntry {
    param([string]$Id)
    $b = Get-VxBackup
    if (-not $b.entries.ContainsKey($Id)) { return $false }
    $e = $b.entries[$Id]
    $items = @($e.items)
    $script:VxNicRestart = $false
    for ($i = $items.Count - 1; $i -ge 0; $i--) {
        try { Restore-VxItem $items[$i] } catch { Write-VxLog "Undo $Id item failed: $($_.Exception.Message)" 'WARN' }
    }
    $b.entries.Remove($Id)
    Save-VxBackup $b
    Add-VxHistory -Id $Id -Title $e.title -Action 'undo'
    Write-VxLog "Undone: $Id"
    return $true
}

# ---------------------------------------------------------------- misc helpers
function Get-VxShortHash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant())) } finally { $sha.Dispose() }
    return (($h[0..5] | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Format-VxBytes {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function New-VxRestorePoint {
    param([string]$Description = 'VeloxPC')
    # Windows keeps one restore point per day anyway: skip the slow attempt if Piki made one in the last 24 hours
    $stamp = Join-Path $script:VxData 'cache\lastrp.txt'
    try {
        if (Test-Path -LiteralPath $stamp) {
            $t = [DateTime]::Parse(([System.IO.File]::ReadAllText($stamp)).Trim(), [Globalization.CultureInfo]::InvariantCulture)
            if (([DateTime]::Now - $t).TotalHours -lt 24) { Write-VxLog 'Restore point: recent one exists, skipped'; return 'recent' }
        }
    } catch { }
    try {
        $freqKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $old = Get-VxRegState -Path $freqKey -Name 'SystemRestorePointCreationFrequency'
        if (-not (Test-Path -LiteralPath $freqKey)) { New-Item -Path $freqKey -Force | Out-Null }
        New-ItemProperty -LiteralPath $freqKey -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value 0 -Force | Out-Null
        try { Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction SilentlyContinue } catch { }
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        if ($old.existed) { New-ItemProperty -LiteralPath $freqKey -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value ([int]$old.value) -Force | Out-Null }
        else { Remove-ItemProperty -LiteralPath $freqKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
        Write-VxLog 'Restore point created'
        try {
            $cd = Split-Path -Parent $stamp
            if (-not (Test-Path -LiteralPath $cd)) { New-Item -ItemType Directory -Path $cd -Force | Out-Null }
            [System.IO.File]::WriteAllText($stamp, [DateTime]::Now.ToString('o', [Globalization.CultureInfo]::InvariantCulture))
        } catch { }
        return $true
    } catch {
        Write-VxLog "Restore point failed: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Test-VxProcessRunning {
    param([string[]]$Names)
    foreach ($n in $Names) { if (Get-Process -Name $n -ErrorAction SilentlyContinue) { return $true } }
    return $false
}
