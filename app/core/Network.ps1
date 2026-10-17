# VeloxPC - network: ping/jitter tests, latency under load, DNS benchmark

$script:VxDnsProviders = @(
    @{ Name = 'Cloudflare'; P = '1.1.1.1'; S = '1.0.0.1' },
    @{ Name = 'Google'; P = '8.8.8.8'; S = '8.8.4.4' },
    @{ Name = 'Quad9'; P = '9.9.9.9'; S = '149.112.112.112' },
    @{ Name = 'OpenDNS'; P = '208.67.222.222'; S = '208.67.220.220' }
)
$script:VxDnsTestDomains = @('google.com', 'youtube.com', 'steampowered.com', 'riotgames.com', 'ea.com', 'twitch.tv')

function Get-VxPingTargets {
    param($Hw)
    $t = @()
    if ($Hw.Network -and $Hw.Network.Gateway) { $t += @{ Label = @{ it = 'Il tuo router'; en = 'Your router' }; Host = [string]$Hw.Network.Gateway } }
    $t += @{ Label = @{ it = 'Cloudflare (Internet)'; en = 'Cloudflare (Internet)' }; Host = '1.1.1.1' }
    $t += @{ Label = @{ it = 'Google (Internet)'; en = 'Google (Internet)' }; Host = '8.8.8.8' }
    $t += @{ Label = @{ it = 'Quad9 (Internet)'; en = 'Quad9 (Internet)' }; Host = '9.9.9.9' }
    return $t
}

function Get-VxPingQuality {
    # returns @(label, kind)
    param([double]$Avg, [double]$Jitter, [double]$Loss, [bool]$IsRouter)
    if ($Loss -ge 5) { return @((L @{ it = 'Pacchetti persi!'; en = 'Packet loss!' }), 'crit') }
    if ($IsRouter) {
        if ($Avg -le 3 -and $Jitter -le 2 -and $Loss -eq 0) { return @((L @{ it = 'Ottima'; en = 'Excellent' }), 'ok') }
        if ($Avg -le 10 -and $Jitter -le 6) { return @((L @{ it = 'Buona'; en = 'Good' }), 'ok') }
        return @((L @{ it = 'Instabile (Wi-Fi?)'; en = 'Unstable (Wi-Fi?)' }), 'warn')
    }
    if ($Avg -le 30 -and $Jitter -le 5 -and $Loss -eq 0) { return @((L @{ it = 'Ottima'; en = 'Excellent' }), 'ok') }
    if ($Avg -le 60 -and $Jitter -le 12 -and $Loss -lt 1) { return @((L @{ it = 'Buona'; en = 'Good' }), 'ok') }
    if ($Avg -le 100 -and $Jitter -le 25) { return @((L @{ it = 'Discreta'; en = 'Fair' }), 'warn') }
    return @((L @{ it = 'Scarsa'; en = 'Poor' }), 'crit')
}

function Get-VxBloatGrade {
    param([double]$Idle, [double]$Loaded)
    if ($Idle -lt 0 -or $Loaded -lt 0) { return @('?', 'info') }
    $d = $Loaded - $Idle
    if ($d -lt 5) { return @('A+', 'ok') }
    if ($d -lt 30) { return @('A', 'ok') }
    if ($d -lt 60) { return @('B', 'ok') }
    if ($d -lt 200) { return @('C', 'warn') }
    if ($d -lt 400) { return @('D', 'crit') }
    return @('F', 'crit')
}

function Invoke-VxDnsBenchmark {
    param($Hw)
    $rows = @()
    $current = @()
    if ($Hw.Network -and $Hw.Network.Dns) { $current = @(([string]$Hw.Network.Dns).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) }
    if ($current.Count -gt 0) {
        $rows += @{ Name = (L @{ it = 'Attuale'; en = 'Current' }); P = $current[0]; S = if ($current.Count -gt 1) { $current[1] } else { '' }; Current = $true }
    }
    foreach ($p in $script:VxDnsProviders) { $rows += @{ Name = $p.Name; P = $p.P; S = $p.S; Current = ($current -contains $p.P) } }
    foreach ($r in $rows) {
        $r.Ms = [VeloxPC.DnsBench]::Benchmark($r.P, [string[]]$script:VxDnsTestDomains, 3)
    }
    return $rows
}

