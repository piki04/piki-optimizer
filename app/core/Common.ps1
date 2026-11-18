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
        # log rotation: at most 2 x 512 KB (veloxpc.log + veloxpc.1.log)
        try {
            $fi = New-Object System.IO.FileInfo $file
            if ($fi.Exists -and $fi.Length -gt 524288) { [System.IO.File]::Copy($file, (Join-Path $script:VxLogs 'veloxpc.1.log'), $true); [System.IO.File]::WriteAllText($file, '') }
        } catch { }
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
    return (Update-VxSettingsSchema $s)
}

# 2.0: new installs are light by default (closing the window exits, no tray, no autostart, no glass).
# Existing settings.json files keep every value the user chose; only missing keys get a default.
function Update-VxSettingsSchema {
    param([hashtable]$S)
    $isNew = ($S.Count -eq 0)
    $defaults = @{
        lang = ''; firstRunDone = $false; autoUpdate = $true; expert = $false; lastHealth = ''; profile = ''; logo = ''; bg = ''; bgLevel = 2
        tray = $false; autostart = $false; glass = $false; shortcutDone = $false
        reducedMotion = $false; retiredSeen = @(); lostSeen = ''; cleanSchedule = ''; lastUpdateCheck = ''
    }
    if (-not $isNew -and -not $S.ContainsKey('tray')) { $defaults.tray = $true }   # 1.x default
    foreach ($k in $defaults.Keys) { if (-not $S.ContainsKey($k)) { $S[$k] = $defaults[$k] } }
    if ($S.profile -eq 'aesthetic' -or $S.profile -eq 'max') { $S.profile = 'piki' }
    $S.retiredSeen = @($S.retiredSeen | Where-Object { $_ })
    $S['schema'] = 2
    return $S
}

# ---------------------------------------------------------------- dry run ("show what would change")
# While $script:VxDryRun is on, every Set-Vx*/Remove-Vx* helper and every external command that changes the
# system only records "would change X from A to B" and does nothing.
$script:VxDryRun = $false
$script:VxDryLog = New-Object System.Collections.ArrayList
function Start-VxDryRun { $script:VxDryRun = $true; $script:VxDryLog = New-Object System.Collections.ArrayList }
function Stop-VxDryRun {
    $script:VxDryRun = $false
    $out = @($script:VxDryLog.ToArray())
    try { if ($script:VxData) { Write-VxJson 'dryrun.json' @{ time = (Get-Date -Format 'yyyy-MM-dd HH:mm'); changes = $out } } } catch { }
    return $out
}
function Add-VxDryRecord {
    param([string]$What, $From = $null, $To = $null)
    $tx = if ($script:VxTx) { [string]$script:VxTx.Id } else { '' }
    [void]$script:VxDryLog.Add(@{ id = $tx; what = $What; from = [string]$From; to = [string]$To })
}
# external commands that change the system (powercfg, netsh, reg...): one place, so dry run can skip them
function Invoke-VxExe {
    param([string]$Exe, [string[]]$ArgList)
    if ($script:VxDryRun) { Add-VxDryRecord ("$Exe " + ($ArgList -join ' ')); return '' }
    return (& $Exe @ArgList 2>&1)
}
# any other change (cmdlets): described in words for the dry run
function Invoke-VxDo {
    param([string]$What, [scriptblock]$Do)
    if ($script:VxDryRun) { Add-VxDryRecord $What; return $null }
    return (& $Do)
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
    if ($bt.backup) { Write-VxBackupFile $bt.backup }
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
    Write-VxBackupFile $Backup
}

