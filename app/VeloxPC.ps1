# =====================================================================
#  Piki Optimizer - (c) 2026 piki04. Tutti i diritti riservati / All rights reserved. See LICENSE.
#  Windows PowerShell 5.1 + WPF. Run through "Avvia VeloxPC.cmd".
# =====================================================================
param([switch]$NoElevate, [switch]$Hosted, [switch]$Tray, [switch]$Cleanup, [switch]$UndoAll)

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
if (-not $NoElevate -and -not (Test-VxAdmin)) {
    # elevate straight into the hidden classic console (saves one extra PowerShell start)
    $conhostE = Join-Path $env:SystemRoot 'System32\conhost.exe'
    try {
        if (Test-Path -LiteralPath $conhostE) { Start-Process -FilePath $conhostE -Verb RunAs -WindowStyle Hidden -ArgumentList "`"$psExe`" $selfArgs -Hosted" }
        else { Start-Process -FilePath $psExe -Verb RunAs -WindowStyle Hidden -ArgumentList $selfArgs }
    } catch { }
    exit
}
if (-not $NoElevate -and -not $Hosted -and -not $Cleanup) {
    # Always run inside a classic (hideable) console: Windows Terminal cannot hide its window
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    if (Test-Path -LiteralPath $conhost) {
        Start-Process -FilePath $conhost -ArgumentList "`"$psExe`" $selfArgs -Hosted" -WindowStyle Hidden
        exit
    }
}
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process -FilePath $psExe -ArgumentList "$selfArgs -Hosted" -WindowStyle Hidden
    exit
}
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if ($Cleanup) { $ProgressPreference = 'SilentlyContinue' }
# single instance: close any other running VeloxPC window (e.g. an old or stuck one)
# (pid file instead of a slow WMI query: the old copy is identified by pid + start time)
$pidFile = Join-Path $Root 'data\app.pid'
try {
    if (Test-Path -LiteralPath $pidFile) {
        $old = ([System.IO.File]::ReadAllText($pidFile)).Trim().Split('|')
        if ($old.Count -eq 2 -and [int]$old[0] -ne $PID) {
            $op = Get-Process -Id ([int]$old[0]) -ErrorAction SilentlyContinue
            if ($op -and $op.ProcessName -eq 'powershell' -and $op.StartTime.Ticks -eq [long]$old[1]) { Stop-Process -Id $op.Id -Force -ErrorAction SilentlyContinue }
        }
    }
} catch { }
if (-not $Cleanup) {
    try {
        $pd = Split-Path -Parent $pidFile
        if (-not (Test-Path -LiteralPath $pd)) { New-Item -ItemType Directory -Path $pd -Force | Out-Null }
        [System.IO.File]::WriteAllText($pidFile, "$PID|$((Get-Process -Id $PID).StartTime.Ticks)")
    } catch { }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing
# the window stays responsive even when the PC is busy (the UI thread is light); background jobs run below normal
try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::AboveNormal } catch { }
# animations follow the monitor's refresh rate (read on the previous run), up to 240 fps
$script:Fps = 120
try {
    $hzFile = Join-Path $Root 'data\cache\hz.txt'
    if (Test-Path -LiteralPath $hzFile) { $hz = [int]([System.IO.File]::ReadAllText($hzFile).Trim()); if ($hz -ge 50) { $script:Fps = [math]::Min(240, $hz) } }
} catch { }
try { [System.Windows.Media.Animation.Timeline]::DesiredFrameRateProperty.OverrideMetadata([System.Windows.Media.Animation.Timeline], (New-Object System.Windows.FrameworkPropertyMetadata([object][int]$script:Fps))) } catch { }

# ---------------------------------------------------------------- native helpers (cached build)
$dataDir = Join-Path $Root 'data'
$cacheDir = Join-Path $dataDir 'cache'
if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
$csPath = Join-Path $AppDir 'core\Native.cs'
$csSrc = [System.IO.File]::ReadAllText($csPath, [System.Text.Encoding]::UTF8)
$sha = [System.Security.Cryptography.SHA1]::Create()
$hash = (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($csSrc))[0..7] | ForEach-Object { $_.ToString('x2') }) -join '')
$dll = Join-Path $cacheDir "VeloxNative_$hash.dll"
if (-not ('VeloxPC.Native' -as [type])) {
    try {
        if (-not (Test-Path -LiteralPath $dll)) { Add-Type -TypeDefinition $csSrc -OutputAssembly $dll -OutputType Library -ErrorAction Stop }
        if (-not ('VeloxPC.Native' -as [type])) { Add-Type -Path $dll -ErrorAction Stop }
    } catch {
        if (-not ('VeloxPC.Native' -as [type])) { Add-Type -TypeDefinition $csSrc -ErrorAction Stop }
    }
}
try { [VeloxPC.Native]::HideConsole() } catch { }
try { [void][VeloxPC.Native]::SetAppId('Piki.Optimizer') } catch { }

# ---------------------------------------------------------------- core modules
$coreFiles = @('Common', 'Hardware', 'Tweaks', 'Services', 'Network', 'AfterEffects', 'Cleanup', 'Health', 'Updater')
foreach ($cf in $coreFiles) { . (Join-Path $AppDir "core\$cf.ps1") }
Initialize-VxPaths $Root
if ($Cleanup) {
    # called by the uninstaller
    if ($UndoAll) { foreach ($id in @((Get-VxBackup).entries.Keys)) { try { [void](Undo-VxEntry $id) } catch { } } }
    Unregister-ScheduledTask -TaskName 'PikiOptimizer' -Confirm:$false -ErrorAction SilentlyContinue
    Write-VxLog 'Cleanup done (uninstall)'
    exit
}
Write-VxLog '---- Piki Optimizer start'
try { if (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PikiOptimizer') { $lmv = Get-VxLocalManifest; if ($lmv) { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PikiOptimizer' -Name DisplayVersion -Value ([string]$lmv.version) } } } catch { }

$script:Settings = Get-VxSettings
if (-not $script:Settings.lang) {
    $cul = (Get-UICulture).TwoLetterISOLanguageName
    if (-not (Test-Path -LiteralPath (Join-Path $AppDir "lang\$cul.json"))) { $cul = (Get-Culture).TwoLetterISOLanguageName }
    $script:Settings.lang = if (Test-Path -LiteralPath (Join-Path $AppDir "lang\$cul.json")) { $cul } else { 'en' }
}
if (-not (Test-Path -LiteralPath (Join-Path $AppDir "lang\$($script:Settings.lang).json"))) { $script:Settings.lang = 'en' }
$script:VxLang = $script:Settings.lang
$script:Expert = [bool]$script:Settings.expert

$langFile = Join-Path $AppDir "lang\$($script:VxLang).json"
$script:Lang = ConvertTo-VxHashtable ([System.IO.File]::ReadAllText($langFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
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
    if ($Fmt) { try { $s = [string]::Format($s, $Fmt) } catch { } }
    return $s
}

# code that background jobs load before running
$coreText = New-Object System.Text.StringBuilder
foreach ($cf in $coreFiles) { [void]$coreText.AppendLine([System.IO.File]::ReadAllText((Join-Path $AppDir "core\$cf.ps1"), [System.Text.Encoding]::UTF8)) }
[void]$coreText.Insert(0, "`$ProgressPreference = 'SilentlyContinue'`n`$script:VxRoot = '$($Root -replace "'", "''")'`n")
[void]$coreText.AppendLine("Initialize-VxPaths '$($Root -replace "'", "''")'")
[void]$coreText.AppendLine("`$script:VxLang = '$($script:VxLang)'")
$script:CoreText = $coreText.ToString()
# background jobs dot-source this file once per runspace instead of re-parsing all the core code on every job
$coreHash = (([System.Security.Cryptography.SHA1]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script:CoreText))[0..7] | ForEach-Object { $_.ToString('x2') }) -join '')
$script:CoreFile = Join-Path $cacheDir "core_$coreHash.ps1"
try {
    if (-not (Test-Path -LiteralPath $script:CoreFile)) {
        Get-ChildItem -LiteralPath $cacheDir -Filter 'core_*.ps1' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($script:CoreFile, $script:CoreText, (New-Object System.Text.UTF8Encoding($true)))
    }
} catch { $script:CoreFile = $null }

$script:Version = '1.0.0'
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
$xamlText = Read-VxXaml 'MainWindow.xaml'
try {
    $script:Window = [Windows.Markup.XamlReader]::Parse($xamlText)
} catch {
    # safety net: if the new look cannot load on this PC, start with the previous, proven one
    Write-VxLog ("UI load failed, using the safe layout: " + $_.Exception.Message) 'ERROR'
    $xamlText = Read-VxXaml 'MainWindow.safe.xaml'
    $script:Window = [Windows.Markup.XamlReader]::Parse($xamlText)
}
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
$script:Window.Dispatcher.add_UnhandledException({
    param($s, $e)
    Write-VxLog ("UI error: " + $e.Exception.Message + ' ' + $e.Exception.StackTrace) 'ERROR'
    $e.Handled = $true
})

# ---------------------------------------------------------------- crash safety
function Show-VxFatal {
    param([string]$Message)
    Write-VxLog "FATAL: $Message" 'ERROR'
    try { [System.IO.File]::WriteAllText((Join-Path $script:VxLogs 'crash.log'), "$(Get-Date)`r`n$Message", [System.Text.Encoding]::UTF8) } catch { }
    [System.Windows.MessageBox]::Show("Piki Optimizer:`n`n$Message", 'Piki Optimizer', 'OK', 'Error') | Out-Null
}

# =====================================================================
#  BACKGROUND JOBS
# =====================================================================
$script:Sync = [hashtable]::Synchronized(@{ Step = ''; Pct = 0 })
$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$script:Pool = [runspacefactory]::CreateRunspacePool($iss)
[void]$script:Pool.SetMinRunspaces(2)
[void]$script:Pool.SetMaxRunspaces(4)
$script:Pool.Open()
$script:Jobs = New-Object System.Collections.ArrayList

function Start-VxJob {
    param([string]$Name, [scriptblock]$Script, [object[]]$Arguments = @(), [scriptblock]$OnDone, [scriptblock]$OnError)
    if ($script:JobTimer -and $script:JobTimer.Interval.TotalMilliseconds -gt 150) { $script:JobTimer.Interval = [TimeSpan]::FromMilliseconds(120) }
    $ps = [powershell]::Create()
    $ps.RunspacePool = $script:Pool
    # one single script: core functions + the job body invoked with the arguments
    # (AddStatement() on a RunspacePool can hang, so it is not used)
    $wrap = "`n`$__t0 = [DateTime]::Now`n`$__r = & {`n" + $Script.ToString() + "`n} @args`n" +
        "Write-VxLog ('job body: $Name ({0:N0} ms)' -f ([DateTime]::Now - `$__t0).TotalMilliseconds)`n,`$__r"
    if ($script:CoreFile) {
        $load = "try { [System.Threading.Thread]::CurrentThread.Priority = 'Lowest' } catch { }`n" +
            "if (-not (Get-Command Initialize-VxPaths -CommandType Function -ErrorAction SilentlyContinue)) { . '" + ($script:CoreFile -replace "'", "''") + "' }`n" +
            "`$script:VxAeCache = `$null; `$script:VxTx = `$null; `$script:VxNicRestart = `$false; `$script:VxBatch = `$null`n"
        [void]$ps.AddScript($load + $wrap)
    } else {
        [void]$ps.AddScript($script:CoreText + $wrap)
    }
    [void]$ps.AddArgument($script:Sync)
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    $job = @{ Name = $Name; PS = $ps; Handle = $ps.BeginInvoke(); OnDone = $OnDone; OnError = $OnError; Start = [DateTime]::Now }
    [void]$script:Jobs.Add($job)
    Write-VxLog "job start: $Name"
}

Start-VxJob -Name 'warmup' -Script { return $true }

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
#  UI HELPERS
# =====================================================================
function New-VxBrush { param([string]$Hex) return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))) }

