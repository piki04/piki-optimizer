# =====================================================================
#  Piki Optimizer 2.0 - (c) 2026 piki04. Tutti i diritti riservati / All rights reserved. See LICENSE.
#  Windows PowerShell 5.1 + WPF. Run through "Avvia Piki Optimizer.cmd".
# =====================================================================
param([switch]$NoElevate, [switch]$Hosted, [switch]$Tray, [switch]$Cleanup, [switch]$UndoAll, [switch]$ScheduledClean, [switch]$DryRun, [string]$Snapshot)

$ErrorActionPreference = 'Stop'
$AppDir = $PSScriptRoot
$Root = Split-Path -Parent $AppDir

# ---------------------------------------------------------------- elevation / host checks
function Test-VxAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$selfArgs = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
if ($Tray) { $selfArgs += ' -Tray' }
if ($DryRun) { $selfArgs += ' -DryRun' }
if ($NoElevate) { $selfArgs += ' -NoElevate' }
if ($Snapshot) { $selfArgs += " -Snapshot `"$Snapshot`"" }
$headless = ($Cleanup -or $ScheduledClean)
if (-not $NoElevate -and -not $headless -and -not (Test-VxAdmin)) {
    # elevate straight into the hidden classic console (saves one extra PowerShell start)
    $conhostE = Join-Path $env:SystemRoot 'System32\conhost.exe'
    try {
        if (Test-Path -LiteralPath $conhostE) { Start-Process -FilePath $conhostE -Verb RunAs -WindowStyle Hidden -ArgumentList "`"$psExe`" $selfArgs -Hosted" }
        else { Start-Process -FilePath $psExe -Verb RunAs -WindowStyle Hidden -ArgumentList $selfArgs }
    } catch { }
    exit
}
if (-not $NoElevate -and -not $Hosted -and -not $headless) {
    # always run inside a classic (hideable) console: Windows Terminal cannot hide its window
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    if (Test-Path -LiteralPath $conhost) {
        Start-Process -FilePath $conhost -ArgumentList "`"$psExe`" $selfArgs -Hosted" -WindowStyle Hidden
        exit
    }
}
if (-not $headless -and [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process -FilePath $psExe -ArgumentList "$selfArgs -Hosted" -WindowStyle Hidden
    exit
}
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# single instance: close any other running window (pid file + start time, no slow WMI query)
$pidFile = Join-Path $Root 'data\app.pid'
if (-not $headless) {
    try {
        if (Test-Path -LiteralPath $pidFile) {
            $old = ([System.IO.File]::ReadAllText($pidFile)).Trim().Split('|')
            if ($old.Count -eq 2 -and [int]$old[0] -ne $PID) {
                $op = Get-Process -Id ([int]$old[0]) -ErrorAction SilentlyContinue
                if ($op -and $op.ProcessName -eq 'powershell' -and $op.StartTime.Ticks -eq [long]$old[1]) { Stop-Process -Id $op.Id -Force -ErrorAction SilentlyContinue }
            }
        }
        $pd = Split-Path -Parent $pidFile
        if (-not (Test-Path -LiteralPath $pd)) { New-Item -ItemType Directory -Path $pd -Force | Out-Null }
        [System.IO.File]::WriteAllText($pidFile, "$PID|$((Get-Process -Id $PID).StartTime.Ticks)")
    } catch { }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing
# the UI thread stays responsive (it is light); background jobs run below normal
try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::AboveNormal } catch { }
# 2.0: every animation is capped at 60 fps (1.x followed the monitor up to 240 fps and kept the CPU busy)
$script:Fps = 60
try { [System.Windows.Media.Animation.Timeline]::DesiredFrameRateProperty.OverrideMetadata([System.Windows.Media.Animation.Timeline], (New-Object System.Windows.FrameworkPropertyMetadata([object][int]$script:Fps))) } catch { }

# ---------------------------------------------------------------- native helpers (cached builds)
$dataDir = Join-Path $Root 'data'
$cacheDir = Join-Path $dataDir 'cache'
if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
function Get-VxSrcHash { param([string]$Text) $s = [System.Security.Cryptography.SHA1]::Create(); try { return (($s.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))[0..7] | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $s.Dispose() } }
$csSrc = [System.IO.File]::ReadAllText((Join-Path $AppDir 'core\Native.cs'), [System.Text.Encoding]::UTF8)
$dll = Join-Path $cacheDir "VeloxNative_$(Get-VxSrcHash $csSrc).dll"
if (-not ('VeloxPC.Native' -as [type])) {
    try {
        if (-not (Test-Path -LiteralPath $dll)) { Add-Type -TypeDefinition $csSrc -OutputAssembly $dll -OutputType Library -ErrorAction Stop }
        if (-not ('VeloxPC.Native' -as [type])) { Add-Type -Path $dll -ErrorAction Stop }
    } catch {
        if (-not ('VeloxPC.Native' -as [type])) { Add-Type -TypeDefinition $csSrc -ErrorAction Stop }
    }
}
# 2.0 helpers (site motion curve, read-only benchmarks). Optional: the app works without them.
try {
    $exSrc = [System.IO.File]::ReadAllText((Join-Path $AppDir 'core\Extra.cs'), [System.Text.Encoding]::UTF8)
    $exDll = Join-Path $cacheDir "VeloxExtra_$(Get-VxSrcHash $exSrc).dll"
    if (-not ('VeloxPC.Extra' -as [type])) {
        $refs = @([System.Windows.Media.Animation.EasingFunctionBase].Assembly.Location, [System.Windows.Freezable].Assembly.Location, [System.Xaml.XamlReader].Assembly.Location)
        if (-not (Test-Path -LiteralPath $exDll)) { Add-Type -TypeDefinition $exSrc -ReferencedAssemblies $refs -OutputAssembly $exDll -OutputType Library -ErrorAction Stop }
        Add-Type -Path $exDll -ErrorAction Stop
    }
} catch { }
if (-not $headless) {
    try { [VeloxPC.Native]::HideConsole() } catch { }
    try { [void][VeloxPC.Native]::SetAppId('Piki.Optimizer') } catch { }
}

# ---------------------------------------------------------------- core modules
$coreFiles = @('Common', 'Hardware', 'Tweaks', 'Services', 'Network', 'AfterEffects', 'Cleanup', 'Health', 'Updater', 'Measure', 'Session')
foreach ($cf in $coreFiles) { . (Join-Path $AppDir "core\$cf.ps1") }
Initialize-VxPaths $Root
if ($Cleanup) {
    # called by the uninstaller
    if ($UndoAll) { foreach ($id in @((Get-VxBackup).entries.Keys)) { try { [void](Undo-VxEntry $id) } catch { } } }
    try { [void](Stop-VxSession) } catch { }
    foreach ($tn in @('PikiOptimizer', 'PikiOptimizer Clean')) { Unregister-ScheduledTask -TaskName $tn -Confirm:$false -ErrorAction SilentlyContinue }
    Write-VxLog 'Cleanup done (uninstall)'
    exit
}
if ($ScheduledClean) {
    # weekly / monthly task: safe items only, then exit
    $script:VxLang = 'en'
    try { $fr = Invoke-VxScheduledClean; Write-VxLog "Scheduled cleaning freed $fr bytes" } catch { Write-VxLog "Scheduled cleaning: $($_.Exception.Message)" 'WARN' }
    exit
}
Write-VxLog '---- Piki Optimizer start'
# the installed copy (not a test copy elsewhere) keeps its version in Settings > Apps up to date
$script:IsInstalledCopy = $false
try { $uk = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PikiOptimizer' -ErrorAction Stop; $script:IsInstalledCopy = ([string]$uk.InstallLocation).TrimEnd('\') -eq $Root.TrimEnd('\') } catch { }
try { if ($script:IsInstalledCopy) { $lmv = Get-VxLocalManifest; if ($lmv) { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PikiOptimizer' -Name DisplayVersion -Value ([string]$lmv.version) } } } catch { }

# a Game/Render session left open by a crash or a restart is undone right away
try { if (Get-VxSession) { [void](Stop-VxSession); Write-VxLog 'Leftover session undone at start' } } catch { }

$script:Settings = Get-VxSettings
if (-not $script:Settings.lang) {
    $cul = (Get-UICulture).TwoLetterISOLanguageName
    if (-not (Test-Path -LiteralPath (Join-Path $AppDir "lang\$cul.json"))) { $cul = (Get-Culture).TwoLetterISOLanguageName }
    $script:Settings.lang = if (Test-Path -LiteralPath (Join-Path $AppDir "lang\$cul.json")) { $cul } else { 'en' }
}
if (-not (Test-Path -LiteralPath (Join-Path $AppDir "lang\$($script:Settings.lang).json"))) { $script:Settings.lang = 'en' }
try { Save-VxSettings $script:Settings } catch { }
$script:VxLang = $script:Settings.lang
$script:Expert = [bool]$script:Settings.expert
$script:GlobalDryRun = [bool]$DryRun

$script:Lang = ConvertTo-VxHashtable ([System.IO.File]::ReadAllText((Join-Path $AppDir "lang\$($script:VxLang).json"), [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
if ($script:VxLang -ne 'en') {
    # any key missing in this language falls back to English
    try {
        $enLang = ConvertTo-VxHashtable ([System.IO.File]::ReadAllText((Join-Path $AppDir 'lang\en.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
        foreach ($k in @($enLang.Keys)) { if (-not $script:Lang.ContainsKey($k)) { $script:Lang[$k] = $enLang[$k] } }
    } catch { }
}
$script:Languages = @(
    @('it', 'Italiano'), @('en', 'English'), @('es', 'Español'), @('fr', 'Français'), @('de', 'Deutsch'),
    @('pt', 'Português'), @('ru', 'Русский'), @('zh', '中文'), @('ja', '日本語')
)
function T {
    param([string]$Key, [object[]]$Fmt)
    $s = $Key
    if ($script:Lang.ContainsKey($Key)) { $s = [string]$script:Lang[$Key] }
    # not "if ($Fmt)": PowerShell treats @(0) as false, so a count of 0 showed "{0}" on screen
    if ($null -ne $Fmt -and $Fmt.Count -gt 0) { try { $s = [string]::Format($s, $Fmt) } catch { } }
    return $s
}

# code that background jobs load before running (dot-sourced once per runspace from a cached file)
$coreText = New-Object System.Text.StringBuilder
foreach ($cf in $coreFiles) { [void]$coreText.AppendLine([System.IO.File]::ReadAllText((Join-Path $AppDir "core\$cf.ps1"), [System.Text.Encoding]::UTF8)) }
[void]$coreText.Insert(0, "`$ProgressPreference = 'SilentlyContinue'`n`$script:VxRoot = '$($Root -replace "'", "''")'`n")
[void]$coreText.AppendLine("Initialize-VxPaths '$($Root -replace "'", "''")'")
[void]$coreText.AppendLine("`$script:VxLang = '$($script:VxLang)'")
$script:CoreText = $coreText.ToString()
$script:CoreFile = Join-Path $cacheDir "core_$(Get-VxSrcHash $script:CoreText).ps1"
try {
    if (-not (Test-Path -LiteralPath $script:CoreFile)) {
        Get-ChildItem -LiteralPath $cacheDir -Filter 'core_*.ps1' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($script:CoreFile, $script:CoreText, (New-Object System.Text.UTF8Encoding($true)))
    }
} catch { $script:CoreFile = $null }

$script:Version = '2.0.0'
$lm = Get-VxLocalManifest
if ($lm -and $lm.version) { $script:Version = [string]$lm.version }

# ---------------------------------------------------------------- XAML
function Read-VxXaml {
    param([string]$File)
    $t = [System.IO.File]::ReadAllText((Join-Path $AppDir "ui\$File"), [System.Text.Encoding]::UTF8)
    return [regex]::Replace($t, '@\{([a-zA-Z0-9_.]+)\}', {
            param($m)
            $v = [System.Security.SecurityElement]::Escape((T $m.Groups[1].Value))
            if ($v.StartsWith('{')) { $v = '{}' + $v }   # not a markup extension
            $v
        })
}
function Show-VxFatal {
    param([string]$Message)
    Write-VxLog "FATAL: $Message" 'ERROR'
    try { [System.IO.File]::WriteAllText((Join-Path $script:VxLogs 'crash.log'), "$(Get-Date)`r`n$Message", [System.Text.Encoding]::UTF8) } catch { }
    [System.Windows.MessageBox]::Show("Piki Optimizer:`n`n$Message`n`n" + (T 'fatal.restore'), 'Piki Optimizer', 'OK', 'Error') | Out-Null
}
$xamlText = Read-VxXaml 'MainWindow.xaml'
try { $script:Window = [Windows.Markup.XamlReader]::Parse($xamlText) }
catch { Show-VxFatal ('UI: ' + $_.Exception.Message); exit }
$script:ui = @{}
foreach ($m in [regex]::Matches($xamlText, 'x:Name="([^"]+)"')) {
    $n = $m.Groups[1].Value
    $el = $script:Window.FindName($n)
    if ($el) { $script:ui[$n] = $el }
}
$ui = $script:ui
try {
    $icoPath = Join-Path $AppDir 'assets\veloxpc.ico'
    if (Test-Path -LiteralPath $icoPath) { $script:Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $icoPath)) }
} catch { }
# Inter (the site font), bundled with the app; Segoe UI if it cannot load
try {
    $fontDir = Join-Path $AppDir 'assets\fonts'
    if (Test-Path -LiteralPath (Join-Path $fontDir 'Inter-Regular.ttf')) {
        $script:Window.FontFamily = New-Object System.Windows.Media.FontFamily((New-Object System.Uri(($fontDir.TrimEnd('\') + '\'))), './#Inter, Segoe UI')
    }
} catch { Write-VxLog "font: $($_.Exception.Message)" 'WARN' }
$script:Window.Dispatcher.add_UnhandledException({
    param($s, $e)
    Write-VxLog ("UI error: " + $e.Exception.Message + ' ' + $e.Exception.StackTrace) 'ERROR'
    $e.Handled = $true
})

# =====================================================================
#  BACKGROUND JOBS
# =====================================================================
$script:Sync = [hashtable]::Synchronized(@{ Step = ''; Pct = 0 })
# background runspaces: opened on demand and closed again after 20 s without jobs. The modules a scan loads
# (storage, network, CIM) stay in memory as long as a runspace lives: closing the pool gives that RAM back.
$script:Pool = $null
$script:Jobs = New-Object System.Collections.ArrayList
$script:LastJobAt = [DateTime]::Now
function Open-VxPool {
    if ($script:Pool) { return }
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $script:Pool = [runspacefactory]::CreateRunspacePool($iss)
    [void]$script:Pool.SetMinRunspaces(1)
    [void]$script:Pool.SetMaxRunspaces(3)
    $script:Pool.Open()
}
function Close-VxPoolIfIdle {
    if (-not $script:Pool -or $script:Jobs.Count -gt 0 -or ([DateTime]::Now - $script:LastJobAt).TotalSeconds -lt 20) { return }
    try { $script:Pool.Close(); $script:Pool.Dispose() } catch { }
    $script:Pool = $null
    [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()
    try { [VeloxPC.Extra]::TrimWorkingSet() } catch { }
    Write-VxLog ("pool closed (idle), private {0:N0} MB" -f ((Get-Process -Id $PID).PrivateMemorySize64 / 1MB))
}
Open-VxPool

function Start-VxJob {
    param([string]$Name, [scriptblock]$Script, [object[]]$Arguments = @(), [scriptblock]$OnDone, [scriptblock]$OnError)
    if ($script:JobTimer -and $script:JobTimer.Interval.TotalMilliseconds -gt 150) { $script:JobTimer.Interval = [TimeSpan]::FromMilliseconds(120) }
    Open-VxPool
    $script:LastJobAt = [DateTime]::Now
    $ps = [powershell]::Create()
    $ps.RunspacePool = $script:Pool
    $wrap = "`n`$__t0 = [DateTime]::Now`n`$__r = & {`n" + $Script.ToString() + "`n} @args`n" +
        "Write-VxLog ('job body: $Name ({0:N0} ms)' -f ([DateTime]::Now - `$__t0).TotalMilliseconds)`n,`$__r"
    $reset = "`$script:VxAeCache = `$null; `$script:VxTopazCache = `$null; `$script:VxTx = `$null; `$script:VxNicRestart = `$false; `$script:VxBatch = `$null; `$script:VxDryRun = `$false; `$script:VxNicChanged = @{}`n"
    if ($script:CoreFile) {
        $load = "try { [System.Threading.Thread]::CurrentThread.Priority = 'BelowNormal' } catch { }`n" +
            "if (-not (Get-Command Initialize-VxPaths -CommandType Function -ErrorAction SilentlyContinue)) { . '" + ($script:CoreFile -replace "'", "''") + "' }`n" + $reset
        [void]$ps.AddScript($load + $wrap)
    } else {
        [void]$ps.AddScript($script:CoreText + "`n" + $reset + $wrap)
    }
    [void]$ps.AddArgument($script:Sync)
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    $job = @{ Name = $Name; PS = $ps; Handle = $ps.BeginInvoke(); OnDone = $OnDone; OnError = $OnError; Start = [DateTime]::Now }
    [void]$script:Jobs.Add($job)
    Write-VxLog "job start: $Name"
}

function Complete-VxJobs {
    for ($i = $script:Jobs.Count - 1; $i -ge 0; $i--) {
        $j = $script:Jobs[$i]
        if (-not $j.Handle.IsCompleted) { continue }
        $script:Jobs.RemoveAt($i)
        Write-VxLog ("job end: {0} ({1:N0} ms)" -f $j.Name, ([DateTime]::Now - $j.Start).TotalMilliseconds)
        $result = $null; $err = $null
        try {
            $out = $j.PS.EndInvoke($j.Handle)
            if ($out.Count -gt 0) { $result = $out[$out.Count - 1] }
            if ($result -is [System.Management.Automation.PSObject] -and $result.BaseObject -is [hashtable]) { $result = $result.BaseObject }
            foreach ($e in $j.PS.Streams.Error) { Write-VxLog "[$($j.Name)] $($e.ToString())" 'WARN' }
        } catch { $err = $_.Exception.InnerException; if (-not $err) { $err = $_.Exception } }
        finally { $j.PS.Dispose() }
        if ($err) {
            Write-VxLog "[$($j.Name)] job failed: $($err.Message)" 'ERROR'
            if ($j.OnError) { try { & $j.OnError $err } catch { Write-VxLog "OnError: $($_.Exception.Message)" 'ERROR' } }
            else { Hide-VxBusy; Show-VxToast ((T 'common.error') + ' ' + $err.Message) 'crit' }
        } elseif ($j.OnDone) {
            try { & $j.OnDone $result } catch { Write-VxLog "[$($j.Name)] OnDone: $($_.Exception.Message) $($_.ScriptStackTrace)" 'ERROR'; Hide-VxBusy }
        }
    }
}

# =====================================================================
#  MOTION: the site curve cubic-bezier(.22,1,.36,1), 150 ms (hover/press) / 300 ms (pages, panels),
#  40 ms stagger. Only opacity and transforms. Reduced / light mode: no stagger, quick fades only.
# =====================================================================
function New-VxBrush { param([string]$Hex) $b = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex)); $b.Freeze(); return $b }
try { $script:Ease = New-Object VeloxPC.BezierEase } catch { $script:Ease = New-Object System.Windows.Media.Animation.CubicEase; $script:Ease.EasingMode = 'EaseOut' }
$script:Ease.Freeze()
$script:OpacityP = [System.Windows.UIElement]::OpacityProperty
$script:TyP = [System.Windows.Media.TranslateTransform]::YProperty
$script:SxP = [System.Windows.Media.ScaleTransform]::ScaleXProperty
$script:Lite = @{ Lite = $false; Hot = 0; Cool = 0 }   # light mode while the CPU is saturated
$script:WeakUi = $false                                   # weak PC: always light
$script:Reduced = $false                                   # Windows "animation effects" off or the app setting
function Test-VxCalm { return ($script:Reduced -or $script:WeakUi -or $script:Lite.Lite) }

function New-VxAnim {
    param([double]$To, [int]$Ms, $From = $null, $Ease = $script:Ease)
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.To = $To
    if ($null -ne $From) { $a.From = [double]$From }
    $a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    if ($Ease) { $a.EasingFunction = $Ease }
    return $a
}

function Get-VxTransform {
    param($El, [string]$Kind = 'Translate')
    $type = if ($Kind -eq 'Scale') { [System.Windows.Media.ScaleTransform] } else { [System.Windows.Media.TranslateTransform] }
    if (-not ($El.RenderTransform -is $type) -or $El.RenderTransform.IsFrozen) { $El.RenderTransform = New-Object $type }
    return $El.RenderTransform
}

function Show-VxOverlay {
    param($Grid)
    $wasOpen = ($Grid.Visibility -eq 'Visible' -and $Grid.Tag -ne 'closing')
    $Grid.Tag = 'open'
    $Grid.Visibility = 'Visible'
    if ($wasOpen) { return }
    $Grid.BeginAnimation($script:OpacityP, (New-VxAnim 1 $(if (Test-VxCalm) { 120 } else { 200 }) 0))
    $panel = $null; foreach ($c in $Grid.Children) { if ($c -is [System.Windows.FrameworkElement] -and $c.VerticalAlignment -eq 'Center') { $panel = $c } }
    if ($panel -and -not (Test-VxCalm)) { (Get-VxTransform $panel).BeginAnimation($script:TyP, (New-VxAnim 0 300 10)) }
}

function Hide-VxOverlay {
    param($Grid)
    if ($Grid.Visibility -ne 'Visible' -or $Grid.Tag -eq 'closing') { return }
    $Grid.Tag = 'closing'
    $g = $Grid
    $a = New-VxAnim 0 110
    $a.add_Completed({ if ($g.Tag -eq 'closing') { $g.Visibility = 'Collapsed'; $g.Tag = $null } }.GetNewClosure())
    $Grid.BeginAnimation($script:OpacityP, $a)
}

# progress bars: ScaleX only (never Width)
function Set-VxBar {
    param($Bar, [double]$Fraction, [switch]$Instant)
    $Fraction = [math]::Max(0, [math]::Min(1, $Fraction))
    $sc = Get-VxTransform $Bar 'Scale'
    if ($Instant -or (Test-VxCalm)) { $sc.BeginAnimation($script:SxP, $null); $sc.ScaleX = $Fraction; return }
    if ($Bar.Tag -is [double] -and [math]::Abs([double]$Bar.Tag - $Fraction) -lt 0.004) { return }
    $Bar.Tag = $Fraction
    $sc.BeginAnimation($script:SxP, (New-VxAnim $Fraction 300))
}

function Show-VxToast {
    param([string]$Text, [string]$Kind = 'ok')
    $ui.ToastText.Text = $Text
    switch ($Kind) {
        'crit' { $ui.ToastIcon.Text = [char]0xE783; $ui.ToastIcon.Foreground = New-VxBrush '#D0606A' }
        'warn' { $ui.ToastIcon.Text = [char]0xE7BA; $ui.ToastIcon.Foreground = New-VxBrush '#D9A55C' }
        'info' { $ui.ToastIcon.Text = [char]0xE946; $ui.ToastIcon.Foreground = New-VxBrush '#D9BC8C' }
        default { $ui.ToastIcon.Text = [char]0xE73E; $ui.ToastIcon.Foreground = New-VxBrush '#9CC69B' }
    }
    $ui.Toast.Tag = 'open'
    $ui.Toast.Visibility = 'Visible'
    $ui.Toast.BeginAnimation($script:OpacityP, (New-VxAnim 1 150 0))
    if (-not (Test-VxCalm)) { (Get-VxTransform $ui.Toast).BeginAnimation($script:TyP, (New-VxAnim 0 300 10)) }
    $script:ToastUntil = (Get-Date).AddSeconds([math]::Max(3.5, $Text.Length / 22))
}

function Hide-VxToast {
    if ($ui.Toast.Visibility -ne 'Visible') { return }
    $ui.Toast.Tag = 'closing'
    $a = New-VxAnim 0 110
    $a.add_Completed({ if ($ui.Toast.Tag -eq 'closing') { $ui.Toast.Visibility = 'Collapsed' } })
    $ui.Toast.BeginAnimation($script:OpacityP, $a)
}

function Show-VxBusy {
    param([string]$Title, [string]$Text = '')
    $script:Sync.Step = $Text; $script:Sync.Pct = 0
    $ui.BusyTitle.Text = $Title
    $ui.BusyText.Text = $Text
    Set-VxBar $ui.BusyBar 0 -Instant
    # the spinner turns only while the busy card is visible
    $spin = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 360, [TimeSpan]::FromSeconds(1.1))
    $spin.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $ui.SpinnerRot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
    Show-VxOverlay $ui.BusyOverlay
    $script:BusyActive = $true
}
function Hide-VxBusy {
    Hide-VxOverlay $ui.BusyOverlay
    $script:BusyActive = $false
    $ui.SpinnerRot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
}

$script:DialogYes = $null; $script:DialogNo = $null
function Show-VxDialog {
    param([string]$Title, [string]$Text, [string]$YesText = 'OK', [string]$NoText = '', [scriptblock]$OnYes, [scriptblock]$OnNo)
    $ui.DialogTitle.Text = $Title
    $ui.DialogText.Text = $Text
    $ui.DialogYes.Content = $YesText
    if ($NoText) { $ui.DialogNo.Content = $NoText; $ui.DialogNo.Visibility = 'Visible' } else { $ui.DialogNo.Visibility = 'Collapsed' }
    $script:DialogYes = $OnYes; $script:DialogNo = $OnNo
    Show-VxOverlay $ui.DialogOverlay
}

function Set-VxRing {
    param($Ellipse, $Label, [double]$Value, [double]$Size, [double]$Thickness)
    if ($Value -le 0) { $Label.Text = $(if ($Value -lt 0) { '--' } else { '0' }); $Ellipse.Visibility = 'Hidden'; return }
    $Ellipse.Visibility = 'Visible'
    $circ = [math]::PI * ($Size - $Thickness) / $Thickness
    $len = [math]::Max(0.01, $circ * [math]::Min(100, $Value) / 100)
    $Ellipse.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection (, [double[]]@($len, 1000))
    $Label.Text = [string][int]$Value
    $Ellipse.Stroke = if ($Value -ge 80) { New-VxBrush '#9CC69B' } elseif ($Value -ge 55) { New-VxBrush '#D9A55C' } else { New-VxBrush '#D0606A' }
}

function Set-VxGrouped {
    param($Control, $Items, [string]$GroupProp = 'Group')
    $list = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($i in $Items) { $list.Add($i) }
    $Control.ItemsSource = $list
    if ($GroupProp) {
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($list)
        $view.GroupDescriptions.Clear()
        $view.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription $GroupProp))
    }
}

function Set-VxItems {
    param($Control, $Items)
    $list = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($i in $Items) { $list.Add($i) }
    $Control.ItemsSource = $list
}

function Get-VxRiskLabel { param([string]$Risk) return (T "risk.$Risk") }

function Open-VxTarget {
    param([string]$Target)
    try { Start-Process $Target } catch { Show-VxToast ((T 'common.error') + ' ' + $_.Exception.Message) 'crit' }
}

# =====================================================================
#  STATE
# =====================================================================
$script:Hw = $null
$script:States = @{}
$script:SvcRows = @()
$script:Health = $null
$script:Lists = @{ opt = @(); proc = @(); net = @(); ae = @() }
$script:Loaded = @{}
$script:CpuHist = New-Object System.Collections.Generic.List[double]
$script:RamHist = New-Object System.Collections.Generic.List[double]
$script:ProcLevels = @{ widgets = 1; edgeboost = 1; bgapps = 2; recall = 1; copilot = 2 }
$script:CurrentPage = 'Home'
$script:Remote = $null
$script:LostIds = @()
$script:Session = $null

# =====================================================================
#  OPTION LISTS (tweaks + services)
# =====================================================================
function New-VxTweakItem {
    param($T, $St)
    $o = New-Object VeloxPC.OptionItem
    $o.Id = $T.Id; $o.Kind = 'tweak'
    $o.Group = L $script:VxCatNames[$T.Cat]
    $o.Title = L $T.Title
    $o.Description = L $T.Desc
    if ($T.Warn) { $o.Warning = L $T.Warn }
    $o.Risk = $T.Risk; $o.RiskLabel = Get-VxRiskLabel $T.Risk
    $o.NeedsReboot = [bool]$T.Reboot; $o.RebootLabel = T 'common.reboot'
    $o.Status = T 'common.active'
    $o.IsApplied = [bool]$St.applied
    $o.IsChecked = $o.IsApplied
    if ($St.rec) {
        $why = L $St.rec.why
        switch ($St.rec.level) {
            'rec' { $o.Badge = (T 'badge.rec') + $(if ($why) { ' · ' + $why } else { '' }); $o.BadgeKind = 'good' }
            'notrec' { $o.Badge = (T 'badge.notrec') + $(if ($why) { ' · ' + $why } else { '' }); $o.BadgeKind = 'bad' }
            default { if ($why) { $o.Badge = $why; $o.BadgeKind = 'info' } }
        }
    }
    if ($script:Expert) {
        if ($T.Reg) { $o.Extra = (@($T.Reg | Select-Object -First 4 | ForEach-Object { "$($_[0])\$($_[1]) = $($_[3])" }) -join "`n") }
        else { $o.Extra = "id: $($T.Id)" }
    }
    return $o
}

function New-VxSvcItem {
    param($Row)
    $e = $Row.Entry
    $o = New-Object VeloxPC.OptionItem
    $o.Id = $Row.Id; $o.Kind = 'svc'; $o.Tag = $e.Target
    $o.Group = T "svc.group.$($e.Level)"
    $o.Title = L $e.Title
    $o.Description = L $e.Desc
    if ($e.Warn) { $o.Warning = L $e.Warn }
    $o.Risk = $e.Risk; $o.RiskLabel = Get-VxRiskLabel $e.Risk
    $o.Status = T 'svc.optimized'
    if ($e.Level -eq 0) {
        $o.IsSelectable = $false
        $o.IsApplied = $false; $o.IsChecked = $false
        if ($Row.Start -eq 4) { $o.Badge = T 'badge.disabledbyother'; $o.BadgeKind = 'bad' } else { $o.Badge = T 'badge.never'; $o.BadgeKind = 'bad' }
    } else {
        $o.IsApplied = [bool]$Row.Applied
        $o.IsChecked = $o.IsApplied
        if ($Row.Need) {
            $o.IsSelectable = $o.IsApplied   # allow turning it back on, never off
            $o.Badge = (T 'badge.need') + ' · ' + (L $Row.Need); $o.BadgeKind = 'protect'
        }
    }
    $startTxt = switch ([int]$Row.Start) { 2 { T 'svc.start.auto' } 3 { T 'svc.start.manual' } 4 { T 'svc.start.disabled' } default { '?' } }
    $runTxt = if ($Row.Running) { T 'svc.running' } else { T 'svc.stopped' }
    if ($script:Expert) { $o.Extra = "$($Row.Name) · $startTxt · $runTxt" } else { $o.Extra = "$startTxt · $runTxt" }
    return $o
}

function Update-VxOptionLists {
    $opt = @(); $proc = @(); $net = @(); $ae = @()
    foreach ($t in (Get-VxAllTweaks)) {
        $st = $script:States[$t.Id]
        if (-not $st -or -not $st.applicable) { continue }
        if (-not $script:Expert -and $t.Risk -eq 'advanced' -and -not $st.applied) { continue }
        $item = New-VxTweakItem $t $st
        switch ($t.Cat) { 'proc' { $proc += $item } 'net' { $net += $item } 'ae' { $ae += $item } default { $opt += $item } }
    }
    $order = @{}; $k = 0; foreach ($c in $script:VxCatOrder) { $order[(L $script:VxCatNames[$c])] = $k; $k++ }
    $opt = @($opt | Sort-Object @{ Expression = { $order[$_.Group] } })
    foreach ($r in $script:SvcRows) { $proc += (New-VxSvcItem $r) }
    $procOrder = @{ (T 'proc.group.tweaks') = 0; (T 'svc.group.1') = 1; (T 'svc.group.2') = 2; (T 'svc.group.3') = 3; (T 'svc.group.0') = 4 }
    foreach ($p in $proc) { if ($p.Kind -eq 'tweak') { $p.Group = T 'proc.group.tweaks' } }
    $proc = @($proc | Sort-Object @{ Expression = { $procOrder[$_.Group] } })
    $script:Lists = @{ opt = $opt; proc = $proc; net = $net; ae = $ae }
    Set-VxGrouped $ui.OptList $opt
    Set-VxGrouped $ui.ProcOptList $proc
    Set-VxItems $ui.NetOptList $net
    Set-VxItems $ui.AeOptList $ae
    foreach ($list in @($opt, $proc, $net, $ae)) {
        foreach ($it in $list) { $it.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'IsChecked') { Update-VxPendingBar } }) }
    }
    $ui.AeNoInstall.Visibility = if ($ae.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    Update-VxPendingBar
}