# backup.json holds the ORIGINAL value of everything Piki changed (registry, services, power plan...).
# The previous copy is kept as backup.prev.json, so "Ripristina Piki.cmd" still works if one write goes wrong.
function Write-VxBackupFile {
    param([hashtable]$Backup)
    try {
        $cur = Join-Path $script:VxData 'backup.json'
        if (Test-Path -LiteralPath $cur) { Copy-Item -LiteralPath $cur -Destination (Join-Path $script:VxData 'backup.prev.json') -Force -ErrorAction SilentlyContinue }
    } catch { }
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
    if ($script:VxDryRun) { $script:VxTx = $null; return }
    $b = Get-VxBackup
    $id = $script:VxTx.Id
    # a change that touched nothing leaves no entry (no fake "applied" states, nothing to undo)
    if ($script:VxTx.Items.Count -eq 0 -and -not $b.entries.ContainsKey($id)) { $script:VxTx = $null; return }
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

# ---- Winstep Nexus (dock that replaces the taskbar): its settings and the taskbar are never touched
$script:VxNexusCache = $null
function Test-VxNexus {
    if ($script:VxNexusCache -and ([DateTime]::Now - $script:VxNexusCache.At).TotalSeconds -lt 60) { return $script:VxNexusCache }
    $running = $false; $auto = $false
    try { $running = [bool](Get-Process -Name 'Nexus' -ErrorAction SilentlyContinue) } catch { }
    foreach ($k in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
        try {
            $key = Get-Item -LiteralPath $k -ErrorAction Stop
            foreach ($n in $key.GetValueNames()) { if (([string]$key.GetValue($n)) -match '(?i)\\Nexus\.exe|Winstep') { $auto = $true } }
        } catch { }
    }
    foreach ($d in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup'))) {
        try { if ($d -and @(Get-ChildItem -LiteralPath $d -File -ErrorAction Stop | Where-Object { $_.Name -match '(?i)nexus|winstep' }).Count -gt 0) { $auto = $true } } catch { }
    }
    $script:VxNexusCache = @{ Running = $running; Autostart = $auto; Detected = ($running -or $auto); At = [DateTime]::Now }
    return $script:VxNexusCache
}

function Test-VxProtectedReg {
    param([string]$Path, [string]$Name)
    if ($Path -match '(?i)WinSTEP2000') { return $true }
    if (-not (Test-VxNexus).Detected) { return $false }
    if ($Path -match '(?i)StuckRects|\\Taskband') { return $true }
    if ($Path -match '(?i)\\Explorer\\Advanced$' -and $Name -match '(?i)^(Taskbar|ShowCopilotButton|ShowTaskViewButton)') { return $true }
    if ($Name -match '(?i)^SearchboxTaskbarMode') { return $true }
    if ($Path -match '(?i)\\Themes\\Personalize$' -and $Name -eq 'EnableTransparency') { return $true }
    return $false
}

function Set-VxReg {
    param([string]$Path, [string]$Name, [string]$Type, $Value)
    if (Test-VxProtectedReg $Path $Name) { throw (L @{ it = 'Impostazione protetta: Winstep Nexus'; en = 'Protected setting: Winstep Nexus' }) }
    $prev = Get-VxRegState -Path $Path -Name $Name
    # already exactly this value: nothing to change, nothing to save
    if ($prev.existed -and $prev.type -eq $Type -and (Test-VxSameRegValue $prev.type $prev.value $Value)) { return }
    if ($script:VxDryRun) { Add-VxDryRecord "reg $Path\$Name" $(if ($prev.existed) { $prev.value } else { '(none)' }) $Value; return }
    Add-VxTxItem @{ key = "reg|$Path|$Name"; kind = 'reg'; path = $Path; name = $Name; existed = $prev.existed; keyExisted = $prev.keyExisted; type = $prev.type; value = $prev.value }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    if ($Type -eq 'Binary' -and $Value -is [string]) { $Value = [Convert]::FromBase64String($Value) }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
}

function Test-VxSameRegValue {
    param([string]$Type, $Old, $New)
    try {
        if ($Type -eq 'DWord' -or $Type -eq 'QWord') {
            $a = [int64]$Old; $b = [int64]$New
            if ($Type -eq 'DWord') { if ($a -lt 0) { $a += 4294967296 }; if ($b -lt 0) { $b += 4294967296 } }
            return ($a -eq $b)
        }
        if ($Type -eq 'Binary') { $nb = if ($New -is [byte[]]) { [Convert]::ToBase64String($New) } else { [string]$New }; return ([string]$Old -eq $nb) }
        if ($Type -eq 'MultiString') { return ((@($Old) -join "`n") -eq (@($New) -join "`n")) }
        return ([string]$Old -ceq [string]$New)
    } catch { return $false }
}

function Remove-VxReg {
    param([string]$Path, [string]$Name)
    if (Test-VxProtectedReg $Path $Name) { return }
    $prev = Get-VxRegState -Path $Path -Name $Name
    if (-not $prev.existed) { return }
    if ($script:VxDryRun) { Add-VxDryRecord "reg $Path\$Name" $prev.value '(removed)'; return }
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
    if (Test-VxProtectedService $Name) { Write-VxLog "Service $Name is protected (security/updates): not changed" 'WARN'; return $false }
    $map = @{ Automatic = 2; Manual = 3; Disabled = 4 }
    if ($prev.start -eq $map[$StartType]) { return $true }
    if ($script:VxDryRun) { Add-VxDryRecord "service $Name start" $prev.start $map[$StartType]; return $true }
    Add-VxTxItem @{ key = "svc|$Name"; kind = 'svc'; name = $Name; start = $prev.start; delayed = $prev.delayed }
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    try { Set-ItemProperty -LiteralPath $p -Name Start -Value $map[$StartType] -Type DWord -ErrorAction Stop }
    catch {
        try { Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop } catch { Write-VxLog "Service $Name : $($_.Exception.Message)" 'WARN'; return $false }
    }
    if ($StartType -eq 'Disabled') { & sc.exe stop $Name 2>&1 | Out-Null }
    return $true
}

# Services Piki never turns off or down, whatever any catalog says (security, updates, antivirus, firewall)
function Test-VxProtectedService {
    param([string]$Name)
    # 2.0 review: also the services Windows needs to boot, sign in, install updates and reach the network
    return ($Name -match '(?i)^(WinDefend|WdNisSvc|Sense|SecurityHealthService|wscsvc|mpssvc|BFE|wuauserv|UsoSvc|WaaSMedicSvc|BITS|DoSvc|TrustedInstaller|AppIDSvc|SgrmBroker|webthreatdefsvc|webthreatdefusersvc|CryptSvc|msiserver|EventLog|RpcSs|RpcEptMapper|DcomLaunch|Winmgmt|Dhcp|Dnscache|nsi|NlaSvc|Audiosrv|AudioEndpointBuilder|TextInputManagementService)$' -or $Name -match '(?i)update|updater|MozillaMaintenance|AdobeARM')
}

# ---- power settings (powercfg)
function Get-VxActiveScheme {
    $out = (& powercfg /getactivescheme 2>$null) -join ' '
    if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        $guid = $Matches[1].ToLower()
        $name = ''
        if ($out -match '\(([^)]+)\)\s*$') { $name = $Matches[1] }
        return @{ guid = $guid; name = $name }
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
    if ($prev -and $prev.ac -eq $Ac -and ($null -eq $Dc -or $prev.dc -eq [int]$Dc)) { return }
    if ($script:VxDryRun) { Add-VxDryRecord "power plan $($scheme.name) $Setting" $(if ($prev) { "$($prev.ac)/$($prev.dc)" } else { '?' }) "$Ac/$Dc"; return }
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
        'regfile' {
            # a registry branch exported before Piki removed it
            $f = [string]$It.file
            if ($f -and $f -like '*.reg' -and (Test-Path -LiteralPath $f)) { & reg.exe import $f 2>&1 | Out-Null }
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
        'schedtask' {
            # a scheduled task Piki created (e.g. scheduled cleaning): only names Piki uses can be removed
            if ([string]$It.name -match '^PikiOptimizer( Clean)?$') { Unregister-ScheduledTask -TaskName ([string]$It.name) -Confirm:$false -ErrorAction SilentlyContinue }
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

function Test-VxSystemRestoreOn {
    # System Protection is on for the Windows drive (read-only check)
    try {
        $k = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction Stop
        if ($null -ne $k.RPSessionInterval -and [int]$k.RPSessionInterval -eq 0) { return $false }
        if ($null -ne $k.DisableSR -and [int]$k.DisableSR -eq 1) { return $false }
    } catch { }
    try { $rp = @(Get-ComputerRestorePoint -ErrorAction Stop); return $true } catch { return $false }
}

function New-VxRestorePoint {
    # Returns $true (created), 'recent' (a real Windows restore point from the last 24 h exists), 'off' (System
    # Protection is off and the user did not allow turning it on) or $false (Windows refused).
    param([string]$Description = 'VeloxPC', [switch]$AllowEnable)
    if ($script:VxDryRun) { Add-VxDryRecord 'Windows restore point'; return $true }
    # Windows keeps one restore point per day anyway: skip only if a REAL point from the last 24 hours exists
    try {
        $last = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending) | Select-Object -First 1
        if ($last) {
            $t = [Management.ManagementDateTimeConverter]::ToDateTime([string]$last.CreationTime)
            if (([DateTime]::Now - $t).TotalHours -lt 24) { Write-VxLog 'Restore point: a recent one exists, skipped'; return 'recent' }
        }
    } catch { }
    if (-not (Test-VxSystemRestoreOn)) {
        if (-not $AllowEnable) { Write-VxLog 'Restore point: System Protection is off (not turned on without asking)' 'WARN'; return 'off' }
        try { Enable-ComputerRestore -Drive "$($env:SystemDrive)\" -ErrorAction Stop; Write-VxLog 'System Protection turned on (user asked)' } catch { return $false }
    }
    $freqKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = Get-VxRegState -Path $freqKey -Name 'SystemRestorePointCreationFrequency'
    try {
        if (-not (Test-Path -LiteralPath $freqKey)) { New-Item -Path $freqKey -Force | Out-Null }
        New-ItemProperty -LiteralPath $freqKey -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value 0 -Force | Out-Null
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        return $true
    } catch {
        Write-VxLog "Restore point failed: $($_.Exception.Message)" 'WARN'
        return $false
    } finally {
        # always put the original value back, also when Windows refused the restore point
        try {
            if ($old.existed) { New-ItemProperty -LiteralPath $freqKey -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value ([int]$old.value) -Force | Out-Null }
            else { Remove-ItemProperty -LiteralPath $freqKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
        } catch { }
    }
}

# Light mode (cheaper animations while the PC is saturated). Hysteresis: ON after 3 s at >= 85 % CPU,
# OFF after 10 s below 60 %; both counters reset on every switch, so it can never flap every second.
function Step-VxLiteMode {
    param([hashtable]$State, [double]$Cpu)
    $changed = $false
    if ($Cpu -ge 85) { $State.Hot++; $State.Cool = 0 }
    elseif ($Cpu -lt 60) { $State.Cool++; $State.Hot = 0 }
    else { $State.Hot = 0; $State.Cool = 0 }
    if (-not $State.Lite -and $State.Hot -ge 3) { $State.Lite = $true; $State.Hot = 0; $State.Cool = 0; $changed = $true }
    elseif ($State.Lite -and $State.Cool -ge 10) { $State.Lite = $false; $State.Hot = 0; $State.Cool = 0; $changed = $true }
    return $changed
}

function Test-VxProcessRunning {
    param([string[]]$Names)
    foreach ($n in $Names) { if (Get-Process -Name $n -ErrorAction SilentlyContinue) { return $true } }
    return $false
}