# =====================================================================
#  MOTION SYSTEM: same durations and curves as the XAML tokens (DurFast/DurBase/DurSlow, EaseOut/EaseOutStrong)
#  Only opacity and transforms are animated (cheap for the GPU); widths only on small progress bars.
# =====================================================================
$script:EaseOut = New-Object System.Windows.Media.Animation.CubicEase
$script:EaseOut.EasingMode = 'EaseOut'; $script:EaseOut.Freeze()
$script:EaseOutStrong = New-Object System.Windows.Media.Animation.QuinticEase
$script:EaseOutStrong.EasingMode = 'EaseOut'; $script:EaseOutStrong.Freeze()
$script:OpacityP = [System.Windows.UIElement]::OpacityProperty

function New-VxAnim {
    param([double]$To, [int]$Ms, $From = $null, $Ease = $script:EaseOut)
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.To = $To
    if ($null -ne $From) { $a.From = [double]$From }
    $a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds($Ms))
    if ($Ease) { $a.EasingFunction = $Ease }
    if ($script:LiteMode) { [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($a, 60) }
    elseif ($script:MonitorFps -and $script:MonitorFps -ne $script:Fps) { [System.Windows.Media.Animation.Timeline]::SetDesiredFrameRate($a, $script:MonitorFps) }
    return $a
}

function Get-VxTransform {
    # returns the element's TranslateTransform or ScaleTransform, creating it if needed
    param($El, [string]$Kind = 'Translate')
    $type = if ($Kind -eq 'Scale') { [System.Windows.Media.ScaleTransform] } else { [System.Windows.Media.TranslateTransform] }
    if (-not ($El.RenderTransform -is $type) -or $El.RenderTransform.IsFrozen) {
        if ($El.RenderTransformOrigin.X -eq 0 -and $El.RenderTransformOrigin.Y -eq 0) { $El.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5) }
        $El.RenderTransform = New-Object $type
    }
    return $El.RenderTransform
}

# popups (dialog, busy, wizard), macOS style: they grow out of the button you clicked
# and, when closed, are sucked back towards it (height first, then width, like the "genie").
$script:EaseIn = New-Object System.Windows.Media.Animation.CubicEase
$script:EaseIn.EasingMode = 'EaseIn'; $script:EaseIn.Freeze()
$script:ClickPt = $null; $script:ClickAt = [DateTime]::MinValue

function Get-VxOverlayPanel {
    param($Grid)
    foreach ($c in $Grid.Children) { if ($c -is [System.Windows.FrameworkElement] -and $c.VerticalAlignment -eq 'Center') { return $c } }
    return $null
}

function Show-VxOverlay {
    param($Grid)
    $wasOpen = ($Grid.Visibility -eq 'Visible' -and $Grid.Tag -ne 'closing')
    $Grid.Tag = 'open'
    $Grid.Visibility = 'Visible'
    if ($wasOpen) { return }
    $Grid.BeginAnimation($script:OpacityP, (New-VxAnim 1 160 0))
    $panel = Get-VxOverlayPanel $Grid
    if (-not $panel) { return }
    $sc = Get-VxTransform $panel 'Scale'
    # origin = the point you just clicked (if the click was a moment ago), otherwise the centre
    $origin = New-Object System.Windows.Point(0.5, 0.5)
    if ($script:ClickPt -and ([DateTime]::Now - $script:ClickAt).TotalSeconds -lt 1.5) {
        try {
            $Grid.UpdateLayout()
            if ($panel.ActualWidth -gt 0 -and $panel.ActualHeight -gt 0) {
                $p = $ui.Root.TranslatePoint($script:ClickPt, $panel)
                $origin = New-Object System.Windows.Point(([math]::Max(-1, [math]::Min(2, $p.X / $panel.ActualWidth))), ([math]::Max(-1, [math]::Min(2, $p.Y / $panel.ActualHeight))))
            }
        } catch { }
    }
    $panel.RenderTransformOrigin = $origin
    $panel.CacheMode = New-Object System.Windows.Media.BitmapCache
    $pnl = $panel
    $ax = New-VxAnim 1 380 0.06 $script:EaseOutStrong
    $ax.add_Completed({ $pnl.CacheMode = $null }.GetNewClosure())
    $panel.BeginAnimation($script:OpacityP, (New-VxAnim 1 180 0))
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $ax)
    $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-VxAnim 1 340 0.06 $script:EaseOutStrong))
}

function Hide-VxOverlay {
    param($Grid)
    if ($Grid.Visibility -ne 'Visible' -or $Grid.Tag -eq 'closing') { return }
    $Grid.Tag = 'closing'
    $g = $Grid
    $panel = Get-VxOverlayPanel $Grid
    if ($panel) {
        $sc = Get-VxTransform $panel 'Scale'
        $panel.CacheMode = New-Object System.Windows.Media.BitmapCache
        # genie: the height collapses first, the width follows
        $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, (New-VxAnim 0.04 200 $null $script:EaseIn))
        $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-VxAnim 0.04 250 $null $script:EaseIn))
        $panel.BeginAnimation($script:OpacityP, (New-VxAnim 0 250 $null $script:EaseIn))
    }
    $a = New-VxAnim 0 260
    $p2 = $panel
    $a.add_Completed({ if ($g.Tag -eq 'closing') { $g.Visibility = 'Collapsed'; $g.Tag = $null }; if ($p2) { $p2.CacheMode = $null } }.GetNewClosure())
    $Grid.BeginAnimation($script:OpacityP, $a)
}

# progress bars glide to the new value instead of jumping
function Set-VxBarWidth {
    param($Bar, [double]$Width, [switch]$Instant)
    $Width = [math]::Max(0, $Width)
    if ($Instant) { $Bar.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, $null); $Bar.Width = $Width; $Bar.Tag = $Width; return }
    if ($Bar.Tag -is [double] -and [math]::Abs([double]$Bar.Tag - $Width) -lt 0.5) { return }
    $Bar.Tag = $Width
    $Bar.BeginAnimation([System.Windows.FrameworkElement]::WidthProperty, (New-VxAnim $Width 450))
}

# score numbers count up smoothly to the new value
function Start-VxCountUp {
    param($Label, [double]$From, [double]$To)
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(16)
    $start = [DateTime]::Now
    $lbl = $Label
    $t.add_Tick({
        $p = ([DateTime]::Now - $start).TotalMilliseconds / 800
        if ($p -ge 1) { $lbl.Text = [string][int]$To; $t.Stop(); return }
        $e = 1 - [math]::Pow(1 - $p, 4)
        $lbl.Text = [string][int][math]::Round($From + ($To - $From) * $e)
    }.GetNewClosure())
    $t.Start()
}

function Show-VxToast {
    param([string]$Text, [string]$Kind = 'ok')
    $ui.ToastText.Text = $Text
    switch ($Kind) {
        'crit' { $ui.ToastIcon.Text = [char]0xE783; $ui.ToastIcon.Foreground = New-VxBrush '#FF5D73' }
        'warn' { $ui.ToastIcon.Text = [char]0xE7BA; $ui.ToastIcon.Foreground = New-VxBrush '#FFB547' }
        'info' { $ui.ToastIcon.Text = [char]0xE946; $ui.ToastIcon.Foreground = New-VxBrush '#5AA9FF' }
        default { $ui.ToastIcon.Text = [char]0xE73E; $ui.ToastIcon.Foreground = New-VxBrush '#2ED47A' }
    }
    $ui.Toast.Tag = 'open'
    $ui.Toast.Visibility = 'Visible'
    $ui.Toast.BeginAnimation($script:OpacityP, (New-VxAnim 1 220 0))
    (Get-VxTransform $ui.Toast).BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-VxAnim 0 380 16 $script:EaseOutStrong))
    $script:ToastUntil = (Get-Date).AddSeconds([math]::Max(3.5, $Text.Length / 22))
}

function Hide-VxToast {
    if ($ui.Toast.Visibility -ne 'Visible') { return }
    $ui.Toast.Tag = 'closing'
    $a = New-VxAnim 0 220
    $a.add_Completed({ if ($ui.Toast.Tag -eq 'closing') { $ui.Toast.Visibility = 'Collapsed' } })
    $ui.Toast.BeginAnimation($script:OpacityP, $a)
    (Get-VxTransform $ui.Toast).BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-VxAnim 8 220))
}

function Show-VxBusy {
    param([string]$Title, [string]$Text = '')
    $script:Sync.Step = $Text; $script:Sync.Pct = 0
    $ui.BusyTitle.Text = $Title
    $ui.BusyText.Text = $Text
    Set-VxBarWidth $ui.BusyBar 0 -Instant
    # the spinner only turns while it is visible (no endless animation in the background)
    $spin = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 360, [TimeSpan]::FromSeconds(0.9))
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
    $prev = if ($Ellipse.Tag -is [double]) { [double]$Ellipse.Tag } else { 0 }
    if ([int]$prev -ne [int]$Value) {
        # the arc sweeps in from its start, the number counts up with it
        $prevLen = $circ * [math]::Min(100, $prev) / 100
        $Ellipse.BeginAnimation([System.Windows.Shapes.Shape]::StrokeDashOffsetProperty, (New-VxAnim 0 900 ([math]::Max(0, $len - $prevLen)) $script:EaseOutStrong))
        Start-VxCountUp $Label $prev $Value
    } else { $Label.Text = [string][int]$Value }
    $Ellipse.Tag = [double]$Value
    if ($Ellipse.Stroke -is [System.Windows.Media.SolidColorBrush]) {
        if ($Value -ge 80) { $Ellipse.Stroke = New-VxBrush '#2ED47A' } elseif ($Value -ge 55) { $Ellipse.Stroke = New-VxBrush '#FFB547' } else { $Ellipse.Stroke = New-VxBrush '#FF5D73' }
    }
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
$script:RenderMode = $null
$script:ProcLevels = @{ widgets = 1; edgeboost = 1; bgapps = 2; svchost = 3 }
$script:CurrentPage = 'Home'
$script:Remote = $null

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
        foreach ($it in $list) {
            $it.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'IsChecked') { Update-VxPendingBar } })
        }
    }
    Update-VxPendingBar
}

function Get-VxAllItems { return @($script:Lists.opt) + @($script:Lists.proc) + @($script:Lists.net) + @($script:Lists.ae) }

function Update-VxPendingBar {
    # many switches can change at once (presets): recount once, after the current frame
    if ($script:PendingQueued) { return }
    $script:PendingQueued = $true
    [void]$script:Window.Dispatcher.BeginInvoke([Action] { $script:PendingQueued = $false; Update-VxPendingBarNow }, [System.Windows.Threading.DispatcherPriority]::Loaded)
}

function Update-VxPendingBarNow {
    $dirty = New-Object System.Collections.Generic.List[object]
    foreach ($list in @($script:Lists.opt, $script:Lists.proc, $script:Lists.net, $script:Lists.ae)) { foreach ($it in @($list)) { if ($it -and $it.IsDirty) { $dirty.Add($it) } } }
    if ($dirty.Count -gt 0) {
        $on = 0; foreach ($d in $dirty) { if ($d.IsChecked) { $on++ } }
        $off = $dirty.Count - $on
        $txt = T 'pending.count' @($dirty.Count)
        if ($off -gt 0) { $txt += '  ·  ' + (T 'pending.detail' @($on, $off)) }
        $ui.PendingText.Text = $txt
        if ($ui.PendingBar.Visibility -ne 'Visible' -or $ui.PendingBar.Tag -eq 'closing') {
            $ui.PendingBar.Tag = 'open'
            $ui.PendingBar.Visibility = 'Visible'
            $ui.PendingBar.BeginAnimation($script:OpacityP, (New-VxAnim 1 220 0))
            (Get-VxTransform $ui.PendingBar).BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-VxAnim 0 420 28 $script:EaseOutStrong))
        }
    } elseif ($ui.PendingBar.Visibility -eq 'Visible' -and $ui.PendingBar.Tag -ne 'closing') {
        $ui.PendingBar.Tag = 'closing'
        $a = New-VxAnim 0 200
        $a.add_Completed({ if ($ui.PendingBar.Tag -eq 'closing') { $ui.PendingBar.Visibility = 'Collapsed' } })
        $ui.PendingBar.BeginAnimation($script:OpacityP, $a)
        (Get-VxTransform $ui.PendingBar).BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-VxAnim 18 200))
    }
}

