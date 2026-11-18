# VeloxPC - services, startup apps and running processes, each with plain-language advice
# Level: 1 = Light (safe), 2 = Balanced, 3 = Maximum, 0 = never touch (shown only as advice)

$script:VxServices = @(
    @{ Name = 'DiagTrack'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Telemetria Microsoft'; en = 'Microsoft telemetry' }
        Desc = @{ it = 'Invia dati di utilizzo a Microsoft in continuazione. Non serve a te.'; en = 'Constantly sends usage data to Microsoft. It does nothing for you.' } },
    @{ Name = 'dmwappushservice'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Instradamento messaggi WAP (telemetria)'; en = 'WAP push message routing (telemetry)' }
        Desc = @{ it = 'Servizio di supporto alla telemetria.'; en = 'Telemetry support service.' } },
    @{ Name = 'MapsBroker'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Gestione mappe scaricate'; en = 'Downloaded Maps Manager' }
        Desc = @{ it = 'Aggiorna le mappe offline dell''app Mappe, che quasi nessuno usa.'; en = 'Updates offline maps for the Maps app, which almost nobody uses.' } },
    @{ Name = 'RetailDemo'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Modalità demo negozio'; en = 'Retail Demo' }
        Desc = @{ it = 'Serve solo ai PC esposti nei negozi.'; en = 'Only used by PCs on display in shops.' } },
    @{ Name = 'Fax'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Fax'; en = 'Fax' }
        Desc = @{ it = 'Invio e ricezione fax dal PC.'; en = 'Sending and receiving faxes from the PC.' } },
    @{ Name = 'RemoteRegistry'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Registro di sistema remoto'; en = 'Remote Registry' }
        Desc = @{ it = 'Permette ad altri PC di modificare il tuo registro. Meglio spento anche per sicurezza.'; en = 'Lets other PCs edit your registry. Better off, also for security.' } },
    @{ Name = 'TrkWks'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Rilevamento collegamenti distribuiti'; en = 'Distributed Link Tracking' }
        Desc = @{ it = 'Tiene traccia dei file spostati tra PC di una rete aziendale.'; en = 'Tracks files moved between PCs on a corporate network.' } },
    @{ Name = 'WMPNetworkSvc'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Condivisione Windows Media Player'; en = 'Windows Media Player sharing' }
        Desc = @{ it = 'Condivide la libreria di Windows Media Player in rete.'; en = 'Shares the Windows Media Player library on the network.' } },
    @{ Name = 'SEMgrSvc'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Pagamenti e NFC'; en = 'Payments and NFC' }
        Desc = @{ it = 'Pagamenti contactless tramite NFC del PC.'; en = 'Contactless payments via the PC''s NFC.' } },
    @{ Name = 'WalletService'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Portafoglio'; en = 'Wallet' }
        Desc = @{ it = 'Vecchio servizio portafoglio di Windows.'; en = 'Old Windows wallet service.' } },
    @{ Name = 'AJRouter'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Router AllJoyn'; en = 'AllJoyn Router' }
        Desc = @{ it = 'Protocollo per dispositivi smart-home ormai abbandonato.'; en = 'Abandoned smart-home device protocol.' } },
    @{ Name = 'diagnosticshub.standardcollector.service'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Raccolta diagnostica per sviluppatori'; en = 'Developer diagnostics collector' }
        Desc = @{ it = 'Usato solo da Visual Studio per analisi delle prestazioni.'; en = 'Only used by Visual Studio for profiling.' } },
    @{ Name = 'wercplsupport'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Pannello segnalazione problemi'; en = 'Problem Reports panel' }
        Desc = @{ it = 'Mostra la cronologia delle segnalazioni di errore.'; en = 'Shows the history of error reports.' } },
    @{ Name = 'WpcMonSvc'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Controllo genitori'; en = 'Parental Controls' }
        Desc = @{ it = 'Serve solo se usi Microsoft Family per controllare un account di un minore.'; en = 'Only needed if you use Microsoft Family to supervise a child account.' } },
    @{ Name = 'SCardSvr'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Smart card'; en = 'Smart Card' }
        Desc = @{ it = 'Lettori di smart card (es. CNS/firma digitale).'; en = 'Smart card readers (e.g. ID cards, digital signature).' }
        Need = { param($hw) if ($hw.Ctx.HasSmartCard) { @{ it = 'Hai un lettore di smart card'; en = 'You have a smart card reader' } } } },
    @{ Name = 'ScDeviceEnum'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Enumerazione smart card'; en = 'Smart Card Device Enumeration' }
        Desc = @{ it = 'Rileva le smart card inserite.'; en = 'Detects inserted smart cards.' }
        Need = { param($hw) if ($hw.Ctx.HasSmartCard) { @{ it = 'Hai un lettore di smart card'; en = 'You have a smart card reader' } } } },
    @{ Name = 'wisvc'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Programma Windows Insider'; en = 'Windows Insider Service' }
        Desc = @{ it = 'Serve solo per ricevere le versioni di prova di Windows.'; en = 'Only needed to receive Windows preview builds.' }
        Need = { param($hw) if ($hw.Ctx.IsInsider) { @{ it = 'Sei iscritto a Windows Insider'; en = 'You are a Windows Insider' } } } },
    @{ Name = 'edgeupdate'; Pattern = 'edgeupdate*'; Level = 0; Target = 'Manual'; Risk = 'avoid'
        Title = @{ it = 'Aggiornamento Microsoft Edge'; en = 'Microsoft Edge Update' }
        Desc = @{ it = 'Porta gli aggiornamenti di sicurezza: Piki non lo tocca. In "Manuale" o disattivato le correzioni arrivano in ritardo.'; en = 'It delivers security fixes: Piki does not touch it. On "Manual" or disabled, fixes arrive late.' } },
    @{ Name = 'GoogleUpdater'; Pattern = 'GoogleUpdater*'; Level = 0; Target = 'Manual'; Risk = 'avoid'
        Title = @{ it = 'Aggiornamento Google Chrome'; en = 'Google Chrome Update' }
        Desc = @{ it = 'Porta gli aggiornamenti di sicurezza: Piki non lo tocca. In "Manuale" o disattivato le correzioni arrivano in ritardo.'; en = 'It delivers security fixes: Piki does not touch it. On "Manual" or disabled, fixes arrive late.' } },
    @{ Name = 'gupdate'; Pattern = 'gupdate*'; Level = 0; Target = 'Manual'; Risk = 'avoid'
        Title = @{ it = 'Aggiornamento Google (vecchio)'; en = 'Google Update (legacy)' }
        Desc = @{ it = 'Porta gli aggiornamenti di sicurezza: Piki non lo tocca. In "Manuale" o disattivato le correzioni arrivano in ritardo.'; en = 'It delivers security fixes: Piki does not touch it. On "Manual" or disabled, fixes arrive late.' } },
    @{ Name = 'AdobeARMservice'; Level = 0; Target = 'Manual'; Risk = 'avoid'
        Title = @{ it = 'Aggiornamento Adobe Acrobat'; en = 'Adobe Acrobat Update' }
        Desc = @{ it = 'Porta gli aggiornamenti di sicurezza: Piki non lo tocca. In "Manuale" o disattivato le correzioni arrivano in ritardo.'; en = 'It delivers security fixes: Piki does not touch it. On "Manual" or disabled, fixes arrive late.' } },
    @{ Name = 'MozillaMaintenance'; Level = 0; Target = 'Manual'; Risk = 'avoid'
        Title = @{ it = 'Manutenzione Firefox'; en = 'Firefox Maintenance' }
        Desc = @{ it = 'Porta gli aggiornamenti di sicurezza: Piki non lo tocca. In "Manuale" o disattivato le correzioni arrivano in ritardo.'; en = 'It delivers security fixes: Piki does not touch it. On "Manual" or disabled, fixes arrive late.' } },
    @{ Name = 'NvTelemetryContainer'; Level = 1; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Telemetria NVIDIA'; en = 'NVIDIA telemetry' }
        Desc = @{ it = 'Invia dati di utilizzo a NVIDIA. I driver funzionano uguale.'; en = 'Sends usage data to NVIDIA. Drivers work the same.' } },

    @{ Name = 'Spooler'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Stampa (Spooler)'; en = 'Printing (Spooler)' }
        Desc = @{ it = 'Gestisce le stampanti. Se non stampi mai, è inutile.'; en = 'Manages printers. Useless if you never print.' }
        Warn = @{ it = 'Anche "Stampa su PDF" smetterà di funzionare.'; en = '"Print to PDF" will stop working too.' }
        Need = { param($hw) if ($hw.Ctx.HasPrinter) { @{ it = 'Hai una stampante installata'; en = 'You have a printer installed' } } } },
    @{ Name = 'PrintNotify'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Notifiche stampanti'; en = 'Printer notifications' }
        Desc = @{ it = 'Mostra avvisi delle stampanti (inchiostro, carta...).'; en = 'Shows printer alerts (ink, paper...).' }
        Need = { param($hw) if ($hw.Ctx.HasPrinter) { @{ it = 'Hai una stampante installata'; en = 'You have a printer installed' } } } },
    @{ Name = 'SysMain'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'SysMain (Superfetch)'; en = 'SysMain (Superfetch)' }
        Desc = @{ it = 'Precarica in RAM i programmi che usi spesso. Su un SSD veloce il vantaggio è minimo e a volte causa uso del disco al 100%.'; en = 'Preloads frequently used apps into RAM. On a fast SSD the benefit is tiny and it sometimes causes 100% disk usage.' }
        Need = { param($hw) if (-not $hw.SystemOnSSD) { @{ it = 'Windows è su un disco meccanico: SysMain lo velocizza'; en = 'Windows is on a hard drive: SysMain speeds it up' } } } },
    @{ Name = 'bthserv'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Bluetooth'; en = 'Bluetooth' }
        Desc = @{ it = 'Necessario per cuffie, controller, mouse e tastiere Bluetooth.'; en = 'Needed for Bluetooth headphones, controllers, mice and keyboards.' }
        Need = { param($hw) if ($hw.Ctx.HasBluetooth) { @{ it = 'Il tuo PC ha il Bluetooth: se usi cuffie o controller wireless serve'; en = 'Your PC has Bluetooth: needed for wireless headsets or controllers' } } } },
    @{ Name = 'BTAGService'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Audio Bluetooth (chiamate)'; en = 'Bluetooth audio gateway' }
        Desc = @{ it = 'Microfono delle cuffie Bluetooth.'; en = 'Microphone of Bluetooth headsets.' }
        Need = { param($hw) if ($hw.Ctx.HasBluetooth) { @{ it = 'Il tuo PC ha il Bluetooth'; en = 'Your PC has Bluetooth' } } } },
    @{ Name = 'WbioSrvc'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Biometria (Windows Hello)'; en = 'Biometrics (Windows Hello)' }
        Desc = @{ it = 'Accesso con impronta digitale o riconoscimento del volto.'; en = 'Sign-in with fingerprint or face recognition.' }
        Need = { param($hw) if ($hw.Ctx.HasBiometric) { @{ it = 'Hai un lettore di impronte o una camera Windows Hello'; en = 'You have a fingerprint reader or Windows Hello camera' } } } },
    @{ Name = 'StiSvc'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Acquisizione immagini (scanner)'; en = 'Windows Image Acquisition (scanners)' }
        Desc = @{ it = 'Serve per scanner e alcune fotocamere collegate via USB.'; en = 'Needed for scanners and some USB cameras.' }
        Need = { param($hw) if ($hw.Ctx.HasScanner) { @{ it = 'Hai uno scanner o un dispositivo immagini'; en = 'You have a scanner or imaging device' } } } },
    @{ Name = 'PcaSvc'; Level = 2; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Assistente compatibilità programmi'; en = 'Program Compatibility Assistant' }
        Desc = @{ it = 'Controlla ogni programma avviato per proporre correzioni di compatibilità a quelli molto vecchi.'; en = 'Checks every launched program to suggest compatibility fixes for very old ones.' } },
    @{ Name = 'WerSvc'; Level = 2; Target = 'Disabled'; Risk = 'safe'
        Title = @{ it = 'Segnalazione errori Windows'; en = 'Windows Error Reporting' }
        Desc = @{ it = 'Quando un programma si blocca, raccoglie dati e li invia a Microsoft.'; en = 'When an app crashes, it collects data and sends it to Microsoft.' } },
    @{ Name = 'lfsvc'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Geolocalizzazione'; en = 'Geolocation' }
        Desc = @{ it = 'Fornisce la tua posizione alle app.'; en = 'Provides your location to apps.' }
        Warn = @{ it = 'Meteo automatico, "Trova il mio dispositivo" e fuso orario automatico non funzioneranno.'; en = 'Automatic weather, "Find my device" and automatic time zone will not work.' } },
    @{ Name = 'PhoneSvc'; Level = 2; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Servizio telefonia'; en = 'Phone Service' }
        Desc = @{ it = 'Gestisce le chiamate per app come Collegamento al telefono.'; en = 'Manages calls for apps like Phone Link.' } },
    @{ Name = 'AnyDesk'; Pattern = 'AnyDesk*'; Level = 2; Target = 'Manual'; Risk = 'caution'
        Title = @{ it = 'AnyDesk (accesso remoto)'; en = 'AnyDesk (remote access)' }
        Desc = @{ it = 'Tiene AnyDesk sempre in ascolto. In "Manuale" funziona quando lo apri tu.'; en = 'Keeps AnyDesk always listening. On "Manual" it works when you open it.' }
        Warn = @{ it = 'Nessuno potrà collegarsi al PC se AnyDesk non è aperto (accesso non presidiato).'; en = 'Nobody can connect to the PC unless AnyDesk is open (unattended access).' } },
    @{ Name = 'TeamViewer'; Pattern = 'TeamViewer*'; Level = 2; Target = 'Manual'; Risk = 'caution'
        Title = @{ it = 'TeamViewer (accesso remoto)'; en = 'TeamViewer (remote access)' }
        Desc = @{ it = 'In "Manuale" funziona quando lo apri tu.'; en = 'On "Manual" it works when you open it.' }
        Warn = @{ it = 'Niente accesso non presidiato.'; en = 'No unattended access.' } },

    @{ Name = 'WSearch'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Indicizzazione ricerca'; en = 'Search indexing' }
        Desc = @{ it = 'Scansiona continuamente i file per rendere la ricerca istantanea.'; en = 'Continuously scans your files to make search instant.' }
        Warn = @{ it = 'Cercare file in Esplora file e nel menu Start diventa lento; anche la ricerca di Outlook.'; en = 'Searching files in Explorer and Start becomes slow; Outlook search too.' } },
    @{ Name = 'TermService'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Desktop remoto'; en = 'Remote Desktop' }
        Desc = @{ it = 'Permette di controllare questo PC con Desktop remoto di Windows (non serve per AnyDesk/TeamViewer).'; en = 'Lets others control this PC with Windows Remote Desktop (not needed for AnyDesk/TeamViewer).' }
        Need = { param($hw) if ($hw.Ctx.UsesRdp) { @{ it = 'Desktop remoto è attivo su questo PC'; en = 'Remote Desktop is enabled on this PC' } } } },
    @{ Name = 'iphlpsvc'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Helper IP (IPv6)'; en = 'IP Helper (IPv6)' }
        Desc = @{ it = 'Tunnel IPv6 su reti IPv4.'; en = 'IPv6 tunnelling over IPv4 networks.' }
        Warn = @{ it = 'Party chat Xbox e alcune VPN possono smettere di funzionare.'; en = 'Xbox party chat and some VPNs may stop working.' }
        Need = { param($hw) if ($hw.Ctx.HasXbox) { @{ it = 'Usi l''app Xbox (party chat)'; en = 'You use the Xbox app (party chat)' } } } },
    @{ Name = 'SSDPSRV'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Rilevamento dispositivi di rete (SSDP)'; en = 'Network device discovery (SSDP)' }
        Desc = @{ it = 'Trova TV, NAS e dispositivi multimediali in rete.'; en = 'Finds TVs, NAS and media devices on the network.' }
        Warn = @{ it = 'Trasmettere a una TV (DLNA) e vedere dispositivi in Rete potrebbe non funzionare.'; en = 'Casting to a TV (DLNA) and seeing devices in Network may not work.' } },
    @{ Name = 'XblAuthManager'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Accesso Xbox Live'; en = 'Xbox Live Auth Manager' }
        Desc = @{ it = 'Login Xbox per app Xbox, Game Pass e giochi Microsoft (es. Minecraft, Forza).'; en = 'Xbox sign-in for the Xbox app, Game Pass and Microsoft games (e.g. Minecraft, Forza).' }
        Need = { param($hw) if ($hw.Ctx.HasXbox) { @{ it = 'Hai l''app Xbox / Game Pass'; en = 'You have the Xbox app / Game Pass' } } } },
    @{ Name = 'XblGameSave'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Salvataggi Xbox nel cloud'; en = 'Xbox cloud saves' }
        Desc = @{ it = 'Sincronizza i salvataggi dei giochi Xbox / Game Pass.'; en = 'Syncs Xbox / Game Pass game saves.' }
        Need = { param($hw) if ($hw.Ctx.HasXbox) { @{ it = 'Hai l''app Xbox / Game Pass'; en = 'You have the Xbox app / Game Pass' } } } },
    @{ Name = 'XboxNetApiSvc'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Rete Xbox Live'; en = 'Xbox Live Networking' }
        Desc = @{ it = 'Multigiocatore dei giochi Xbox / Game Pass.'; en = 'Multiplayer for Xbox / Game Pass games.' }
        Need = { param($hw) if ($hw.Ctx.HasXbox) { @{ it = 'Hai l''app Xbox / Game Pass'; en = 'You have the Xbox app / Game Pass' } } } },
    @{ Name = 'lmhosts'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Helper NetBIOS'; en = 'NetBIOS helper' }
        Desc = @{ it = 'Condivisione file con PC e NAS molto vecchi.'; en = 'File sharing with very old PCs and NAS.' }
        Warn = @{ it = 'Cartelle condivise su vecchi NAS potrebbero non comparire.'; en = 'Shared folders on old NAS may not appear.' } },
    @{ Name = 'DPS'; Level = 3; Target = 'Disabled'; Risk = 'caution'
        Title = @{ it = 'Servizio criteri di diagnostica'; en = 'Diagnostic Policy Service' }
        Desc = @{ it = 'Rileva problemi e alimenta gli strumenti "Risoluzione problemi".'; en = 'Detects problems and powers the Troubleshooters.' }
        Warn = @{ it = 'Le procedure guidate di risoluzione problemi non funzioneranno.'; en = 'Windows troubleshooters will not work.' } },

    # ---- never touch: shown so users know why other "optimizers" are wrong
    @{ Name = 'wuauserv'; Level = 0; Target = 'Disabled'; Risk = 'avoid'
        Title = @{ it = 'Windows Update'; en = 'Windows Update' }
        Desc = @{ it = 'Molti ottimizzatori lo disattivano: è un errore. Senza aggiornamenti il PC resta esposto a virus e ai bug già corretti.'; en = 'Many optimizers disable it: that is a mistake. Without updates the PC stays exposed to malware and already-fixed bugs.' } },
    @{ Name = 'TextInputManagementService'; Level = 0; Target = 'Disabled'; Risk = 'avoid'
        Title = @{ it = 'Tastiera virtuale e input testo'; en = 'Touch keyboard and text input' }
        Desc = @{ it = 'Su Windows 11 disattivarlo impedisce di scrivere nel menu Start, nella ricerca e nelle emoji.'; en = 'On Windows 11 disabling it stops you typing in Start, search and the emoji panel.' } },
    @{ Name = 'Audiosrv'; Level = 0; Target = 'Disabled'; Risk = 'avoid'
        Title = @{ it = 'Audio di Windows'; en = 'Windows Audio' }
        Desc = @{ it = 'Senza questo servizio il PC non ha audio.'; en = 'Without this service the PC has no sound.' } },
    @{ Name = 'mpssvc'; Level = 0; Target = 'Disabled'; Risk = 'avoid'
        Title = @{ it = 'Firewall di Windows'; en = 'Windows Firewall' }
        Desc = @{ it = 'Ti protegge dagli attacchi dalla rete. Non migliora il ping disattivarlo.'; en = 'Protects you from network attacks. Turning it off does not improve ping.' } },
    @{ Name = 'Dnscache'; Level = 0; Target = 'Disabled'; Risk = 'avoid'
        Title = @{ it = 'Client DNS'; en = 'DNS Client' }
        Desc = @{ it = 'Ricorda gli indirizzi dei siti: disattivarlo rende Internet più lenta, non più veloce.'; en = 'Remembers website addresses: disabling it makes the Internet slower, not faster.' } },
    @{ Name = 'Themes'; Level = 0; Target = 'Disabled'; Risk = 'avoid'
        Title = @{ it = 'Temi'; en = 'Themes' }
        Desc = @{ it = 'Disattivarlo rende Windows brutto e non dà FPS in più.'; en = 'Disabling it makes Windows ugly and gives no extra FPS.' } }
)

