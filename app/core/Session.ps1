# Piki Optimizer 2.0 - temporary "Gioco" / "Render" sessions (they replace Render Mode).
# A session changes only temporary things (active power plan, closing confirmed helpers, process priority) and is
# written to data\session.json BEFORE anything changes, so it is undone on stop, on app exit, after a crash
# (next start) or - for Render - automatically when After Effects / Media Encoder close.

$script:VxHighPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:VxSessionHelpers = @('Widgets', 'WidgetService', 'PhoneExperienceHost', 'YourPhone', 'Copilot', 'Overwolf', 'OverwolfBrowser', 'Medal', 'wallpaper32', 'wallpaper64', 'webwallpaper32')
$script:VxRenderApps = @('AfterFX', 'aerender', 'Adobe Media Encoder', 'Adobe Premiere Pro', 'Topaz Video AI', 'Topaz Video')

function Get-VxSession {
    $s = ConvertTo-VxHashtable (Read-VxJson 'session.json' $null)
    if ($s -and $s.kind) { return $s }
    return $null
}

function Get-VxSessionHelpersRunning {
    # helpers a session would close (shown to the user before starting); Game Bar stays on dual-CCD Ryzen X3D
    param($Hw)
    $list = @($script:VxSessionHelpers)
    if (-not ($Hw -and $Hw.CPU.IsX3DDual)) { $list += @('GameBar', 'GameBarFTServer') }
    $out = @()
    foreach ($n in $list) {
        $p = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        if ($p.Count -gt 0) { $out += @{ name = $n; mem = [int64](($p | Measure-Object WorkingSet64 -Sum).Sum) } }
    }
    return $out
}

function Start-VxSession {
    param([ValidateSet('game', 'render')][string]$Kind, $Hw, [string[]]$Close = @())
    if (Get-VxSession) { [void](Stop-VxSession) }
    $prev = Get-VxActiveScheme
    $plan = $script:VxHighPerf
    # dual-CCD Ryzen X3D need Balanced (core parking); on battery we never force High performance
    if (($Hw -and $Hw.CPU.IsX3DDual) -or ($Hw -and $Hw.OnBattery)) { $plan = '' }
    $s = @{ kind = $Kind; started = (Get-Date -Format 'o'); prevScheme = $(if ($prev) { $prev.guid } else { '' }); plan = $plan; closed = @() }
    Write-VxJson 'session.json' $s   # written first: a crash after this point is still undone at the next start
    if ($plan -and $prev -and $prev.guid -ne $plan) { [void](Invoke-VxExe 'powercfg' @('/setactive', $plan)) }
    foreach ($n in $Close) {
        if ($n -notin @($script:VxSessionHelpers + @('GameBar', 'GameBarFTServer'))) { continue }
        if ((Stop-VxProcessGroup $n) -gt 0) { $s.closed += $n }
    }
    if ($Kind -eq 'render') {
        foreach ($p in @(Get-Process -Name $script:VxRenderApps -ErrorAction SilentlyContinue)) { try { $p.PriorityClass = 'AboveNormal' } catch { } }
    }
    Write-VxJson 'session.json' $s
    Write-VxLog "Session $Kind started (plan $plan, closed $($s.closed -join ', '))"
    return $s
}

function Stop-VxSession {
    $s = Get-VxSession
    if (-not $s) { return $false }
    try {
        $cur = Get-VxActiveScheme
        # only put the plan back if the session's plan is still the active one (the user may have changed it since)
        if ($s.plan -and $s.prevScheme -match '^[0-9a-fA-F-]{36}$' -and $cur -and $cur.guid -eq $s.plan) { [void](Invoke-VxExe 'powercfg' @('/setactive', [string]$s.prevScheme)) }
    } catch { }
    try { Remove-Item -LiteralPath (Join-Path $script:VxData 'session.json') -Force -ErrorAction Stop } catch { }
    Write-VxLog "Session $($s.kind) ended"
    return $true
}

function Test-VxRenderAppsRunning { return (Test-VxProcessRunning $script:VxRenderApps) }