function Invoke-VxApplyItems {
    param([string[]]$ApplyIds, [string[]]$RevertIds, [bool]$RestorePoint, [string]$Title, [scriptblock]$After)
    if ($ApplyIds.Count -eq 0 -and $RevertIds.Count -eq 0) { return }
    Show-VxBusy $Title (T 'busy.preparing')
    $script:AfterApply = $After
    Start-VxJob -Name 'apply' -Arguments @($script:Hw, [string[]]$ApplyIds, [string[]]$RevertIds, $RestorePoint) -Script {
        param($Sync, $Hw, $ApplyIds, $RevertIds, $Rp)
        $res = @{ ok = 0; failed = @(); reboot = $false; noUndo = 0; reverted = 0; rp = $null }
        $total = [math]::Max(1, $ApplyIds.Count + $RevertIds.Count)
        $i = 0
        if ($Rp) { $Sync.Step = (L @{ it = 'Creo un punto di ripristino...'; en = 'Creating a restore point...' }); $res.rp = New-VxRestorePoint 'VeloxPC' }
        # the power plan goes first: settings stored in the plan must land in the new plan
        $ApplyIds = @(@($ApplyIds | Where-Object { $_ -eq 'powerplan' }) + @($ApplyIds | Where-Object { $_ -ne 'powerplan' }))
        Start-VxBatch
        try {
        foreach ($id in $ApplyIds) {
            $i++; $Sync.Pct = [int](100 * $i / $total)
            if ($id -like 'svc:*') {
                $name = $id.Substring(4)
                $e = $script:VxServices | Where-Object { $_.Name -eq $name -or ($_.Pattern -and $name -like $_.Pattern) } | Select-Object -First 1
                if (-not $e) { continue }
                $Sync.Step = L $e.Title
                if (Set-VxServiceOptimized -Name $name -Target $e.Target -Title (L $e.Title)) { $res.ok++ } else { $res.failed += (L $e.Title) }
            } else {
                $t = Find-VxTweak $id
                if (-not $t) { continue }
                $Sync.Step = L $t.Title
                $r = Invoke-VxTweak $t $Hw
                if ($r.ok) { $res.ok++; if ($t.Reboot) { $res.reboot = $true } } else { $res.failed += ((L $t.Title) + ': ' + $r.error) }
            }
        }
        foreach ($id in $RevertIds) {
            $i++; $Sync.Pct = [int](100 * $i / $total)
            $Sync.Step = (L @{ it = 'Ripristino: '; en = 'Restoring: ' }) + $id
            if (Test-VxBackupEntry $id) {
                [void](Undo-VxEntry $id); $res.reverted++
                $t = Find-VxTweak $id
                if ($t -and $t.Reboot) { $res.reboot = $true }
            } else { $res.noUndo++ }
        }
        [void](Repair-VxLostTweaks $Hw)
        } finally { Stop-VxBatch }
        return $res
    } -OnDone {
        param($r)
        Hide-VxBusy
        $msg = T 'apply.done' @($r.ok, $r.reverted)
        if ($r.noUndo -gt 0) { $msg += "`n" + (T 'apply.noundo' @($r.noUndo)) }
        if ($r.failed.Count -gt 0) { $msg += "`n`n" + (T 'apply.failed') + "`n- " + ($r.failed -join "`n- ") }
        if ($r.rp -eq $false) { $msg += "`n`n" + (T 'apply.norp') }
        if ($r.reboot) {
            $msg += "`n`n" + (T 'apply.reboot')
            Show-VxDialog -Title (T 'apply.title') -Text $msg -YesText (T 'common.rebootnow') -NoText (T 'common.later') -OnYes { Restart-Computer -Force }
        } else {
            Show-VxDialog -Title (T 'apply.title') -Text $msg -YesText 'OK'
        }
        Update-VxStates
        if ($script:AfterApply) { & $script:AfterApply }
    }
}

function Invoke-VxPendingApply {
    $dirty = @(Get-VxAllItems | Where-Object { $_.IsDirty })
    $apply = @($dirty | Where-Object { $_.IsChecked } | ForEach-Object { $_.Id })
    $revert = @($dirty | Where-Object { -not $_.IsChecked } | ForEach-Object { $_.Id })
    Invoke-VxApplyItems -ApplyIds $apply -RevertIds $revert -RestorePoint ([bool]$ui.ChkRestorePoint.IsChecked) -Title (T 'busy.applying')
}

