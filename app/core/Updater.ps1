# VeloxPC - incremental updater: downloads only the files that changed (SHA-256 manifest)

function Get-VxConfig {
    $file = Join-Path $script:VxRoot 'config.json'
    $cfg = @{ repo = ''; branch = 'main' }
    if (Test-Path -LiteralPath $file) {
        try {
            $j = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($j.repo) { $cfg.repo = [string]$j.repo }
            if ($j.branch) { $cfg.branch = [string]$j.branch }
        } catch { }
    }
    return $cfg
}

function Get-VxLocalManifest {
    $file = Join-Path $script:VxRoot 'version.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return ([System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Get-VxRawUrl {
    param([string]$RelPath)
    $cfg = Get-VxConfig
    $enc = (($RelPath -replace '\\', '/').Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "https://raw.githubusercontent.com/$($cfg.repo)/$($cfg.branch)/$enc"
}

function New-VxWebClient {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $wc = New-Object System.Net.WebClient
    $wc.Headers['User-Agent'] = 'VeloxPC-Updater'
    $wc.Headers['Cache-Control'] = 'no-cache'
    $wc.Encoding = [System.Text.Encoding]::UTF8
    return $wc
}

function Get-VxRemoteManifest {
    $cfg = Get-VxConfig
    if (-not $cfg.repo -or $cfg.repo -match 'OWNER') { throw 'Update source not configured' }
    $wc = New-VxWebClient
    try {
        $raw = $wc.DownloadString((Get-VxRawUrl 'version.json') + '?t=' + [DateTime]::UtcNow.Ticks)
        $m = $raw | ConvertFrom-Json
        return @{ manifest = $m; raw = $raw }
    } finally { $wc.Dispose() }
}

function Test-VxNewer {
    param([string]$Remote, [string]$Local)
    try { return ([version]$Remote -gt [version]$Local) } catch { return ($Remote -ne $Local) }
}

function Get-VxFileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($Path)
    try { return (($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $fs.Dispose(); $sha.Dispose() }
}

function Invoke-VxUpdate {
    param($Remote, $Sync)
    $m = $Remote.manifest
    $changed = @()
    foreach ($f in @($m.files)) {
        $rel = [string]$f.path
        if (-not $rel -or $rel -match '\.\.' -or [IO.Path]::IsPathRooted($rel)) { continue }
        $local = Join-Path $script:VxRoot ($rel -replace '/', '\')
        if ((Get-VxFileSha256 $local) -ne ([string]$f.sha256).ToLower()) { $changed += $f }
    }
    if ($changed.Count -eq 0) {
        [System.IO.File]::WriteAllText((Join-Path $script:VxRoot 'version.json'), $Remote.raw, (New-Object System.Text.UTF8Encoding($false)))
        return 0
    }
    $tmpDir = Join-Path $script:VxData ('update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $wc = New-VxWebClient
    try {
        $i = 0
        # 1) download everything and verify it before touching the installed files
        foreach ($f in $changed) {
            $i++
            if ($Sync) { $Sync.Step = [string]$f.path; $Sync.Pct = [int](80 * $i / $changed.Count) }
            $dest = Join-Path $tmpDir ([string]$i)
            $wc.DownloadFile((Get-VxRawUrl ([string]$f.path)) + '?t=' + [DateTime]::UtcNow.Ticks, $dest)
            if ((Get-VxFileSha256 $dest) -ne ([string]$f.sha256).ToLower()) { throw "Checksum mismatch: $($f.path)" }
        }
        # 2) swap files in
        $i = 0
        foreach ($f in $changed) {
            $i++
            $local = Join-Path $script:VxRoot (([string]$f.path) -replace '/', '\')
            $dir = Split-Path -Parent $local
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath (Join-Path $tmpDir ([string]$i)) -Destination $local -Force
        }
        [System.IO.File]::WriteAllText((Join-Path $script:VxRoot 'version.json'), $Remote.raw, (New-Object System.Text.UTF8Encoding($false)))
        if ($Sync) { $Sync.Pct = 100 }
        Write-VxLog "Updated to $($m.version): $($changed.Count) files"
        return $changed.Count
    } finally {
        $wc.Dispose()
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