function Get-VxSvcMatches {
    param($Entry)
    if ($Entry.Pattern) { return @(Get-Service -Name $Entry.Pattern -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_[0-9a-f]{4,}$' }) }
    $s = Get-Service -Name $Entry.Name -ErrorAction SilentlyContinue
    if ($s) { return @($s) }
    return @()
}

function Get-VxServiceRows {
    param($Hw)
    $b = Get-VxBackup
    $rows = @()
    foreach ($e in $script:VxServices) {
        foreach ($s in (Get-VxSvcMatches $e)) {
            $st = Get-VxSvcStart $s.Name
            if (-not $st) { continue }
            $need = $null
            if ($e.Need) { try { $need = & $e.Need $Hw } catch { } }
            $targetVal = if ($e.Target -eq 'Disabled') { 4 } else { 3 }
            $rows += [pscustomobject]@{
                Id = "svc:$($s.Name)"
                Name = $s.Name
                Display = [string]$s.DisplayName
                Entry = $e
                Start = $st.start
                Running = ([string]$s.Status -eq 'Running')
                Need = $need
                Applied = ($st.start -ge $targetVal)
                CanUndo = $b.entries.ContainsKey("svc:$($s.Name)")
            }
        }
    }
    return $rows
}

function Set-VxServiceOptimized {
    param([string]$Name, [string]$Target, [string]$Title)
    Start-VxTx -Id "svc:$Name" -Title $Title
    $ok = Set-VxSvc -Name $Name -StartType $Target
    Complete-VxTx
    return $ok
}

# ---------------------------------------------------------------- startup apps
$script:VxStartupAdvice = @(
    @{ P = 'Nexus|Winstep'; Risk = 'avoid'; A = @{ it = 'Dock Winstep Nexus: protetta da Piki, resta all''avvio.'; en = 'Winstep Nexus dock: protected by Piki, it stays at startup.' } },
    @{ P = 'SecurityHealth|Windows Security|WindowsDefender'; Risk = 'avoid'; A = @{ it = 'Sicurezza di Windows: lasciala attiva.'; en = 'Windows Security: keep it on.' } },
    @{ P = 'SynTP|ETDCtrl|Elan|Synaptics|TouchPad|Precision'; Risk = 'avoid'; A = @{ it = 'Driver del touchpad: senza, gesti e scorrimento possono smettere di funzionare.'; en = 'Touchpad driver: without it gestures and scrolling may stop working.' } },
    @{ P = 'RtkAud|RAVCpl|RAVBg|Realtek|Waves|MaxxAudio|Nahimic|A-Volute|DTS|Dolby|SonicStudio|Sonic Studio'; Risk = 'caution'; A = @{ it = 'Pannello/effetti audio: senza, alcuni effetti o il rilevamento del jack cuffie potrebbero non funzionare.'; en = 'Audio panel/effects: without it some effects or headphone-jack detection may not work.' } },
    @{ P = 'IGCC|igfx|Intel.*Graphics|HD Audio Background'; Risk = 'caution'; A = @{ it = 'Componente driver Intel: in genere si può disattivare, ma alcune scorciatoie grafiche smettono di funzionare.'; en = 'Intel driver component: usually safe to disable, but some graphics shortcuts stop working.' } },
    @{ P = 'NVIDIA|nvcpl|NvBackend|NvTmru|ShadowPlay'; Risk = 'caution'; A = @{ it = 'App NVIDIA: overlay e registrazioni partono solo aprendo l''app. Il driver funziona comunque.'; en = 'NVIDIA app: overlay and recording only start when you open the app. The driver keeps working.' } },
    @{ P = 'Radeon|AMD Software|cncmd|RadeonSoftware'; Risk = 'caution'; A = @{ it = 'Software AMD: overlay e statistiche partono solo aprendolo. I profili del driver restano attivi.'; en = 'AMD Software: overlay and stats only start when opened. Driver profiles stay active.' } },
    @{ P = 'MSI ?Afterburner|RTSS|RivaTuner|EVGA ?Precision'; Risk = 'caution'; A = @{ it = 'Overclock/curva ventole della GPU e contatore FPS non verranno applicati finché non lo apri.'; en = 'GPU overclock/fan curve and FPS counter will not be applied until you open it.' } },
    @{ P = 'TRCC|Thermalright|NZXT ?CAM|Lian ?Li|L-Connect|Fan ?Control|Argus'; Risk = 'caution'; A = @{ it = 'Controllo dissipatore/ventole/display: senza, il display del dissipatore o le curve ventole non funzionano.'; en = 'Cooler/fan/display control: without it the cooler display or fan curves will not work.' } },
    @{ P = 'iCUE|Corsair|LGHUB|G ?HUB|Logitech|Razer|Synapse|SteelSeries|GG\.exe|Attack ?Shark|AULA|HyperX|NGENUITY|Glorious|Wooting|ASUS|Armoury|MSI ?Center|Dragon ?Center|RGB ?Fusion|OpenRGB|SignalRGB|Mystic'; Risk = 'caution'; A = @{ it = 'Software periferiche/RGB: i profili salvati nella memoria del mouse/tastiera restano, quelli solo software (macro, luci) no.'; en = 'Peripheral/RGB software: profiles stored on the mouse/keyboard stay, software-only ones (macros, lighting) do not.' } },
    @{ P = 'Wallpaper ?Engine|wallpaper32|wallpaper64|webwallpaper'; Risk = 'caution'; A = @{ it = 'Sfondo animato: consuma GPU. Se lo tieni, nelle sue impostazioni metti "Pausa" quando un''app è a schermo intero.'; en = 'Animated wallpaper: uses GPU. If you keep it, set it to "Pause" when another app is fullscreen.' } },
    @{ P = 'OneDrive|MEGAsync|MEGA|Dropbox|GoogleDrive|Google Drive|iCloud|pCloud|Sync'; Risk = 'caution'; A = @{ it = 'Sincronizzazione cloud: i file non si sincronizzano finché non apri il programma.'; en = 'Cloud sync: files will not sync until you open the program.' } },
    @{ P = 'Creative Cloud|CCXProcess|Adobe Desktop|AdobeGC|CCLibrary|CoreSync|Adobe Creative'; Risk = 'caution'; A = @{ it = 'Adobe Creative Cloud: After Effects funziona lo stesso, ma Adobe Fonts e Librerie si attivano solo aprendo Creative Cloud.'; en = 'Adobe Creative Cloud: After Effects still works, but Adobe Fonts and Libraries only activate when Creative Cloud is open.' } },
    @{ P = 'Discord'; Risk = 'safe'; A = @{ it = 'Si apre in un attimo quando ti serve.'; en = 'Opens in a second when you need it.' } },
    @{ P = 'Spotify|Deezer|Apple ?Music|TIDAL'; Risk = 'safe'; A = @{ it = 'Aprilo quando vuoi ascoltare musica.'; en = 'Open it when you want to listen to music.' } },
    @{ P = 'Steam|EpicGames|Epic Games|Ubisoft|upc\.exe|UplayWeb|Rockstar|EADesktop|EA app|Origin|Battle\.net|GOG|Galaxy|Riot|Xbox|Playnite|Heroic'; Risk = 'safe'; A = @{ it = 'Launcher giochi: si apre quando avvii un gioco; gli aggiornamenti partono all''apertura.'; en = 'Game launcher: opens when you launch a game; updates start when opened.' } },
    @{ P = 'Teams|Skype|Zoom|Slack|WhatsApp|Telegram|Messenger|Signal'; Risk = 'safe'; A = @{ it = 'Messaggi/chiamate: riceverai notifiche solo quando è aperto.'; en = 'Chat/calls: you only get notifications while it is open.' } },
    @{ P = 'AnyDesk|TeamViewer|Parsec|RustDesk'; Risk = 'safe'; A = @{ it = 'Accesso remoto: aprilo quando ti serve.'; en = 'Remote access: open it when you need it.' } },
    @{ P = 'Overwolf|CurseForge|Medal|Outplayed|Insights|Blitz|Porofessor|Mobalytics'; Risk = 'safe'; A = @{ it = 'App companion per giochi: pesante in background.'; en = 'Gaming companion app: heavy in the background.' } },
    @{ P = 'Edge|msedge|Chrome|Opera|Brave|Firefox|Vivaldi'; Risk = 'safe'; A = @{ it = 'Browser pre-caricato: si apre comunque in un attimo.'; en = 'Pre-loaded browser: it still opens in a moment.' } },
    @{ P = 'Copilot|Cortana|YourPhone|PhoneExperience|Phone Link'; Risk = 'safe'; A = @{ it = 'Si può disattivare senza problemi.'; en = 'Safe to disable.' } },
    @{ P = 'Update|Updater|jusched|AdobeARM'; Risk = 'caution'; A = @{ it = 'Controllo aggiornamenti: se lo disattivi, il programma riceve le correzioni di sicurezza solo quando lo apri.'; en = 'Update checker: if you disable it, the app only gets security fixes when you open it.' } },
    @{ P = 'OBS|Streamlabs|XSplit'; Risk = 'safe'; A = @{ it = 'Aprilo quando registri o fai live.'; en = 'Open it when you record or stream.' } },
    @{ P = 'Docker|WSL|VirtualBox|VMware'; Risk = 'caution'; A = @{ it = 'Virtualizzazione: disattivalo se non lavori con container o macchine virtuali.'; en = 'Virtualisation: disable it if you do not work with containers or VMs.' } }
)

function Get-VxStartupAdvice {
    param([string]$Text)
    foreach ($a in $script:VxStartupAdvice) { if ($Text -match $a.P) { return $a } }
    return @{ Risk = 'info'; A = @{ it = 'Programma non riconosciuto: se non ti serve appena accendi il PC, puoi disattivarlo. Puoi sempre riattivarlo.'; en = 'Unrecognised program: if you do not need it right at startup, you can disable it. You can always re-enable it.' } }
}

function Get-VxApprovedEnabled {
    param([string]$Path, [string]$Name)
    $s = Get-VxRegState $Path $Name
    if (-not $s.existed) { return $true }
    try { $bytes = [Convert]::FromBase64String([string]$s.value); return (($bytes[0] % 2) -eq 0) } catch { return $true }
}

function Get-VxStartupItems {
    $items = @()
    $sources = @(
        @{ Reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Scope = 'user' },
        @{ Reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Scope = 'all' },
        @{ Reg = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Scope = 'all' }
    )
    foreach ($src in $sources) {
        if (-not (Test-Path -LiteralPath $src.Reg)) { continue }
        $key = Get-Item -LiteralPath $src.Reg
        foreach ($n in $key.GetValueNames()) {
            if (-not $n) { continue }
            $cmd = [string]$key.GetValue($n)
            $items += [pscustomobject]@{
                Id = 'start:' + (Get-VxShortHash ($src.Reg + '|' + $n))
                Name = $n; Command = $cmd; Kind = 'run'; Scope = $src.Scope
                ApprovedPath = $src.Approved; ApprovedName = $n
                Enabled = (Get-VxApprovedEnabled $src.Approved $n)
            }
        }
    }
    $folders = @(
        @{ Dir = [Environment]::GetFolderPath('Startup'); Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Scope = 'user' },
        @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Scope = 'all' }
    )
    foreach ($f in $folders) {
        if (-not $f.Dir -or -not (Test-Path -LiteralPath $f.Dir)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $f.Dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
            $items += [pscustomobject]@{
                Id = 'start:' + (Get-VxShortHash ($f.Dir + '|' + $file.Name))
                Name = [IO.Path]::GetFileNameWithoutExtension($file.Name); Command = $file.FullName; Kind = 'run'; Scope = $f.Scope
                ApprovedPath = $f.Approved; ApprovedName = $file.Name
                Enabled = (Get-VxApprovedEnabled $f.Approved $file.Name)
            }
        }
    }
    # Store apps with a startup task (Teams, Spotify, WhatsApp...)
    $appBase = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
    if (Test-Path -LiteralPath $appBase) {
        foreach ($pkg in @(Get-ChildItem -LiteralPath $appBase -ErrorAction SilentlyContinue)) {
            foreach ($task in @(Get-ChildItem -LiteralPath $pkg.PSPath -ErrorAction SilentlyContinue)) {
                $st = (Get-ItemProperty -LiteralPath $task.PSPath -ErrorAction SilentlyContinue).State
                if ($null -eq $st) { continue }
                $friendly = ($pkg.PSChildName -replace '_[a-z0-9]{13}$', '') -replace '^[0-9A-F]+\.', '' -replace '^Microsoft\.', ''
                $items += [pscustomobject]@{
                    Id = 'start:' + (Get-VxShortHash ($pkg.PSChildName + '|' + $task.PSChildName))
                    Name = $friendly; Command = $pkg.PSChildName; Kind = 'appx'; Scope = 'user'
                    ApprovedPath = "$appBase\$($pkg.PSChildName)\$($task.PSChildName)"; ApprovedName = 'State'
                    Enabled = ([int]$st -eq 2 -or [int]$st -eq 4)
                }
            }
        }
    }
    $impact = Get-VxStartupImpactMap
    foreach ($i in $items) {
        $adv = Get-VxStartupAdvice ($i.Name + ' ' + $i.Command)
        $i | Add-Member -NotePropertyName Advice -NotePropertyValue $adv -Force
        $exe = Get-VxStartupExe $i
        $imp = $null
        if ($exe -and $impact.ContainsKey($exe.ToLowerInvariant())) { $imp = $impact[$exe.ToLowerInvariant()] }
        elseif ($i.Kind -eq 'appx') { foreach ($k in $impact.Keys) { if ($impact[$k].path -like "*\WindowsApps\$($i.Command)*") { $imp = $impact[$k]; break } } }
        $i | Add-Member -NotePropertyName Impact -NotePropertyValue $(if ($imp) { Get-VxImpactLevel $imp.cpuMs $imp.disk } else { '' }) -Force
        $i | Add-Member -NotePropertyName ImpactCpuMs -NotePropertyValue $(if ($imp) { [int]$imp.cpuMs } else { -1 }) -Force
        $i | Add-Member -NotePropertyName ImpactDisk -NotePropertyValue $(if ($imp) { [int64]$imp.disk } else { -1 }) -Force
        $pub = ''
        try { if ($exe -and (Test-Path -LiteralPath $exe)) { $pub = [string][System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).CompanyName } } catch { }
        $i | Add-Member -NotePropertyName Publisher -NotePropertyValue $pub.Trim() -Force
    }
    $rank = @{ high = 0; medium = 1; low = 2; '' = 3 }
    return @($items | Sort-Object @{ Expression = { if ($_.Enabled) { 0 } else { 1 } } }, @{ Expression = { $rank[[string]$_.Impact] } }, Name)
}

# ---- startup impact: same source Task Manager uses (CPU time and disk read by each startup app at the last boots)
function Get-VxImpactLevel {
    # Task Manager thresholds: High > 1 s CPU or > 3 MB disk; Medium > 300 ms or > 300 KB; otherwise Low
    param([double]$CpuMs, [double]$DiskBytes)
    if ($CpuMs -gt 1000 -or $DiskBytes -gt 3MB) { return 'high' }
    if ($CpuMs -gt 300 -or $DiskBytes -gt 300KB) { return 'medium' }
    return 'low'
}

function ConvertFrom-VxStartupInfoXml {
    # one StartupInfo XML -> list of @{ exe; path; cpuMs; disk }
    param([string]$Xml)
    $out = @()
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($Xml)
        foreach ($p in @($doc.SelectNodes('//Process'))) {
            $path = [string]$p.GetAttribute('Name')
            if (-not $path) { continue }
            $cpuUs = 0.0; $disk = 0.0
            $c = $p.SelectSingleNode('CpuUsage'); if ($c) { [void][double]::TryParse($c.InnerText, [ref]$cpuUs) }
            $d = $p.SelectSingleNode('DiskUsage'); if ($d) { [void][double]::TryParse($d.InnerText, [ref]$disk) }
            $out += @{ exe = [IO.Path]::GetFileName($path); path = $path; cpuMs = $cpuUs / 1000; disk = $disk }
        }
    } catch { }
    return $out
}