function Update-VxStates {
    param([scriptblock]$Then)
    $script:AfterStates = $Then
    Start-VxJob -Name 'states' -Arguments @($script:Hw) -Script {
        param($Sync, $Hw)
        try { [void](Repair-VxLostTweaks $Hw) } catch { }
        return @{ states = (Get-VxTweakStates $Hw); services = @(Get-VxServiceRows $Hw) }
    } -OnDone {
        param($r)
        $script:States = $r.states
        $script:SvcRows = @($r.services)
        try { Write-VxJson 'cache\states.json' $r.states } catch { }
        Update-VxOptionLists
        Update-VxHome
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
#  HOME
# =====================================================================

function Update-VxHwCards {
    $hw = $script:Hw
    $cards = @()
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xE9D9; $c.Label = T 'hw.cpu'; $c.Title = $hw.CPU.Name
    $c.Sub = T 'hw.cpu.sub' @($hw.CPU.Cores, $hw.CPU.Threads); $c.Detail = if ($hw.CPU.MaxMHz) { ('{0:N1} GHz ' -f ($hw.CPU.MaxMHz / 1000)) + (T 'hw.base') } else { '' }; $cards += $c
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xE7F4; $c.Label = T 'hw.gpu'
    if ($hw.GPU) { $c.Title = $hw.GPU.Name; $c.Sub = if ($hw.GPU.VramBytes -gt 0) { '{0} GB VRAM' -f [math]::Round($hw.GPU.VramBytes / 1GB) } else { '' }; $c.Detail = (T 'hw.driver') + ' ' + $(if ($hw.GPU.NvidiaVersion) { $hw.GPU.NvidiaVersion } else { $hw.GPU.DriverVersion }) } else { $c.Title = T 'hw.unknown' }
    $cards += $c
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xE950; $c.Label = 'RAM'; $c.Title = "$($hw.RAM.GB) GB $($hw.RAM.Type)"
    $c.Sub = if ($hw.RAM.SpeedMTs) { "$($hw.RAM.SpeedMTs) MT/s" + $(if ($hw.RAM.KitMTs -gt $hw.RAM.SpeedMTs) { ' ' + (T 'hw.ram.kit' @($hw.RAM.KitMTs)) } else { '' }) } else { '' }
    $c.Detail = (T 'hw.ram.modules' @($hw.RAM.Modules)) + $(if ($hw.RAM.Modules -ge 2) { ' · Dual channel' } elseif ($hw.RAM.Modules -eq 1) { ' · Single channel' } else { '' }); $cards += $c
    $sys = @($hw.Disks | Where-Object { $_.IsSystem }) | Select-Object -First 1
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xEDA2; $c.Label = T 'hw.disk'
    if ($sys) { $c.Title = $sys.Name; $c.Sub = "$($sys.Media) $($sys.Bus) · " + ('{0:N0} GB' -f ($sys.SizeBytes / 1GB)) } else { $c.Title = '-' }
    $c.Detail = T 'hw.disk.count' @($hw.Disks.Count); $cards += $c
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xE7F4; $c.Label = T 'hw.screen'
    $d = @($hw.Displays | Where-Object { $_.Primary }) | Select-Object -First 1
    if (-not $d) { $d = @($hw.Displays) | Select-Object -First 1 }
    if ($d) { $c.Title = "$($d.Width) x $($d.Height) · $($d.CurrentHz) Hz"; $c.Sub = (T 'hw.screen.max' @($d.MaxHz)); $c.Detail = $d.Monitor } else { $c.Title = '-' }
    $cards += $c
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xE968; $c.Label = T 'hw.net'
    if ($hw.Network) { $c.Title = if ($hw.Network.IsWifi) { 'Wi-Fi' } else { 'Ethernet' }; $c.Sub = $hw.Network.LinkSpeed; $c.Detail = $hw.Network.Description } else { $c.Title = T 'hw.offline' }
    $cards += $c
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xE964; $c.Label = T 'hw.board'; $c.Title = if ($hw.Board.Name) { $hw.Board.Name } else { $hw.Model }
    $c.Sub = if ($hw.Board.Bios) { "BIOS $($hw.Board.Bios)" } else { '' }
    $c.Detail = [string]$hw.Board.BiosDate; $cards += $c
    $c = New-Object VeloxPC.HwCard; $c.Glyph = [string][char]0xE7F8; $c.Label = 'Windows'; $c.Title = $hw.OS.Name
    $c.Sub = "$($hw.OS.DisplayVersion) · build $($hw.OS.Build).$($hw.OS.Ubr)"; $c.Detail = if ($hw.IsLaptop) { T 'hw.laptop' } else { T 'hw.desktop' }; $cards += $c
    Set-VxItems $ui.HwList $cards
}

function New-VxFindingObj {
    param($F)
    $o = New-Object VeloxPC.Finding
    $o.Severity = $F.sev; $o.Title = $F.title; $o.Detail = $F.detail
    $o.ActionId = $F.action; $o.ActionLabel = $F.actionLabel; $o.Category = $F.cat
    return $o
}

function Get-VxPerfScore {
    if (-not $script:Hw -or $script:States.Count -eq 0) { return -1 }
    $profile = if ($script:Settings.profile) { $script:Settings.profile } else { if ($script:Hw.IsLaptop) { 'laptop' } else { 'gaming' } }
    $sel = @(Get-VxPresetSelection -Preset $profile -Hw $script:Hw -States $script:States)
    $applied = @($sel | Where-Object { $script:States[$_].applied }).Count
    $ratio = if ($sel.Count -gt 0) { $applied / $sel.Count } else { 1 }
    $cfgIssues = 0
    if ($script:Health) { $cfgIssues = @($script:Health.findings | Where-Object { $_.cat -in @('perf', 'memory') -and $_.sev -in @('warn', 'crit') }).Count }
    return [int][math]::Round(25 + 55 * $ratio + 20 * [math]::Max(0, 1 - $cfgIssues / 4))
}

function Update-VxHome {
    if (-not $script:Hw) { return }
    $hs = -1
    if ($script:Health) { $hs = [int]$script:Health.score }
    Set-VxRing $ui.RingHealth $ui.RingHealthText $hs 118 11
    $ps = Get-VxPerfScore
    Set-VxRing $ui.RingPerf $ui.RingPerfText $ps 118 11
    $issues = 0
    if ($script:Health) { $issues = [int]$script:Health.crit + [int]$script:Health.warn }
    if ($hs -lt 0) { $ui.HomeStatus.Text = T 'home.status.unknown'; $ui.HomeStatusSub.Text = T 'home.status.unknown.sub' }
    elseif ($issues -eq 0 -and $ps -ge 85) { $ui.HomeStatus.Text = T 'home.status.great'; $ui.HomeStatusSub.Text = T 'home.status.great.sub' }
    elseif ($issues -eq 0) { $ui.HomeStatus.Text = T 'home.status.healthy'; $ui.HomeStatusSub.Text = T 'home.status.healthy.sub' }
    else { $ui.HomeStatus.Text = T 'home.status.issues' @($issues); $ui.HomeStatusSub.Text = T 'home.status.issues.sub' }
    # advice
    $adv = @()
    if ($script:Health) {
        $rank = @{ crit = 0; warn = 1; info = 2; ok = 3 }
        $adv += @($script:Health.findings | Where-Object { $_.sev -ne 'ok' } | Sort-Object @{ Expression = { $rank[$_.sev] } } | Select-Object -First 5 | ForEach-Object { New-VxFindingObj $_ })
    }
    if ($ps -ge 0 -and $ps -lt 85) {
        $f = New-Object VeloxPC.Finding; $f.Severity = 'info'; $f.Title = T 'home.adv.tweaks'; $f.Detail = T 'home.adv.tweaks.sub'; $f.ActionId = 'oneclick'; $f.ActionLabel = T 'home.oneclick'
        $adv = @($f) + $adv
    }
    if ($adv.Count -eq 0) { $f = New-Object VeloxPC.Finding; $f.Severity = 'ok'; $f.Title = T 'home.adv.none'; $f.Detail = T 'home.adv.none.sub'; $adv += $f }
    Set-VxItems $ui.HomeAdvice $adv
    # sidebar badge
    $n = 0; if ($script:Health) { $n = [int]$script:Health.crit + [int]$script:Health.warn }
    if ($n -gt 0) { $ui.HealthBadgeText.Text = [string]$n; $ui.HealthBadge.Visibility = 'Visible' } else { $ui.HealthBadge.Visibility = 'Collapsed' }
}

# =====================================================================
#  HEALTH
# =====================================================================
function Update-VxHealthPage {
    $h = $script:Health
    if (-not $h) { return }
    Set-VxRing $ui.RingHealth2 $ui.RingHealth2Text ([int]$h.score) 104 10
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
        $map = @{ cleanup = 'Cleanup'; processes = 'Processes'; network = 'Network'; optimize = 'Optimize'; ae = 'Ae' }
        Show-VxPage $map[$Action.Substring(5)]; return
    }
    if ($Action -like 'open:*') {
        $hwv = if ($script:Hw.GPU) { $script:Hw.GPU.Vendor } else { '' }
        $gpuUrl = switch ($hwv) { 'NVIDIA' { 'https://www.nvidia.com/software/nvidia-app/' } 'AMD' { 'https://www.amd.com/support/download/drivers.html' } 'Intel' { 'https://www.intel.com/content/www/us/en/support/detect.html' } default { 'ms-settings:windowsupdate' } }
        $map = @{ windowsupdate = 'ms-settings:windowsupdate'; security = 'windowsdefender:'; devmgr = 'devmgmt.msc'; gpudriver = $gpuUrl; display = 'ms-settings:display-advanced' }
        Open-VxTarget $map[$Action.Substring(5)]; return
    }
    if ($Action -eq 'restart') {
        Show-VxDialog -Title (T 'fix.restart.q') -Text (T 'fix.restart.text') -YesText (T 'common.rebootnow') -NoText (T 'common.cancel') -OnYes { Restart-Computer -Force }
        return
    }
    if ($Action -eq 'fix:bios') {
        Show-VxDialog -Title (T 'fix.bios.q') -Text (T 'fix.bios.text') -YesText (T 'fix.bios.yes') -NoText (T 'common.cancel') -OnYes { Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList '/r /fw /t 5' -WindowStyle Hidden }
        return
    }
    if ($Action -like 'fix:*') {
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
#  WIZARD (one click)
# =====================================================================
function Show-VxWizard {
    if (-not $script:Hw -or $script:States.Count -eq 0) { Show-VxToast (T 'common.wait') 'info'; return }
    foreach ($n in @('WizMax', 'WizGaming', 'WizCompetitive', 'WizCreator', 'WizBalanced', 'WizLaptop')) { if ($ui[$n]) { $ui[$n].IsChecked = $false } }
    $ui.WizSummary.Text = T 'wiz.pick'; $ui.WizDetail.Text = ''
    $ui.WizGo.IsEnabled = $false
    $script:WizPreset = $null
    Show-VxOverlay $ui.WizardOverlay
}

function Get-VxWizardPlan {
    param([string]$Preset)
    $sel = @(Get-VxPresetSelection -Preset $Preset -Hw $script:Hw -States $script:States | Where-Object { -not $script:States[$_].applied })
    $level = if ($Preset -eq 'max') { 2 } else { 1 }
    $svc = @($script:SvcRows | Where-Object { $_.Entry.Level -ge 1 -and $_.Entry.Level -le $level -and -not $_.Need -and -not $_.Applied } | ForEach-Object { $_.Id })
    return @{ tweaks = $sel; services = $svc }
}

function Update-VxWizardSummary {
    param([string]$Preset)
    $script:WizPreset = $Preset
    $plan = Get-VxWizardPlan $Preset
    $n = $plan.tweaks.Count + $plan.services.Count
    if ($n -eq 0) { $ui.WizSummary.Text = T 'wiz.nothing'; $ui.WizDetail.Text = ''; $ui.WizGo.IsEnabled = $false; return }
    $ui.WizSummary.Text = T 'wiz.summary' @($plan.tweaks.Count, $plan.services.Count)
    $names = @()
    foreach ($id in ($plan.tweaks | Select-Object -First 8)) { $t = Find-VxTweak $id; if ($t) { $names += (L $t.Title) } }
    $more = $plan.tweaks.Count - $names.Count
    $ui.WizDetail.Text = ($names -join ' · ') + $(if ($more -gt 0) { ' · ' + (T 'wiz.more' @($more)) } else { '' })
    $ui.WizGo.IsEnabled = $true
}

# =====================================================================
#  PROCESSES PAGE
# =====================================================================
function Update-VxProcStats {
    Start-VxJob -Name 'counts' -Script {
        param($Sync)
        $c = Get-VxSystemCounts
        $c.Startup = @(Get-VxStartupItems | Where-Object { $_.Enabled }).Count
        $m = [VeloxPC.Native]::Memory()
        $c.Ram = [int]$m[0]
        return $c
    } -OnDone {
        param($r)
        $ui.StatProcs.Text = [string]$r.Processes
        $ui.StatSvcs.Text = [string]$r.Services
        $ui.StatStartup.Text = [string]$r.Startup
        $ui.StatRam.Text = "$($r.Ram)%"
    }
}

function Update-VxStartupList {
    Start-VxJob -Name 'startup' -Script { param($Sync) return @{ items = @(Get-VxStartupItems) } } -OnDone {
        param($r)
        $script:StartupRaw = @($r.items)
        $items = @()
        foreach ($s in $script:StartupRaw) {
            $o = New-Object VeloxPC.OptionItem
            $o.Id = $s.Id; $o.Kind = 'startup'; $o.Tag = $s
            $o.Title = $s.Name
            $o.Description = L $s.Advice.A
            $o.Risk = $s.Advice.Risk; $o.RiskLabel = Get-VxRiskLabel $s.Advice.Risk
            $o.IsChecked = [bool]$s.Enabled; $o.IsApplied = [bool]$s.Enabled
            $o.IsSelectable = ($s.Advice.Risk -ne 'avoid') -or (-not $s.Enabled)
            $o.Status = if ($s.Enabled) { T 'startup.on' } else { T 'startup.off' }
            $o.Extra = [string]$s.Command
            $items += $o
        }
        $script:StartupSuppress = $true
        Set-VxItems $ui.StartupList $items
        $script:StartupSuppress = $false
    }
}

function Update-VxProcList {
    $ui.BtnProcRefresh.IsEnabled = $false
    Start-VxJob -Name 'procs' -Script { param($Sync) return @{ groups = @(Get-VxProcessGroups) } } -OnDone {
        param($r)
        $ui.BtnProcRefresh.IsEnabled = $true
        $rows = @()
        foreach ($g in @($r.groups | Select-Object -First 120)) {
            $o = New-Object VeloxPC.ProcRow
            $o.Name = $g.Name
            $o.Count = $g.Count
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
        $script:ProcRows = $rows
        Set-VxItems $ui.ProcList $rows
    }
}

function Invoke-VxBoost {
    param([switch]$Silent)
    Show-VxBusy (T 'boost.title') (T 'busy.wait')
    Start-VxJob -Name 'boost' -Script {
        param($Sync)
        $before = ([VeloxPC.Native]::Memory())[2]
        $closed = @()
        foreach ($g in @(Get-VxProcessGroups)) {
            if ($g.Risk -eq 'safe' -and $g.Name -notin @('Spotify', 'AnyDesk')) {
                if ((Stop-VxProcessGroup $g.Name) -gt 0) { $closed += $g.Name }
            }
        }
        Start-Sleep -Milliseconds 600
        [void][VeloxPC.Native]::PurgeStandbyList()
        $after = ([VeloxPC.Native]::Memory())[2]
        return @{ closed = $closed; freed = [math]::Max(0, $after - $before) }
    } -OnDone {
        param($r)
        Hide-VxBusy
        $list = if ($r.closed.Count -gt 0) { ($r.closed -join ', ') } else { T 'boost.none' }
        Show-VxDialog -Title (T 'boost.done') -Text (T 'boost.text' @((Format-VxBytes $r.freed), $list)) -YesText 'OK'
        if ($script:Loaded.Processes) { Update-VxProcList; Update-VxProcStats }
    }
}

# =====================================================================
#  NETWORK PAGE
# =====================================================================
$script:PingColors = @('#22D3EE', '#7C5CFF', '#2ED47A', '#FFB547', '#FF5D73')

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
    # ping rows
    $targets = Get-VxPingTargets $hw
    $prow = @(); $k = 0
    foreach ($t in $targets) { $p = New-Object VeloxPC.PingRow; $p.Label = L $t.Label; $p.Host = $t.Host; $p.Color = $script:PingColors[$k % 5]; $prow += $p; $k++ }
    $script:PingRowsData = $prow
    Set-VxItems $ui.PingRows $prow
}

function Start-VxPingTest {
    $hosts = [string[]]@($script:PingRowsData | ForEach-Object { $_.Host })
    $script:Pinger = New-Object VeloxPC.PingRunner -ArgumentList (, $hosts)
    $script:Pinger.Start(40, 250)
    $ui.BtnPingTest.IsEnabled = $false
    $ui.PingCanvas.Children.Clear()
    $script:PingLines = @()
    for ($i = 0; $i -lt $hosts.Count; $i++) {
        $pl = New-Object System.Windows.Shapes.Polyline
        $pl.Stroke = New-VxBrush $script:PingColors[$i % 5]
        $pl.StrokeThickness = 2; $pl.StrokeLineJoin = 'Round'
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
        $color = switch ($g[1]) { 'ok' { '#2ED47A' } 'warn' { '#FFB547' } 'crit' { '#FF5D73' } default { '#8E96AB' } }
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
        $rows = @()
        $best = $null
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
#  AFTER EFFECTS PAGE
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
        $ui.AeNoInstall.Visibility = if ($script:Lists.ae.Count -eq 0) { 'Visible' } else { 'Collapsed' }
    }
}

function Switch-VxRenderMode {
    if (-not $script:RenderMode) {
        $rm = @{ prev = (Get-VxActiveScheme); closed = @() }
        if ($rm.prev -and $rm.prev.guid -ne '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' -and $rm.prev.name -notmatch 'VeloxPC') { & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null }
        [VeloxPC.Native]::KeepAwake($true)
        foreach ($n in @('Widgets', 'WidgetService', 'PhoneExperienceHost', 'YourPhone', 'GameBar', 'GameBarFTServer', 'Copilot', 'Overwolf', 'OverwolfBrowser', 'Medal', 'wallpaper32', 'wallpaper64', 'webwallpaper32')) {
            if ((Stop-VxProcessGroup $n) -gt 0) { $rm.closed += $n }
        }
        foreach ($p in @(Get-Process -Name 'AfterFX', 'aerender', 'Adobe Media Encoder' -ErrorAction SilentlyContinue)) { try { $p.PriorityClass = 'High' } catch { } }
        try { [void][VeloxPC.Native]::PurgeStandbyList() } catch { }
        $script:RenderMode = $rm
        $ui.BtnRenderMode.Content = T 'ae.render.off'
        $ui.RenderModeStatus.Text = T 'ae.render.status' @($(if ($rm.closed.Count) { $rm.closed -join ', ' } else { '-' }))
        Write-VxLog 'Render mode ON'
    } else {
        $rm = $script:RenderMode
        if ($rm.prev -and $rm.prev.guid) { & powercfg /setactive $rm.prev.guid 2>&1 | Out-Null }
        [VeloxPC.Native]::KeepAwake($false)
        $script:RenderMode = $null
        $ui.BtnRenderMode.Content = T 'ae.render.on'
        $ui.RenderModeStatus.Text = T 'ae.render.offstatus'
        Write-VxLog 'Render mode OFF'
    }
}

# =====================================================================
#  CLEANUP PAGE
# =====================================================================
function Start-VxCleanScan {
    $ui.BtnCleanScan.IsEnabled = $false
    $ui.CleanTotal.Text = T 'clean.scanning'
    Start-VxJob -Name 'cleanscan' -Script { param($Sync) return @{ sizes = (Get-VxCleanSizes) } } -OnDone {
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
            $o.IsChecked = [bool]$c.Default -and $o.Size -gt 0
            $o.add_PropertyChanged({ param($s, $e) if ($e.PropertyName -eq 'IsChecked') { Update-VxCleanTotal } })
            $items += $o
        }
        $script:CleanItems = $items
        Set-VxItems $ui.CleanList $items
        Update-VxCleanTotal
    }
}

function Update-VxCleanTotal {
    $sum = [int64]0
    foreach ($i in $script:CleanItems) { if ($i.IsChecked) { $sum += $i.Size } }
    $ui.CleanTotal.Text = Format-VxBytes $sum
    $ui.BtnCleanRun.IsEnabled = ($sum -gt 0)
}

# =====================================================================
#  RESTORE PAGE
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
}

function Invoke-VxUndo {
    param([string[]]$Ids)
    Show-VxBusy (T 'busy.restoring') (T 'busy.wait')
    Start-VxJob -Name 'undo' -Arguments @(, [string[]]$Ids) -Script {
        param($Sync, $Ids)
        $n = 0; $i = 0
        foreach ($id in $Ids) { $i++; $Sync.Pct = [int](100 * $i / [math]::Max(1, $Ids.Count)); $Sync.Step = $id; if (Undo-VxEntry $id) { $n++ } }
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

# =====================================================================
#  UPDATES
# =====================================================================
function Start-VxUpdateCheck {
    param([switch]$Manual)
    $script:UpdManual = [bool]$Manual
    if ($Manual) { $ui.UpdateStatus.Text = T 'update.checking' }
    Start-VxJob -Name 'updcheck' -Script { param($Sync) return (Get-VxRemoteManifest) } -OnDone {
        param($r)
        $script:Remote = $r
        $rv = [string]$r.manifest.version
        if (Test-VxNewer $rv $script:Version) {
            $notes = ''
            try { $notes = L (ConvertTo-VxHashtable $r.manifest.notes) } catch { }
            $ui.UpdateBannerText.Text = T 'update.available' @($rv, $notes)
            $ui.UpdateBanner.Visibility = 'Visible'
            $ui.UpdateStatus.Text = T 'update.available' @($rv, '')
            Show-VxUpdateNotice $rv $notes
        } else {
            if ($script:UpdManual) { $ui.UpdateStatus.Text = T 'update.latest' @($script:Version) }
        }
    } -OnError {
        param($e)
        if ($script:UpdManual) { $ui.UpdateStatus.Text = T 'update.offline' }
    }
}

# Windows notification (bottom-right) once per new version, also while the app sits in the tray
function Show-VxUpdateNotice {
    param([string]$Ver, [string]$Notes)
    if ($script:NotifiedVer -eq $Ver) { return }
    $script:NotifiedVer = $Ver
    try {
        if (-not $script:TrayIcon) { Update-VxTrayIcon }
        if (-not $script:TrayIcon) { return }
        if (-not $script:TrayIcon.Visible) {
            # tray icon turned off: show it just for the notification
            $script:TrayIcon.Visible = $true
            $script:TrayTempTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:TrayTempTimer.Interval = [TimeSpan]::FromSeconds(15)
            $script:TrayTempTimer.add_Tick({ $script:TrayTempTimer.Stop(); if (-not $script:Settings.tray -and $script:TrayIcon) { $script:TrayIcon.Visible = $false } })
            $script:TrayTempTimer.Start()
        }
        $text = T 'update.notify.text' @($Ver)
        if ($Notes) { $text += "`n" + $Notes }
        if ($text.Length -gt 250) { $text = $text.Substring(0, 247) + '...' }
        $script:BalloonKind = 'update'
        $script:TrayIcon.ShowBalloonTip(10000, (T 'update.notify.title'), $text, 'Info')
        Write-VxLog "update notice shown: $Ver"
    } catch { Write-VxLog "update notice: $($_.Exception.Message)" 'WARN' }
    if ($script:Window.IsVisible) { Show-VxToast (T 'update.notify.title') 'info' }
}

function Start-VxUpdate {
    # always re-reads the latest version first (never installs from an old check)
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
        if ($r.latest) {
            $ui.UpdateStatus.Text = T 'update.latest' @($script:Version)
            Show-VxToast (T 'update.latest' @($script:Version)) 'info'
            return
        }
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
#  GLASS EFFECT (Windows 11 acrylic)
# =====================================================================
function Enable-VxGlass {
    if (-not $script:Settings.glass) { return }
    try {
        $build = [Environment]::OSVersion.Version.Build
        if ($build -lt 22621) { return }
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($script:Window)).Handle
        $src = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
        $src.CompositionTarget.BackgroundColor = [System.Windows.Media.Colors]::Transparent
        $hr = [VeloxPC.Native]::EnableBackdrop($hwnd, 3)
        if ($hr -ne 0) { Write-VxLog "glass: backdrop hr=$hr" 'WARN'; return }
        $script:Window.Background = [System.Windows.Media.Brushes]::Transparent
        $ui.Root.Background = New-VxBrush '#AD07090F'
        $ui.Blobs.Opacity = 0.72
        $script:GlassOn = $true
        Write-VxLog 'glass: acrylic on'
    } catch { Write-VxLog "glass: $($_.Exception.Message)" 'WARN' }
}

# desktop icon created automatically the first time (not recreated if the user deletes it)
function Ensure-VxDesktopIcon {
    if ($script:Settings.shortcutDone) { return }
    try {
        $desk = [Environment]::GetFolderPath('Desktop')
        $lnkPath = Join-Path $desk 'Piki Optimizer.lnk'
        if (-not (Test-Path -LiteralPath $lnkPath)) {
            $sh = New-Object -ComObject WScript.Shell
            $lnk = $sh.CreateShortcut($lnkPath)
            $lnk.TargetPath = Join-Path $Root 'Avvia Piki Optimizer.cmd'
            $lnk.WorkingDirectory = $Root
            $lnk.WindowStyle = 7
            $lnk.IconLocation = Get-VxIconPath
            $lnk.Description = 'Piki Optimizer'
            $lnk.Save()
        }
        $script:Settings.shortcutDone = $true
        Save-VxSettings $script:Settings
    } catch { Write-VxLog "shortcut: $($_.Exception.Message)" 'WARN' }
}

# =====================================================================
#  LOOK (logo / background), TRAY, AUTOSTART
# =====================================================================
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
    # centre-cropped square bitmap of an image, scaled to $Size
    param([string]$Path, [int]$Size)
    $src = Get-VxBitmap $Path 0
    $side = [math]::Min($src.PixelWidth, $src.PixelHeight)
    $rect = New-Object System.Windows.Int32Rect([int](($src.PixelWidth - $side) / 2), [int](($src.PixelHeight - $side) / 2), $side, $side)
    $crop = New-Object System.Windows.Media.Imaging.CroppedBitmap($src, $rect)
    $scale = New-Object System.Windows.Media.ScaleTransform(($Size / $side), ($Size / $side))
    return (New-Object System.Windows.Media.Imaging.TransformedBitmap($crop, $scale))
}

function Save-VxIco {
    # writes a PNG-compressed .ico (Windows Vista+) from an image
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
    # logo
    $logo = Get-VxCustomPath 'logo'
    if ($logo) {
        try {
            $b = New-Object System.Windows.Media.ImageBrush (New-VxSquare $logo 256)
            $b.Stretch = 'UniformToFill'
            $ui.LogoCustom.Background = $b; $ui.LogoCustom.Visibility = 'Visible'; $ui.LogoDefault.Visibility = 'Collapsed'
            $ui.SplashLogoCustom.Background = $b; $ui.SplashLogoCustom.Visibility = 'Visible'
            $ico = Join-Path $script:CustomDir 'logo.ico'
            if (-not (Test-Path -LiteralPath $ico)) { Save-VxIco $logo $ico }
        } catch { Write-VxLog "logo: $($_.Exception.Message)" 'WARN' }
    } else {
        $ui.LogoCustom.Visibility = 'Collapsed'; $ui.LogoDefault.Visibility = 'Visible'; $ui.SplashLogoCustom.Visibility = 'Collapsed'
    }
    try { $script:Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri (Get-VxIconPath))) } catch { }
    # background
    $bg = Get-VxCustomPath 'bg'
    if ($bg) {
        try {
            $ui.BgImage.Source = Get-VxBitmap $bg 2560
            $lv = [int]$script:Settings.bgLevel; if ($lv -lt 1) { $lv = 2 }
            $ui.BgImage.Opacity = @(0, 0.18, 0.32, 0.5)[$lv]
            $ui.BgImage.Visibility = 'Visible'
            $ui.Sidebar.Background = New-VxBrush '#990E111B'
            $ui["BgLevel$lv"].IsChecked = $true
        } catch { Write-VxLog "bg: $($_.Exception.Message)" 'WARN' }
    } else {
        $ui.BgImage.Visibility = 'Collapsed'; $ui.BgImage.Source = $null
        $ui.Sidebar.Background = New-VxBrush '#A60E111B'
    }
    Update-VxTrayIcon
}

