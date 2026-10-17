# Piki Optimizer installer
# Usage (PowerShell):  irm https://raw.githubusercontent.com/piki04/piki-optimizer/main/install.ps1 | iex
$ErrorActionPreference = 'Stop'
$repo = 'piki04/piki-optimizer'
$branch = 'main'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$dest = Join-Path $env:LOCALAPPDATA 'PikiOptimizer'
$base = "https://raw.githubusercontent.com/$repo/$branch"
function Get-Url([string]$rel) { return $base + '/' + ((($rel -replace '\\', '/').Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/') }
function Get-Sha([string]$p) {
    $s = [Security.Cryptography.SHA256]::Create(); $f = [IO.File]::OpenRead($p)
    try { return (($s.ComputeHash($f) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $f.Dispose(); $s.Dispose() }
}

Write-Host ''
Write-Host '  Piki Optimizer' -ForegroundColor Cyan -NoNewline; Write-Host ' - installazione / installing...'
$wc = New-Object Net.WebClient
$wc.Headers['User-Agent'] = 'Piki Optimizer-Installer'
$wc.Encoding = [Text.Encoding]::UTF8
$raw = $wc.DownloadString((Get-Url 'version.json') + '?t=' + [DateTime]::UtcNow.Ticks)
$m = $raw | ConvertFrom-Json
$i = 0; $n = @($m.files).Count
foreach ($f in $m.files) {
    $i++
    $rel = [string]$f.path
    if ($rel -match '\.\.') { continue }
    $out = Join-Path $dest ($rel -replace '/', '\')
    $dir = Split-Path -Parent $out
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-Progress -Activity 'Piki Optimizer' -Status $rel -PercentComplete (100 * $i / $n)
    $wc.DownloadFile((Get-Url $rel) + '?t=' + [DateTime]::UtcNow.Ticks, $out)
    if ((Get-Sha $out) -ne ([string]$f.sha256).ToLower()) { throw "Download corrotto / corrupted download: $rel" }
}
Write-Progress -Activity 'Piki Optimizer' -Completed
[IO.File]::WriteAllText((Join-Path $dest 'version.json'), $raw, (New-Object Text.UTF8Encoding($false)))

Write-Host "  OK! Piki Optimizer $($m.version)" -ForegroundColor Green
& powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $dest 'app\Setup.ps1') -Silent -Installed