function Get-VxAllItems { return @($script:Lists.opt) + @($script:Lists.proc) + @($script:Lists.net) + @($script:Lists.ae) }

function Update-VxPendingBar {
    if ($script:PendingQueued) { return }
    $script:PendingQueued = $true
    [void]$script:Window.Dispatcher.BeginInvoke([Action] { $script:PendingQueued = $false; Update-VxPendingBarNow }, [System.Windows.Threading.DispatcherPriority]::Loaded)
}

function Update-VxPendingBarNow {
    $dirty = @(Get-VxAllItems | Where-Object { $_ -and $_.IsDirty })
    if ($dirty.Count -gt 0) {
        $on = @($dirty | Where-Object { $_.IsChecked }).Count
        $off = $dirty.Count - $on
        $txt = T 'pending.count' @($dirty.Count)
        if ($off -gt 0) { $txt += '  ·  ' + (T 'pending.detail' @($on, $off)) }
        $ui.PendingText.Text = $txt
        if ($ui.PendingBar.Visibility -ne 'Visible' -or $ui.PendingBar.Tag -eq 'closing') {
            $ui.PendingBar.Tag = 'open'
            $ui.PendingBar.Visibility = 'Visible'
            $ui.PendingBar.BeginAnimation($script:OpacityP, (New-VxAnim 1 150 0))
            if (-not (Test-VxCalm)) { (Get-VxTransform $ui.PendingBar).BeginAnimation($script:TyP, (New-VxAnim 0 300 14)) }
        }
    } elseif ($ui.PendingBar.Visibility -eq 'Visible' -and $ui.PendingBar.Tag -ne 'closing') {
        $ui.PendingBar.Tag = 'closing'
        $a = New-VxAnim 0 110
        $a.add_Completed({ if ($ui.PendingBar.Tag -eq 'closing') { $ui.PendingBar.Visibility = 'Collapsed' } })
        $ui.PendingBar.BeginAnimation($script:OpacityP, $a)
    }
}

# the job that applies / reverts; with $Preview it only lists what would change (dry run)
$script:ApplyJob = {
    param($Sync, $Hw, $ApplyIds, $RevertIds, $Rp, $Preview)
    $res = @{ ok = 0; failed = @(); reboot = $false; hags = $false; noUndo = 0; reverted = 0; rp = $null; preview = @() }
    if ($Preview) { Start-VxDryRun }
    $total = [math]::Max(1, $ApplyIds.Count + $RevertIds.Count)
    $i = 0
    if ($Rp -and -not $Preview) { $Sync.Step = (L @{ it = 'Creo un punto di ripristino...'; en = 'Creating a restore point...' }); $res.rp = New-VxRestorePoint 'Piki Optimizer' }
    # the power plan goes first (settings stored in the plan must land in the new plan), then the Ryzen X3D fix
    $ApplyIds = @(@($ApplyIds | Where-Object { $_ -eq 'powerplan' }) + @($ApplyIds | Where-Object { $_ -eq 'x3dfix' }) + @($ApplyIds | Where-Object { $_ -ne 'powerplan' -and $_ -ne 'x3dfix' }))
    if ($ApplyIds -contains 'x3dfix') { $RevertIds = @($RevertIds | Where-Object { @('powerplan', 'cpumin', 'coreparking', 'bgapps', 'svchost') -notcontains $_ }) }
    if (-not $Preview) { Start-VxBatch }
    try {
        foreach ($id in $ApplyIds) {
            $i++; $Sync.Pct = [int](100 * $i / $total)
            if ($id -like 'svc:*') {
                $name = $id.Substring(4)
                $e = $script:VxServices | Where-Object { $_.Name -eq $name -or ($_.Pattern -and $name -like $_.Pattern) } | Select-Object -First 1
                if (-not $e -or $e.Level -eq 0) { continue }
                $Sync.Step = L $e.Title
                if (Set-VxServiceOptimized -Name $name -Target $e.Target -Title (L $e.Title)) { $res.ok++ } else { $res.failed += (L $e.Title) }
            } else {
                $t = Find-VxTweak $id
                if (-not $t) { continue }
                $Sync.Step = L $t.Title
                $r = Invoke-VxTweak $t $Hw
                if ($r.ok) { $res.ok++; if ($t.Reboot) { $res.reboot = $true }; if ($id -eq 'hags') { $res.hags = $true } } else { $res.failed += ((L $t.Title) + ': ' + $r.error) }
            }
        }
        foreach ($id in $RevertIds) {
            $i++; $Sync.Pct = [int](100 * $i / $total)
            $Sync.Step = (L @{ it = 'Ripristino: '; en = 'Restoring: ' }) + $id
            if ($Preview) { Add-VxDryRecord ((L @{ it = 'annulla: '; en = 'undo: ' }) + $id); continue }
            if (Test-VxBackupEntry $id) {
                [void](Undo-VxEntry $id); $res.reverted++
                $t = Find-VxTweak $id
                if ($t -and $t.Reboot) { $res.reboot = $true }
            } else { $res.noUndo++ }
        }
    } finally { if (-not $Preview) { Stop-VxBatch } }
    if ($Preview) { $res.preview = @(Stop-VxDryRun) }
    return $res
}

function Format-VxPreview {
    param($Changes)
    $lines = @()
    $titles = @{}; foreach ($t in (Get-VxAllTweaks)) { $titles[$t.Id] = L $t.Title }
    $lastId = $null
    foreach ($c in @($Changes)) {
        if ($c.id -and $c.id -ne $lastId) { $lastId = $c.id; $lines += ''; $lines += $(if ($titles.ContainsKey($c.id)) { $titles[$c.id] } else { $c.id }) }
        $l = '   • ' + $c.what
        if ($c.from -or $c.to) { $l += ": $($c.from) -> $($c.to)" }
        $lines += $l
    }
    if ($lines.Count -eq 0) { return (T 'preview.nothing') }
    return ((T 'preview.head') + "`n" + ($lines -join "`n"))
}