function Select-VxImage {
    param([string]$Kind)
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Immagini|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|*.*|*.*'
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

# ---- notification area icon
$script:TrayIcon = $null
function Update-VxTrayIcon {
    try {
        if (-not $script:TrayIcon) {
            $ni = New-Object System.Windows.Forms.NotifyIcon
            $ni.Text = 'Piki Optimizer'
            $menu = New-Object System.Windows.Forms.ContextMenuStrip
            $miOpen = $menu.Items.Add((T 'tray.open')); $miOpen.add_Click({ Show-VxFromTray })
            $miBoost = $menu.Items.Add((T 'tray.boost')); $miBoost.add_Click({ Show-VxFromTray; Invoke-VxBoost })
            $miRender = $menu.Items.Add((T 'tray.render')); $miRender.add_Click({ Switch-VxRenderMode; Show-VxToast $ui.RenderModeStatus.Text 'info' })
            [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
            $miExit = $menu.Items.Add((T 'tray.exit')); $miExit.add_Click({ $script:ReallyExit = $true; $script:Window.Close() })
            $ni.ContextMenuStrip = $menu
            $ni.add_MouseDoubleClick({ Show-VxFromTray })
            $ni.add_BalloonTipClicked({
                if ($script:BalloonKind -eq 'update') { $script:BalloonKind = $null; Show-VxFromTray; Show-VxPage 'Settings'; Start-VxUpdate }
                else { Show-VxFromTray }
            })
            $script:TrayIcon = $ni
        }
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
        $script:TrayIcon.Visible = [bool]$script:Settings.tray
    } catch { Write-VxLog "tray: $($_.Exception.Message)" 'WARN' }
}

function Show-VxFromTray {
    $script:Window.ShowInTaskbar = $true
    $script:Window.Show()
    if ($script:Window.WindowState -eq 'Minimized') { $script:Window.WindowState = 'Normal' }
    $script:Window.Activate() | Out-Null
    # the icon was shown only for this trip to the background: hide it again if the user turned it off
    if ($script:TrayIcon -and -not $script:Settings.tray) { $script:TrayIcon.Visible = $false }
}

# one click: the app goes to the background and keeps running next to the clock
function Send-VxToTray {
    try {
        if (-not $script:TrayIcon) { Update-VxTrayIcon }
        if ($script:TrayIcon) { $script:TrayIcon.Visible = $true }
        $script:Window.Hide()
        if ($script:TrayIcon -and -not $script:TrayHintShown) {
            $script:TrayHintShown = $true; $script:BalloonKind = 'hint'
            $script:TrayIcon.ShowBalloonTip(3000, 'Piki Optimizer', (T 'tray.still'), 'Info')
        }
        Write-VxLog 'sent to background'
    } catch { Write-VxLog "tray: $($_.Exception.Message)" 'WARN' }
}

function Set-VxAutoStart {
    param([bool]$On)
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
$script:PageNames = @('Home', 'Health', 'Optimize', 'Processes', 'Network', 'Remote', 'Ae', 'Cleanup', 'Restore', 'Settings')
# the selected-section capsule slides to the clicked item with a gentle spring
$script:EaseSlide = New-Object System.Windows.Media.Animation.BackEase
$script:EaseSlide.EasingMode = 'EaseOut'; $script:EaseSlide.Amplitude = 0.22; $script:EaseSlide.Freeze()
function Move-VxNavIndicator {
    param([string]$Name, [switch]$Instant)
    try {
        $nav = $ui["Nav$Name"]
        $ind = $ui.NavIndicator
        if (-not $nav -or -not $ind -or $nav.ActualHeight -le 0) { return }
        $y = $nav.TranslatePoint((New-Object System.Windows.Point(0, 0)), $ui.NavStack).Y
        $h = $nav.ActualHeight
        $tt = Get-VxTransform $ind
        if ($Instant -or $ind.Opacity -lt 0.5) {
            $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null); $tt.Y = $y
            $ind.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, $null); $ind.Height = $h
            $ind.BeginAnimation($script:OpacityP, (New-VxAnim 1 260 0))
            return
        }
        $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-VxAnim $y 340 $null $script:EaseSlide))
        $ind.BeginAnimation([System.Windows.FrameworkElement]::HeightProperty, (New-VxAnim $h 220))
    } catch { Write-VxLog "nav indicator: $($_.Exception.Message)" 'WARN' }
}