function Get-VxStartupImpactMap {
    # exe file name (lower case) -> worst values seen in the last boots of this user
    $map = @{}
    $dir = Join-Path $env:SystemRoot 'System32\wdi\LogFiles\StartupInfo'
    try {
        $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File -ErrorAction Stop | Where-Object { $_.Name -like "$sid*" } | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
        if ($files.Count -eq 0) { $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 3) }
        foreach ($f in $files) {
            foreach ($r in (ConvertFrom-VxStartupInfoXml ([System.IO.File]::ReadAllText($f.FullName)))) {
                $k = $r.exe.ToLowerInvariant()
                if (-not $map.ContainsKey($k)) { $map[$k] = @{ cpuMs = 0.0; disk = 0.0; path = $r.path } }
                $map[$k].cpuMs = [math]::Max($map[$k].cpuMs, $r.cpuMs)
                $map[$k].disk = [math]::Max($map[$k].disk, $r.disk)
            }
        }
    } catch { }
    return $map
}

function Get-VxStartupExe {
    # the program a startup entry runs (Run key command line or a shortcut in the Startup folder)
    param($Item)
    $cmd = [string]$Item.Command
    if ($Item.Kind -eq 'appx') { return '' }
    try {
        if ($cmd -like '*.lnk' -and (Test-Path -LiteralPath $cmd)) {
            $sh = New-Object -ComObject WScript.Shell
            $cmd = [string]$sh.CreateShortcut($cmd).TargetPath
        }
    } catch { }
    $cmd = [Environment]::ExpandEnvironmentVariables($cmd)
    if ($cmd -match '^\s*"([^"]+)"') { return $Matches[1] }
    if ($cmd -match '^\s*(.+?\.exe)\b') { return $Matches[1] }
    return ($cmd -split '\s+')[0]
}