function Invoke-VxApplyItems {
    param([string[]]$ApplyIds, [string[]]$RevertIds, [bool]$RestorePoint, [string]$Title, [scriptblock]$After, [switch]$Preview)
    if ($ApplyIds.Count -eq 0 -and $RevertIds.Count -eq 0) { return }
    $pv = [bool]$Preview -or $script:GlobalDryRun
    Show-VxBusy $(if ($pv) { T 'preview.busy' } else { $Title }) (T 'busy.preparing')
    $script:AfterApply = $After
    $script:ApplyWasPreview = $pv
    Start-VxJob -Name $(if ($pv) { 'preview' } else { 'apply' }) -Arguments @($script:Hw, [string[]]$ApplyIds, [string[]]$RevertIds, $RestorePoint, $pv) -Script $script:ApplyJob -OnDone {
        param($r)
        Hide-VxBusy
        if ($script:ApplyWasPreview) {
            Show-VxDialog -Title (T 'preview.title') -Text (Format-VxPreview $r.preview) -YesText 'OK'
            return
        }
        $msg = T 'apply.done' @($r.ok, $r.reverted)
        if ($r.noUndo -gt 0) { $msg += "`n" + (T 'apply.noundo' @($r.noUndo)) }
        if ($r.failed.Count -gt 0) { $msg += "`n`n" + (T 'apply.failed') + "`n- " + ($r.failed -join "`n- ") }
        if ($r.rp -eq $false -or $r.rp -eq 'off') { $msg += "`n`n" + (T 'apply.norp') }
        if ($r.ok -gt 0) { try { Set-VxMeasureAfterReboot } catch { } }
        $hasBase = $false; try { $hasBase = [bool](ConvertTo-VxHashtable (Read-VxJson 'bench.json' $null)).baseline } catch { }
        if ($r.reboot) {
            $msg += "`n`n" + (T 'apply.reboot')
            if ($r.hags) { $msg += "`n" + (T 'apply.reboot.hags') }
            if ($hasBase) { $msg += "`n" + (T 'apply.measure.reboot') }
            Show-VxDialog -Title (T 'apply.title') -Text $msg -YesText (T 'common.rebootnow') -NoText (T 'common.later') -OnYes { Restart-VxPc }
        } elseif ($r.ok -gt 0) {
            Show-VxDialog -Title (T 'apply.title') -Text ($msg + "`n`n" + (T 'apply.measure')) -YesText (T 'measure.run') -NoText 'OK' -OnYes { Show-VxPage 'Measure'; Start-VxMeasure }
        } else {
            Show-VxDialog -Title (T 'apply.title') -Text $msg -YesText 'OK'
        }
        Update-VxStates
        if ($script:AfterApply) { & $script:AfterApply }
    }
}

# never restart while After Effects or a render is open (a forced restart loses unsaved work)
function Restart-VxPc {
    if (Test-VxProcessRunning @('AfterFX', 'aerender', 'Adobe Media Encoder')) {
        Show-VxDialog -Title (T 'restart.ae.title') -Text (T 'restart.ae.text') -YesText 'OK'
        return
    }
    Restart-Computer -Force
}

function Get-VxPendingIds {
    $dirty = @(Get-VxAllItems | Where-Object { $_.IsDirty })
    return @{ apply = [string[]]@($dirty | Where-Object { $_.IsChecked } | ForEach-Object { $_.Id }); revert = [string[]]@($dirty | Where-Object { -not $_.IsChecked } | ForEach-Object { $_.Id }) }
}

function Update-VxStates {
    param([scriptblock]$Then)
    $script:AfterStates = $Then
    Start-VxJob -Name 'states' -Arguments @($script:Hw) -Script {
        param($Sync, $Hw)
        $st = Get-VxTweakStates $Hw
        $lost = @(); try { $lost = @(Find-VxLostTweaks $Hw $st) } catch { }
        $aeOld = $false; try { $aeOld = [bool](Test-VxAePriorityOld) } catch { }
        return @{ states = $st; services = @(Get-VxServiceRows $Hw); lost = $lost; aeOld = $aeOld }
    } -OnDone {
        param($r)
        $script:States = $r.states
        $script:SvcRows = @($r.services)
        $script:LostIds = @($r.lost)
        $script:AePrioOld = [bool]$r.aeOld
        try { Write-VxJson 'cache\states.json' $r.states } catch { }
        Update-VxOptionLists
        Update-VxHome
        Update-VxNotices
        if ($script:Loaded.Restore) { Update-VxRestorePage }
        if ($script:AfterStates) { $cb = $script:AfterStates; $script:AfterStates = $null; & $cb }
    }
}

function Select-VxPreset {
    param([string]$Preset)
    $sel = Get-VxPresetSelection -Preset $Preset -Hw $script:Hw -States $script:States
    foreach ($it in (@($script:Lists.opt) + @($script:Lists.net) + @($script:Lists.ae) + @($script:Lists.proc | Where-Object { $_.Kind -eq 'tweak' }))) {
        if (-not $it.IsSelectable) { continue }
        $it.IsChecked = ($sel -contains $it.Id)
    }
    $script:Settings.profile = $Preset
    Save-VxSettings $script:Settings
    Update-VxPendingBar
}

function Select-VxProcLevel {
    param([int]$Level)
    foreach ($it in $script:Lists.proc) {
        if (-not $it.IsSelectable) { continue }
        if ($it.Kind -eq 'svc') {
            $row = $script:SvcRows | Where-Object { $_.Id -eq $it.Id } | Select-Object -First 1
            if ($row) { $it.IsChecked = ($row.Entry.Level -ge 1 -and $row.Entry.Level -le $Level) -or ($it.IsApplied -and $row.Entry.Level -le $Level) }
        } else {
            $lv = $script:ProcLevels[$it.Id]
            if ($lv) { $it.IsChecked = ($lv -le $Level) }
        }
    }
    Update-VxPendingBar
}

# =====================================================================
#  NOTICES: settings Windows undid / options removed in 2.0
# =====================================================================
function Get-VxRetiredEntries {
    $b = Get-VxBackup
    return @($b.entries.Keys | Where-Object { (Test-VxRetiredId $_) -and @($b.entries[$_].items).Count -gt 0 } | ForEach-Object { $b.entries[$_] })
}

function Update-VxNotices {
    # Windows undid N settings
    $lost = @($script:LostIds)
    $key = ($lost | Sort-Object) -join ','
    if ($lost.Count -gt 0 -and $key -ne [string]$script:Settings.lostSeen) {
        $names = @(); foreach ($id in $lost) { $t = Find-VxTweak $id; if ($t) { $names += (L $t.Title) } }
        $ui.LostTitle.Text = T 'lost.title' @($lost.Count)
        $ui.LostText.Text = (T 'lost.text') + ' ' + ($names -join ' · ')
        $ui.LostCard.Visibility = 'Visible'
    } else { $ui.LostCard.Visibility = 'Collapsed' }
    # options removed in 2.0 (Defender exclusions, app updaters, placebo items)
    $ret = @(Get-VxRetiredEntries)
    $unseen = @($ret | Where-Object { @($script:Settings.retiredSeen) -notcontains $_.id })
    $ui.RetiredCardHome.Visibility = if ($unseen.Count -gt 0 -or ($script:AePrioOld -and @($script:Settings.retiredSeen) -notcontains 'ae.priority')) { 'Visible' } else { 'Collapsed' }
    $lines = @($ret | ForEach-Object { '• ' + $_.title + $(if ($_.id -like '*defender*') { '  — ' + (T 'retired.defender') } else { '' }) })
    if ($script:AePrioOld) { $lines += '• ' + (T 'retired.aeprio') }
    $ui.RetiredList.Text = $lines -join "`n"
    $ui.BtnRetiredUndo.Visibility = if ($ret.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $ui.BtnRetiredUpdate.Visibility = if ($script:AePrioOld) { 'Visible' } else { 'Collapsed' }
    $ui.RetiredCard.Visibility = if ($ret.Count -gt 0 -or $script:AePrioOld) { 'Visible' } else { 'Collapsed' }
}

# =====================================================================
#  HOME
# =====================================================================
function New-VxStat { param([string]$Label, $Value, [string]$Unit, [string]$Sub) return [pscustomobject]@{ Label = $Label; Value = [string]$Value; Unit = $Unit; Sub = $Sub } }

function Update-VxHwCards {
    $hw = $script:Hw
    $rows = @()
    $mk = { param($g, $l, $t, $s) $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]$g; $c.Label = $l; $c.Title = $t; $c.Sub = $s; $c }
    $rows += (& $mk 0xE9D9 (T 'hw.cpu') $hw.CPU.Name (T 'hw.cpu.sub' @($hw.CPU.Cores, $hw.CPU.Threads)))
    if ($hw.GPU) { $rows += (& $mk 0xE7F4 (T 'hw.gpu') $hw.GPU.Name $(if ($hw.GPU.VramBytes -gt 0) { '{0} GB VRAM' -f [math]::Round($hw.GPU.VramBytes / 1GB) } else { '' })) }
    $rows += (& $mk 0xE950 'RAM' "$($hw.RAM.GB) GB $($hw.RAM.Type)" $(if ($hw.RAM.SpeedMTs) { "$($hw.RAM.SpeedMTs) MT/s · " + (T 'hw.ram.modules' @($hw.RAM.Modules)) } else { '' }))
    $sys = @($hw.Disks | Where-Object { $_.IsSystem }) | Select-Object -First 1
    if ($sys) { $rows += (& $mk 0xEDA2 (T 'hw.disk') $sys.Name ("$($sys.Media) $($sys.Bus) · " + ('{0:N0} GB' -f ($sys.SizeBytes / 1GB)))) }
    $d = @($hw.Displays | Where-Object { $_.Primary }) | Select-Object -First 1
    if ($d) { $rows += (& $mk 0xE7F8 (T 'hw.screen') "$($d.Width) x $($d.Height) · $($d.CurrentHz) Hz" $d.Monitor) }
    $rows += (& $mk 0xE7F8 'Windows' $hw.OS.Name "$($hw.OS.DisplayVersion) · build $($hw.OS.Build) · $(if ($hw.IsLaptop) { T 'hw.laptop' } else { T 'hw.desktop' })")
    Set-VxItems $ui.HwList $rows
}

function New-VxFindingObj {
    param($F)
    $o = New-Object VeloxPC.Finding
    $o.Severity = $F.sev; $o.Title = $F.title; $o.Detail = $F.detail
    $o.ActionId = $F.action; $o.ActionLabel = $F.actionLabel; $o.Category = $F.cat
    return $o
}

function Update-VxHomeStats {
    # four measured numbers: boot time, RAM in use, startup apps, free space (read-only, ~1 s)
    Start-VxJob -Name 'homestats' -Script {
        param($Sync)
        $r = @{ boot = (Get-VxBootTime) }
        try { $st = @(Get-VxStartupItems | Where-Object { $_.Enabled }); $r.startup = $st.Count; $r.high = @($st | Where-Object { $_.Impact -eq 'high' }).Count } catch { $r.startup = -1; $r.high = 0 }
        $m = [VeloxPC.Native]::Memory(); $r.ramUsed = [math]::Round(($m[1] - $m[2]) / 1GB, 1); $r.ramTotal = [math]::Round($m[1] / 1GB)
        try { $sd = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop; $r.free = [math]::Round([int64]$sd.FreeSpace / 1GB); $r.freePct = [int](100 * [int64]$sd.FreeSpace / [math]::Max(1, [int64]$sd.Size)) } catch { $r.free = -1 }
        return $r
    } -OnDone {
        param($r)
        $script:HomeStats = $r
        $stats = @()
        $stats += New-VxStat (T 'stat.boot') $(if ($r.boot) { '{0:N0}' -f ($r.boot.total / 1000) } else { '—' }) $(if ($r.boot) { ' s' } else { '' }) $(if ($r.boot) { T 'stat.boot.sub' } else { T 'stat.boot.none' })
        $stats += New-VxStat (T 'stat.ram') ('{0:N1}' -f $r.ramUsed) ' GB' (T 'stat.ram.sub' @($r.ramTotal))
        $stats += New-VxStat (T 'stat.startup') $(if ($r.startup -ge 0) { $r.startup } else { '—' }) '' $(if ($r.high -gt 0) { T 'stat.startup.high' @($r.high) } else { T 'stat.startup.sub' })
        $stats += New-VxStat (T 'stat.free') $(if ($r.free -ge 0) { $r.free } else { '—' }) ' GB' $(if ($r.free -ge 0) { T 'stat.free.sub' @($r.freePct) } else { '' })
        Set-VxItems $ui.HomeStats $stats
        $ui.StatStartup.Text = if ($r.startup -ge 0) { [string]$r.startup } else { '-' }
        $ui.StatHigh.Text = [string]$r.high
    }
}

function Update-VxHome {
    if (-not $script:Hw) { return }
    $issues = 0
    if ($script:Health) { $issues = [int]$script:Health.crit + [int]$script:Health.warn }
    $weak = Test-VxWeakPc $script:Hw
    if (-not $script:Health) { $ui.HomeStatus.Text = T 'home.status.unknown'; $ui.HomeStatusSub.Text = T 'home.status.unknown.sub' }
    elseif ($issues -gt 0) { $ui.HomeStatus.Text = T 'home.status.issues' @($issues); $ui.HomeStatusSub.Text = T 'home.status.issues.sub' }
    elseif ($weak) { $ui.HomeStatus.Text = T 'home.status.weak'; $ui.HomeStatusSub.Text = T 'home.status.weak.sub' }
    else { $ui.HomeStatus.Text = T 'home.status.healthy'; $ui.HomeStatusSub.Text = T 'home.status.healthy2.sub' }
    $adv = @()
    if ($script:Health) {
        $rank = @{ crit = 0; warn = 1; info = 2; ok = 3 }
        $adv += @($script:Health.findings | Where-Object { $_.sev -ne 'ok' } | Sort-Object @{ Expression = { $rank[$_.sev] } } | Select-Object -First 5 | ForEach-Object { New-VxFindingObj $_ })
    }
    if ($adv.Count -eq 0) { $f = New-Object VeloxPC.Finding; $f.Severity = 'ok'; $f.Title = T 'home.adv.none'; $f.Detail = T 'home.adv.none.sub'; $adv += $f }
    Set-VxItems $ui.HomeAdvice $adv
    $n = $issues
    if ($n -gt 0) { $ui.HealthBadgeText.Text = [string]$n; $ui.HealthBadge.Visibility = 'Visible' } else { $ui.HealthBadge.Visibility = 'Collapsed' }
    $ui.SlowBadge.Visibility = if ($weak) { 'Visible' } else { 'Collapsed' }
    $ui.WizSlowBadge.Visibility = $ui.SlowBadge.Visibility
}

# =====================================================================
#  MEASURE
# =====================================================================
function Start-VxMeasure {
    param([switch]$Baseline, [scriptblock]$Then)
    if ($script:MeasureRunning) { return }
    $script:MeasureRunning = $true
    $script:MeasureThen = $Then
    $ui.BtnMeasureRun.IsEnabled = $false
    $ui.MeasureStatus.Text = T 'measure.running'
    Show-VxBusy (T 'measure.busy') (T 'busy.preparing')
    Start-VxJob -Name 'measure' -Arguments @($script:Hw, [bool]$Baseline) -Script {
        param($Sync, $Hw, $AsBase)
        $s = New-VxMeasureSnapshot $Hw $Sync
        if ($AsBase) { return (Save-VxMeasureSnapshot $s -AsBaseline) }
        return (Save-VxMeasureSnapshot $s)
    } -OnDone {
        param($b)
        $script:MeasureRunning = $false
        $ui.BtnMeasureRun.IsEnabled = $true
        Hide-VxBusy
        Update-VxMeasurePage
        Show-VxToast (T 'measure.done') 'ok'
        if ($script:MeasureThen) { $cb = $script:MeasureThen; $script:MeasureThen = $null; & $cb }
    } -OnError {
        param($e)
        $script:MeasureRunning = $false
        $ui.BtnMeasureRun.IsEnabled = $true
        Hide-VxBusy
        Show-VxToast ((T 'common.error') + ' ' + $e.Message) 'crit'
    }
}

function Format-VxNum { param($v, [int]$Dec = 1) if ($null -eq $v) { return '—' }; $d = [double]$v; if ([math]::Abs($d) -ge 100) { return ('{0:N0}' -f $d) }; return ("{0:N$Dec}" -f $d) }

function Update-VxMeasurePage {
    $b = ConvertTo-VxHashtable (Read-VxJson 'bench.json' $null)
    $cards = @()
    if ($b -and $b.latest) {
        $same = ($b.baseline.time -eq $b.latest.time)
        foreach ($r in (Get-VxMeasureDeltas $(if ($same) { $null } else { $b.baseline }) $b.latest)) {
            $kind = ''; $delta = ''
            if ($null -ne $r.delta -and -not $same) {
                $arrow = if ($r.delta -lt 0) { [string][char]0x2193 } else { [string][char]0x2191 }
                $delta = $arrow + ' ' + (Format-VxNum ([math]::Abs($r.delta))) + $r.unit
                if ($null -ne $r.good) { $kind = if ($r.good) { 'good' } else { 'bad' } } else { $delta = T 'measure.same' }
            }
            $cards += [pscustomobject]@{
                Label = T "metric.$($r.key)"; Value = (Format-VxNum $r.after); Unit = $(if ($r.unit) { ' ' + $r.unit } else { '' })
                Before = $(if ($null -ne $r.before -and -not $same) { (T 'measure.before') + ' ' + (Format-VxNum $r.before) + $(if ($r.unit) { ' ' + $r.unit } else { '' }) } else { '' })
                Delta = $delta; Kind = $kind
            }
        }
        $txt = T 'measure.status' @($b.baseline.time, $b.latest.time)
        if ($b.pendingAfterReboot) { $txt += "`n" + (T 'measure.pending') }
        $ui.MeasureStatus.Text = $txt
        $top = @()
        foreach ($p in @($b.latest.cpu.top)) { if ($p) { $k = New-Object VeloxPC.KeyValueRow; $k.Key = [string]$p.name; $k.Value = ('{0:N1} %' -f [double]$p.cpu); $top += $k } }
        Set-VxItems $ui.TopProcList $top
    } else { $ui.MeasureStatus.Text = T 'measure.none' }
    Set-VxItems $ui.MetricList $cards
    Update-VxTrend
}

function Update-VxTrend {
    $trRaw = ConvertTo-VxHashtable (Read-VxJson 'healthtrend.json' $null)   # assign first: the function returns the array as one object
    $tr = @($trRaw | Where-Object { $_ })
    $ui.TrendLine.Points = New-Object System.Windows.Media.PointCollection
    if ($tr.Count -lt 1) { $ui.TrendText.Text = T 'measure.trend.none'; return }
    $w = [math]::Max(200, $ui.TrendCanvas.ActualWidth); $h = 80
    $pts = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $tr.Count; $i++) {
        $x = if ($tr.Count -eq 1) { $w / 2 } else { $i * ($w - 4) / ($tr.Count - 1) + 2 }
        $pts.Add((New-Object System.Windows.Point($x, ($h - 4 - ([double]$tr[$i].score / 100) * ($h - 8)))))
    }
    $ui.TrendLine.Points = $pts
    $ui.TrendText.Text = T 'measure.trend.text' @($tr.Count, $tr[0].score, $tr[$tr.Count - 1].score)
}