# the blocks of a page come in one after another (fade + short slide), then the animation is released
function Start-VxStagger {
    param($Page, [int]$Dir = 1)
    if ($script:LiteMode) { return }   # PC under heavy load: skip the cascade, keep the simple glide
    try {
        $panel = $Page
        if ($Page -is [System.Windows.Controls.ScrollViewer]) { $panel = $Page.Content }
        if (-not ($panel -is [System.Windows.Controls.Panel])) { return }
        $i = 0
        foreach ($c in $panel.Children) {
            if ($i -ge 6) { break }
            if (-not ($c -is [System.Windows.FrameworkElement]) -or $c.Visibility -ne 'Visible') { continue }
            $delay = 26 * $i
            $op = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
            [void]$op.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame(0, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero))))
            [void]$op.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame(0, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($delay)))))
            [void]$op.KeyFrames.Add((New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame(1, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($delay + 220)), $script:EaseOut)))
            $el = $c
            $op.add_Completed({ $el.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null) }.GetNewClosure())
            # fading a tall list means redrawing all of it every frame: only small blocks fade, big ones just glide
            if ($c.ActualHeight -lt 420) { $c.BeginAnimation($script:OpacityP, $op) }
            if ($c.RenderTransform -is [System.Windows.Media.TranslateTransform] -or $c.RenderTransform -eq [System.Windows.Media.Transform]::Identity) {
                $mv = New-Object System.Windows.Media.Animation.DoubleAnimationUsingKeyFrames
                [void]$mv.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame((14 * $Dir), [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::Zero))))
                [void]$mv.KeyFrames.Add((New-Object System.Windows.Media.Animation.DiscreteDoubleKeyFrame((14 * $Dir), [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($delay)))))
                [void]$mv.KeyFrames.Add((New-Object System.Windows.Media.Animation.EasingDoubleKeyFrame(0, [System.Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($delay + 320)), $script:EaseOutStrong)))
                (Get-VxTransform $c).BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $mv)
            }
            $i++
        }
    } catch { Write-VxLog "stagger: $($_.Exception.Message)" 'WARN' }
}

# smooth scrolling (macOS-like): the wheel sets a target, the page glides to it frame by frame
$script:ScrollFx = @{ Sv = $null; Target = 0.0; Last = [DateTime]::MinValue; On = $false }
$script:ScrollTick = [EventHandler] {
    $fx = $script:ScrollFx
    $sv = $fx.Sv
    if (-not $sv) { return }
    $now = [DateTime]::Now
    $dt = [math]::Min(0.05, [math]::Max(0.001, ($now - $fx.Last).TotalSeconds))
    $fx.Last = $now
    $cur = $sv.VerticalOffset
    $diff = $fx.Target - $cur
    if ([math]::Abs($diff) -lt 0.6) {
        $sv.ScrollToVerticalOffset($fx.Target)
        [System.Windows.Media.CompositionTarget]::remove_Rendering($script:ScrollTick); $fx.On = $false
        return
    }
    $k = 1 - [math]::Exp(-$dt * 20)       # time-based easing: same feel at 60, 144 or 360 Hz
    $sv.ScrollToVerticalOffset($cur + $diff * $k)
}
function Enable-VxSmoothScroll {
    param($Sv)
    $Sv.add_PreviewMouseWheel({
        param($s, $e)
        if ($s.ScrollableHeight -le 0) { return }
        $e.Handled = $true
        $fx = $script:ScrollFx
        if ($fx.Sv -ne $s -or -not $fx.On) { $fx.Target = $s.VerticalOffset }
        $fx.Sv = $s
        $fx.Target = [math]::Max(0, [math]::Min($s.ScrollableHeight, $fx.Target - $e.Delta * 1.1))
        if (-not $fx.On) { $fx.On = $true; $fx.Last = [DateTime]::Now; [System.Windows.Media.CompositionTarget]::add_Rendering($script:ScrollTick) }
    })
}

function Show-VxPage {
    param([string]$Name)
    if (-not $Name) { return }
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
    # direction-aware: going down the menu the page rises from below, going up it comes from above
    $idx = [array]::IndexOf($script:PageNames, $Name)
    $dir = if ($null -ne $script:PageIdx -and $idx -lt $script:PageIdx) { -1 } else { 1 }
    $script:PageIdx = $idx
    # the blocks themselves fade/slide in (Start-VxStagger); the page only does a short glide
    (Get-VxTransform $page).BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-VxAnim 0 300 (8 * $dir) $script:EaseOutStrong))
    Start-VxStagger $page $dir
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
        'Processes' { if (-not $script:Loaded.Processes) { $script:Loaded.Processes = $true; Update-VxStartupList; Update-VxProcList }; Update-VxProcStats }
        'Network' { if (-not $script:Loaded.Network) { $script:Loaded.Network = $true; Update-VxNetworkPage } }
        'Ae' { if (-not $script:Loaded.Ae) { $script:Loaded.Ae = $true; Update-VxAePage } }
        'Cleanup' { if (-not $script:Loaded.Cleanup) { $script:Loaded.Cleanup = $true; Start-VxCleanScan } }
        'Restore' { $script:Loaded.Restore = $true; Update-VxRestorePage }
        'Health' { if (-not $script:Health) { Start-VxHealthCheck } }
    }
}

# remote assistance: Microsoft Quick Assist (free, encrypted, works over the Internet like AnyDesk)
function Start-VxQuickAssist {
    try {
        $hasProto = Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\ms-quick-assist'
        $exe = Join-Path $env:WINDIR 'System32\quickassist.exe'
        if ($hasProto) {
            # through explorer so it runs as the normal user, not elevated like this app
            Start-Process -FilePath 'explorer.exe' -ArgumentList 'ms-quick-assist:'
        } elseif (Test-Path -LiteralPath $exe) {
            Start-Process -FilePath 'explorer.exe' -ArgumentList $exe
        } else {
            Start-Process -FilePath 'explorer.exe' -ArgumentList 'ms-windows-store://pdp/?productid=9P7BP5VNWKX5'
            $ui.RemoteStatus.Text = T 'remote.install'
            Write-VxLog 'remote: Quick Assist missing, opened Store'
            return
        }
        $ui.RemoteStatus.Text = T 'remote.opened'
        Write-VxLog 'remote: Quick Assist started'
    } catch {
        $ui.RemoteStatus.Text = (T 'common.error') + ' ' + $_.Exception.Message
        Write-VxLog "remote: $($_.Exception.Message)" 'WARN'
    }
}

function Hide-VxSplash {
    $a = New-VxAnim 0 420 1
    $a.add_Completed({ $ui.SplashOverlay.Visibility = 'Collapsed' })
    $ui.SplashOverlay.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $a)
    $script:SplashActive = $false
}

# =====================================================================
#  EVENT WIRING
# =====================================================================
$ui.BtnMin.add_Click({ $script:Window.WindowState = 'Minimized' })
if ($ui.BtnTray) { $ui.BtnTray.add_Click({ Send-VxToTray }) }
$script:Window.add_PreviewMouseLeftButtonDown({ param($s, $e) try { $script:ClickPt = $e.GetPosition($ui.Root); $script:ClickAt = [DateTime]::Now } catch { } })
$ui.BtnRemoteGet.add_Click({ Start-VxQuickAssist })
$ui.BtnRemoteGive.add_Click({ Start-VxQuickAssist })
$ui.BtnMax.add_Click({ if ($script:Window.WindowState -eq 'Maximized') { $script:Window.WindowState = 'Normal' } else { $script:Window.WindowState = 'Maximized' } })
$ui.BtnClose.add_Click({ $script:Window.Close() })
$ui.SplashClose.add_Click({ $script:Window.Close() })
$script:Window.add_StateChanged({
    if ($script:Window.WindowState -eq 'Maximized') { $ui.Root.Margin = New-Object System.Windows.Thickness(7); $ui.BtnMax.Content = [string][char]0xE923 }
    else { $ui.Root.Margin = New-Object System.Windows.Thickness(0); $ui.BtnMax.Content = [string][char]0xE922 }
})

foreach ($p in $script:PageNames) {
    $ui["Nav$p"].add_Checked({ param($s, $e) if (-not $script:NavSuppress) { Show-VxPage ([string]$s.Tag) } })
}

# home
$ui.BtnOneClick.add_Click({ Show-VxWizard })
$ui.BtnHomeCheck.add_Click({ Start-VxHealthCheck })
$ui.BtnHomeBoost.add_Click({ Invoke-VxBoost })
$findingHandler = [System.Windows.RoutedEventHandler] {
    param($s, $e)
    $btn = $e.OriginalSource
    if ($btn -is [System.Windows.Controls.Button] -and $btn.Tag) { Invoke-VxFindingAction ([string]$btn.Tag) $btn.DataContext }
}
foreach ($n in @('HomeAdvice', 'HealthList')) { $ui[$n].AddHandler([System.Windows.Controls.Button]::ClickEvent, $findingHandler) }

# health
$ui.BtnHealthRun.add_Click({ Start-VxHealthCheck })

# wizard
$ui.WizClose.add_Click({ Hide-VxOverlay $ui.WizardOverlay })
foreach ($n in @('WizMax', 'WizGaming', 'WizCompetitive', 'WizCreator', 'WizBalanced', 'WizLaptop')) {
    if (-not $ui[$n]) { continue }
    $ui[$n].add_Checked({ param($s, $e) Update-VxWizardSummary ([string]$s.Tag) })
}
$ui.WizGo.add_Click({
    $plan = Get-VxWizardPlan $script:WizPreset
    Hide-VxOverlay $ui.WizardOverlay
    $script:Settings.profile = $script:WizPreset
    Save-VxSettings $script:Settings
    Invoke-VxApplyItems -ApplyIds (@($plan.tweaks) + @($plan.services)) -RevertIds @() -RestorePoint $true -Title (T 'busy.optimizing')
})