function Set-VxStartupEnabled {
    param($Item, [bool]$Enabled)
    # the Winstep Nexus dock is never removed from startup
    if (-not $Enabled -and (([string]$Item.Name + ' ' + [string]$Item.Command) -match '(?i)nexus|winstep')) { Write-VxLog "startup: $($Item.Name) is protected (Winstep Nexus)"; return }
    if (-not $Enabled) {
        Start-VxTx -Id $Item.Id -Title ("Avvio: " + $Item.Name)
        if ($Item.Kind -eq 'appx') {
            $prev = (Get-ItemProperty -LiteralPath $Item.ApprovedPath -ErrorAction SilentlyContinue).State
            Add-VxCustomUndo "appx|$($Item.ApprovedPath)" @{ kind = 'appx'; path = $Item.ApprovedPath; state = [int]$prev }
            Set-ItemProperty -LiteralPath $Item.ApprovedPath -Name State -Value 1 -Type DWord
        } else {
            $val = [Convert]::ToBase64String([VeloxPC.Native]::StartupApprovedValue($false))
            Set-VxReg $Item.ApprovedPath $Item.ApprovedName 'Binary' $val
        }
        Complete-VxTx
        return
    }
    if (Test-VxBackupEntry $Item.Id) { [void](Undo-VxEntry $Item.Id); return }
    if ($Item.Kind -eq 'appx') { Set-ItemProperty -LiteralPath $Item.ApprovedPath -Name State -Value 2 -Type DWord }
    else {
        if (-not (Test-Path -LiteralPath $Item.ApprovedPath)) { New-Item -Path $Item.ApprovedPath -Force | Out-Null }
        New-ItemProperty -LiteralPath $Item.ApprovedPath -Name $Item.ApprovedName -PropertyType Binary -Value ([VeloxPC.Native]::StartupApprovedValue($true)) -Force | Out-Null
    }
}

