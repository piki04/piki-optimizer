# VeloxPC - incremental updater: downloads only the files that changed (SHA-256 manifest)

function Get-VxConfig {
    $file = Join-Path $script:VxRoot 'config.json'
    $cfg = @{ repo = ''; branch = 'main'; pubKey = '' }
    if (Test-Path -LiteralPath $file) {
        try {
            $j = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($j.repo) { $cfg.repo = [string]$j.repo }
            if ($j.branch) { $cfg.branch = [string]$j.branch }
            if ($j.pubKey) { $cfg.pubKey = [string]$j.pubKey }
        } catch { }
    }
    return $cfg
}

# Signed updates: when config.json carries the public key (RSA, XML form), version.json must come with a valid
# version.sig (base64 RSA-SHA256 signature of the exact version.json bytes), made offline with tools\Sign-Manifest.ps1.
# Without a public key the app behaves like 1.x (per-file SHA-256 check only).
function Test-VxManifestSignature {
    param([string]$Raw, [string]$SigBase64, [string]$PubKeyXml)
    try {
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        try {
            $rsa.PersistKeyInCsp = $false
            $rsa.FromXmlString($PubKeyXml)
            # normalised text (no BOM, LF line ends): git may change CRLF/LF, the signature must survive that
            $data = (New-Object System.Text.UTF8Encoding($false)).GetBytes(($Raw.TrimStart([char]0xFEFF) -replace "`r", ''))
            $sig = [Convert]::FromBase64String($SigBase64.Trim())
            return $rsa.VerifyData($data, 'SHA256', $sig)
        } finally { $rsa.Dispose() }
    } catch { return $false }
}

function Get-VxLocalManifest {
    $file = Join-Path $script:VxRoot 'version.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return ([System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Get-VxRawUrl {
    param([string]$RelPath, [string]$Ref)
    $cfg = Get-VxConfig
    if (-not $Ref) { $Ref = $cfg.branch }
    $enc = (($RelPath -replace '\\', '/').Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    return "https://raw.githubusercontent.com/$($cfg.repo)/$Ref/$enc"
}

# The exact id of the latest published version: files addressed by it are never served stale by the CDN
# (addressing by branch name can return the previous version for a few minutes after a release).
function Get-VxLatestRef {
    $cfg = Get-VxConfig
    $wc = $null
    try {
        $wc = New-VxWebClient
        $wc.Headers['Accept'] = 'application/vnd.github.sha'
        $sha = ($wc.DownloadString("https://api.github.com/repos/$($cfg.repo)/commits/$($cfg.branch)")).Trim()
        if ($sha -match '^[0-9a-f]{40}$') { return $sha }
    } catch { Write-VxLog "update: latest ref lookup failed ($($_.Exception.Message)), using branch" 'WARN' }
    finally { if ($wc) { $wc.Dispose() } }
    return $cfg.branch
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
    $ref = Get-VxLatestRef
    $wc = New-VxWebClient
    try {
        $raw = $wc.DownloadString((Get-VxRawUrl 'version.json' $ref) + '?t=' + [DateTime]::UtcNow.Ticks)
        if ($cfg.pubKey) {
            $sig = ''
            try { $sig = $wc.DownloadString((Get-VxRawUrl 'version.sig' $ref) + '?t=' + [DateTime]::UtcNow.Ticks) } catch { }
            if (-not $sig -or -not (Test-VxManifestSignature $raw $sig $cfg.pubKey)) { Write-VxLog 'update: manifest signature missing or invalid, update refused' 'ERROR'; throw 'Update signature check failed' }
        }
        $m = $raw | ConvertFrom-Json
        return @{ manifest = $m; raw = $raw; ref = $ref }
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

function Test-VxManifestPath {
    param([string]$Rel)
    if (-not $Rel -or $Rel -match '\.\.' -or $Rel -match '[:*?"<>|]' -or $Rel -match '^[\\/]') { return $false }
    if ($Rel -match '(?i)^data([\\/]|$)') { return $false }
    try { if ([IO.Path]::IsPathRooted($Rel)) { return $false } } catch { return $false }
    return $true
}

function Invoke-VxUpdate {
    param($Remote, $Sync)
    $m = $Remote.manifest
    $changed = @()
    foreach ($f in @($m.files)) {
        $rel = [string]$f.path
        # only plain relative paths inside the app; never the user's data\ folder (settings, backups of original values)
        if (-not (Test-VxManifestPath $rel)) { Write-VxLog "update: path refused: $rel" 'WARN'; continue }
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
            $wc.DownloadFile((Get-VxRawUrl ([string]$f.path) ([string]$Remote.ref)) + '?t=' + [DateTime]::UtcNow.Ticks, $dest)
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