# optimize presets
foreach ($n in @('PresetMax', 'PresetGaming', 'PresetCompetitive', 'PresetCreator', 'PresetBalanced', 'PresetLaptop')) {
    if (-not $ui[$n]) { continue }
    $ui[$n].add_Click({ param($s, $e) Select-VxPreset ([string]$s.Tag) })
}

# pending bar
$ui.BtnPendingApply.add_Click({ Invoke-VxPendingApply })
$ui.BtnPendingReset.add_Click({
    foreach ($it in (Get-VxAllItems)) { if ($it.IsDirty) { $it.IsChecked = $it.IsApplied } }
    foreach ($n in @('PresetMax', 'PresetGaming', 'PresetCompetitive', 'PresetCreator', 'PresetBalanced', 'PresetLaptop', 'LevelLight', 'LevelBalanced', 'LevelMax')) { if ($ui[$n]) { $ui[$n].IsChecked = $false } }
    Update-VxPendingBar
})

# processes
$ui.ProcTabReduce.add_Checked({ $ui.ProcPaneReduce.Visibility = 'Visible'; $ui.ProcPaneStartup.Visibility = 'Collapsed'; $ui.ProcPaneRunning.Visibility = 'Collapsed' })
$ui.ProcTabStartup.add_Checked({ $ui.ProcPaneReduce.Visibility = 'Collapsed'; $ui.ProcPaneStartup.Visibility = 'Visible'; $ui.ProcPaneRunning.Visibility = 'Collapsed' })
$ui.ProcTabRunning.add_Checked({ $ui.ProcPaneReduce.Visibility = 'Collapsed'; $ui.ProcPaneStartup.Visibility = 'Collapsed'; $ui.ProcPaneRunning.Visibility = 'Visible' })
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
    $item.Status = if ($enable) { T 'startup.on' } else { T 'startup.off' }
    Start-VxJob -Name 'startuptoggle' -Arguments @($item.Tag, $enable) -Script { param($Sync, $It, $En) Set-VxStartupEnabled -Item $It -Enabled $En; return @{ ok = $true } } -OnDone {
        param($r)
        Update-VxProcStats
    }
    Show-VxToast $(if ($enable) { T 'startup.toast.on' @($item.Title) } else { T 'startup.toast.off' @($item.Title) }) 'ok'
}
$ui.StartupList.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent, $startupToggle)
$ui.StartupList.AddHandler([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent, $startupToggle)
$ui.ProcList.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler] {
    param($s, $e)
    $btn = $e.OriginalSource
    if (-not ($btn -is [System.Windows.Controls.Button])) { return }
    $row = $btn.DataContext
    $script:ProcToKill = $row.Name
    $go = {
        Start-VxJob -Name 'kill' -Arguments @($script:ProcToKill) -Script { param($Sync, $N) return @{ n = (Stop-VxProcessGroup $N) } } -OnDone { param($r) Show-VxToast (T 'proc.killed' @($script:ProcToKill)) 'ok'; Update-VxProcList }
    }
    if ($row.Risk -eq 'safe') { & $go }
    else { Show-VxDialog -Title (T 'proc.kill.q' @($row.Name)) -Text $row.Advice -YesText (T 'proc.kill.yes') -NoText (T 'common.cancel') -OnYes $go }
})

# network
$ui.BtnNetBoost.add_Click({
    if (-not $script:Hw) { Show-VxToast (T 'common.wait') 'info'; return }
    $ids = [string[]]@($script:Lists.net | Where-Object { $_.Risk -ne 'advanced' -and -not $_.IsApplied } | ForEach-Object { $_.Id })
    Show-VxBusy (T 'net.boost.busy') (T 'busy.wait')
    Start-VxJob -Name 'netboost' -Arguments @($script:Hw, $ids) -Script {
        param($Sync, $Hw, $Ids)
        $n = 0; $i = 0
        foreach ($id in $Ids) {
            $i++; $Sync.Pct = [int](60 * $i / [math]::Max(1, $Ids.Count))
            $t = Find-VxTweak $id; if (-not $t) { continue }
            $Sync.Step = L $t.Title
            if ((Invoke-VxTweak $t $Hw).ok) { $n++ }
        }
        $Sync.Step = (L @{ it = 'Cerco il DNS più veloce...'; en = 'Finding the fastest DNS...' }); $Sync.Pct = 70
        $dns = ''
        try {
            $rows = @(Invoke-VxDnsBenchmark $Hw | Where-Object { $_.Ms -ge 0 })
            $cur = $rows | Where-Object { $_.Current } | Sort-Object Ms | Select-Object -First 1
            $best = $rows | Where-Object { $_.S } | Sort-Object Ms | Select-Object -First 1
            if ($best -and -not $best.Current -and (-not $cur -or $best.Ms -lt $cur.Ms * 0.85) -and $Hw.Network) {
                if (Set-VxDnsServers ([int]$Hw.Network.IfIndex) $best.P $best.S) { $dns = $best.Name }
            }
        } catch { }
        $Sync.Pct = 95
        Clear-DnsClientCache -ErrorAction SilentlyContinue
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
    if (-not $b -or -not $script:Hw.Network) { return }
    Start-VxJob -Name 'dnsapply' -Arguments @([int]$script:Hw.Network.IfIndex, $b.Primary, $b.Secondary) -Script { param($Sync, $I, $P, $S) return @{ ok = (Set-VxDnsServers $I $P $S) } } -OnDone {
        param($r)
        if ($r.ok) { Show-VxToast (T 'net.dns.applied' @($script:DnsBest.Provider)) 'ok' } else { Show-VxToast (T 'common.error') 'crit' }
    }
})
$ui.BtnDnsRevert.add_Click({
    if (-not (Test-VxBackupEntry 'dns')) { Show-VxToast (T 'net.dns.norevert') 'info'; return }
    Invoke-VxUndo @('dns')
})
$ui.BtnFlushDns.add_Click({ try { Clear-DnsClientCache; Show-VxToast (T 'net.flushed') 'ok' } catch { Show-VxToast $_.Exception.Message 'crit' } })
$ui.BtnNetReset.add_Click({
    Show-VxDialog -Title (T 'net.reset') -Text (T 'net.reset.q') -YesText (T 'net.reset.yes') -NoText (T 'common.cancel') -OnYes {
        Start-VxJob -Name 'netreset' -Script { param($Sync) Invoke-VxNetworkReset; return @{ ok = $true } } -OnDone {
            Show-VxDialog -Title (T 'net.reset') -Text (T 'net.reset.done') -YesText (T 'common.rebootnow') -NoText (T 'common.later') -OnYes { Restart-Computer -Force }
        }
    }
})

# after effects
$ui.BtnRenderMode.add_Click({ Switch-VxRenderMode })
$ui.BtnAeFolders.add_Click({
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
    Start-VxJob -Name 'clean' -Arguments @(, $ids) -Script { param($Sync, $Ids) return @{ freed = (Invoke-VxClean $Ids) } } -OnDone {
        param($r)
        Hide-VxBusy
        $ui.CleanResult.Text = T 'clean.freed' @((Format-VxBytes $r.freed))
        Show-VxToast (T 'clean.freed' @((Format-VxBytes $r.freed))) 'ok'
        Start-VxCleanScan
    }
})

# restore
$ui.BtnRestorePoint.add_Click({
    Show-VxBusy (T 'restore.point.creating') (T 'busy.wait')
    Start-VxJob -Name 'rp' -Script { param($Sync) return @{ ok = (New-VxRestorePoint 'Piki Optimizer') } } -OnDone {
        param($r)
        Hide-VxBusy
        if ($r.ok) { Show-VxToast (T 'restore.point.ok') 'ok' } else { Show-VxToast (T 'restore.point.fail') 'warn' }
    }
})
$ui.BtnRstrui.add_Click({ Open-VxTarget 'rstrui.exe' })
$ui.BtnUndoAll.add_Click({
    Show-VxDialog -Title (T 'restore.all') -Text (T 'restore.all.q') -YesText (T 'restore.all.btn') -NoText (T 'common.cancel') -OnYes {
        $ids = [string[]]@((Get-VxBackup).entries.Keys)
        Invoke-VxUndo $ids
    }
})
$ui.ActiveList.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler] {
    param($s, $e)
    $btn = $e.OriginalSource
    if ($btn -is [System.Windows.Controls.Button] -and $btn.Tag) { Invoke-VxUndo @([string]$btn.Tag) }
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
    [void]$ui.LangPanel.Children.Add($rb)
}
$ui.ExpertSwitch.IsChecked = $script:Expert
$ui.AutoUpdateSwitch.IsChecked = [bool]$script:Settings.autoUpdate
$langHandler = {
    param($s, $e)
    $new = [string]$s.Tag
    if ($new -eq $script:VxLang) { return }
    $script:Settings.lang = $new
    Save-VxSettings $script:Settings
    Restart-VxApp
}
foreach ($rb in @($ui.LangPanel.Children)) { $rb.add_Click($langHandler) }
$ui.ExpertSwitch.add_Click({
    $script:Expert = [bool]$ui.ExpertSwitch.IsChecked
    $script:Settings.expert = $script:Expert
    Save-VxSettings $script:Settings
    Update-VxOptionLists
})
$ui.AutoUpdateSwitch.add_Click({ $script:Settings.autoUpdate = [bool]$ui.AutoUpdateSwitch.IsChecked; Save-VxSettings $script:Settings })
$ui.BtnCheckUpdate.add_Click({ Start-VxUpdateCheck -Manual })
$ui.BtnLogoPick.add_Click({ Select-VxImage 'logo' })
$ui.BtnBgPick.add_Click({ Select-VxImage 'bg' })
$ui.BtnLogoReset.add_Click({ $script:Settings.logo = ''; Save-VxSettings $script:Settings; Remove-Item -LiteralPath (Join-Path $script:CustomDir 'logo.ico') -Force -ErrorAction SilentlyContinue; Update-VxLook; Show-VxToast (T 'set.logo.ok') 'ok' })
$ui.BtnBgRemove.add_Click({ $script:Settings.bg = ''; Save-VxSettings $script:Settings; Update-VxLook })
foreach ($n in @('BgLevel1', 'BgLevel2', 'BgLevel3')) { $ui[$n].add_Click({ param($s, $e) $script:Settings.bgLevel = [int]$s.Tag; Save-VxSettings $script:Settings; Update-VxLook }) }
$ui.TraySwitch.IsChecked = [bool]$script:Settings.tray
$ui.AutoStartSwitch.IsChecked = [bool]$script:Settings.autostart
$ui.TraySwitch.add_Click({ $script:Settings.tray = [bool]$ui.TraySwitch.IsChecked; Save-VxSettings $script:Settings; Update-VxTrayIcon })
$ui.AutoStartSwitch.add_Click({ Set-VxAutoStart ([bool]$ui.AutoStartSwitch.IsChecked) })
$ui.BtnBannerUpdate.add_Click({ Start-VxUpdate })
$ui.BtnShortcut.add_Click({
    try {
        $desk = [Environment]::GetFolderPath('Desktop')
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut((Join-Path $desk 'Piki Optimizer.lnk'))
        $lnk.TargetPath = Join-Path $Root 'Avvia Piki Optimizer.cmd'
        $lnk.WorkingDirectory = $Root
        $lnk.WindowStyle = 7
        $lnk.IconLocation = Get-VxIconPath
        $lnk.Description = 'Piki Optimizer'
        $lnk.Save()
        Show-VxToast (T 'set.shortcut.ok') 'ok'
    } catch { Show-VxToast $_.Exception.Message 'crit' }
})
$ui.BtnOpenLogs.add_Click({ Open-VxTarget $script:VxLogs })
$ui.BtnPurgeRam.add_Click({
    $before = ([VeloxPC.Native]::Memory())[2]
    [void][VeloxPC.Native]::PurgeStandbyList()
    $after = ([VeloxPC.Native]::Memory())[2]
    Show-VxToast (T 'set.purge.ok' @((Format-VxBytes ([math]::Max(0, $after - $before))))) 'ok'
})