# ---------------------------------------------------------------- running processes
$script:VxProcDb = @(
    @{ P = '^(Nexus|NexusDock|WinstepXP|Winstep.*)$'; Risk = 'avoid'; A = @{ it = 'Dock Winstep Nexus: protetta, non chiuderla.'; en = 'Winstep Nexus dock: protected, do not close it.' } },
    @{ P = '^(System|Idle|Registry|smss|csrss|wininit|winlogon|services|lsass|LsaIso|svchost|fontdrvhost|Memory Compression|dwm|sihost|ctfmon|conhost|dllhost|taskhostw|WmiPrvSE|spoolsv|audiodg|SgrmBroker|MsMpEng|NisSrv|SecurityHealthService|SecurityHealthSystray|MpDefenderCoreService|WUDFHost|wlanext|unsecapp|SearchIndexer|smartscreen|TextInputHost|ShellExperienceHost|StartMenuExperienceHost|SearchHost|SearchApp|explorer|RuntimeBroker|ApplicationFrameHost|SystemSettingsBroker|ShellHost|AggregatorHost|dasHost|WindowsTerminal|OpenConsole|powershell|pwsh|LockApp|UserOOBEBroker|CompPkgSrv|vmmem|vmmemWSL|Secure System|MemCompression|atiesrxx|atieclxx|amdfendrsr|nvcontainer|NVDisplay\.Container|igfxEM|IntelCpHDCPSvc|RtkAudUService64|SecurityHealthHost|wudfhost|crss|winlogon|lsm|WmiApSrv|MoUsoCoreWorker|TiWorker|TrustedInstaller|msiexec|mobsync|PresentationFontCache|SppExtComObj|sppsvc|ngen|ngentask|backgroundTaskHost|smss|CrossDeviceResume|Widgets?Board)$'
        Risk = 'avoid'; A = @{ it = 'Parte di Windows o di un driver: non chiuderlo.'; en = 'Part of Windows or a driver: do not close it.' } },
    # updaters are never "safe to close": killed halfway they can leave a broken install (Edge/WebView2, OneDrive...)
    @{ P = '^(OneDriveStandaloneUpdater|GoogleUpdate|GoogleUpdater|updater|MicrosoftEdgeUpdate|jusched|AdobeARM|MozillaMaintenance)$'
        Risk = 'caution'; A = @{ it = 'Sta forse installando un aggiornamento: chiuderlo a metà può rovinarlo. Lascialo finire, si chiude da solo.'; en = 'It may be installing an update: closing it halfway can break it. Let it finish, it closes by itself.' } },
    @{ P = '^(AnyDesk|TeamViewer|Parsec|parsecd|rustdesk)$'
        Risk = 'caution'; A = @{ it = 'Accesso remoto: se qualcuno è collegato al PC, la connessione cade.'; en = 'Remote access: if someone is connected to this PC, the connection drops.' } },
    @{ P = '^(Widgets|WidgetService|PhoneExperienceHost|YourPhone|GameBar|GameBarFTServer|Cortana|Copilot|M365Copilot|AdobeCollabSync|CCXProcess|AdobeIPCBroker|Creative Cloud|Creative Cloud Helper|Overwolf|OverwolfBrowser|Medal|EpicWebHelper|SkypeApp|SkypeBackgroundHost|Spotify|EADesktop|EABackgroundService|upc|UplayWebCore|RockstarService|Battle\.net|GalaxyClient)$'
        Risk = 'safe'; A = @{ it = 'App o helper in background: si può chiudere senza problemi.'; en = 'Background app or helper: safe to close.' } },
    @{ P = '^(msedge|chrome|firefox|opera|brave|vivaldi)$'; Risk = 'caution'; A = @{ it = 'È un browser: chiudendolo perdi le schede aperte non salvate.'; en = 'It is a browser: closing it loses unsaved open tabs.' } },
    @{ P = '^(Discord|Telegram|WhatsApp|Slack|Zoom|ms-teams|Teams|msteams|msedgewebview2|steamwebhelper|Launcher)$'; Risk = 'caution'; A = @{ it = 'Se sei in chiamata la chiamata si interrompe.'; en = 'If you are on a call, the call drops.' } },
    @{ P = '^(OneDrive|MEGAsync|Dropbox|GoogleDriveFS|iCloudDrive|CoreSync)$'; Risk = 'caution'; A = @{ it = 'Sincronizzazione cloud: si interrompe finché non lo riapri.'; en = 'Cloud sync: stops until you reopen it.' } },
    @{ P = '^(wallpaper32|wallpaper64|wallpaperservice32|webwallpaper32|lively)$'; Risk = 'caution'; A = @{ it = 'Sfondo animato: chiudendolo liberi GPU.'; en = 'Animated wallpaper: closing it frees GPU.' } },
    @{ P = '^(obs64|obs32|Streamlabs OBS|XSplit)$'; Risk = 'caution'; A = @{ it = 'Attenzione: potrebbe star registrando o trasmettendo.'; en = 'Careful: it may be recording or streaming.' } },
    @{ P = '^(AfterFX|aerender|Adobe Premiere Pro|Adobe Media Encoder|Photoshop|Resolve|Topaz Video AI|HandBrake)$'; Risk = 'caution'; A = @{ it = 'Programma di lavoro: chiudendolo perdi le modifiche non salvate.'; en = 'Work app: closing it loses unsaved changes.' } },
    @{ P = '^(lghub|lghub_agent|lghub_updater|iCUE|Razer Synapse.*|RazerCentral|SteelSeriesGG|NGENUITY|TRCC|Armoury.*|MSI.*Center|SignalRgb|OpenRGB|MSIAfterburner|RTSS|NVIDIA (app|Overlay|Share)|nvsphelper64|RadeonSoftware|AMDRSServ)$'; Risk = 'caution'; A = @{ it = 'Software per periferiche, RGB o GPU: chiudendolo potresti perdere macro, luci o curve ventole.'; en = 'Peripheral, RGB or GPU software: closing it may lose macros, lighting or fan curves.' } }
)