function Copy-VxReport {
    param([switch]$Save)
    $b = ConvertTo-VxHashtable (Read-VxJson 'bench.json' $null)
    $txt = Get-VxReportText $script:Hw $script:Health $b $script:Version
    if ($Save) {
        try {
            $f = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Piki-Optimizer-report.txt'
            [System.IO.File]::WriteAllText($f, $txt, (New-Object System.Text.UTF8Encoding($true)))
            Show-VxToast (T 'report.saved') 'ok'
        } catch { Show-VxToast $_.Exception.Message 'crit' }
    } else {
        try { [System.Windows.Clipboard]::SetText($txt); Show-VxToast (T 'report.copied') 'ok' } catch { Show-VxToast $_.Exception.Message 'crit' }
    }
}

# =====================================================================
#  HEALTH
# =====================================================================
function Update-VxHealthPage {
    $h = $script:Health
    if (-not $h) { return }
    Set-VxRing $ui.RingHealth2 $ui.RingHealth2Text ([int]$h.score) 96 8
    $ok = @($h.findings | Where-Object { $_.sev -eq 'ok' }).Count
    $ui.HealthCrit.Text = T 'health.crit' @($h.crit)
    $ui.HealthWarn.Text = T 'health.warn' @($h.warn)
    $ui.HealthOk.Text = T 'health.ok' @($ok)
    $ui.HealthStatus.Text = if ($h.score -ge 90) { T 'health.s.great' } elseif ($h.score -ge 75) { T 'health.s.good' } elseif ($h.score -ge 50) { T 'health.s.fix' } else { T 'health.s.bad' }
    $ui.HealthWhen.Text = T 'health.when' @($h.time)
    $rank = @{ crit = 0; warn = 1; info = 2; ok = 3 }
    $items = @()
    foreach ($f in @($h.findings | Sort-Object @{ Expression = { $rank[$_.sev] } })) {
        $o = New-VxFindingObj $f
        $o.Category = switch ($f.sev) { 'crit' { T 'health.g.crit' } 'warn' { T 'health.g.warn' } 'info' { T 'health.g.info' } default { T 'health.g.ok' } }
        $items += $o
    }
    Set-VxGrouped $ui.HealthList $items 'Category'
}

function Start-VxHealthCheck {
    param([switch]$Splash)
    if (-not $Splash) { Show-VxBusy (T 'health.running') (T 'busy.preparing') }
    $script:HealthSplash = [bool]$Splash
    Start-VxJob -Name 'health' -Arguments @($script:Hw) -Script {
        param($Sync, $Hw)
        $r = Invoke-VxHealthCheck $Hw $Sync
        Write-VxJson 'health.json' $r
        return $r
    } -OnDone {
        param($r)
        $script:Health = ConvertTo-VxHashtable $r
        $script:Settings.firstRunDone = $true
        $script:Settings.lastHealth = $script:Health.time
        Save-VxSettings $script:Settings
        Hide-VxBusy
        Update-VxHealthPage
        Update-VxHome
        if ($script:Loaded.Measure) { Update-VxTrend }
        if ($script:HealthSplash) { Hide-VxSplash; Show-VxPage 'Health' }
    } -OnError {
        param($e)
        Hide-VxBusy
        if ($script:HealthSplash) { Hide-VxSplash }
        Show-VxToast ((T 'common.error') + ' ' + $e.Message) 'crit'
    }
}

function Invoke-VxFindingAction {
    param([string]$Action, $Finding)
    if (-not $Action) { return }
    if ($Action -eq 'oneclick') { Show-VxWizard; return }
    if ($Action -like 'goto:*') {
        $map = @{ cleanup = 'Cleanup'; processes = 'Processes'; network = 'Network'; optimize = 'Optimize'; ae = 'Ae'; measure = 'Measure' }
        Show-VxPage $map[$Action.Substring(5)]; return
    }
    if ($Action -like 'open:*') {
        $hwv = if ($script:Hw.GPU) { $script:Hw.GPU.Vendor } else { '' }
        $gpuUrl = switch ($hwv) { 'NVIDIA' { 'https://www.nvidia.com/software/nvidia-app/' } 'AMD' { 'https://www.amd.com/support/download/drivers.html' } 'Intel' { 'https://www.intel.com/content/www/us/en/support/detect.html' } default { 'ms-settings:windowsupdate' } }
        $map = @{ windowsupdate = 'ms-settings:windowsupdate'; security = 'windowsdefender:'; devmgr = 'devmgmt.msc'; gpudriver = $gpuUrl; display = 'ms-settings:display-advanced' }
        Open-VxTarget $map[$Action.Substring(5)]; return
    }
    if ($Action -eq 'restart' -or $Action -eq 'fix:bios') {
        if (Test-VxPreviewStop $Action) { return }
    }
    if ($Action -eq 'restart') {
        Show-VxDialog -Title (T 'fix.restart.q') -Text (T 'fix.restart.text') -YesText (T 'common.rebootnow') -NoText (T 'common.cancel') -OnYes { Restart-VxPc }
        return
    }
    if ($Action -eq 'fix:bios') {
        Show-VxDialog -Title (T 'fix.bios.q') -Text (T 'fix.bios.text') -YesText (T 'fix.bios.yes') -NoText (T 'common.cancel') -OnYes { Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList '/r /fw /t 5' -WindowStyle Hidden }
        return
    }
    if ($Action -like 'fix:*') {
        if (Test-VxPreviewStop $Action) { return }
        $script:FixFinding = $Finding
        $title = if ($Action -eq 'fix:repair') { T 'health.repairing' } else { T 'busy.fixing' }
        Show-VxBusy $title (T 'busy.wait')
        Start-VxJob -Name 'fix' -Arguments @($Action, $script:Hw) -Script {
            param($Sync, $Action, $Hw)
            return @{ msg = (Invoke-VxHealthFix -Action $Action -Hw $Hw -Sync $Sync) }
        } -OnDone {
            param($r)
            Hide-VxBusy
            if ($script:FixFinding) { $script:FixFinding.Status = [string][char]0x2713 + ' ' + $r.msg }
            Show-VxDialog -Title (T 'fix.done') -Text $r.msg -YesText 'OK' -OnYes { Start-VxHealthCheck }
            Update-VxStates
        }
    }
}

# =====================================================================
#  WIZARD ("Velocizza il PC")
# =====================================================================
$script:WizNames = @('WizSlowpc', 'WizPiki', 'WizGaming', 'WizCompetitive', 'WizCreator', 'WizBalanced', 'WizLaptop')
function Show-VxWizard {
    if (-not $script:Hw -or $script:States.Count -eq 0) { Show-VxToast (T 'common.wait') 'info'; return }
    foreach ($n in $script:WizNames) { $ui[$n].IsChecked = $false }
    $ui.WizSummary.Text = T 'wiz.pick'; $ui.WizDetail.Text = ''
    $ui.WizGo.IsEnabled = $false; $ui.WizPreview.IsEnabled = $false
    $script:WizPreset = $null
    Show-VxOverlay $ui.WizardOverlay
    # weak PC: "PC lento" is suggested and preselected
    if (Test-VxWeakPc $script:Hw) { $ui.WizSlowpc.IsChecked = $true }
}

function Get-VxWizardPlan {
    param([string]$Preset)
    $sel = @(Get-VxPresetSelection -Preset $Preset -Hw $script:Hw -States $script:States | Where-Object { -not $script:States[$_].applied })
    $level = if ($Preset -eq 'piki') { 0 } else { 1 }
    $svc = @($script:SvcRows | Where-Object { $_.Entry.Level -ge 1 -and $_.Entry.Level -le $level -and -not $_.Need -and -not $_.Applied } | ForEach-Object { $_.Id })
    return @{ tweaks = $sel; services = $svc }
}

function Update-VxWizardSummary {
    param([string]$Preset)
    $script:WizPreset = $Preset
    $plan = Get-VxWizardPlan $Preset
    $n = $plan.tweaks.Count + $plan.services.Count
    if ($n -eq 0) { $ui.WizSummary.Text = T 'wiz.nothing'; $ui.WizDetail.Text = ''; $ui.WizGo.IsEnabled = $false; $ui.WizPreview.IsEnabled = $false; return }
    $ui.WizSummary.Text = T 'wiz.summary' @($plan.tweaks.Count, $plan.services.Count)
    $names = @()
    foreach ($id in ($plan.tweaks | Select-Object -First 8)) { $t = Find-VxTweak $id; if ($t) { $names += (L $t.Title) } }
    $more = $plan.tweaks.Count - $names.Count
    $ui.WizDetail.Text = ($names -join ' · ') + $(if ($more -gt 0) { ' · ' + (T 'wiz.more' @($more)) } else { '' })
    $ui.WizGo.IsEnabled = $true; $ui.WizPreview.IsEnabled = $true
}

function Start-VxWizardApply {
    $plan = Get-VxWizardPlan $script:WizPreset
    $script:Settings.profile = $script:WizPreset
    Save-VxSettings $script:Settings
    Invoke-VxApplyItems -ApplyIds (@($plan.tweaks) + @($plan.services)) -RevertIds @() -RestorePoint $true -Title (T 'busy.optimizing')
}

# =====================================================================
#  STARTUP APPS AND PROCESSES ("Avvio e app")
# =====================================================================
function Update-VxProcStats {
    Start-VxJob -Name 'counts' -Script {
        param($Sync)
        $c = Get-VxSystemCounts
        $m = [VeloxPC.Native]::Memory()
        $c.Ram = [int]$m[0]
        return $c
    } -OnDone {
        param($r)
        $ui.StatProcs.Text = [string]$r.Processes
        $ui.StatRam.Text = "$($r.Ram)%"
    }
}

function Update-VxStartupList {
    Start-VxJob -Name 'startup' -Script { param($Sync) return @{ items = @(Get-VxStartupItems) } } -OnDone {
        param($r)
        $items = @(); $high = 0; $on = 0
        foreach ($s in @($r.items)) {
            $o = New-Object VeloxPC.OptionItem
            $o.Id = $s.Id; $o.Kind = 'startup'; $o.Tag = $s
            $o.Title = $s.Name
            $o.Description = L $s.Advice.A
            $o.Risk = $s.Advice.Risk; $o.RiskLabel = Get-VxRiskLabel $s.Advice.Risk
            $o.IsChecked = [bool]$s.Enabled; $o.IsApplied = [bool]$s.Enabled
            $o.IsSelectable = ($s.Advice.Risk -ne 'avoid') -or (-not $s.Enabled)
            $lvl = [string]$s.Impact
            $o.BadgeKind = $lvl
            $o.Badge = if ($lvl) { T "impact.$lvl" } else { T 'impact.none' }
            if ($s.Enabled) { $on++; if ($lvl -eq 'high') { $high++ } }
            $ex = @()
            if ($s.Publisher) { $ex += $s.Publisher }
            if ($s.ImpactCpuMs -ge 0) { $ex += (T 'impact.detail' @([int]$s.ImpactCpuMs, [math]::Round([double]$s.ImpactDisk / 1MB, 1))) }
            $ex += [string]$s.Command
            $o.Extra = $ex -join '  ·  '
            $items += $o
        }
        $script:StartupSuppress = $true
        Set-VxItems $ui.StartupList $items
        $script:StartupSuppress = $false
        $ui.StatStartup.Text = [string]$on
        $ui.StatHigh.Text = [string]$high
    }
}

function Update-VxProcList {
    $ui.BtnProcRefresh.IsEnabled = $false
    Start-VxJob -Name 'procs' -Script { param($Sync) return @{ groups = @(Get-VxProcessGroups) } } -OnDone {
        param($r)
        $ui.BtnProcRefresh.IsEnabled = $true
        $rows = @()
        foreach ($g in @($r.groups | Select-Object -First 100)) {
            $o = New-Object VeloxPC.ProcRow
            $o.Name = $g.Name; $o.Count = $g.Count
            $o.MemMB = [math]::Round($g.Mem / 1MB)
            $o.MemText = if ($g.Mem -ge 1GB) { '{0:N1} GB' -f ($g.Mem / 1GB) } else { '{0:N0} MB' -f ($g.Mem / 1MB) }
            $o.Cpu = $g.Cpu; $o.CpuText = '{0:N1}%' -f $g.Cpu
            $o.Description = $(if ($g.Count -gt 1) { "x$($g.Count)  " } else { '' }) + [string]$g.Description
            $o.Risk = $g.Risk; $o.RiskLabel = Get-VxRiskLabel $g.Risk
            $o.Advice = L $g.Advice
            $o.CanEnd = ($g.Risk -ne 'avoid')
            $o.Path = $g.Path
            $rows += $o
        }
        Set-VxItems $ui.ProcList $rows
    }
}

# global preview (-DryRun): actions that are not item changes (close apps, sessions, undo, fixes, restore point,
# network reset, cache folders) are not recorded by the dry-run engine, so in preview they only say so and stop.
function Test-VxPreviewStop {
    param([string]$What = '')
    if (-not $script:GlobalDryRun) { return $false }
    Show-VxToast ((T 'preview.title') + $(if ($What) { ': ' + $What } else { '' })) 'info'
    Write-VxLog "Preview: skipped $What"
    return $true
}

# Boost: shows what it would close (with the RAM each one uses) and closes only after one confirmation
function Invoke-VxBoost {
    if (Test-VxPreviewStop 'boost') { return }
    $keep = @('Spotify', 'AnyDesk')
    if ($script:Hw -and $script:Hw.CPU.IsX3DDual) { $keep += @('GameBar', 'GameBarFTServer') }
    Start-VxJob -Name 'boostplan' -Arguments @(, [string[]]$keep) -Script { param($Sync, $Keep) return @{ plan = @(Get-VxBoostPlan $Keep) } } -OnDone {
        param($r)
        $plan = @($r.plan)
        if ($plan.Count -eq 0) { Show-VxDialog -Title (T 'boost.done') -Text (T 'boost.nothing') -YesText 'OK'; return }
        $script:BoostNames = [string[]]@($plan | ForEach-Object { $_.Name })
        $total = [int64]0; foreach ($p in $plan) { $total += [int64]$p.Mem }
        $lines = @($plan | ForEach-Object { '• ' + $_.Name + $(if ($_.Count -gt 1) { " (x$($_.Count))" } else { '' }) + ' — ' + (Format-VxBytes $_.Mem) })
        Show-VxDialog -Title (T 'boost.confirm.title') -Text ((T 'boost.confirm.text' @((Format-VxBytes $total))) + "`n`n" + ($lines -join "`n")) -YesText (T 'boost.confirm.yes') -NoText (T 'common.cancel') -OnYes {
            Show-VxBusy (T 'boost.title') (T 'busy.wait')
            Start-VxJob -Name 'boost' -Arguments @(, $script:BoostNames) -Script { param($Sync, $Names) return (Invoke-VxBoostClose $Names) } -OnDone {
                param($r2)
                Hide-VxBusy
                $list = if (@($r2.closed).Count -gt 0) { (@($r2.closed) -join ', ') } else { T 'boost.none' }
                Show-VxDialog -Title (T 'boost.done') -Text (T 'boost.text2' @((Format-VxBytes $r2.freed), $list)) -YesText 'OK'
                if ($script:Loaded.Processes) { Update-VxProcList; Update-VxProcStats }
            }
        }
    }
}

# =====================================================================
#  NETWORK
# =====================================================================
$script:PingColors = @('#D9BC8C', '#EFE9E0', '#9CC69B', '#B39C8E', '#D9A55C')

function Update-VxNetworkPage {
    $hw = $script:Hw
    $rows = @()
    $n = $hw.Network
    $kv = { param($k, $v, $h) $x = New-Object VeloxPC.KeyValueRow; $x.Key = $k; $x.Value = $v; $x.Hint = $h; $x }
    if ($n) {
        $rows += (& $kv (T 'net.k.type') $(if ($n.IsWifi) { 'Wi-Fi' } else { 'Ethernet' }) $n.Description)
        $rows += (& $kv (T 'net.k.speed') $n.LinkSpeed '')
        $rows += (& $kv (T 'net.k.ip') $n.IPv4 '')
        $rows += (& $kv (T 'net.k.gw') ([string]$n.Gateway) '')
        $rows += (& $kv 'DNS' $n.Dns '')
    } else { $rows += (& $kv (T 'net.k.type') (T 'hw.offline') '') }
    $tr = [VeloxPC.Native]::TimerResolution()
    $rows += (& $kv (T 'net.k.timer') ('{0:N2} ms' -f $tr[0]) (T 'net.k.timer.h'))
    Set-VxItems $ui.NetInfo $rows
    $adv = @()
    foreach ($a in (Get-VxNetworkAdvice $hw)) { $f = New-Object VeloxPC.Finding; $f.Severity = $a.sev; $f.Title = $a.text; $adv += $f }
    Set-VxItems $ui.NetAdvice $adv
    $targets = Get-VxPingTargets $hw
    $prow = @(); $k = 0
    foreach ($t in $targets) { $p = New-Object VeloxPC.PingRow; $p.Label = L $t.Label; $p.Host = $t.Host; $p.Color = $script:PingColors[$k % 5]; $prow += $p; $k++ }
    $script:PingRowsData = $prow
    Set-VxItems $ui.PingRows $prow
}

function Start-VxPingTest {
    if (-not $script:PingRowsData) { Update-VxNetworkPage }
    $hosts = [string[]]@($script:PingRowsData | ForEach-Object { $_.Host })
    $script:Pinger = New-Object VeloxPC.PingRunner -ArgumentList (, $hosts)
    $script:Pinger.Start(40, 250)
    $ui.BtnPingTest.IsEnabled = $false
    $ui.PingCanvas.Children.Clear()
    $script:PingLines = @()
    for ($i = 0; $i -lt $hosts.Count; $i++) {
        $pl = New-Object System.Windows.Shapes.Polyline
        $pl.Stroke = New-VxBrush $script:PingColors[$i % 5]
        $pl.StrokeThickness = 1.8; $pl.StrokeLineJoin = 'Round'
        [void]$ui.PingCanvas.Children.Add($pl)
        $script:PingLines += $pl
    }
}

function Update-VxPingLive {
    $pr = $script:Pinger
    if (-not $pr) { return }
    $w = [math]::Max(50, $ui.PingCanvas.ActualWidth); $h = [math]::Max(50, $ui.PingCanvas.ActualHeight)
    $all = @(); $snaps = @()
    for ($i = 0; $i -lt $script:PingRowsData.Count; $i++) { $s = $pr.Snapshot($i); $snaps += , $s; $all += @($s | Where-Object { $_ -ge 0 }) }
    $max = 20; if ($all.Count -gt 0) { $max = [math]::Max(20, ($all | Measure-Object -Maximum).Maximum * 1.15) }
    for ($i = 0; $i -lt $script:PingRowsData.Count; $i++) {
        $s = $snaps[$i]
        $pts = New-Object System.Windows.Media.PointCollection
        for ($k = 0; $k -lt $s.Count; $k++) {
            $v = if ($s[$k] -lt 0) { $max } else { $s[$k] }
            $pts.Add((New-Object System.Windows.Point(($k * $w / 39), ($h - ($v / $max) * ($h - 4)))))
        }
        $script:PingLines[$i].Points = $pts
        $st = [VeloxPC.PingRunner]::Stats($s)
        $row = $script:PingRowsData[$i]
        if ($st[5] -gt 0) {
            $row.Avg = '{0:N0} ms' -f $st[0]; $row.Jitter = '{0:N1} ms' -f $st[3]; $row.Loss = '{0:N0}%' -f $st[4]
            $q = Get-VxPingQuality $st[0] $st[3] $st[4] ($i -eq 0 -and $script:Hw.Network -and $row.Host -eq [string]$script:Hw.Network.Gateway)
            $row.Quality = $q[0]; $row.QualityKind = $q[1]
        }
    }
    if (-not $pr.Running) { $script:Pinger = $null; $ui.BtnPingTest.IsEnabled = $true; Show-VxToast (T 'net.ping.done') 'ok' }
}