# dialog buttons
$ui.DialogYes.add_Click({ Hide-VxOverlay $ui.DialogOverlay; $cb = $script:DialogYes; $script:DialogYes = $null; if ($cb) { & $cb } })
$ui.DialogNo.add_Click({ Hide-VxOverlay $ui.DialogOverlay; $cb = $script:DialogNo; $script:DialogNo = $null; if ($cb) { & $cb } })

# =====================================================================
#  TIMERS
# =====================================================================
# Input priority: below rendering and above idle work, so clicks are never kept waiting by the job poller
$script:JobTimer = New-Object System.Windows.Threading.DispatcherTimer([System.Windows.Threading.DispatcherPriority]::Input)
$script:JobTimer.Interval = [TimeSpan]::FromMilliseconds(120)
$script:LastTick = [DateTime]::Now
$script:JobTimer.add_Tick({
    try {
        $gap = ([DateTime]::Now - $script:LastTick).TotalMilliseconds
        if ($gap -gt 2000) { Write-VxLog ("UI thread was busy for {0:N0} ms" -f $gap) 'WARN' }
        $script:LastTick = [DateTime]::Now
        Complete-VxJobs
        if ($script:BusyActive) {
            $ui.BusyText.Text = [string]$script:Sync.Step
            Set-VxBarWidth $ui.BusyBar (406 * [double]$script:Sync.Pct / 100)
        }
        if ($script:SplashActive) {
            if ($script:Sync.Step) { $ui.SplashStep.Text = [string]$script:Sync.Step }
            if ($script:HealthSplash) { Set-VxBarWidth $ui.SplashBar (520 * (0.3 + 0.7 * [double]$script:Sync.Pct / 100)) }
            elseif (-not $script:Hw) { Set-VxBarWidth $ui.SplashBar ([math]::Min(150, 60 + 90 * [double]$script:Sync.Pct / 100)) }
        }
        if ($script:Pinger) { Update-VxPingLive }
        if ($script:LoadT) { Update-VxLoadLive }
        if ($script:ToastUntil -and (Get-Date) -gt $script:ToastUntil) { $script:ToastUntil = $null; Hide-VxToast }
        # fast while something is running, relaxed when idle (leaves the UI thread free for animations)
        $active = ($script:Jobs.Count -gt 0 -or $script:BusyActive -or $script:SplashActive -or $script:Pinger -or $script:LoadT)
        $want = if ($active) { 120 } else { 450 }
        if ([int]$script:JobTimer.Interval.TotalMilliseconds -ne $want) { $script:JobTimer.Interval = [TimeSpan]::FromMilliseconds($want) }
    } catch { Write-VxLog "Timer: $($_.Exception.Message)" 'ERROR' }
})
$script:JobTimer.Start()

[void][VeloxPC.Native]::CpuUsage()
$script:LiveTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:LiveTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:LiveTimer.add_Tick({
    try {
        $cpu = [VeloxPC.Native]::CpuUsage()
        $mem = [VeloxPC.Native]::Memory()
        # light mode: when the PC is saturated (e.g. a render), animations get cheaper automatically
        if ($cpu -ge 80) { $script:HotSecs++; $script:CoolSecs = 0 } else { $script:CoolSecs++; if ($cpu -lt 60) { $script:HotSecs = 0 } }
        if (-not $script:LiteMode -and $script:HotSecs -ge 3) { $script:LiteMode = $true; Write-VxLog "light mode on (CPU $([int]$cpu)%)" }
        elseif ($script:LiteMode -and $script:CoolSecs -ge 6) { $script:LiteMode = $false; Write-VxLog 'light mode off' }
        if ($script:TrayIcon -and $script:TrayIcon.Visible) { $script:TrayIcon.Text = ('Piki Optimizer · CPU {0:N0}% · RAM {1:N0}%' -f $cpu, $mem[0]) }
        if (-not $script:Window.IsVisible -or $script:Window.WindowState -eq 'Minimized') { return }
        $ui.SideCpuText.Text = '{0:N0}%' -f $cpu
        $ui.SideRamText.Text = '{0:N0}%' -f $mem[0]
        foreach ($pair in @(@($ui.SideCpuBar, $cpu), @($ui.SideRamBar, $mem[0]))) {
            if ($pair[0].HorizontalAlignment -eq 'Left') { $pair[0].Width = 180 * [double]$pair[1] / 100; continue }   # safe layout
            $sc = Get-VxTransform $pair[0] 'Scale'
            $pair[0].RenderTransformOrigin = New-Object System.Windows.Point(0, 0.5)
            $sc.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, (New-VxAnim ([math]::Max(0.02, [double]$pair[1] / 100)) 700))
        }
        if ($script:CurrentPage -eq 'Home') {
            $script:CpuHist.Add($cpu); $script:RamHist.Add($mem[0])
            while ($script:CpuHist.Count -gt 60) { $script:CpuHist.RemoveAt(0); $script:RamHist.RemoveAt(0) }
            $w = $ui.LiveCanvas.ActualWidth; $h = $ui.LiveCanvas.ActualHeight
            if ($w -gt 10 -and $h -gt 10) {
                foreach ($pair in @(@($script:CpuHist, $ui.LiveCpuLine), @($script:RamHist, $ui.LiveRamLine))) {
                    $pts = New-Object System.Windows.Media.PointCollection
                    $data = $pair[0]
                    for ($k = 0; $k -lt $data.Count; $k++) { $pts.Add((New-Object System.Windows.Point(($w - ($data.Count - 1 - $k) * $w / 59), ($h - 2 - ($data[$k] / 100) * ($h - 4))))) }
                    $pair[1].Points = $pts
                }
            }
            $ui.LiveCpuText.Text = '{0:N0}%' -f $cpu
            $ui.LiveRamText.Text = ('{0:N0}%' -f $mem[0]) + ' · ' + (Format-VxBytes ($mem[1] - $mem[2])) + ' / ' + (Format-VxBytes $mem[1])
        }
    } catch { }
})
$script:LiveTimer.Start()

# spinner animation
# (the busy spinner is started/stopped by Show-VxBusy / Hide-VxBusy)

# =====================================================================
#  STARTUP SEQUENCE
# =====================================================================
$ui.VersionText.Text = "v$script:Version"
Update-VxLook
$script:Window.add_SourceInitialized({ Enable-VxGlass })
if ($Tray) {
    # started with Windows: live only in the notification area until opened
    $script:Window.ShowInTaskbar = $false
    $script:Window.add_Loaded({ if (-not $script:TrayStarted) { $script:TrayStarted = $true; $script:Window.Dispatcher.BeginInvoke([Action] { $script:Window.Hide() }) | Out-Null } })
}
$script:SplashActive = $true
$ui.SplashStep.Text = T 'splash.hw'
Set-VxBarWidth $ui.SplashBar 60 -Instant

$script:CacheHw = Read-VxJson 'cache\hardware.json' $null
$script:CacheStates = ConvertTo-VxHashtable (Read-VxJson 'cache\states.json' $null)
foreach ($pn in $script:PageNames) { $pg = $ui["Page$pn"]; if ($pg -is [System.Windows.Controls.ScrollViewer]) { Enable-VxSmoothScroll $pg } }
$script:Window.add_ContentRendered({
    try {
        $tier = [System.Windows.Media.RenderCapability]::Tier -shr 16
        $prim = @([VeloxPC.Native]::GetDisplays() | Where-Object { $_.Primary }) | Select-Object -First 1
        if ($prim -and $prim.CurrentHz -ge 50) {
            [System.IO.File]::WriteAllText((Join-Path $Root 'data\cache\hz.txt'), [string]$prim.CurrentHz)
            $script:MonitorFps = [math]::Min(240, [int]$prim.CurrentHz)
        }
        Write-VxLog ("render: tier {0} ({1}), animations {2} fps, monitor {3} Hz" -f $tier, $(if ($tier -ge 2) { 'GPU' } else { 'SOFTWARE - slow' }), $script:Fps, $(if ($prim) { $prim.CurrentHz } else { '?' }))
    } catch { }
    Move-VxNavIndicator $(if ($script:CurrentPage) { $script:CurrentPage } else { 'Home' }) -Instant
    if ($script:CacheHw -and $script:Settings.firstRunDone -and -not $script:Hw) {
        # instant start: show the last known data right away, refresh in the background
        try {
            $script:Hw = $script:CacheHw
            if ($script:CacheStates) { $script:States = $script:CacheStates }
            $ui.TitlePc.Text = (@($script:Hw.Model, $script:Hw.ComputerName) | Where-Object { $_ }) -join ' · '
            $ui.HomeHello.Text = T 'home.title2' @($env:USERNAME)
            Update-VxHwCards
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
    Start-VxJob -Name 'hardware' -Script { param($Sync) return (Get-VxHardware -Sync $Sync) } -OnDone {
        param($hw)
        $script:Hw = $hw
        try { Write-VxJson 'cache\hardware.json' $hw } catch { }
        Write-VxLog "Hardware: $($hw.CPU.Name) | $(if ($hw.GPU) { $hw.GPU.Name }) | $($hw.RAM.GB) GB | $($hw.OS.Name) $($hw.OS.DisplayVersion)"
        $ui.TitlePc.Text = (@($hw.Model, $hw.ComputerName) | Where-Object { $_ }) -join ' · '
        $ui.HomeHello.Text = T 'home.title2' @($env:USERNAME)
        Set-VxBarWidth $ui.SplashBar 150
        $script:Sync.Step = T 'splash.states'
        $ui.SplashStep.Text = T 'splash.states'
        Update-VxHwCards
        $saved = Read-VxJson 'health.json' $null
        if ($saved) { $script:Health = ConvertTo-VxHashtable $saved; Update-VxHealthPage }
        $firstRun = (-not $script:Settings.firstRunDone -or -not $script:Health)
        if ($firstRun) {
            # check-up and settings scan run at the same time
            $ui.SplashTitle.Text = T 'splash.first'
            Start-VxHealthCheck -Splash
            Update-VxStates
        } elseif ($script:FastStart) {
            Update-VxStates
        } else {
            Update-VxStates -Then { Hide-VxSplash; Show-VxPage 'Home' }
        }
        if ($script:Settings.autoUpdate) { Start-VxUpdateCheck }
        # keep checking every 3 hours while the app stays open or in the tray
        if (-not $script:UpdTimer) {
            $script:UpdTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:UpdTimer.Interval = [TimeSpan]::FromHours(3)
            $script:UpdTimer.add_Tick({ if ($script:Settings.autoUpdate) { Start-VxUpdateCheck } })
            $script:UpdTimer.Start()
        }
    } -OnError {
        param($e)
        Show-VxFatal ("Hardware scan failed: " + $e.Message)
        Hide-VxSplash
    }
})

$script:Window.add_Closing({
    param($s, $e)
    if ($script:Settings.tray -and -not $script:ReallyExit) {
        $e.Cancel = $true
        $script:Window.Hide()
        if (-not $script:TrayHintShown -and $script:TrayIcon) { $script:TrayHintShown = $true; $script:BalloonKind = 'hint'; $script:TrayIcon.ShowBalloonTip(3000, 'Piki Optimizer', (T 'tray.still'), 'Info') }
        return
    }
    try { if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() } } catch { }
    try { if ($script:RenderMode) { Switch-VxRenderMode } } catch { }
    try { $script:JobTimer.Stop(); $script:LiveTimer.Stop() } catch { }
    Write-VxLog '---- VeloxPC exit'
})

# the window runs on a normal message loop, not ShowDialog: hiding a modal window ends its loop,
# which made "send to background" quit the whole app
$script:Window.add_Closed({ try { $script:Window.Dispatcher.InvokeShutdown() } catch { } })
try {
    $script:Window.Show()
    [System.Windows.Threading.Dispatcher]::Run()
} catch {
    Show-VxFatal ($_.Exception.Message + "`n" + $_.ScriptStackTrace)
} finally {
    try { [VeloxPC.Native]::KeepAwake($false) } catch { }
    [Environment]::Exit(0)
}