function Set-VxDnsServers {
    param([int]$IfIndex, [string]$Primary, [string]$Secondary)
    Start-VxTx -Id 'dns' -Title (L @{ it = 'DNS più veloce'; en = 'Fastest DNS' })
    try {
        $prev = @((Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
        $dhcp = $true
        try {
            $guid = (Get-NetAdapter -InterfaceIndex $IfIndex -ErrorAction Stop).InterfaceGuid
            $ns = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -ErrorAction Stop).NameServer
            if ($ns) { $dhcp = $false }
        } catch { }
        Add-VxCustomUndo "dns|$IfIndex" @{ kind = 'dns'; ifIndex = $IfIndex; servers = $prev; dhcp = $dhcp }
        $list = @($Primary); if ($Secondary) { $list += $Secondary }
        Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $list -ErrorAction Stop
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Complete-VxTx
        return $true
    } catch {
        Complete-VxTx
        Write-VxLog "DNS change failed: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Invoke-VxNetworkReset {
    & netsh winsock reset 2>&1 | Out-Null
    & netsh int ip reset 2>&1 | Out-Null
    & ipconfig /flushdns 2>&1 | Out-Null
    Write-VxLog 'Network stack reset (reboot required)'
}

function Get-VxNetworkAdvice {
    param($Hw)
    $adv = @()
    $n = $Hw.Network
    if (-not $n) {
        $adv += @{ sev = 'crit'; text = (L @{ it = 'Nessuna connessione a Internet rilevata.'; en = 'No Internet connection detected.' }) }
        return $adv
    }
    if ($n.IsWifi) {
        $adv += @{ sev = 'warn'; text = (L @{ it = 'Sei in Wi-Fi: per giocare usa un cavo Ethernet. Il Wi-Fi aggiunge latenza e soprattutto "jitter" (ping che salta). Se non puoi, usa la rete a 5 GHz o 6 GHz e stai vicino al router.'; en = 'You are on Wi-Fi: use an Ethernet cable for gaming. Wi-Fi adds latency and especially jitter (jumping ping). If you cannot, use the 5 GHz or 6 GHz band and stay close to the router.' }) }
    } else {
        $adv += @{ sev = 'ok'; text = (L @{ it = 'Sei collegato via cavo: ottimo per il ping.'; en = 'You are on a cable: great for ping.' }) }
        if ($n.LinkBps -gt 0 -and $n.LinkBps -le 100000000) {
            $adv += @{ sev = 'warn'; text = (L @{ it = "La scheda di rete è collegata a solo $($n.LinkSpeed). Di solito è un cavo vecchio/rovinato (usa un Cat5e o Cat6) o una porta del router lenta."; en = "The network card is linked at only $($n.LinkSpeed). Usually an old/damaged cable (use Cat5e or Cat6) or a slow router port." }) }
        }
    }
    $adv += @{ sev = 'info'; text = (L @{ it = 'Il DNS non abbassa il ping in partita: rende solo più veloce l''apertura di siti e il collegamento ai server.'; en = 'DNS does not lower in-game ping: it only speeds up opening sites and connecting to servers.' }) }
    $adv += @{ sev = 'info'; text = (L @{ it = 'Se il test "sotto carico" dà C o peggio, attiva QoS/SQM nel router: elimina i picchi di ping quando qualcuno in casa scarica o guarda video.'; en = 'If the "under load" test scores C or worse, enable QoS/SQM on your router: it removes ping spikes when someone at home downloads or streams.' }) }
    return $adv
}