function Start-VxLoadTest {
    $script:LoadT = New-Object VeloxPC.LoadTest
    $script:LoadT.Start(3, 10, 4)
    $script:LoadStart = Get-Date
    $ui.BtnLoadTest.IsEnabled = $false
    $ui.GradeText.Text = '...'
    $ui.LoadVerdict.Text = T 'net.load.phase.idle'
}

function Update-VxLoadLive {
    $lt = $script:LoadT
    if (-not $lt) { return }
    $idle = [VeloxPC.LoadTest]::Median($lt.IdleRtts)
    $loaded = [VeloxPC.LoadTest]::Median($lt.LoadedRtts)
    if ($idle -ge 0) { $ui.LoadIdle.Text = ' {0:N0} ms' -f $idle }
    if ($loaded -ge 0) { $ui.LoadLoaded.Text = ' {0:N0} ms' -f $loaded }
    if ($lt.Phase -eq 'load') {
        $ui.LoadVerdict.Text = T 'net.load.phase.load'
        $secs = ((Get-Date) - $script:LoadStart).TotalSeconds - 3
        if ($secs -gt 0.5) { $ui.LoadDown.Text = ' {0:N0} Mbps' -f $lt.CurrentMbps($secs) }
    }
    if (-not $lt.Running) {
        $script:LoadT = $null
        $ui.BtnLoadTest.IsEnabled = $true
        $ui.LoadDown.Text = ' {0:N0} Mbps' -f $lt.Mbps
        $g = Get-VxBloatGrade $idle $loaded
        $ui.GradeText.Text = $g[0]
        $color = switch ($g[1]) { 'ok' { '#9CC69B' } 'warn' { '#D9A55C' } 'crit' { '#D0606A' } default { '#A89F92' } }
        $ui.GradeText.Foreground = New-VxBrush $color
        $ui.GradeBox.BorderBrush = New-VxBrush $color
        if ($lt.Error -and $lt.Bytes -eq 0) { $ui.LoadVerdict.Text = (T 'net.load.err') + ' ' + $lt.Error }
        else { $ui.LoadVerdict.Text = T "net.load.v.$($g[1])" @([int]([math]::Max(0, $loaded - $idle))) }
    }
}

function Start-VxDnsBench {
    $ui.BtnDnsTest.IsEnabled = $false
    $ui.BtnDnsTest.Content = T 'net.dns.testing'
    Start-VxJob -Name 'dns' -Arguments @($script:Hw) -Script { param($Sync, $Hw) return @{ rows = @(Invoke-VxDnsBenchmark $Hw) } } -OnDone {
        param($r)
        $ui.BtnDnsTest.IsEnabled = $true
        $ui.BtnDnsTest.Content = T 'net.dns.run'
        $rows = @(); $best = $null
        foreach ($x in @($r.rows)) {
            $d = New-Object VeloxPC.DnsRow
            $d.Provider = $x.Name + $(if ($x.Current -and $x.Name -ne (L @{ it = 'Attuale'; en = 'Current' })) { ' (' + (T 'net.dns.current') + ')' } else { '' })
            $d.Primary = $x.P; $d.Secondary = $x.S
            $d.Value = [double]$x.Ms
            $d.Ms = if ($x.Ms -ge 0) { '{0:N1} ms' -f $x.Ms } else { T 'net.dns.fail' }
            if ($x.Ms -ge 0 -and (-not $best -or $x.Ms -lt $best.Value)) { $best = $d }
            $rows += $d
        }
        if ($best) { $best.IsBest = $true }
        $script:DnsBest = $best
        $ui.BtnDnsApply.IsEnabled = [bool]($best -and $best.Secondary -ne '' -and $script:Hw.Network)
        Set-VxItems $ui.DnsRows $rows
    }
}

# =====================================================================
#  AFTER EFFECTS + SESSIONS (Gioco / Render)
# =====================================================================
function Update-VxAePage {
    Start-VxJob -Name 'ae' -Arguments @($script:Hw) -Script {
        param($Sync, $Hw)
        $r = Get-VxAeReport $Hw
        $r.MediaSize = Get-VxMediaCacheSize
        return $r
    } -OnDone {
        param($r)
        $script:AeReport = $r
        $rows = @()
        foreach ($x in $r.Rows) { $k = New-Object VeloxPC.KeyValueRow; $k.Key = $x.K; $k.Value = $x.V; $k.Hint = $x.H; $rows += $k }
        Set-VxItems $ui.AeRows $rows
        $checks = @()
        foreach ($c in $r.Checks) { $f = New-Object VeloxPC.Finding; $f.Severity = $c.sev; $f.Title = $c.t; $checks += $f }
        Set-VxItems $ui.AeChecks $checks
        $ui.BtnAeMediaClean.Content = (T 'ae.mediaclean') + ' (' + (Format-VxBytes $r.MediaSize) + ')'
        $ui.BtnAeFolders.IsEnabled = [bool]$r.Best
    }
}

function Update-VxSessionUi {
    $s = $script:Session
    if ($s) {
        $closed = if (@($s.closed).Count -gt 0) { @($s.closed) -join ', ' } else { '-' }
        $txt = T "session.on.$($s.kind)" @($closed)
        $ui.SessionStatus.Text = $txt
        $ui.BtnSessionStop.Visibility = 'Visible'
        $ui.BtnSessionGame.IsEnabled = $false
        $ui.BtnRenderMode.Content = if ($s.kind -eq 'render') { T 'session.stop' } else { T 'ae.render.start' }
        $ui.RenderModeStatus.Text = if ($s.kind -eq 'render') { $txt } else { '' }
    } else {
        $ui.SessionStatus.Text = ''
        $ui.BtnSessionStop.Visibility = 'Collapsed'
        $ui.BtnSessionGame.IsEnabled = $true
        $ui.BtnRenderMode.Content = T 'ae.render.start'
        $ui.RenderModeStatus.Text = ''
    }
}

function Start-VxSessionUi {
    param([string]$Kind)
    if (Test-VxPreviewStop "session $Kind") { return }
    $script:SessionKind = $Kind
    Start-VxJob -Name 'sessionplan' -Arguments @($script:Hw) -Script { param($Sync, $Hw) return @{ helpers = @(Get-VxSessionHelpersRunning $Hw) } } -OnDone {
        param($r)
        $h = @($r.helpers)
        $script:SessionClose = [string[]]@($h | ForEach-Object { $_.name })
        $list = if ($h.Count -gt 0) { ($h | ForEach-Object { '• ' + $_.name + ' — ' + (Format-VxBytes $_.mem) }) -join "`n" } else { T 'session.nothing' }
        Show-VxDialog -Title (T "session.q.$($script:SessionKind)") -Text ((T 'session.q.text') + "`n`n" + $list) -YesText (T 'session.start') -NoText (T 'common.cancel') -OnYes {
            Start-VxJob -Name 'session' -Arguments @($script:SessionKind, $script:Hw, $script:SessionClose) -Script { param($Sync, $K, $Hw, $C) return (Start-VxSession -Kind $K -Hw $Hw -Close $C) } -OnDone {
                param($s)
                $script:Session = ConvertTo-VxHashtable $s
                $script:SessionSawApp = $false
                try { [VeloxPC.Native]::KeepAwake($true) } catch { }   # per thread: set from the UI thread
                Update-VxSessionUi
                Show-VxToast (T 'session.started') 'ok'
            }
        }
    }
}

function Stop-VxSessionUi {
    param([switch]$Quiet)
    try { [VeloxPC.Native]::KeepAwake($false) } catch { }
    $script:Session = $null
    Update-VxSessionUi
    Start-VxJob -Name 'sessionstop' -Script { param($Sync) return @{ ok = (Stop-VxSession) } } -OnDone { param($r) if (-not $script:QuietStop) { Show-VxToast (T 'session.ended') 'info' }; $script:QuietStop = $false }
    $script:QuietStop = [bool]$Quiet
}

# =====================================================================
#  CLEANUP (+ scheduled cleaning)
# =====================================================================
function Start-VxCleanScan {
    $ui.BtnCleanScan.IsEnabled = $false
    $ui.CleanTotal.Text = T 'clean.scanning'
    Start-VxJob -Name 'cleanscan' -Script { param($Sync) return @{ sizes = (Get-VxCleanSizes); task = (Get-VxCleanTaskInfo); last = (ConvertTo-VxHashtable (Read-VxJson 'cleanlast.json' $null)) } } -OnDone {
        param($r)
        $ui.BtnCleanScan.IsEnabled = $true
        $items = @()
        foreach ($c in $script:VxCleanItems) {
            $o = New-Object VeloxPC.OptionItem
            $o.Id = $c.Id; $o.Kind = 'clean'
            $o.Title = L $c.Title; $o.Description = L $c.Desc
            $o.Risk = $c.Risk; $o.RiskLabel = Get-VxRiskLabel $c.Risk
            $o.Size = [int64]$r.sizes[$c.Id]
            $o.Extra = Format-VxBytes $o.Size
            $def = Get-VxCleanDefault $c $script:Health
            if ($c.Id -eq 'dumps' -and $c.Default -and -not $def) { $o.Badge = T 'clean.dumps.kept'; $o.BadgeKind = 'protect' }
            if ($c.Scheduled) { if (-not $o.Badge) { $o.Badge = T 'clean.sched.badge'; $o.BadgeKind = 'info' } }
            $o.IsChecked = $def -and $o.Size -gt 0
            $o.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'IsChecked') { Update-VxCleanTotal } })
            $items += $o
        }
        $script:CleanItems = $items
        Set-VxItems $ui.CleanList $items
        Update-VxCleanTotal
        Update-VxSchedUi $r.task $r.last
    }
}

function Update-VxCleanTotal {
    $sum = [int64]0
    foreach ($i in $script:CleanItems) { if ($i.IsChecked) { $sum += $i.Size } }
    $ui.CleanTotal.Text = Format-VxBytes $sum
    $ui.BtnCleanRun.IsEnabled = ($sum -gt 0)
}

function Update-VxSchedUi {
    param($Task, $Last)
    $script:SchedSuppress = $true
    $mode = [string]$script:Settings.cleanSchedule
    if (-not $Task.exists) { $mode = '' }
    $ui.SchedOff.IsChecked = ($mode -eq '')
    $ui.SchedWeekly.IsChecked = ($mode -eq 'weekly')
    $ui.SchedMonthly.IsChecked = ($mode -eq 'monthly')
    $script:SchedSuppress = $false
    $t = if ($Task.exists) { T 'sched.next' @($Task.next) } else { T 'sched.none' }
    if ($Last -and $Last.time) { $t += "`n" + (T 'sched.last' @($Last.time, (Format-VxBytes ([double]$Last.freed)))) }
    $ui.SchedStatus.Text = $t
}

function Set-VxSchedule {
    param([string]$Mode)
    Start-VxJob -Name 'schedule' -Arguments @($Mode, (Join-Path $AppDir 'VeloxPC.ps1')) -Script {
        param($Sync, $M, $Script)
        if ($M) { [void](Register-VxCleanTask -Frequency $M -ScriptPath $Script) } else { Unregister-VxCleanTask }
        return @{ task = (Get-VxCleanTaskInfo) }
    } -OnDone {
        param($r)
        $script:Settings.cleanSchedule = $(if ($r.task.exists) { $script:SchedWanted } else { '' })
        Save-VxSettings $script:Settings
        Update-VxSchedUi $r.task $null
        Show-VxToast $(if ($r.task.exists) { T 'sched.on' } else { T 'sched.off.toast' }) 'ok'
        if ($script:Loaded.Restore) { Update-VxRestorePage }
    }
}

# =====================================================================
#  RESTORE
# =====================================================================
function Update-VxRestorePage {
    $b = Get-VxBackup
    $rows = @()
    foreach ($e in @($b.entries.Values | Sort-Object { $_.time } -Descending)) {
        $r = New-Object VeloxPC.HistRow
        $r.Id = $e.id; $r.Time = $e.time; $r.Title = $e.title
        $r.Detail = T 'restore.items' @(@($e.items).Count)
        $r.CanUndo = $true
        $rows += $r
    }
    Set-VxItems $ui.ActiveList $rows
    $ui.ActiveEmpty.Visibility = if ($rows.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    $ui.BtnUndoAll.IsEnabled = ($rows.Count -gt 0)
    $hist = @()
    $histRaw = ConvertTo-VxHashtable (Read-VxJson 'history.json' $null)
    foreach ($h in @($histRaw | Where-Object { $_ } | Select-Object -First 60)) {
        $r = New-Object VeloxPC.HistRow
        $r.Time = $h.time; $r.Title = $h.title
        $r.Detail = if ($h.action -eq 'undo') { T 'restore.undone' } else { T 'restore.applied' }
        $r.CanUndo = $false
        $hist += $r
    }
    Set-VxItems $ui.HistoryList $hist
    Update-VxNotices
}

function Invoke-VxUndo {
    param([string[]]$Ids)
    if (Test-VxPreviewStop 'undo') { return }
    Show-VxBusy (T 'busy.restoring') (T 'busy.wait')
    Start-VxJob -Name 'undo' -Arguments @(, [string[]]$Ids) -Script {
        param($Sync, $Ids)
        $n = 0; $i = 0
        foreach ($id in $Ids) { $i++; $Sync.Pct = [int](100 * $i / [math]::Max(1, $Ids.Count)); $Sync.Step = $id; if (Undo-VxEntry $id) { $n++ } }
        if ($script:VxNicRestart) { try { Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Restart-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue } catch { } }
        return @{ n = $n }
    } -OnDone {
        param($r)
        Hide-VxBusy
        Show-VxToast (T 'restore.done' @($r.n)) 'ok'
        Update-VxRestorePage
        Update-VxStates
        if ($script:Loaded.Processes) { Update-VxStartupList }
    }
}

function New-VxRestorePointUi {
    param([switch]$AllowEnable)
    if (Test-VxPreviewStop 'restore point') { return }
    Show-VxBusy (T 'restore.point.creating') (T 'busy.wait')
    Start-VxJob -Name 'rp' -Arguments @([bool]$AllowEnable) -Script { param($Sync, $Allow) if ($Allow) { return @{ ok = (New-VxRestorePoint 'Piki Optimizer' -AllowEnable) } }; return @{ ok = (New-VxRestorePoint 'Piki Optimizer') } } -OnDone {
        param($r)
        Hide-VxBusy
        if ($r.ok -eq 'off') {
            Show-VxDialog -Title (T 'restore.point.off.q') -Text (T 'restore.point.off.text') -YesText (T 'restore.point.off.yes') -NoText (T 'common.cancel') -OnYes { New-VxRestorePointUi -AllowEnable }
        } elseif ($r.ok -eq 'recent') { Show-VxToast (T 'restore.point.recent') 'info' }
        elseif ($r.ok) { Show-VxToast (T 'restore.point.ok') 'ok' }
        else { Show-VxToast (T 'restore.point.fail') 'warn' }
    }
}

# =====================================================================
#  UPDATES (checked at start, then once a day; the banner stays on screen until you update)
# =====================================================================
function Start-VxUpdateCheck {
    param([switch]$Manual)
    $script:UpdManual = [bool]$Manual
    if ($Manual) { $ui.UpdateStatus.Text = T 'update.checking' }
    Start-VxJob -Name 'updcheck' -Script { param($Sync) return (Get-VxRemoteManifest) } -OnDone {
        param($r)
        $script:Remote = $r
        $script:Settings.lastUpdateCheck = (Get-Date -Format 'o'); Save-VxSettings $script:Settings
        $rv = [string]$r.manifest.version
        if (Test-VxNewer $rv $script:Version) {
            $notes = ''
            try { $notes = L (ConvertTo-VxHashtable $r.manifest.notes) } catch { }
            $ui.UpdateBannerText.Text = T 'update.available' @($rv, $notes)
            $ui.UpdateBanner.Visibility = 'Visible'
            $ui.UpdateStatus.Text = T 'update.available' @($rv, '')
            Show-VxUpdateNotice $rv $notes
        } elseif ($script:UpdManual) { $ui.UpdateStatus.Text = T 'update.latest' @($script:Version) }
    } -OnError {
        param($e)
        if ($script:UpdManual) { $ui.UpdateStatus.Text = T 'update.offline' }
    }
}

function Show-VxUpdateNotice {
    param([string]$Ver, [string]$Notes)
    if ($script:NotifiedVer -eq $Ver) { return }
    $script:NotifiedVer = $Ver
    if ($script:Window.IsVisible) { Show-VxToast (T 'update.notify.title') 'info'; return }
    try {
        if (-not $script:TrayIcon) { Update-VxTrayIcon }
        if (-not $script:TrayIcon) { return }
        $script:TrayIcon.Visible = $true
        $text = T 'update.notify.text' @($Ver)
        if ($text.Length -gt 250) { $text = $text.Substring(0, 247) + '...' }
        $script:BalloonKind = 'update'
        $script:TrayIcon.ShowBalloonTip(10000, (T 'update.notify.title'), $text, 'Info')
    } catch { Write-VxLog "update notice: $($_.Exception.Message)" 'WARN' }
}

function Start-VxUpdate {
    Show-VxBusy (T 'update.installing') (T 'update.checking')
    Start-VxJob -Name 'update' -Arguments @($script:Version) -Script {
        param($Sync, $Current)
        $r = Get-VxRemoteManifest
        $v = [string]$r.manifest.version
        if (-not (Test-VxNewer $v $Current)) { return @{ n = 0; v = $v; latest = $true } }
        return @{ n = (Invoke-VxUpdate $r $Sync); v = $v; latest = $false }
    } -OnDone {
        param($r)
        Hide-VxBusy
        if ($r.latest) { $ui.UpdateStatus.Text = T 'update.latest' @($script:Version); Show-VxToast (T 'update.latest' @($script:Version)) 'info'; return }
        $ui.UpdateBanner.Visibility = 'Collapsed'
        Show-VxDialog -Title (T 'update.done') -Text (T 'update.done.text' @($r.n)) -YesText (T 'update.restart') -OnYes { Restart-VxApp }
    } -OnError {
        param($e)
        Hide-VxBusy
        $ui.UpdateStatus.Text = T 'update.offline'
        Show-VxToast ((T 'update.offline') + ' (' + $e.Message + ')') 'warn'
    }
}

function Restart-VxApp {
    $script:ReallyExit = $true
    $launcher = Join-Path $Root 'Avvia Piki Optimizer.cmd'
    if (Test-Path -LiteralPath $launcher) { Start-Process -FilePath $launcher -WindowStyle Hidden }
    else { Start-Process -FilePath $psExe -WindowStyle Hidden -ArgumentList $selfArgs }
    $script:Window.Close()
}

# =====================================================================
#  LOOK: glass only on strong PCs, logo / background, tray, autostart
# =====================================================================
function Test-VxStrongPc {
    $hw = $script:Hw
    if (-not $hw) { return $false }
    return ([int]$script:RenderTier -ge 2 -and [int]$hw.RAM.GB -ge 16 -and -not $hw.OnBattery -and -not (Test-VxWeakPc $hw))
}

function Enable-VxGlass {
    if (-not $script:Settings.glass -or -not (Test-VxStrongPc) -or $script:GlassOn) { return }
    try {
        if ([Environment]::OSVersion.Version.Build -lt 22621) { return }
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($script:Window)).Handle
        $src = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
        $src.CompositionTarget.BackgroundColor = [System.Windows.Media.Colors]::Transparent
        $hr = [VeloxPC.Native]::EnableBackdrop($hwnd, 3)
        if ($hr -ne 0) { return }
        $script:Window.Background = [System.Windows.Media.Brushes]::Transparent
        $ui.Root.Background = New-VxBrush '#CC000000'
        $script:GlassOn = $true
        Write-VxLog 'glass: acrylic on (strong PC)'
    } catch { Write-VxLog "glass: $($_.Exception.Message)" 'WARN' }
}