function Get-VxProcAdvice {
    param([string]$Name, [int]$Session)
    foreach ($d in $script:VxProcDb) { if ($Name -match $d.P) { return $d } }
    if ($Session -eq 0) { return @{ Risk = 'avoid'; A = @{ it = 'Servizio di sistema: gestiscilo dalla scheda Servizi, non chiuderlo qui.'; en = 'System service: manage it from the Services tab, do not close it here.' } } }
    return @{ Risk = 'info'; A = @{ it = 'Programma aperto: chiudilo solo se sai cos''è e non ti serve.'; en = 'Open program: only close it if you know what it is and do not need it.' } }
}

function Get-VxProcessGroups {
    $procs = [VeloxPC.Native]::SnapshotProcesses(700)
    $self = $PID
    $groups = @{}
    foreach ($p in $procs) {
        if ($p.Id -eq 0 -or $p.Id -eq $self) { continue }
        $k = $p.Name
        if (-not $groups.ContainsKey($k)) { $groups[$k] = @{ Name = $k; Count = 0; Mem = [int64]0; Cpu = 0.0; Path = $p.Path; Session = $p.SessionId } }
        $g = $groups[$k]
        $g.Count++; $g.Mem += $p.WorkingSet; $g.Cpu += $p.Cpu
        if (-not $g.Path -and $p.Path) { $g.Path = $p.Path }
        if ($p.SessionId -gt 0) { $g.Session = $p.SessionId }
    }
    $descCache = @{}
    $out = @()
    foreach ($g in $groups.Values) {
        $desc = ''
        if ($g.Path) {
            if ($descCache.ContainsKey($g.Path)) { $desc = $descCache[$g.Path] }
            else { try { $desc = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($g.Path).FileDescription } catch { }; $descCache[$g.Path] = $desc }
        }
        $adv = Get-VxProcAdvice $g.Name ([int]$g.Session)
        $out += [pscustomobject]@{ Name = $g.Name; Count = $g.Count; Mem = $g.Mem; Cpu = $g.Cpu; Path = $g.Path; Description = $desc; Risk = $adv.Risk; Advice = $adv.A; Session = $g.Session }
    }
    return @($out | Sort-Object Mem -Descending)
}

