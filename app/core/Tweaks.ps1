# VeloxPC - optimization catalog + engine
# Each tweak is data: registry values (Reg) and/or a custom Apply block that only
# uses the Set-Vx* helpers, so every change is recorded and can be undone.

$script:VxPresets = @('gaming', 'competitive', 'creator', 'balanced', 'laptop')

$script:VxTweaks = @(
    # ======================================================= GAMING & LATENCY
    @{
        Id = 'gamemode'; Cat = 'latency'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced', 'laptop')
        Title = @{ it = 'Modalità Gioco di Windows'; en = 'Windows Game Mode' }
        Desc = @{ it = 'Quando giochi, Windows dà la precedenza al gioco e rimanda aggiornamenti e lavori in background.'; en = 'While you play, Windows prioritises the game and postpones updates and background work.' }
        Reg = @(@('HKCU:\Software\Microsoft\GameBar', 'AutoGameModeEnabled', 'DWord', 1), @('HKCU:\Software\Microsoft\GameBar', 'AllowAutoGameMode', 'DWord', 1))
    },
    @{
        Id = 'gamedvr'; Cat = 'latency'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'laptop')
        Title = @{ it = 'Stop alla registrazione in background'; en = 'Stop background game recording' }
        Desc = @{ it = 'Xbox Game Bar non registra più di nascosto gli ultimi minuti di gioco: meno lavoro per scheda video e disco, più FPS stabili.'; en = 'Xbox Game Bar stops secretly recording your last minutes of gameplay: less GPU/disk work, steadier FPS.' }
        Warn = @{ it = 'Non potrai salvare clip con Win+Alt+G. Se registri con NVIDIA, OBS o Medal non cambia nulla.'; en = 'You will not be able to save clips with Win+Alt+G. NVIDIA, OBS or Medal recording is unaffected.' }
        Reg = @(@('HKCU:\System\GameConfigStore', 'GameDVR_Enabled', 'DWord', 0), @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR', 'AppCaptureEnabled', 'DWord', 0))
    },
    @{
        Id = 'mmcss'; Cat = 'latency'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator')
        Title = @{ it = 'Priorità massima a giochi e audio'; en = 'Top priority for games and audio' }
        Desc = @{ it = 'Dice allo scheduler multimediale di Windows di riservare più CPU e GPU al gioco attivo e di non rallentare la rete mentre giochi.'; en = 'Tells the Windows multimedia scheduler to reserve more CPU/GPU for the active game and not to throttle the network while you play.' }
        Reg = @(
            @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile', 'SystemResponsiveness', 'DWord', 10),
            @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile', 'NetworkThrottlingIndex', 'DWord', -1),
            @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'GPU Priority', 'DWord', 8),
            @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'Priority', 'DWord', 6),
            @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'Scheduling Category', 'String', 'High'),
            @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games', 'SFIO Priority', 'String', 'High')
        )
    },
    @{
        Id = 'prioritysep'; Cat = 'latency'; Risk = 'caution'; Presets = @('gaming', 'competitive')
        Title = @{ it = 'Più CPU alla finestra in primo piano'; en = 'More CPU for the foreground window' }
        Desc = @{ it = 'Il programma che stai usando (il gioco) riceve turni di CPU più lunghi e frequenti: input più reattivo.'; en = 'The app you are using (the game) gets longer and more frequent CPU turns: snappier input.' }
        Warn = @{ it = 'Le cose lasciate in secondo piano (download, render mentre fai altro) vanno un po'' più lente.'; en = 'Things left in the background (downloads, renders while you do something else) get slightly slower.' }
        Reg = @(, @('HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl', 'Win32PrioritySeparation', 'DWord', 38))
    },
    @{
        Id = 'hags'; Cat = 'latency'; Risk = 'caution'; Reboot = $true; Presets = @('gaming', 'competitive')
        Title = @{ it = 'Pianificazione GPU con accelerazione hardware'; en = 'Hardware-accelerated GPU scheduling' }
        Desc = @{ it = 'La scheda video gestisce da sola la sua coda di lavoro: meno latenza. È obbligatoria per DLSS Frame Generation sulle RTX 40/50.'; en = 'The graphics card manages its own work queue: lower latency. Required for DLSS Frame Generation on RTX 40/50.' }
        Warn = @{ it = 'Su alcune schede più vecchie può causare piccoli scatti: se succede, annullala.'; en = 'On some older cards it can cause small stutters: if so, undo it.' }
        When = { param($hw) $g = $hw.GPU; $g -and -not $g.Integrated -and $hw.OS.Build -ge 19041 -and ($g.Name -match 'GTX 1[0-6]\d\d|RTX|RX [5-9]\d{3}|Arc') }
        Rec = { param($hw) if ($hw.GPU.Name -match 'RTX [45]0\d0') { @{ level = 'rec'; why = @{ it = 'La tua RTX la richiede per Frame Generation'; en = 'Your RTX needs it for Frame Generation' } } } }
        Reg = @(, @('HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers', 'HwSchMode', 'DWord', 2))
    },
    @{
        Id = 'windowedopt'; Cat = 'latency'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'balanced')
        Title = @{ it = 'Ottimizzazioni per giochi in finestra'; en = 'Optimizations for windowed games' }
        Desc = @{ it = 'I giochi in finestra o "senza bordi" ottengono la stessa bassa latenza dello schermo intero.'; en = 'Windowed and borderless games get the same low latency as fullscreen.' }
        When = { param($hw) $hw.OS.IsWin11 }
        Apply = {
            param($hw)
            $p = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
            $cur = (Get-VxRegState $p 'DirectXUserGlobalSettings').value
            $parts = @()
            if ($cur) { $parts = @(([string]$cur).Split(';') | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' }) }
            $parts += 'SwapEffectUpgradeEnable=1'
            Set-VxReg $p 'DirectXUserGlobalSettings' 'String' (($parts -join ';') + ';')
        }
        Test = { param($hw) ([string](Get-VxRegState 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings').value) -match 'SwapEffectUpgradeEnable=1' }
    },

    # ======================================================= INPUT
    @{
        Id = 'mouseaccel'; Cat = 'input'; Risk = 'safe'; Presets = @('gaming', 'competitive')
        Title = @{ it = 'Mouse senza accelerazione'; en = 'Mouse without acceleration' }
        Desc = @{ it = 'Disattiva "Precisione puntatore avanzata": lo stesso movimento della mano sposta sempre il mirino della stessa distanza. Mira più costante.'; en = 'Turns off "Enhance pointer precision": the same hand movement always moves the crosshair the same distance. More consistent aim.' }
        Apply = {
            param($hw)
            $p = 'HKCU:\Control Panel\Mouse'
            $prev = @{ t1 = [int](Get-VxRegState $p 'MouseThreshold1').value; t2 = [int](Get-VxRegState $p 'MouseThreshold2').value; accel = [int](Get-VxRegState $p 'MouseSpeed').value }
            Add-VxCustomUndo 'mouse' @{ kind = 'mouse'; t1 = $prev.t1; t2 = $prev.t2; accel = $prev.accel }
            Set-VxReg $p 'MouseSpeed' 'String' '0'
            Set-VxReg $p 'MouseThreshold1' 'String' '0'
            Set-VxReg $p 'MouseThreshold2' 'String' '0'
            try { [void][VeloxPC.Native]::SetMouse(0, 0, 0) } catch { }
        }
        Test = { param($hw) Test-VxRegValue 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' }
    },
    @{
        Id = 'keyboard'; Cat = 'input'; Risk = 'safe'; Presets = @('gaming', 'competitive')
        Title = @{ it = 'Tastiera più rapida'; en = 'Faster keyboard' }
        Desc = @{ it = 'Ritardo minimo e ripetizione massima quando tieni premuto un tasto.'; en = 'Minimum delay and maximum repeat rate when holding a key.' }
        Apply = {
            param($hw)
            $p = 'HKCU:\Control Panel\Keyboard'
            Add-VxCustomUndo 'kbd' @{ kind = 'kbd'; delay = [int](Get-VxRegState $p 'KeyboardDelay').value; speed = [int](Get-VxRegState $p 'KeyboardSpeed').value }
            Set-VxReg $p 'KeyboardDelay' 'String' '0'
            Set-VxReg $p 'KeyboardSpeed' 'String' '31'
            try { [void][VeloxPC.Native]::Spi(0x0017, 0); [void][VeloxPC.Native]::Spi(0x000B, 31) } catch { }
        }
        Test = { param($hw) (Test-VxRegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0') -and (Test-VxRegValue 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31') }
    },
    @{
        Id = 'stickykeys'; Cat = 'input'; Risk = 'safe'; Reboot = $true; Presets = @('gaming', 'competitive', 'balanced')
        Title = @{ it = 'Niente popup "Tasti permanenti"'; en = 'No "Sticky Keys" pop-up' }
        Desc = @{ it = 'Premere Shift 5 volte durante una partita non farà più uscire dal gioco con la finestra dei Tasti permanenti.'; en = 'Pressing Shift 5 times mid-game will no longer kick you out with the Sticky Keys window.' }
        Reg = @(
            @('HKCU:\Control Panel\Accessibility\StickyKeys', 'Flags', 'String', '506'),
            @('HKCU:\Control Panel\Accessibility\Keyboard Response', 'Flags', 'String', '122'),
            @('HKCU:\Control Panel\Accessibility\ToggleKeys', 'Flags', 'String', '58')
        )
    },

    # ======================================================= POWER
    @{
        Id = 'powerplan'; Cat = 'power'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator')
        Title = @{ it = 'Piano energetico Prestazioni massime'; en = 'Maximum performance power plan' }
        Desc = @{ it = 'Attiva il piano "Prestazioni eccellenti": la CPU non si addormenta e risponde subito, senza ritardi di risveglio.'; en = 'Enables the "Ultimate Performance" plan: the CPU never dozes off and responds instantly, no wake-up delays.' }
        Warn = @{ it = 'Consuma un po'' più corrente a PC fermo.'; en = 'Uses a bit more power when idle.' }
        Rec = {
            param($hw)
            if ($hw.CPU.IsX3DDual) { return @{ level = 'notrec'; why = @{ it = 'Il tuo Ryzen X3D a due CCD funziona meglio con "Bilanciato" (serve il core parking)'; en = 'Your dual-CCD Ryzen X3D works best on "Balanced" (it needs core parking)' } } }
            if ($hw.IsLaptop) { return @{ level = 'neutral'; why = @{ it = 'Sul portatile riduce la durata della batteria'; en = 'On a laptop it reduces battery life' } } }
            return @{ level = 'rec'; why = @{ it = 'Ideale per un PC fisso'; en = 'Ideal for a desktop PC' } }
        }
        Apply = {
            param($hw)
            $prev = Get-VxActiveScheme
            $guidRx = '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
            $out = (& powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1) -join ' '
            if ($out -match $guidRx) {
                $new = $Matches[1].ToLower()
                & powercfg /changename $new 'VeloxPC Ultimate' 'VeloxPC' 2>&1 | Out-Null
                & powercfg /setactive $new 2>&1 | Out-Null
                Add-VxCustomUndo 'plan' @{ kind = 'plan'; prev = $prev.guid; created = $new }
                return
            }
            & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
            $now = Get-VxActiveScheme
            if ($now -and $now.guid -eq '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') { Add-VxCustomUndo 'plan' @{ kind = 'plan'; prev = $prev.guid; created = '' }; return }
            # Modern Standby devices: only "Balanced" exists -> use the Best performance power mode
            $ov = Get-VxRegState 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActiveOverlayAcPowerScheme'
            $prevOv = if ($ov.existed -and $ov.value) { [string]$ov.value } else { '00000000-0000-0000-0000-000000000000' }
            Add-VxCustomUndo 'overlay' @{ kind = 'overlay'; prev = $prevOv }
            & powercfg /overlaysetactive ded574b5-45a0-4f42-8737-46345c09c238 2>&1 | Out-Null
        }
        Test = {
            param($hw)
            $s = Get-VxActiveScheme
            if (-not $s) { return $false }
            if (@('8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'e9a42b02-d5df-448d-aa00-03f14749eb61') -contains $s.guid) { return $true }
            if ($s.name -match 'VeloxPC|Ultimate|eccellenti') { return $true }
            $ov = Get-VxRegState 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActiveOverlayAcPowerScheme'
            return ([string]$ov.value -eq 'ded574b5-45a0-4f42-8737-46345c09c238')
        }
    },
    @{
        Id = 'powerlat'; Cat = 'power'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator')
        Title = @{ it = 'USB e PCIe sempre svegli'; en = 'USB and PCIe always awake' }
        Desc = @{ it = 'Mouse, tastiera, cuffie USB e scheda video non vengono mai messi in risparmio energetico: niente micro-lag o disconnessioni.'; en = 'Mouse, keyboard, USB headsets and the graphics card are never put into power saving: no micro-lag or disconnects.' }
        Rec = { param($hw) if ($hw.IsLaptop) { @{ level = 'neutral'; why = @{ it = 'Sul portatile consuma più batteria'; en = 'Uses more battery on a laptop' } } } }
        Apply = {
            param($hw)
            Set-VxPower '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0
            Set-VxPower '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0
        }
        Test = {
            param($hw)
            $s = Get-VxActiveScheme; if (-not $s) { return $false }
            $u = Get-VxPowerValue $s.guid '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
            $p = Get-VxPowerValue $s.guid '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5'
            return ($u -and $p -and $u.ac -eq 0 -and $p.ac -eq 0)
        }
    },
    @{
        Id = 'powerthrottle'; Cat = 'power'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator')
        Title = @{ it = 'Niente rallentamento dei programmi in background'; en = 'No throttling of background programs' }
        Desc = @{ it = 'Windows non riduce più la velocità dei programmi che considera "in secondo piano" (es. un render o Discord durante la partita).'; en = 'Windows stops slowing down programs it considers "in the background" (e.g. a render or Discord during a match).' }
        Rec = { param($hw) if ($hw.IsLaptop) { @{ level = 'neutral'; why = @{ it = 'Sul portatile consuma più batteria'; en = 'Uses more battery on a laptop' } } } }
        Reg = @(, @('HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling', 'PowerThrottlingOff', 'DWord', 1))
    },
    @{
        Id = 'cpumin'; Cat = 'power'; Risk = 'advanced'; Presets = @('competitive')
        Title = @{ it = 'CPU sempre alla massima frequenza'; en = 'CPU always at full clock' }
        Desc = @{ it = 'La CPU non scende mai di frequenza: zero attese quando arriva un picco di lavoro.'; en = 'The CPU never clocks down: zero waiting when a burst of work arrives.' }
        Warn = @{ it = 'Più calore e consumi anche a PC fermo. Sconsigliato con dissipatori piccoli.'; en = 'More heat and power draw even when idle. Not advised with small coolers.' }
        When = { param($hw) -not $hw.IsLaptop }
        Rec = { param($hw) if ($hw.CPU.IsX3DDual) { @{ level = 'notrec'; why = @{ it = 'Peggiora il core parking dei Ryzen X3D'; en = 'Hurts Ryzen X3D core parking' } } } }
        Apply = { param($hw) Set-VxPower '54533251-82be-4824-96c1-47b60b740d00' '893dee8e-2bef-41e0-89c6-b55d0929964c' 100 }
        Test = {
            param($hw)
            $s = Get-VxActiveScheme; if (-not $s) { return $false }
            $v = Get-VxPowerValue $s.guid '54533251-82be-4824-96c1-47b60b740d00' '893dee8e-2bef-41e0-89c6-b55d0929964c'
            return ($v -and $v.ac -eq 100)
        }
    },

    # ======================================================= SYSTEM
    @{
        Id = 'fastboot'; Cat = 'system'; Risk = 'safe'; Reboot = $true; Presets = @('gaming', 'competitive', 'creator')
        Title = @{ it = 'Spegnimento completo (no Avvio rapido)'; en = 'Full shutdown (no Fast Startup)' }
        Desc = @{ it = 'Con l''avvio rapido Windows non si spegne mai davvero e piccoli problemi restano in memoria per giorni. Così ogni accensione è "pulita". L''avvio impiega 1-3 secondi in più.'; en = 'With Fast Startup Windows never truly shuts down and small glitches stay in memory for days. This makes every boot clean. Boot takes 1-3 seconds longer.' }
        Reg = @(, @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power', 'HiberbootEnabled', 'DWord', 0))
    },
    @{
        Id = 'memcompress'; Cat = 'system'; Risk = 'caution'; Reboot = $true; Presets = @('competitive', 'creator')
        Title = @{ it = 'Niente compressione della memoria'; en = 'No memory compression' }
        Desc = @{ it = 'Con tanta RAM, comprimere la memoria è solo lavoro inutile per la CPU. Disattivarla libera cicli di CPU.'; en = 'With plenty of RAM, compressing memory is just useless CPU work. Turning it off frees CPU cycles.' }
        Warn = @{ it = 'Consigliato solo con 32 GB di RAM o più.'; en = 'Only recommended with 32 GB of RAM or more.' }
        When = { param($hw) $hw.RAM.GB -ge 16 }
        Rec = {
            param($hw)
            if ($hw.RAM.GB -ge 32) { return @{ level = 'rec'; why = @{ it = "Hai $($hw.RAM.GB) GB di RAM"; en = "You have $($hw.RAM.GB) GB of RAM" } } }
            return @{ level = 'notrec'; why = @{ it = 'Con meno di 32 GB è meglio lasciarla attiva'; en = 'Below 32 GB it is better left on' } }
        }
        Apply = {
            param($hw)
            $prev = $true
            try { $prev = [bool](Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { }
            Add-VxCustomUndo 'mmagent' @{ kind = 'mmagent'; prev = $prev }
            Disable-MMAgent -MemoryCompression -ErrorAction Stop
        }
        # Get-MMAgent fails when the SysMain service is disabled: then trust the change Piki made
        Test = { param($hw) try { -not [bool](Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { Test-VxBackupEntry 'memcompress' } }
    },

    # ======================================================= VISUAL
    @{
        Id = 'visualfx'; Cat = 'visual'; Risk = 'safe'; Reboot = $true; Presets = @('competitive', 'laptop')
        Title = @{ it = 'Animazioni di Windows più leggere'; en = 'Lighter Windows animations' }
        Desc = @{ it = 'Menu istantanei e meno animazioni di finestre e barra: Windows sembra più scattante. Testo e anteprime restano belli.'; en = 'Instant menus and fewer window/taskbar animations: Windows feels snappier. Text and thumbnails stay nice.' }
        Reg = @(
            @('HKCU:\Control Panel\Desktop', 'MenuShowDelay', 'String', '0'),
            @('HKCU:\Control Panel\Desktop\WindowMetrics', 'MinAnimate', 'String', '0'),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'TaskbarAnimations', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\DWM', 'EnableAeroPeek', 'DWord', 0)
        )
    },
    @{
        Id = 'transparency'; Cat = 'visual'; Risk = 'safe'; Presets = @('competitive', 'laptop')
        Title = @{ it = 'Niente trasparenze'; en = 'No transparency effects' }
        Desc = @{ it = 'Barra e menu Start diventano opachi: un po'' meno lavoro per la scheda video.'; en = 'Taskbar and Start menu become opaque: slightly less GPU work.' }
        Reg = @(, @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', 'EnableTransparency', 'DWord', 0))
    },

    # ======================================================= PRIVACY
    @{
        Id = 'telemetry'; Cat = 'privacy'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced', 'laptop')
        Title = @{ it = 'Meno dati inviati a Microsoft'; en = 'Less data sent to Microsoft' }
        Desc = @{ it = 'Riduce la telemetria al minimo consentito e disattiva i sondaggi di feedback e le "esperienze personalizzate".'; en = 'Reduces telemetry to the minimum allowed and turns off feedback surveys and "tailored experiences".' }
        Reg = @(
            @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Siuf\Rules', 'NumberOfSIUFInPeriod', 'DWord', 0)
        )
    },
    @{
        Id = 'ads'; Cat = 'privacy'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced', 'laptop')
        Title = @{ it = 'Via pubblicità e suggerimenti'; en = 'Remove ads and suggestions' }
        Desc = @{ it = 'Niente app sponsorizzate installate da sole, niente "consigli" nel menu Start e nelle Impostazioni.'; en = 'No sponsored apps installing themselves, no "tips" in Start and Settings.' }
        Reg = @(
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SilentInstalledAppsEnabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SystemPaneSuggestionsEnabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SoftLandingEnabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338388Enabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-338389Enabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-353694Enabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager', 'SubscribedContent-353696Enabled', 'DWord', 0),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 'DWord', 0)
        )
    },
    @{
        Id = 'websearch'; Cat = 'privacy'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced', 'laptop')
        Title = @{ it = 'Ricerca Start solo sul PC'; en = 'Start search on this PC only' }
        Desc = @{ it = 'La ricerca nel menu Start smette di interrogare Bing a ogni lettera: risultati più veloci, meno processi.'; en = 'Start menu search stops querying Bing on every keystroke: faster results, fewer processes.' }
        Warn = @{ it = 'Non vedrai più risultati web nel menu Start.'; en = 'You will no longer see web results in Start.' }
        Reg = @(
            @('HKCU:\Software\Policies\Microsoft\Windows\Explorer', 'DisableSearchBoxSuggestions', 'DWord', 1),
            @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search', 'BingSearchEnabled', 'DWord', 0)
        )
    },

    # ======================================================= BACKGROUND PROCESSES (Processes page)
    @{
        Id = 'bgapps'; Cat = 'proc'; Risk = 'caution'; Presets = @('gaming', 'competitive', 'laptop')
        Title = @{ it = 'Blocca le app dello Store in background'; en = 'Block Store apps in the background' }
        Desc = @{ it = 'Le app dello Store (Meteo, Foto, Collegamento al telefono...) non restano attive quando sono chiuse.'; en = 'Store apps (Weather, Photos, Phone Link...) stop running when closed.' }
        Warn = @{ it = 'Le app dello Store chiuse non mandano più notifiche (es. WhatsApp versione Store, Posta).'; en = 'Closed Store apps no longer send notifications (e.g. WhatsApp from the Store, Mail).' }
        Apply = {
            param($hw)
            if ($hw.OS.IsWin11) { Set-VxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 'DWord' 2 }
            Set-VxReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 'DWord' 1
        }
        Test = { param($hw) Test-VxRegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 }
    },
    @{
        Id = 'widgets'; Cat = 'proc'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'laptop')
        Title = @{ it = 'Disattiva Widget e Notizie'; en = 'Turn off Widgets and News' }
        Desc = @{ it = 'Il pannello Widget (meteo, notizie, borsa) tiene aperti diversi processi web anche se non lo guardi mai.'; en = 'The Widgets panel (weather, news, stocks) keeps several web processes open even if you never look at it.' }
        Apply = {
            param($hw)
            if ($hw.OS.IsWin11) { Set-VxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 'DWord' 0 }
            else { Set-VxReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 'DWord' 0 }
        }
        Test = { param($hw) if ($hw.OS.IsWin11) { Test-VxRegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 } else { Test-VxRegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 } }
    },
    @{
        Id = 'edgeboost'; Cat = 'proc'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'laptop')
        Title = @{ it = 'Edge non resta acceso in background'; en = 'Edge does not keep running in the background' }
        Desc = @{ it = 'Microsoft Edge smette di pre-caricarsi all''avvio e di restare aperto dopo che lo chiudi.'; en = 'Microsoft Edge stops preloading at startup and staying open after you close it.' }
        Warn = @{ it = 'Nelle impostazioni di Edge comparirà la scritta "Gestito dalla tua organizzazione": è normale.'; en = 'Edge settings will show "Managed by your organization": this is normal.' }
        Reg = @(
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'StartupBoostEnabled', 'DWord', 0),
            @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'BackgroundModeEnabled', 'DWord', 0)
        )
    },
    @{
        Id = 'svchost'; Cat = 'proc'; Risk = 'caution'; Reboot = $true; Presets = @('competitive')
        Title = @{ it = 'Raggruppa i servizi di Windows (meno processi)'; en = 'Group Windows services (fewer processes)' }
        Desc = @{ it = 'Windows avvia ogni servizio in un processo "svchost" separato. Raggrupparli può ridurre il numero di processi anche del 40-60%.'; en = 'Windows runs each service in its own "svchost" process. Grouping them can cut the process count by 40-60%.' }
        Warn = @{ it = 'Meno isolamento: se un servizio si blocca (raro) può trascinare con sé gli altri del gruppo.'; en = 'Less isolation: if a service crashes (rare) it can take the others in its group down with it.' }
        Apply = {
            param($hw)
            $kb = [int64]([math]::Floor($hw.RAM.UsableBytes / 1KB))
            if ($kb -gt [int]::MaxValue) { $kb = [int]::MaxValue }
            Set-VxReg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' 'DWord' ([int]$kb)
        }
        Test = {
            param($hw)
            $v = (Get-VxRegState 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB').value
            return ($v -and [int64]$v -ge [int64]([math]::Floor($hw.RAM.UsableBytes / 1KB)) - 1024)
        }
    },

    # ======================================================= NETWORK (Network page)
    @{
        Id = 'nagle'; Cat = 'net'; Risk = 'safe'; Presets = @('gaming', 'competitive')
        Title = @{ it = 'Pacchetti inviati subito (no algoritmo di Nagle)'; en = 'Send packets immediately (no Nagle)' }
        Desc = @{ it = 'Windows smette di "aspettare" per unire piccoli pacchetti: i giochi che usano TCP rispondono prima.'; en = 'Windows stops "waiting" to merge small packets: games that use TCP respond sooner.' }
        Apply = {
            param($hw)
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if ($p.DhcpIPAddress -or $p.IPAddress) {
                    $path = "$base\$($k.PSChildName)"
                    Set-VxReg $path 'TcpAckFrequency' 'DWord' 1
                    Set-VxReg $path 'TCPNoDelay' 'DWord' 1
                }
            }
        }
        Test = {
            # same interfaces the Apply step changes (not only the adapter remembered from the last scan)
            param($hw)
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
            $n = 0
            foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if ($p.DhcpIPAddress -or $p.IPAddress) {
                    if (-not (Test-VxRegValue "$base\$($k.PSChildName)" 'TCPNoDelay' 1)) { return $false }
                    $n++
                }
            }
            return ($n -gt 0)
        }
    },
    @{
        Id = 'tcpstack'; Cat = 'net'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced')
        Title = @{ it = 'Stack TCP/IP ottimale'; en = 'Optimal TCP/IP stack' }
        Desc = @{ it = 'Ripristina le impostazioni di rete più veloci: distribuzione del traffico su tutti i core (RSS) e finestra TCP automatica senza limitazioni.'; en = 'Restores the fastest network settings: traffic spread across all cores (RSS) and an unrestricted automatic TCP window.' }
        Apply = {
            param($hw)
            try {
                $t = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop
                $lvl = ([string]$t.AutoTuningLevelLocal).ToLower()
                if ($lvl) { Add-VxCustomUndo 'tcp|autotuninglevel' @{ kind = 'tcp'; prop = 'autotuninglevel'; value = $lvl } }
                $heu = ([string]$t.ScalingHeuristics).ToLower()
                if ($heu) { Add-VxCustomUndo 'tcp|heuristics' @{ kind = 'tcp'; prop = 'heuristics'; value = $heu } }
            } catch { }
            try {
                $o = Get-NetOffloadGlobalSetting -ErrorAction Stop
                $rss = ([string]$o.ReceiveSideScaling).ToLower()
                if ($rss) { Add-VxCustomUndo 'tcp|rss' @{ kind = 'tcp'; prop = 'rss'; value = $rss } }
            } catch { }
            & netsh int tcp set global autotuninglevel=normal 2>&1 | Out-Null
            & netsh int tcp set global rss=enabled 2>&1 | Out-Null
            & netsh int tcp set heuristics disabled 2>&1 | Out-Null
        }
        Test = {
            param($hw)
            try {
                $t = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop
                $o = Get-NetOffloadGlobalSetting -ErrorAction Stop
                return ([string]$t.AutoTuningLevelLocal -eq 'Normal' -and [string]$o.ReceiveSideScaling -eq 'Enabled')
            } catch { return $false }
        }
    },
    @{
        Id = 'nicsave'; Cat = 'net'; Risk = 'caution'; Presets = @('gaming', 'competitive', 'creator')
        Title = @{ it = 'Scheda di rete senza risparmio energetico'; en = 'Network card without power saving' }
        Desc = @{ it = 'Disattiva "Ethernet a basso consumo", "Green Ethernet" e simili: la scheda di rete non rallenta mai per risparmiare corrente. Meno picchi di ping.'; en = 'Turns off "Energy-Efficient Ethernet", "Green Ethernet" and similar: the network card never slows down to save power. Fewer ping spikes.' }
        Warn = @{ it = 'Internet si interrompe per qualche secondo mentre applica.'; en = 'Internet drops for a few seconds while applying.' }
        When = { param($hw) $hw.Network -and -not $hw.Network.IsWifi }
        Apply = {
            param($hw)
            $keys = @('*EEE', 'EEELinkAdvertisement', 'AdvancedEEE', 'EnableGreenEthernet', 'GreenEthernet', 'PowerSavingMode', 'ULPMode', 'EnablePME', '*SelectiveSuspend', 'GigaLite', 'AutoPowerSaveModeEnabled')
            foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
                $changed = $false
                foreach ($prop in @(Get-NetAdapterAdvancedProperty -Name $a.Name -AllProperties -ErrorAction SilentlyContinue)) {
                    if ($keys -contains $prop.RegistryKeyword) {
                        $cur = [string](@($prop.RegistryValue) | Select-Object -First 1)
                        $valid = @($prop.ValidRegistryValues)
                        if ($cur -ne '0' -and ($valid.Count -eq 0 -or $valid -contains '0')) {
                            Add-VxCustomUndo "nic|$($a.Name)|$($prop.RegistryKeyword)" @{ kind = 'nic'; adapter = $a.Name; keyword = $prop.RegistryKeyword; value = $cur }
                            try { Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $prop.RegistryKeyword -RegistryValue '0' -NoRestart -ErrorAction Stop; $changed = $true } catch { }
                        }
                    }
                }
                if ($changed) { Restart-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
            }
        }
        Test = { param($hw) Test-VxBackupEntry 'nicsave' }
    },
    @{
        Id = 'nicirq'; Cat = 'net'; Risk = 'advanced'; Presets = @('competitive')
        Title = @{ it = 'Pacchetti di rete elaborati all''istante'; en = 'Network packets processed instantly' }
        Desc = @{ it = 'Disattiva la "moderazione degli interrupt": ogni pacchetto viene gestito subito invece di essere raggruppato. Ping un filo più basso e stabile.'; en = 'Turns off "interrupt moderation": each packet is handled immediately instead of being batched. Slightly lower, steadier ping.' }
        Warn = @{ it = 'Usa un po'' più CPU durante download pesanti. Internet si interrompe per qualche secondo.'; en = 'Uses a bit more CPU during heavy downloads. Internet drops for a few seconds.' }
        When = { param($hw) $hw.Network -and -not $hw.Network.IsWifi }
        Apply = {
            param($hw)
            foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
                $prop = Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*InterruptModeration' -ErrorAction SilentlyContinue
                if ($prop) {
                    $cur = [string](@($prop.RegistryValue) | Select-Object -First 1)
                    if ($cur -ne '0') {
                        Add-VxCustomUndo "nic|$($a.Name)|*InterruptModeration" @{ kind = 'nic'; adapter = $a.Name; keyword = '*InterruptModeration'; value = $cur }
                        try { Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*InterruptModeration' -RegistryValue '0' -ErrorAction Stop } catch { }
                    }
                }
            }
        }
        Test = { param($hw) Test-VxBackupEntry 'nicirq' }
    },
    @{
        Id = 'netthrottle'; Cat = 'net'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced')
        Title = @{ it = 'Nessun limite alla rete durante giochi e video'; en = 'No network limit during games and video' }
        Desc = @{ it = 'Windows di default rallenta i pacchetti di rete mentre riproduci audio/video o giochi. Questo limite viene tolto.'; en = 'By default Windows slows network packets while audio/video or games play. This limit is removed.' }
        Reg = @(, @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile', 'NetworkThrottlingIndex', 'DWord', -1))
    },
    @{
        Id = 'nicbuffers'; Cat = 'net'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator')
        Title = @{ it = 'Buffer della scheda di rete al massimo'; en = 'Network card buffers at maximum' }
        Desc = @{ it = 'Più memoria per i pacchetti in arrivo e in uscita: nessun pacchetto perso nei momenti di traffico intenso (download + partita).'; en = 'More memory for incoming and outgoing packets: no dropped packets during heavy traffic (download + match).' }
        Warn = @{ it = 'Internet si interrompe per qualche secondo mentre applica.'; en = 'Internet drops for a few seconds while applying.' }
        When = { param($hw) $hw.Network -and -not $hw.Network.IsWifi }
        Apply = {
            param($hw)
            foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
                $changed = $false
                foreach ($kw in @('*ReceiveBuffers', '*TransmitBuffers')) {
                    $prop = Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $kw -ErrorAction SilentlyContinue
                    if (-not $prop -or -not $prop.NumericParameterMaxValue) { continue }
                    $cur = [string](@($prop.RegistryValue) | Select-Object -First 1)
                    $max = [string][int]$prop.NumericParameterMaxValue
                    if ($cur -ne $max) {
                        Add-VxCustomUndo "nic|$($a.Name)|$kw" @{ kind = 'nic'; adapter = $a.Name; keyword = $kw; value = $cur }
                        try { Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $kw -RegistryValue $max -NoRestart -ErrorAction Stop; $changed = $true } catch { }
                    }
                }
                if ($changed) { Restart-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction SilentlyContinue }
            }
        }
        Test = { param($hw) Test-VxBackupEntry 'nicbuffers' }
    },
    @{
        Id = 'wifipower'; Cat = 'net'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced')
        Title = @{ it = 'Wi-Fi sempre alla massima potenza'; en = 'Wi-Fi always at full power' }
        Desc = @{ it = 'La scheda Wi-Fi non entra mai in risparmio energetico: niente picchi di ping e disconnessioni improvvise.'; en = 'The Wi-Fi card never enters power saving: no ping spikes or sudden disconnects.' }
        When = { param($hw) $hw.Network -and $hw.Network.IsWifi }
        Apply = { param($hw) Set-VxPower '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1' '12bbebe6-58d6-4636-95bb-3217ef867c1a' 0 0 }
        Test = {
            param($hw)
            $s = Get-VxActiveScheme; if (-not $s) { return $false }
            $v = Get-VxPowerValue $s.guid '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1' '12bbebe6-58d6-4636-95bb-3217ef867c1a'
            return ($v -and $v.ac -eq 0)
        }
    },
    @{
        Id = 'delivopt'; Cat = 'net'; Risk = 'safe'; Presets = @('gaming', 'competitive', 'creator', 'balanced', 'laptop')
        Title = @{ it = 'Niente upload di aggiornamenti ad altri PC'; en = 'No uploading updates to other PCs' }
        Desc = @{ it = 'Windows smette di usare la tua connessione per inviare pezzi di aggiornamenti ad altri PC su Internet: più banda libera e ping stabile.'; en = 'Windows stops using your connection to send update pieces to other PCs on the Internet: more free bandwidth and steadier ping.' }
        Reg = @(, @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization', 'DODownloadMode', 'DWord', 0))
    }
)

$script:VxCatOrder = @('latency', 'power', 'input', 'system', 'visual', 'privacy', 'proc', 'net', 'ae')
$script:VxCatNames = @{
    latency = @{ it = 'Gioco e latenza'; en = 'Gaming & latency' }
    power = @{ it = 'Energia'; en = 'Power' }
    input = @{ it = 'Mouse e tastiera'; en = 'Mouse & keyboard' }
    system = @{ it = 'Sistema'; en = 'System' }
    visual = @{ it = 'Effetti grafici'; en = 'Visual effects' }
    privacy = @{ it = 'Privacy e pubblicità'; en = 'Privacy & ads' }
    proc = @{ it = 'Processi in background'; en = 'Background processes' }
    net = @{ it = 'Rete'; en = 'Network' }
    ae = @{ it = 'After Effects'; en = 'After Effects' }
}

# ---------------------------------------------------------------- engine
function Get-VxAllTweaks {
    $list = @($script:VxTweaks)
    if (Get-Command Get-VxAeTweaks -ErrorAction SilentlyContinue) { $list += @(Get-VxAeTweaks) }
    return $list
}

function Find-VxTweak { param([string]$Id) return (Get-VxAllTweaks | Where-Object { $_.Id -eq $Id } | Select-Object -First 1) }

function Test-VxTweakApplicable {
    param($Tweak, $Hw)
    if (-not $Tweak.When) { return $true }
    try { return [bool](& $Tweak.When $Hw) } catch { return $false }
}

function Get-VxTweakRec {
    param($Tweak, $Hw)
    if (-not $Tweak.Rec) { return $null }
    try { return (& $Tweak.Rec $Hw) } catch { return $null }
}

function Test-VxTweakApplied {
    param($Tweak, $Hw)
    try {
        if ($Tweak.Test) { return [bool](& $Tweak.Test $Hw) }
        if ($Tweak.Reg) {
            foreach ($r in $Tweak.Reg) { if (-not (Test-VxRegValue $r[0] $r[1] $r[3])) { return $false } }
            return $true
        }
        return (Test-VxBackupEntry $Tweak.Id)
    } catch { return $false }
}

function Invoke-VxTweak {
    param($Tweak, $Hw)
    $title = L $Tweak.Title
    Start-VxTx -Id $Tweak.Id -Title $title
    try {
        if ($Tweak.Reg) { foreach ($r in $Tweak.Reg) { Set-VxReg $r[0] $r[1] $r[2] $r[3] } }
        if ($Tweak.Apply) { & $Tweak.Apply $Hw }
        Complete-VxTx
        Write-VxLog "Applied: $($Tweak.Id)"
        return @{ ok = $true }
    } catch {
        $msg = $_.Exception.Message
        Complete-VxTx   # keep the partial backup so it can still be undone
        Write-VxLog "Apply $($Tweak.Id) failed: $msg" 'ERROR'
        return @{ ok = $false; error = $msg }
    }
}

# Settings stored inside the active power plan (or per network interface) get lost when Windows or another
# program switches plan / adds an interface. If the user turned them on (backup entry exists), put them back.
$script:VxHealIds = @('powerlat', 'cpumin', 'wifipower', 'nagle')
function Repair-VxLostTweaks {
    param($Hw)
    $fixed = @()
    foreach ($id in $script:VxHealIds) {
        try {
            if (-not (Test-VxBackupEntry $id)) { continue }
            $t = Find-VxTweak $id
            if (-not $t -or -not (Test-VxTweakApplicable $t $Hw)) { continue }
            if (Test-VxTweakApplied $t $Hw) { continue }
            $r = Invoke-VxTweak $t $Hw
            if ($r.ok) { $fixed += $id; Write-VxLog "Re-applied lost setting: $id" }
        } catch { Write-VxLog "Repair $id : $($_.Exception.Message)" 'WARN' }
    }
    return $fixed
}

function Get-VxTweakStates {
    # Returns id -> @{ applicable; applied; rec; canUndo } for the UI
    param($Hw, [string[]]$Cats)
    $b = Get-VxBackup
    $res = @{}
    foreach ($t in (Get-VxAllTweaks)) {
        if ($Cats -and -not ($Cats -contains $t.Cat)) { continue }
        $app = Test-VxTweakApplicable $t $Hw
        $res[$t.Id] = @{
            applicable = $app
            applied = if ($app) { Test-VxTweakApplied $t $Hw } else { $false }
            rec = if ($app) { Get-VxTweakRec $t $Hw } else { $null }
            canUndo = $b.entries.ContainsKey($t.Id)
        }
    }
    return $res
}

function Get-VxPresetSelection {
    # Which tweaks a preset turns on for this PC (skips "not recommended for you")
    param([string]$Preset, $Hw, [hashtable]$States)
    $ids = @()
    foreach ($t in (Get-VxAllTweaks)) {
        if (-not ($t.Presets -contains $Preset)) { continue }
        $st = $States[$t.Id]
        if (-not $st -or -not $st.applicable) { continue }
        if ($st.rec -and $st.rec.level -eq 'notrec') { continue }
        if ($Preset -eq 'laptop' -and $t.Risk -eq 'advanced') { continue }
        $ids += $t.Id
    }
    return $ids
}