function Ensure-VxDesktopIcon {
    if ($script:Settings.shortcutDone) { return }
    # a test or portable copy must never replace the Desktop icon of the installed app
    if (-not $script:IsInstalledCopy) { return }
    try { New-VxShortcut; $script:Settings.shortcutDone = $true; Save-VxSettings $script:Settings } catch { Write-VxLog "shortcut: $($_.Exception.Message)" 'WARN' }
}
function New-VxShortcut {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Piki Optimizer.lnk'))
    $lnk.TargetPath = Join-Path $Root 'Avvia Piki Optimizer.cmd'
    $lnk.WorkingDirectory = $Root
    $lnk.WindowStyle = 7
    $lnk.IconLocation = Get-VxIconPath
    $lnk.Description = 'Piki Optimizer'
    $lnk.Save()
}

$script:CustomDir = Join-Path $script:VxData 'custom'
function Get-VxBitmap {
    param([string]$Path, [int]$Width = 0)
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile
    if ($Width -gt 0) { $bi.DecodePixelWidth = $Width }
    $bi.UriSource = New-Object System.Uri $Path
    $bi.EndInit()
    $bi.Freeze()
    return $bi
}
function Get-VxCustomPath { param([string]$Name) $v = [string]$script:Settings[$Name]; if ($v) { $p = Join-Path $script:CustomDir $v; if (Test-Path -LiteralPath $p) { return $p } }; return $null }
function Get-VxIconPath {
    $ico = Join-Path $script:CustomDir 'logo.ico'
    if ((Get-VxCustomPath 'logo') -and (Test-Path -LiteralPath $ico)) { return $ico }
    return (Join-Path $AppDir 'assets\veloxpc.ico')
}
function New-VxSquare {
    param([string]$Path, [int]$Size)
    $src = Get-VxBitmap $Path 0
    $side = [math]::Min($src.PixelWidth, $src.PixelHeight)
    $rect = New-Object System.Windows.Int32Rect([int](($src.PixelWidth - $side) / 2), [int](($src.PixelHeight - $side) / 2), $side, $side)
    $crop = New-Object System.Windows.Media.Imaging.CroppedBitmap($src, $rect)
    $scale = New-Object System.Windows.Media.ScaleTransform(($Size / $side), ($Size / $side))
    return (New-Object System.Windows.Media.Imaging.TransformedBitmap($crop, $scale))
}
function Save-VxIco {
    param([string]$Path, [string]$Dest)
    $bmp = New-VxSquare $Path 256
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $ms = New-Object System.IO.MemoryStream
    $enc.Save($ms)
    $png = $ms.ToArray()
    $fs = [System.IO.File]::Create($Dest)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
    $bw.Write($png)
    $bw.Close(); $fs.Close()
}

function Update-VxLook {
    $logo = Get-VxCustomPath 'logo'
    if ($logo) {
        try {
            $b = New-Object System.Windows.Media.ImageBrush (New-VxSquare $logo 128)
            $b.Stretch = 'UniformToFill'
            $ui.LogoCustom.Background = $b; $ui.LogoCustom.Visibility = 'Visible'; $ui.LogoDefault.Visibility = 'Collapsed'
            $ui.SplashLogoCustom.Background = $b; $ui.SplashLogoCustom.Visibility = 'Visible'
            $ico = Join-Path $script:CustomDir 'logo.ico'
            if (-not (Test-Path -LiteralPath $ico)) { Save-VxIco $logo $ico }
        } catch { Write-VxLog "logo: $($_.Exception.Message)" 'WARN' }
    } else { $ui.LogoCustom.Visibility = 'Collapsed'; $ui.LogoDefault.Visibility = 'Visible'; $ui.SplashLogoCustom.Visibility = 'Collapsed' }
    try { $script:Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri (Get-VxIconPath))) } catch { }
    $bg = Get-VxCustomPath 'bg'
    if ($bg) {
        try {
            # decoded at window size, no blur (a blur at runtime costs CPU/GPU on every frame)
            $ui.BgImage.Source = Get-VxBitmap $bg 1600
            $lv = [int]$script:Settings.bgLevel; if ($lv -lt 1) { $lv = 2 }
            $ui.BgImage.Opacity = @(0, 0.14, 0.24, 0.38)[$lv]
            $ui.BgImage.Visibility = 'Visible'
            $ui["BgLevel$lv"].IsChecked = $true
        } catch { Write-VxLog "bg: $($_.Exception.Message)" 'WARN' }
    } else { $ui.BgImage.Visibility = 'Collapsed'; $ui.BgImage.Source = $null }
    if ($script:Settings.tray -or $script:TrayIcon) { Update-VxTrayIcon }
}

function Select-VxImage {
    param([string]$Kind)
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|*.*|*.*'
    if (-not $dlg.ShowDialog($script:Window)) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:CustomDir)) { New-Item -ItemType Directory -Path $script:CustomDir -Force | Out-Null }
        $ext = [IO.Path]::GetExtension($dlg.FileName).ToLower()
        $name = "$Kind-$([DateTime]::Now.ToString('yyyyMMddHHmmss'))$ext"
        Copy-Item -LiteralPath $dlg.FileName -Destination (Join-Path $script:CustomDir $name) -Force
        $old = Get-VxCustomPath $Kind
        $script:Settings[$Kind] = $name
        Save-VxSettings $script:Settings
        if ($Kind -eq 'logo') { Remove-Item -LiteralPath (Join-Path $script:CustomDir 'logo.ico') -Force -ErrorAction SilentlyContinue }
        Update-VxLook
        if ($old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
        Show-VxToast (T "set.$Kind.ok") 'ok'
    } catch { Show-VxToast $_.Exception.Message 'crit' }
}

$script:TrayIcon = $null
function Update-VxTrayIcon {
    try {
        if (-not $script:TrayIcon) {
            $ni = New-Object System.Windows.Forms.NotifyIcon
            $ni.Text = 'Piki Optimizer'
            $menu = New-Object System.Windows.Forms.ContextMenuStrip
            $miOpen = $menu.Items.Add((T 'tray.open')); $miOpen.add_Click({ Show-VxFromTray })
            $miMeasure = $menu.Items.Add((T 'nav.measure')); $miMeasure.add_Click({ Show-VxFromTray; Show-VxPage 'Measure' })
            [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
            $miExit = $menu.Items.Add((T 'tray.exit')); $miExit.add_Click({ $script:ReallyExit = $true; $script:Window.Close() })
            $ni.ContextMenuStrip = $menu
            $ni.add_MouseDoubleClick({ Show-VxFromTray })
            $ni.add_BalloonTipClicked({
                if ($script:BalloonKind -eq 'update') { $script:BalloonKind = $null; Show-VxFromTray; Show-VxPage 'Settings'; Start-VxUpdate }
                else { Show-VxFromTray }
            })
            $script:TrayIcon = $ni
            $img = Get-VxCustomPath 'logo'
            if (-not $img) { $img = Join-Path $AppDir 'assets\logo.png' }
            $src = [System.Drawing.Image]::FromFile($img)
            $side = [math]::Min($src.Width, $src.Height)
            $bmp = New-Object System.Drawing.Bitmap(32, 32)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, 32, 32)), (New-Object System.Drawing.Rectangle([int](($src.Width - $side) / 2), [int](($src.Height - $side) / 2), $side, $side)), [System.Drawing.GraphicsUnit]::Pixel)
            $g.Dispose(); $src.Dispose()
            $script:TrayIcon.Icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
        }
        $script:TrayIcon.Visible = [bool]$script:Settings.tray
    } catch { Write-VxLog "tray: $($_.Exception.Message)" 'WARN' }
}

function Show-VxFromTray {
    $script:Window.ShowInTaskbar = $true
    $script:Window.Show()
    if ($script:Window.WindowState -eq 'Minimized') { $script:Window.WindowState = 'Normal' }
    $script:Window.Activate() | Out-Null
    $script:InTray = $false
    $script:LiveTimer.Interval = [TimeSpan]::FromSeconds(1)
    if ($script:TrayIcon -and -not $script:Settings.tray) { $script:TrayIcon.Visible = $false }
}