function Stop-VxProcessGroup {
    param([string]$Name)
    $n = 0
    # never close the shell, the Winstep Nexus dock or After Effects / its renders (unsaved work) from here
    if ($Name -match '(?i)^(explorer|Nexus|NexusDock|Winstep.*|AfterFX|aerender)$') { Write-VxLog "Not closing $Name (protected)"; return 0 }
    # parts of Windows and drivers (csrss, wininit, lsass, dwm...) are refused here too, not only greyed out in the list:
    # killing some of them crashes Windows on the spot
    if ((Get-VxProcAdvice $Name 1).Risk -eq 'avoid') { Write-VxLog "Not closing $Name (part of Windows)"; return 0 }
    foreach ($p in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        if ($p.Id -eq $PID) { continue }
        try { $p.Kill(); $n++ } catch { }
    }
    Write-VxLog "Closed process group $Name ($n)"
    return $n
}

# Boost: what it WOULD close (shown to the user first, closed only after one confirmation)
$script:VxBoostNever = '^(msedgewebview2|steamwebhelper|steam|Launcher|ms-teams|Teams|msteams|Discord|Zoom|explorer|AfterFX|aerender|Adobe Media Encoder)$'
function Get-VxBoostPlan {
    param([string[]]$Keep = @())
    $plan = @()
    foreach ($g in @(Get-VxProcessGroups)) {
        if ($g.Risk -ne 'safe' -or $g.Name -in $Keep -or $g.Name -match $script:VxBoostNever) { continue }
        $plan += [pscustomobject]@{ Name = $g.Name; Count = $g.Count; Mem = [int64]$g.Mem; Description = $g.Description }
    }
    return @($plan | Sort-Object Mem -Descending)
}

function Invoke-VxBoostClose {
    param([string[]]$Names)
    $closed = @(); $freed = [int64]0
    $groups = @{}; foreach ($g in @(Get-VxProcessGroups)) { $groups[$g.Name] = $g }
    foreach ($n in $Names) {
        if ($n -match $script:VxBoostNever) { continue }
        $g = $groups[$n]
        if (-not $g -or $g.Risk -ne 'safe') { continue }
        if ((Stop-VxProcessGroup $n) -gt 0) { $closed += $n; $freed += [int64]$g.Mem }
    }
    return @{ closed = $closed; freed = $freed }
}

function Get-VxSystemCounts {
    $procs = @(Get-Process -ErrorAction SilentlyContinue)
    $svcs = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' })
    return @{ Processes = $procs.Count; Services = $svcs.Count; Svchost = @($procs | Where-Object { $_.ProcessName -eq 'svchost' }).Count }
}