# light resident mode: in the tray only the icon and a slow timer stay alive, memory is given back to Windows
function Send-VxToTray {
    try {
        Update-VxTrayIcon
        if ($script:TrayIcon) { $script:TrayIcon.Visible = $true }
        $script:Window.ShowInTaskbar = $false
        $script:Window.Hide()
        $script:InTray = $true
        $script:LiveTimer.Interval = [TimeSpan]::FromSeconds(30)
        if ($script:TrayIcon -and -not $script:TrayHintShown) {
            $script:TrayHintShown = $true; $script:BalloonKind = 'hint'
            $script:TrayIcon.ShowBalloonTip(3000, 'Piki Optimizer', (T 'tray.still'), 'Info')
        }
        [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
        try { [VeloxPC.Extra]::TrimWorkingSet() } catch { }
        Write-VxLog 'sent to background (light resident mode)'
    } catch { Write-VxLog "tray: $($_.Exception.Message)" 'WARN' }
}

function Set-VxAutoStart {
    param([bool]$On)
    if (Test-VxPreviewStop 'autostart') { $ui.AutoStartSwitch.IsChecked = [bool]$script:Settings.autostart; return }
    try {
        if ($On) {
            $act = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`" -Tray"
            $trg = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
            $prn = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
            $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
            Register-ScheduledTask -TaskName 'PikiOptimizer' -Action $act -Trigger $trg -Principal $prn -Settings $set -Force -ErrorAction Stop | Out-Null
            if (-not $script:Settings.tray) { $script:Settings.tray = $true; $ui.TraySwitch.IsChecked = $true; Update-VxTrayIcon }
            Show-VxToast (T 'set.autostart.on') 'ok'
        } else {
            Unregister-ScheduledTask -TaskName 'PikiOptimizer' -Confirm:$false -ErrorAction SilentlyContinue
            Show-VxToast (T 'set.autostart.off') 'info'
        }
        $script:Settings.autostart = $On
        Save-VxSettings $script:Settings
    } catch { Show-VxToast $_.Exception.Message 'crit'; $ui.AutoStartSwitch.IsChecked = -not $On }
}

# =====================================================================
#  NAVIGATION
# =====================================================================
$script:PageNames = @('Home', 'Measure', 'Optimize', 'Processes', 'Cleanup', 'Network', 'Ae', 'Health', 'Restore', 'Settings')
function Move-VxNavIndicator {
    param([string]$Name, [switch]$Instant)
    try {
        $nav = $ui["Nav$Name"]; $ind = $ui.NavIndicator
        if (-not $nav -or -not $ind -or $nav.ActualHeight -le 0) { return }
        $y = $nav.TranslatePoint((New-Object System.Windows.Point(0, 0)), $ui.SideGrid).Y
        $tt = Get-VxTransform $ind
        if ($Instant -or $ind.Opacity -lt 0.5 -or (Test-VxCalm)) {
            $tt.BeginAnimation($script:TyP, $null); $tt.Y = $y
            $ind.Opacity = 1
            return
        }
        $tt.BeginAnimation($script:TyP, (New-VxAnim $y 300))
    } catch { Write-VxLog "nav indicator: $($_.Exception.Message)" 'WARN' }
}

# blocks of a page come in one after another: 10 px rise + fade, 40 ms apart, first 6 blocks only
function Start-VxStagger {
    param($Page)
    if (Test-VxCalm) { return }
    try {
        $panel = $Page
        if ($Page -is [System.Windows.Controls.ScrollViewer]) { $panel = $Page.Content }
        if (-not ($panel -is [System.Windows.Controls.Panel])) { return }
        $i = 0
        foreach ($c in $panel.Children) {
            if ($i -ge 6) { break }
            if (-not ($c -is [System.Windows.FrameworkElement]) -or $c.Visibility -ne 'Visible') { continue }
            $delay = [TimeSpan]::FromMilliseconds(40 * $i)
            $op = New-VxAnim 1 300 0; $op.BeginTime = $delay
            $el = $c
            $op.add_Completed({ $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null) }.GetNewClosure())
            if ($i -gt 0) { $c.Opacity = 1; $c.BeginAnimation($script:OpacityP, $op) }
            if ($c.RenderTransform -is [System.Windows.Media.TranslateTransform] -or $c.RenderTransform -eq [System.Windows.Media.Transform]::Identity) {
                $mv = New-VxAnim 0 300 10; $mv.BeginTime = $delay
                $mv.FillBehavior = 'Stop'
                $tt = Get-VxTransform $c
                $tt.Y = 0
                $tt.BeginAnimation($script:TyP, $mv)
            }
            $i++
        }
    } catch { Write-VxLog "stagger: $($_.Exception.Message)" 'WARN' }
}

function Show-VxPage {
    param([string]$Name)
    if (-not $Name -or -not $ui["Page$Name"]) { return }
    if (-not $script:Visited) { $script:Visited = @{} }
    foreach ($p in $script:PageNames) {
        if ($p -eq $Name) { $ui["Page$p"].Visibility = 'Visible' }
        elseif ($script:Visited[$p]) { $ui["Page$p"].Visibility = 'Hidden' }   # keeps its layout: switching back is instant
        else { $ui["Page$p"].Visibility = 'Collapsed' }
    }
    $script:Visited[$Name] = $true
    $nav = $ui["Nav$Name"]
    if ($nav -and -not $nav.IsChecked) { $script:NavSuppress = $true; $nav.IsChecked = $true; $script:NavSuppress = $false }
    $page = $ui["Page$Name"]
    if (Test-VxCalm) { $page.BeginAnimation($script:OpacityP, (New-VxAnim 1 120 0)) }
    else { $page.BeginAnimation($script:OpacityP, (New-VxAnim 1 300 0)); Start-VxStagger $page }
    Move-VxNavIndicator $Name
    $script:CurrentPage = $Name
    if (-not $script:Hw) { return }
    $script:PageToLoad = $Name
    [void]$script:Window.Dispatcher.BeginInvoke([Action] { Invoke-VxPageLoad $script:PageToLoad }, [System.Windows.Threading.DispatcherPriority]::Loaded)
}

function Invoke-VxPageLoad {
    param([string]$Name)
    if ($Name -ne $script:CurrentPage) { return }
    switch ($Name) {
        'Measure' { $script:Loaded.Measure = $true; Update-VxMeasurePage }
        'Processes' { if (-not $script:Loaded.Processes) { $script:Loaded.Processes = $true; Update-VxStartupList; Update-VxProcList }; Update-VxProcStats }
        'Network' { if (-not $script:Loaded.Network) { $script:Loaded.Network = $true; Update-VxNetworkPage } }
        'Ae' { if (-not $script:Loaded.Ae) { $script:Loaded.Ae = $true; Update-VxAePage } }
        'Cleanup' { if (-not $script:Loaded.Cleanup) { $script:Loaded.Cleanup = $true; Start-VxCleanScan } }
        'Restore' { $script:Loaded.Restore = $true; Update-VxRestorePage }
        'Health' { if (-not $script:Health) { Start-VxHealthCheck } }
    }
}

function Hide-VxSplash {
    $a = New-VxAnim 0 $(if (Test-VxCalm) { 120 } else { 300 }) 1
    $a.add_Completed({ $ui.SplashOverlay.Visibility = 'Collapsed' })
    $ui.SplashOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
    $script:SplashActive = $false
}

# =====================================================================
#  EVENT WIRING
# =====================================================================
$ui.BtnMin.add_Click({ $script:Window.WindowState = 'Minimized' })
$ui.BtnTray.add_Click({ Send-VxToTray })
$ui.BtnMax.add_Click({ if ($script:Window.WindowState -eq 'Maximized') { $script:Window.WindowState = 'Normal' } else { $script:Window.WindowState = 'Maximized' } })
$ui.BtnClose.add_Click({ $script:Window.Close() })
$ui.SplashClose.add_Click({ $script:ReallyExit = $true; $script:Window.Close() })
$script:Window.add_StateChanged({
    if ($script:Window.WindowState -eq 'Maximized') { $ui.Root.Margin = New-Object System.Windows.Thickness(7); $ui.BtnMax.Content = [string][char]0xE923 }
    else { $ui.Root.Margin = New-Object System.Windows.Thickness(0); $ui.BtnMax.Content = [string][char]0xE922 }
})

foreach ($p in $script:PageNames) { $ui["Nav$p"].add_Checked({ param($s, $e) if (-not $script:NavSuppress) { Show-VxPage ([string]$s.Tag) } }) }

# home
$ui.BtnOneClick.add_Click({ Show-VxWizard })
$ui.BtnHomeMeasure.add_Click({ Show-VxPage 'Measure' })
$ui.BtnHomeCheck.add_Click({ Start-VxHealthCheck })
$findingHandler = [System.Windows.RoutedEventHandler] {
    param($s, $e)
    $btn = $e.OriginalSource
    if ($btn -is [System.Windows.Controls.Button] -and $btn.Tag) { Invoke-VxFindingAction ([string]$btn.Tag) $btn.DataContext }
}
foreach ($n in @('HomeAdvice', 'HealthList')) { $ui[$n].AddHandler([System.Windows.Controls.Button]::ClickEvent, $findingHandler) }
$ui.BtnLostFix.add_Click({
    $ids = [string[]]@($script:LostIds)
    if ($ids.Count -eq 0) { return }
    Show-VxBusy (T 'busy.applying') (T 'busy.wait')
    Start-VxJob -Name 'relost' -Arguments @($script:Hw, $ids) -Script { param($Sync, $Hw, $Ids) Start-VxBatch; try { return @{ n = @(Repair-VxLostTweaks $Hw $Ids).Count } } finally { Stop-VxBatch } } -OnDone {
        param($r)
        Hide-VxBusy
        Show-VxToast (T 'lost.done' @($r.n)) 'ok'
        Update-VxStates
    }
})
$ui.BtnLostIgnore.add_Click({ $script:Settings.lostSeen = (@($script:LostIds) | Sort-Object) -join ','; Save-VxSettings $script:Settings; Update-VxNotices })
$ui.BtnRetiredOpen.add_Click({ Show-VxPage 'Restore' })

# measure
$ui.BtnMeasureRun.add_Click({ Start-VxMeasure })
$ui.BtnMeasureBaseline.add_Click({ Start-VxMeasure -Baseline })
$ui.BtnReportCopy.add_Click({ Copy-VxReport })
$ui.BtnReportSave.add_Click({ Copy-VxReport -Save })

# health
$ui.BtnHealthRun.add_Click({ Start-VxHealthCheck })

# wizard
$ui.WizClose.add_Click({ Hide-VxOverlay $ui.WizardOverlay })
foreach ($n in $script:WizNames) { $ui[$n].add_Checked({ param($s, $e) Update-VxWizardSummary ([string]$s.Tag) }) }
$ui.WizPreview.add_Click({
    $plan = Get-VxWizardPlan $script:WizPreset
    Invoke-VxApplyItems -ApplyIds (@($plan.tweaks) + @($plan.services)) -RevertIds @() -RestorePoint $false -Title '' -Preview
})
$ui.WizGo.add_Click({
    Hide-VxOverlay $ui.WizardOverlay
    $hasBase = $false; try { $hasBase = [bool](ConvertTo-VxHashtable (Read-VxJson 'bench.json' $null)).baseline } catch { }
    if ($hasBase -or $script:GlobalDryRun) { Start-VxWizardApply; return }
    # first time: measure "before", so the user sees real numbers after
    Show-VxDialog -Title (T 'wiz.measure.q') -Text (T 'wiz.measure.text') -YesText (T 'wiz.measure.yes') -NoText (T 'wiz.measure.no') -OnYes { Start-VxMeasure -Baseline -Then { Start-VxWizardApply } } -OnNo { Start-VxWizardApply }
})

# optimize
foreach ($n in @('PresetSlowpc', 'PresetPiki', 'PresetGaming', 'PresetCompetitive', 'PresetCreator', 'PresetBalanced', 'PresetLaptop')) { $ui[$n].add_Click({ param($s, $e) Select-VxPreset ([string]$s.Tag) }) }
$previewHandler = {
    $p = Get-VxPendingIds
    if ($p.apply.Count -eq 0 -and $p.revert.Count -eq 0) { Show-VxToast (T 'preview.pick') 'info'; return }
    Invoke-VxApplyItems -ApplyIds $p.apply -RevertIds $p.revert -RestorePoint $false -Title '' -Preview
}
$ui.BtnPreview.add_Click($previewHandler)
$ui.BtnPendingPreview.add_Click($previewHandler)
$ui.BtnSessionGame.add_Click({ Start-VxSessionUi 'game' })
$ui.BtnSessionStop.add_Click({ Stop-VxSessionUi })

# pending bar
$ui.BtnPendingApply.add_Click({
    $p = Get-VxPendingIds
    Invoke-VxApplyItems -ApplyIds $p.apply -RevertIds $p.revert -RestorePoint ([bool]$ui.ChkRestorePoint.IsChecked) -Title (T 'busy.applying')
})
$ui.BtnPendingReset.add_Click({
    foreach ($it in (Get-VxAllItems)) { if ($it.IsDirty) { $it.IsChecked = $it.IsApplied } }
    foreach ($n in @('PresetSlowpc', 'PresetPiki', 'PresetGaming', 'PresetCompetitive', 'PresetCreator', 'PresetBalanced', 'PresetLaptop', 'LevelLight', 'LevelBalanced', 'LevelMax')) { $ui[$n].IsChecked = $false }
    Update-VxPendingBar
})

# startup apps and processes
$ui.ProcTabStartup.add_Checked({ $ui.ProcPaneStartup.Visibility = 'Visible'; $ui.ProcPaneReduce.Visibility = 'Collapsed'; $ui.ProcPaneRunning.Visibility = 'Collapsed' })
$ui.ProcTabReduce.add_Checked({ $ui.ProcPaneStartup.Visibility = 'Collapsed'; $ui.ProcPaneReduce.Visibility = 'Visible'; $ui.ProcPaneRunning.Visibility = 'Collapsed' })
$ui.ProcTabRunning.add_Checked({ $ui.ProcPaneStartup.Visibility = 'Collapsed'; $ui.ProcPaneReduce.Visibility = 'Collapsed'; $ui.ProcPaneRunning.Visibility = 'Visible' })
foreach ($n in @('LevelLight', 'LevelBalanced', 'LevelMax')) { $ui[$n].add_Click({ param($s, $e) Select-VxProcLevel ([int]$s.Tag) }) }
$ui.BtnProcRefresh.add_Click({ Update-VxProcList; Update-VxProcStats })
$ui.BtnBoost.add_Click({ Invoke-VxBoost })
$startupToggle = [System.Windows.RoutedEventHandler] {
    param($s, $e)
    if ($script:StartupSuppress) { return }
    $cb = $e.OriginalSource
    if (-not ($cb -is [System.Windows.Controls.CheckBox])) { return }
    $item = $cb.DataContext
    if (-not $item -or $item.Kind -ne 'startup') { return }
    $enable = [bool]$cb.IsChecked
    if ($enable -eq $item.IsApplied) { return }
    $item.IsApplied = $enable
    if ($script:GlobalDryRun) { Show-VxToast ((T 'preview.title') + ': ' + $item.Title) 'info'; return }
    Start-VxJob -Name 'startuptoggle' -Arguments @($item.Tag, $enable) -Script { param($Sync, $It, $En) Set-VxStartupEnabled -Item $It -Enabled $En; return @{ ok = $true } } -OnDone { param($r) Update-VxHomeStats }
    Show-VxToast $(if ($enable) { T 'startup.toast.on' @($item.Title) } else { T 'startup.toast.off2' @($item.Title) }) 'ok'
}
$ui.StartupList.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $startupToggle)
$ui.StartupList.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $startupToggle)
$ui.ProcList.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler] {
    param($s, $e)
    $btn = $e.OriginalSource
    if (-not ($btn -is [System.Windows.Controls.Button])) { return }
    $row = $btn.DataContext
    if (Test-VxPreviewStop ('close ' + $row.Name)) { return }
    $script:ProcToKill = $row.Name
    $go = { Start-VxJob -Name 'kill' -Arguments @($script:ProcToKill) -Script { param($Sync, $N) return @{ n = (Stop-VxProcessGroup $N) } } -OnDone { param($r) Show-VxToast (T 'proc.killed' @($script:ProcToKill)) 'ok'; Update-VxProcList } }
    if ($row.Risk -eq 'safe') { & $go }
    else { Show-VxDialog -Title (T 'proc.kill.q' @($row.Name)) -Text $row.Advice -YesText (T 'proc.kill.yes') -NoText (T 'common.cancel') -OnYes $go }
})

# network
$ui.BtnNetBoost.add_Click({
    if (-not $script:Hw) { Show-VxToast (T 'common.wait') 'info'; return }
    $ids = [string[]]@($script:Lists.net | Where-Object { $_.Risk -ne 'advanced' -and -not $_.IsApplied } | ForEach-Object { $_.Id })
    Show-VxBusy (T 'net.boost.busy') (T 'busy.wait')
    Start-VxJob -Name 'netboost' -Arguments @($script:Hw, $ids, $script:GlobalDryRun) -Script {
        param($Sync, $Hw, $Ids, $Dry)
        if ($Dry) { Start-VxDryRun }
        $n = 0; $i = 0
        foreach ($id in $Ids) {
            $i++; $Sync.Pct = [int](60 * $i / [math]::Max(1, $Ids.Count))
            $t = Find-VxTweak $id; if (-not $t) { continue }
            $Sync.Step = L $t.Title
            if ((Invoke-VxTweak $t $Hw).ok) { $n++ }
        }
        $Sync.Step = (L @{ it = 'Cerco il DNS più veloce...'; en = 'Finding the fastest DNS...' }); $Sync.Pct = 70
        $dns = ''
        if (-not $Dry) {
            try {
                $rows = @(Invoke-VxDnsBenchmark $Hw | Where-Object { $_.Ms -ge 0 })
                $cur = $rows | Where-Object { $_.Current } | Sort-Object Ms | Select-Object -First 1
                $best = $rows | Where-Object { $_.S } | Sort-Object Ms | Select-Object -First 1
                if ($best -and -not $best.Current -and (-not $cur -or $best.Ms -lt $cur.Ms * 0.85) -and $Hw.Network) {
                    if (Set-VxDnsServers ([int]$Hw.Network.IfIndex) $best.P $best.S) { $dns = $best.Name }
                }
            } catch { }
            Clear-DnsClientCache -ErrorAction SilentlyContinue
        } else { [void](Stop-VxDryRun) }
        $Sync.Pct = 95
        return @{ n = $n; dns = $dns }
    } -OnDone {
        param($r)
        Hide-VxBusy
        $msg = T 'net.boost.done' @($r.n)
        if ($r.dns) { $msg += ' ' + (T 'net.boost.dns' @($r.dns)) }
        $ui.NetBoostStatus.Text = [string][char]0x2713 + ' ' + $msg
        Show-VxDialog -Title (T 'apply.title') -Text ($msg + "`n`n" + (T 'net.boost.next')) -YesText (T 'net.ping.run') -NoText 'OK' -OnYes { Start-VxPingTest }
        Update-VxStates
    }
})
$ui.BtnPingTest.add_Click({ Start-VxPingTest })
$ui.BtnLoadTest.add_Click({ Start-VxLoadTest })
$ui.BtnDnsTest.add_Click({ Start-VxDnsBench })
$ui.BtnDnsApply.add_Click({
    $b = $script:DnsBest
    if (-not $b -or -not $script:Hw.Network -or $script:GlobalDryRun) { return }
    Start-VxJob -Name 'dnsapply' -Arguments @([int]$script:Hw.Network.IfIndex, $b.Primary, $b.Secondary) -Script { param($Sync, $I, $P, $S) return @{ ok = (Set-VxDnsServers $I $P $S) } } -OnDone {
        param($r)
        if ($r.ok) { Show-VxToast (T 'net.dns.applied' @($script:DnsBest.Provider)) 'ok' } else { Show-VxToast (T 'common.error') 'crit' }
    }
})
$ui.BtnDnsRevert.add_Click({
    if (-not (Test-VxBackupEntry 'dns')) { Show-VxToast (T 'net.dns.norevert') 'info'; return }
    Invoke-VxUndo @('dns')
})
# flush DNS in a job (1.x ran it on the UI thread)
$ui.BtnFlushDns.add_Click({ Start-VxJob -Name 'flushdns' -Script { param($Sync) Clear-DnsClientCache -ErrorAction Stop; return @{ ok = $true } } -OnDone { param($r) Show-VxToast (T 'net.flushed') 'ok' } })
$ui.BtnNetReset.add_Click({
    if (Test-VxPreviewStop 'network reset') { return }
    Show-VxDialog -Title (T 'net.reset') -Text (T 'net.reset.q') -YesText (T 'net.reset.yes') -NoText (T 'common.cancel') -OnYes {
        Start-VxJob -Name 'netreset' -Script { param($Sync) Invoke-VxNetworkReset; return @{ ok = $true } } -OnDone {
            Show-VxDialog -Title (T 'net.reset') -Text (T 'net.reset.done') -YesText (T 'common.rebootnow') -NoText (T 'common.later') -OnYes { Restart-VxPc }
        }
    }
})

# after effects
$ui.BtnRenderMode.add_Click({ if ($script:Session -and $script:Session.kind -eq 'render') { Stop-VxSessionUi } else { Start-VxSessionUi 'render' } })
$ui.BtnAeFolders.add_Click({
    if (Test-VxPreviewStop 'AE cache folders') { return }
    Start-VxJob -Name 'aefolders' -Arguments @($script:Hw) -Script { param($Sync, $Hw) $r = New-VxAeCacheFolders $Hw; return @{ disk = $r.Disk; media = $r.Media } } -OnDone {
        param($r)
        try { [System.Windows.Clipboard]::SetText($r.disk) } catch { }
        Show-VxDialog -Title (T 'ae.folders.done') -Text (T 'ae.folders.text' @($r.disk, $r.media)) -YesText 'OK'
    }
})
$ui.BtnAeCopy.add_Click({
    if (-not $script:AeReport) { return }
    $txt = ($script:AeReport.Rows | ForEach-Object { "$($_.K): $($_.V)`r`n   $($_.H)" }) -join "`r`n"
    try { [System.Windows.Clipboard]::SetText($txt); Show-VxToast (T 'ae.copied') 'ok' } catch { }
})
$ui.BtnAeMediaClean.add_Click({
    if (Test-VxPreviewStop 'media cache') { return }
    Start-VxJob -Name 'mediaclean' -Script { param($Sync) return @{ freed = (Clear-VxMediaCache) } } -OnDone {
        param($r)
        if ($r.freed -lt 0) { Show-VxToast (T 'ae.close.first') 'warn' } else { Show-VxToast (T 'clean.freed' @((Format-VxBytes $r.freed))) 'ok'; $ui.BtnAeMediaClean.Content = (T 'ae.mediaclean') + ' (0 MB)' }
    }
})

# cleanup
$ui.BtnCleanScan.add_Click({ Start-VxCleanScan })
$ui.BtnCleanRun.add_Click({
    $ids = [string[]]@($script:CleanItems | Where-Object { $_.IsChecked } | ForEach-Object { $_.Id })
    Show-VxBusy (T 'clean.running') (T 'busy.wait')
    Start-VxJob -Name 'clean' -Arguments @($ids, $script:GlobalDryRun) -Script { param($Sync, $Ids, $Dry) if ($Dry) { Start-VxDryRun }; $f = Invoke-VxClean $Ids; if ($Dry) { [void](Stop-VxDryRun) }; return @{ freed = $f } } -OnDone {
        param($r)
        Hide-VxBusy
        $ui.CleanResult.Text = T 'clean.freed' @((Format-VxBytes $r.freed))
        Show-VxToast (T 'clean.freed' @((Format-VxBytes $r.freed))) 'ok'
        Start-VxCleanScan
        Update-VxHomeStats
    }
})
foreach ($n in @('SchedOff', 'SchedWeekly', 'SchedMonthly')) {
    $ui[$n].add_Checked({ param($s, $e) if ($script:SchedSuppress) { return }; $script:SchedWanted = [string]$s.Tag; if ($script:GlobalDryRun) { Show-VxToast (T 'preview.title') 'info'; return }; Set-VxSchedule ([string]$s.Tag) })
}

# restore
$ui.BtnRestorePoint.add_Click({ New-VxRestorePointUi })
$ui.BtnRstrui.add_Click({ Open-VxTarget 'rstrui.exe' })
$ui.BtnUndoAll.add_Click({
    Show-VxDialog -Title (T 'restore.all') -Text (T 'restore.all.q') -YesText (T 'restore.all.btn') -NoText (T 'common.cancel') -OnYes { Invoke-VxUndo ([string[]]@((Get-VxBackup).entries.Keys)) }
})
$ui.ActiveList.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler] {
    param($s, $e)
    $btn = $e.OriginalSource
    if ($btn -is [System.Windows.Controls.Button] -and $btn.Tag) { Invoke-VxUndo @([string]$btn.Tag) }
})
$ui.BtnRetiredUndo.add_Click({
    $ids = [string[]]@(Get-VxRetiredEntries | ForEach-Object { $_.id })
    if ($ids.Count -gt 0) { Invoke-VxUndo $ids }
})
$ui.BtnRetiredUpdate.add_Click({ Invoke-VxApplyItems -ApplyIds @('ae.priority') -RevertIds @() -RestorePoint $false -Title (T 'busy.applying') })
$ui.BtnRetiredKeep.add_Click({
    $seen = @($script:Settings.retiredSeen) + @(Get-VxRetiredEntries | ForEach-Object { $_.id })
    if ($script:AePrioOld) { $seen += 'ae.priority' }
    $script:Settings.retiredSeen = @($seen | Select-Object -Unique)
    Save-VxSettings $script:Settings
    $ui.RetiredCard.Visibility = 'Collapsed'; $ui.RetiredCardHome.Visibility = 'Collapsed'
})

# settings
foreach ($lg in $script:Languages) {
    if (-not (Test-Path -LiteralPath (Join-Path $AppDir "lang\$($lg[0]).json"))) { continue }
    $rb = New-Object System.Windows.Controls.RadioButton
    $rb.Style = $script:Window.FindResource('Pill')
    $rb.GroupName = 'lang'
    $rb.Content = $lg[1]
    $rb.Tag = $lg[0]
    $rb.Margin = '0,0,8,8'
    if ($lg[0] -eq $script:VxLang) { $rb.IsChecked = $true }
    $rb.add_Click({ param($s, $e) $new = [string]$s.Tag; if ($new -eq $script:VxLang) { return }; $script:Settings.lang = $new; Save-VxSettings $script:Settings; Restart-VxApp })
    [void]$ui.LangPanel.Children.Add($rb)
}
$ui.ExpertSwitch.IsChecked = $script:Expert
$ui.AutoUpdateSwitch.IsChecked = [bool]$script:Settings.autoUpdate
$ui.MotionSwitch.IsChecked = [bool]$script:Settings.reducedMotion
$ui.GlassSwitch.IsChecked = [bool]$script:Settings.glass
$ui.TraySwitch.IsChecked = [bool]$script:Settings.tray
$ui.AutoStartSwitch.IsChecked = [bool]$script:Settings.autostart
$ui.ExpertSwitch.add_Click({ $script:Expert = [bool]$ui.ExpertSwitch.IsChecked; $script:Settings.expert = $script:Expert; Save-VxSettings $script:Settings; Update-VxOptionLists })
$ui.AutoUpdateSwitch.add_Click({ $script:Settings.autoUpdate = [bool]$ui.AutoUpdateSwitch.IsChecked; Save-VxSettings $script:Settings })
$ui.MotionSwitch.add_Click({ $script:Settings.reducedMotion = [bool]$ui.MotionSwitch.IsChecked; Save-VxSettings $script:Settings; Update-VxMotionMode })
$ui.GlassSwitch.add_Click({ $script:Settings.glass = [bool]$ui.GlassSwitch.IsChecked; Save-VxSettings $script:Settings; if ($script:Settings.glass) { Enable-VxGlass } else { Show-VxToast (T 'set.glass.restart') 'info' } })
$ui.TraySwitch.add_Click({ $script:Settings.tray = [bool]$ui.TraySwitch.IsChecked; Save-VxSettings $script:Settings; Update-VxTrayIcon; $ui.BtnTray.Visibility = if ($script:Settings.tray) { 'Visible' } else { 'Collapsed' } })
$ui.AutoStartSwitch.add_Click({ Set-VxAutoStart ([bool]$ui.AutoStartSwitch.IsChecked) })
$ui.BtnCheckUpdate.add_Click({ Start-VxUpdateCheck -Manual })
$ui.BtnBannerUpdate.add_Click({ Start-VxUpdate })
$ui.BtnLogoPick.add_Click({ Select-VxImage 'logo' })
$ui.BtnBgPick.add_Click({ Select-VxImage 'bg' })
$ui.BtnLogoReset.add_Click({ $script:Settings.logo = ''; Save-VxSettings $script:Settings; Remove-Item -LiteralPath (Join-Path $script:CustomDir 'logo.ico') -Force -ErrorAction SilentlyContinue; Update-VxLook; Show-VxToast (T 'set.logo.ok') 'ok' })
$ui.BtnBgRemove.add_Click({ $script:Settings.bg = ''; Save-VxSettings $script:Settings; Update-VxLook })
foreach ($n in @('BgLevel1', 'BgLevel2', 'BgLevel3')) { $ui[$n].add_Click({ param($s, $e) $script:Settings.bgLevel = [int]$s.Tag; Save-VxSettings $script:Settings; Update-VxLook }) }
$ui.BtnShortcut.add_Click({ try { New-VxShortcut; Show-VxToast (T 'set.shortcut.ok') 'ok' } catch { Show-VxToast $_.Exception.Message 'crit' } })
$ui.BtnOpenLogs.add_Click({ Open-VxTarget $script:VxLogs })
$ui.BtnRescan.add_Click({ Start-VxHardwareScan -Manual })

$ui.DialogYes.add_Click({ Hide-VxOverlay $ui.DialogOverlay; $cb = $script:DialogYes; $script:DialogYes = $null; $script:DialogNo = $null; if ($cb) { & $cb } })
$ui.DialogNo.add_Click({ Hide-VxOverlay $ui.DialogOverlay; $cb = $script:DialogNo; $script:DialogYes = $null; $script:DialogNo = $null; if ($cb) { & $cb } })

# =====================================================================
#  MOTION MODE (reduced / weak PC / saturated CPU)
# =====================================================================
function Update-VxMotionMode {
    $sysAnim = $true
    try { $sysAnim = [System.Windows.SystemParameters]::ClientAreaAnimation } catch { }
    $script:Reduced = ([bool]$script:Settings.reducedMotion -or -not $sysAnim)
    $script:WeakUi = ($script:Hw -and (Test-VxWeakPc $script:Hw))
    $parts = @()
    if ($script:WeakUi) { $parts += (T 'set.perf.weak') }
    if ($script:Reduced) { $parts += (T 'set.perf.reduced') }
    $ui.PerfModeText.Text = if ($parts.Count -gt 0) { $parts -join ' ' } else { T 'set.perf.normal' }
    $strong = Test-VxStrongPc
    $ui.GlassSwitch.IsEnabled = $strong
    if (-not $strong) { $ui.GlassSub.Text = T 'set.glass.weak' }
}

# =====================================================================
#  TIMERS: job poller (fast only while something runs) + 1 Hz live meter (only while visible and focused)
# =====================================================================
$script:JobTimer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$script:JobTimer.Interval = [TimeSpan]::FromMilliseconds(120)
$script:LastTick = [DateTime]::Now
$script:JobTimer.add_Tick({
    try {
        $gap = ([DateTime]::Now - $script:LastTick).TotalMilliseconds
        if ($gap -gt 2000 -and -not $script:InTray) { Write-VxLog ("UI thread was busy for {0:N0} ms" -f $gap) 'WARN' }
        $script:LastTick = [DateTime]::Now
        Complete-VxJobs
        if ($script:BusyActive) {
            $ui.BusyText.Text = [string]$script:Sync.Step
            Set-VxBar $ui.BusyBar ([double]$script:Sync.Pct / 100)
        }
        if ($script:SplashActive) {
            if ($script:Sync.Step) { $ui.SplashStep.Text = [string]$script:Sync.Step }
            if ($script:HealthSplash) { Set-VxBar $ui.SplashBar (0.3 + 0.7 * [double]$script:Sync.Pct / 100) }
            elseif (-not $script:Hw) { Set-VxBar $ui.SplashBar ([math]::Min(0.3, 0.1 + 0.2 * [double]$script:Sync.Pct / 100)) }
        }
        if ($script:Pinger) { Update-VxPingLive }
        if ($script:LoadT) { Update-VxLoadLive }
        if ($script:ToastUntil -and (Get-Date) -gt $script:ToastUntil) { $script:ToastUntil = $null; Hide-VxToast }
        if ($script:Jobs.Count -gt 0) { $script:LastJobAt = [DateTime]::Now } else { Close-VxPoolIfIdle }
        $active = ($script:Jobs.Count -gt 0 -or $script:BusyActive -or $script:SplashActive -or $script:Pinger -or $script:LoadT)
        $want = if ($active) { 120 } elseif ($script:InTray) { 2000 } else { 1000 }
        if ([int]$script:JobTimer.Interval.TotalMilliseconds -ne $want) { $script:JobTimer.Interval = [TimeSpan]::FromMilliseconds($want) }
    } catch { Write-VxLog "Timer: $($_.Exception.Message)" 'ERROR' }
})
$script:JobTimer.Start()

[void][VeloxPC.Native]::CpuUsage()
$script:LivePts = $null
$script:LiveTick = 0
$script:LiveTimer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Background)
$script:LiveTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:LiveTimer.add_Tick({
    try {
        $script:LiveTick++
        # Render session: ends by itself when After Effects / Media Encoder / Topaz close (checked every 15 s)
        if ($script:Session -and $script:Session.kind -eq 'render' -and ($script:LiveTick % 15 -eq 0 -or $script:InTray)) {
            if (Test-VxRenderAppsRunning) { $script:SessionSawApp = $true }
            elseif ($script:SessionSawApp) { Stop-VxSessionUi -Quiet; Show-VxToast (T 'session.auto') 'info' }
        }
        $visible = ($script:Window.IsVisible -and $script:Window.WindowState -ne 'Minimized' -and $script:Window.IsActive)
        if (-not $visible -and -not ($script:TrayIcon -and $script:TrayIcon.Visible)) { return }
        $cpu = [VeloxPC.Native]::CpuUsage()
        $mem = [VeloxPC.Native]::Memory()
        if (Step-VxLiteMode $script:Lite $cpu) { Write-VxLog ("light mode {0} (CPU {1:N0}%)" -f $(if ($script:Lite.Lite) { 'on' } else { 'off' }), $cpu) }
        if ($script:TrayIcon -and $script:TrayIcon.Visible) { $script:TrayIcon.Text = ('Piki Optimizer · CPU {0:N0}% · RAM {1:N0}%' -f $cpu, $mem[0]) }
        if (-not $visible) { return }
        $ui.SideCpuText.Text = '{0:N0}%' -f $cpu
        $ui.SideRamText.Text = '{0:N0}%' -f $mem[0]
        (Get-VxTransform $ui.SideCpuBar 'Scale').ScaleX = [math]::Max(0.02, $cpu / 100)
        (Get-VxTransform $ui.SideRamBar 'Scale').ScaleX = [math]::Max(0.02, [double]$mem[0] / 100)
        if ($script:CurrentPage -eq 'Home') {
            $script:CpuHist.Add($cpu); $script:RamHist.Add($mem[0])
            while ($script:CpuHist.Count -gt 60) { $script:CpuHist.RemoveAt(0); $script:RamHist.RemoveAt(0) }
            $w = $ui.LiveCanvas.ActualWidth; $h = $ui.LiveCanvas.ActualHeight
            if ($w -gt 10 -and $h -gt 10) {
                foreach ($pair in @(@($script:CpuHist, $ui.LiveCpuLine), @($script:RamHist, $ui.LiveRamLine))) {
                    $data = $pair[0]; $pts = $pair[1].Points
                    if (-not $pts -or $pts.IsFrozen) { $pts = New-Object System.Windows.Media.PointCollection; $pair[1].Points = $pts }
                    # reuse the point list: only the coordinates change
                    while ($pts.Count -gt $data.Count) { $pts.RemoveAt($pts.Count - 1) }
                    for ($k = 0; $k -lt $data.Count; $k++) {
                        $p = New-Object System.Windows.Point(($w - ($data.Count - 1 - $k) * $w / 59), ($h - 2 - ($data[$k] / 100) * ($h - 4)))
                        if ($k -lt $pts.Count) { $pts[$k] = $p } else { $pts.Add($p) }
                    }
                }
            }
            $ui.LiveCpuText.Text = '{0:N0}%' -f $cpu
            $ui.LiveRamText.Text = ('{0:N0}%' -f $mem[0]) + ' · ' + (Format-VxBytes ($mem[1] - $mem[2])) + ' / ' + (Format-VxBytes $mem[1])
        }
    } catch { }
})
$script:LiveTimer.Start()

# =====================================================================
#  HARDWARE (cached for 24 h; rescanned after a reboot or on request)
# =====================================================================
function Get-VxBootTimeNow { try { return [DateTime]::Now.AddSeconds(-([System.Diagnostics.Stopwatch]::GetTimestamp() / [System.Diagnostics.Stopwatch]::Frequency)) } catch { return [DateTime]::MinValue } }

function Test-VxHwCacheFresh {
    $f = Join-Path $script:VxData 'cache\hardware.json'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    $t = (Get-Item -LiteralPath $f).LastWriteTime
    return ((([DateTime]::Now - $t).TotalHours -lt 24) -and ($t -gt (Get-VxBootTimeNow).AddMinutes(1)))
}

function Set-VxHw {
    param($Hw)
    $script:Hw = $Hw
    try { $script:Hw | Add-Member -NotePropertyName RenderTier -NotePropertyValue ([int]$script:RenderTier) -Force } catch { }
    $ui.TitlePc.Text = (@($Hw.Model) | Where-Object { $_ }) -join ' · '
    $ui.HomeHello.Text = T 'home.title3'
    Update-VxHwCards
    Update-VxMotionMode
}

function Start-VxHardwareScan {
    param([switch]$Manual)
    if ($Manual) { Show-VxBusy (T 'splash.hw') (T 'busy.wait') }
    Start-VxJob -Name 'hardware' -Script { param($Sync) return (Get-VxHardware -Sync $Sync) } -OnDone {
        param($hw)
        $firstHw = (-not $script:Hw)
        Set-VxHw $hw
        try { Write-VxJson 'cache\hardware.json' $hw } catch { }
        Write-VxLog "Hardware: $($hw.CPU.Name) | $(if ($hw.GPU) { $hw.GPU.Name }) | $($hw.RAM.GB) GB | $($hw.OS.Name) $($hw.OS.DisplayVersion)"
        if ($script:BusyActive) { Hide-VxBusy }
        if ($firstHw) { Start-VxAfterHardware }
        else { Update-VxStates }
    } -OnError {
        param($e)
        Hide-VxBusy
        if (-not $script:Hw) { Show-VxFatal ("Hardware scan failed: " + $e.Message); Hide-VxSplash }
    }
}

function Start-VxAfterHardware {
    $saved = Read-VxJson 'health.json' $null
    if ($saved -and -not $script:Health) { $script:Health = ConvertTo-VxHashtable $saved; Update-VxHealthPage }
    $firstRun = (-not $script:Settings.firstRunDone -or -not $script:Health)
    Set-VxBar $ui.SplashBar 0.3
    $script:Sync.Step = T 'splash.states'
    if ($firstRun) {
        $ui.SplashTitle.Text = T 'splash.first'
        Start-VxHealthCheck -Splash
        Update-VxStates
    } elseif ($script:FastStart) { Update-VxStates }
    else { Update-VxStates -Then { Hide-VxSplash; Show-VxPage 'Home' } }
    Update-VxHomeStats
    # after optimizing + a restart: measure again automatically (read-only)
    try { if (Test-VxMeasureDue (Get-VxBootTimeNow)) { Write-VxLog 'measure after reboot'; Start-VxMeasure } } catch { }
    if ($script:Settings.autoUpdate) { Start-VxUpdateCheck }
    if (-not $script:UpdTimer) {
        $script:UpdTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:UpdTimer.Interval = [TimeSpan]::FromHours(24)
        $script:UpdTimer.add_Tick({ if ($script:Settings.autoUpdate) { Start-VxUpdateCheck } })
        $script:UpdTimer.Start()
    }
}

# =====================================================================
#  STARTUP SEQUENCE
# =====================================================================
$ui.VersionText.Text = "v$script:Version" + $(if ($script:GlobalDryRun) { ' · preview' } else { '' })
$ui.BtnTray.Visibility = if ($script:Settings.tray) { 'Visible' } else { 'Collapsed' }
Update-VxLook
Update-VxMotionMode
try {
    $nx = Test-VxNexus
    if ($nx.Detected) { $ui.NexusNote.Visibility = 'Visible'; Write-VxLog ("Winstep Nexus detected (running={0}, autostart={1}): dock settings protected" -f $nx.Running, $nx.Autostart) }
} catch { }
# Start menu entry for "Ripristina Piki.cmd" (in-app updates do not run the setup again)
try {
    $rstCmd = Join-Path $Root 'Ripristina Piki.cmd'
    $rstLnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'Ripristina Piki Optimizer.lnk'
    if ((Test-Path -LiteralPath $rstCmd) -and -not (Test-Path -LiteralPath $rstLnk) -and $script:IsInstalledCopy) {
        $wsh = New-Object -ComObject WScript.Shell
        $l = $wsh.CreateShortcut($rstLnk); $l.TargetPath = $rstCmd; $l.WorkingDirectory = $Root
        $l.IconLocation = "$env:SystemRoot\System32\shell32.dll,238"; $l.Description = 'Piki Optimizer - Ripristina come prima'; $l.Save()
    }
} catch { }
# small laptop screens (1366x768, or 1920x1080 at 150%): the 1180x760 window was taller than the screen and
# CenterScreen pushed the title bar (close/minimise) above the top edge. Fit the window to the work area.
try {
    $wa = [System.Windows.SystemParameters]::WorkArea
    if ($wa.Width -gt 200 -and $wa.Height -gt 200) {
        $script:Window.MinWidth = [math]::Min($script:Window.MinWidth, $wa.Width)
        $script:Window.MinHeight = [math]::Min($script:Window.MinHeight, $wa.Height)
        if ($script:Window.Width -gt $wa.Width) { $script:Window.Width = $wa.Width }
        if ($script:Window.Height -gt $wa.Height) { $script:Window.Height = $wa.Height }
    }
} catch { }
$script:Window.add_SourceInitialized({ Enable-VxGlass })
if ($Tray) {
    # started with Windows: lives only in the notification area until opened
    $script:Window.ShowInTaskbar = $false
    $script:Window.add_Loaded({ if (-not $script:TrayStarted) { $script:TrayStarted = $true; $script:Window.Dispatcher.BeginInvoke([Action] { Send-VxToTray }) | Out-Null } })
}
$script:SplashActive = $true
$ui.SplashStep.Text = T 'splash.hw'
Set-VxBar $ui.SplashBar 0.1 -Instant
$script:CacheHw = Read-VxJson 'cache\hardware.json' $null
$script:CacheStates = ConvertTo-VxHashtable (Read-VxJson 'cache\states.json' $null)

$script:Window.add_ContentRendered({
    if ($script:Started) { return }
    $script:Started = $true
    try { $script:RenderTier = [System.Windows.Media.RenderCapability]::Tier -shr 16 } catch { $script:RenderTier = 2 }
    Write-VxLog ("render tier {0}, animations {1} fps" -f $script:RenderTier, $script:Fps)
    Move-VxNavIndicator 'Home' -Instant
    if ($script:CacheHw -and $script:Settings.firstRunDone) {
        # instant start: last known data right away
        try {
            Set-VxHw $script:CacheHw
            if ($script:CacheStates) { $script:States = $script:CacheStates }
            $saved = Read-VxJson 'health.json' $null
            if ($saved) { $script:Health = ConvertTo-VxHashtable $saved; Update-VxHealthPage }
            if ($script:States.Count -gt 0) { Update-VxOptionLists }
            Update-VxHome
            Hide-VxSplash
            Show-VxPage 'Home'
            $script:FastStart = $true
            Write-VxLog 'fast start from cache'
        } catch { Write-VxLog "cache start: $($_.Exception.Message)" 'WARN'; $script:Hw = $null }
    }
    Ensure-VxDesktopIcon
    if ($script:Hw -and (Test-VxHwCacheFresh)) {
        # hardware unchanged since this boot and less than a day old: no 8-12 s WMI scan
        Write-VxLog 'hardware cache fresh: scan skipped'
        Start-VxAfterHardware
    } else {
        $script:Hw = $null
        if ($script:CacheHw -and $script:Settings.firstRunDone) { $script:Hw = $script:CacheHw; $script:HwRescanQuiet = $true }
        if ($script:HwRescanQuiet) {
            Start-VxJob -Name 'hardware' -Script { param($Sync) return (Get-VxHardware -Sync $Sync) } -OnDone {
                param($hw)
                Set-VxHw $hw
                try { Write-VxJson 'cache\hardware.json' $hw } catch { }
                Start-VxAfterHardware
            } -OnError { param($e) Write-VxLog "hardware: $($e.Message)" 'WARN'; Start-VxAfterHardware }
        } else { Start-VxHardwareScan }
    }
})

$script:Window.add_Closing({
    param($s, $e)
    if ($script:Settings.tray -and -not $script:ReallyExit) {
        $e.Cancel = $true
        Write-VxLog 'close -> background'
        Send-VxToTray
        return
    }
    try { if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() } } catch { }
    try { if ($script:Session) { [VeloxPC.Native]::KeepAwake($false); [void](Stop-VxSession) } } catch { }
    try { $script:JobTimer.Stop(); $script:LiveTimer.Stop() } catch { }
    Write-VxLog '---- Piki Optimizer exit'
})

# ---- self-test: -Snapshot <folder> renders every page to PNG once the app is ready, logs timings, then exits
if ($Snapshot) {
    $script:SnapT0 = (Get-Process -Id $PID).StartTime
    $script:SnapTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:SnapTimer.Interval = [TimeSpan]::FromMilliseconds(900)
    $script:SnapStep = -1
    $script:SnapTimer.add_Tick({
        try {
            if ($script:SnapStep -lt 0) {
                if (-not $script:Hw -or $script:States.Count -eq 0 -or $script:SplashActive -or $script:Jobs.Count -gt 0) { return }
                Write-VxLog ("SNAPSHOT ready after {0:N1} s, private {1:N0} MB" -f ([DateTime]::Now - $script:SnapT0).TotalSeconds, ((Get-Process -Id $PID).PrivateMemorySize64 / 1MB))
                if (-not (Test-Path -LiteralPath $Snapshot)) { New-Item -ItemType Directory -Path $Snapshot -Force | Out-Null }
                $script:SnapStep = 0
            }
            if ($script:SnapStep -gt 0 -and -not $script:SnapIdleAt) {
                # render each page once (the idle measurement below must not include screenshot work)
                $prev = $script:PageNames[$script:SnapStep - 1]
                $w = [int]$ui.Root.ActualWidth; $h = [int]$ui.Root.ActualHeight
                $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
                $rtb.Render($ui.Root)
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                $fs = [System.IO.File]::Create((Join-Path $Snapshot "$prev.png")); $enc.Save($fs); $fs.Close()
            }
            if ($script:SnapStep -ge $script:PageNames.Count) {
                if (-not $script:SnapIdleAt) { Show-VxPage 'Home'; $script:SnapIdleAt = [DateTime]::Now; return }
                if (([DateTime]::Now - $script:SnapIdleAt).TotalSeconds -lt 30) { return }
                if (-not $script:SnapCpu0) { $script:SnapCpu0 = (Get-Process -Id $PID).TotalProcessorTime; $script:SnapCpuAt = [DateTime]::Now; return }
                if (([DateTime]::Now - $script:SnapCpuAt).TotalSeconds -lt 10) { return }
                $p = Get-Process -Id $PID
                $cpuPct = 100 * ($p.TotalProcessorTime - $script:SnapCpu0).TotalSeconds / ([DateTime]::Now - $script:SnapCpuAt).TotalSeconds
                Write-VxLog ("SNAPSHOT idle: CPU {0:N2}% of one core, private {1:N0} MB, working set {2:N0} MB" -f $cpuPct, ($p.PrivateMemorySize64 / 1MB), ($p.WorkingSet64 / 1MB))
                $script:SnapTimer.Stop(); $script:ReallyExit = $true; $script:Window.Close(); return
            }
            Show-VxPage $script:PageNames[$script:SnapStep]
            $script:SnapStep++
        } catch { Write-VxLog "SNAPSHOT: $($_.Exception.Message)" 'ERROR' }
    })
    $script:Window.add_ContentRendered({ Write-VxLog ("SNAPSHOT window visible after {0:N1} s" -f ([DateTime]::Now - $script:SnapT0).TotalSeconds); $script:SnapTimer.Start() })
}

# normal message loop (not ShowDialog: hiding a modal window would end its loop)
$script:Window.add_Closed({ try { $script:Window.Dispatcher.InvokeShutdown() } catch { } })
try {
    $script:Window.Show()
    [System.Windows.Threading.Dispatcher]::Run()
} catch {
    Show-VxFatal ($_.Exception.Message + "`n" + $_.ScriptStackTrace)
} finally {
    try { [VeloxPC.Native]::KeepAwake($false) } catch { }
    try { if (Get-VxSession) { [void](Stop-VxSession) } } catch { }
    [Environment]::Exit(0)
}
