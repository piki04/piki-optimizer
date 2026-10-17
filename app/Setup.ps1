# Piki Optimizer - setup (installs for the current user, no admin needed)
param([switch]$Silent, [switch]$Installed)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SrcRoot = Split-Path -Parent $PSScriptRoot
$Dest = Join-Path $env:LOCALAPPDATA 'PikiOptimizer'
$UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PikiOptimizer'
$it = ((Get-Culture).TwoLetterISOLanguageName -eq 'it')
function Tx($i, $e) { if ($it) { $i } else { $e } }

function Install-Piki {
    param([bool]$Desktop = $true, [scriptblock]$Progress)
    if (-not $Installed -and ($SrcRoot.TrimEnd('\') -ne $Dest.TrimEnd('\'))) {
        # close a running copy first
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
            if ([string]$p.CommandLine -like '*VeloxPC.ps1*') { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
        }
        if ($Progress) { & $Progress 20 }
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
        foreach ($item in @('app', 'Avvia Piki Optimizer.cmd', 'config.json', 'version.json', 'README.md', 'install.ps1')) {
            $s = Join-Path $SrcRoot $item
            if (Test-Path -LiteralPath $s) { Copy-Item -LiteralPath $s -Destination $Dest -Recurse -Force }
        }
        # personal files (logo/background) shipped next to the setup
        $customSrc = Join-Path $SrcRoot 'data'
        if ((Test-Path -LiteralPath $customSrc) -and -not (Test-Path -LiteralPath (Join-Path $Dest 'data\settings.json'))) {
            Copy-Item -LiteralPath $customSrc -Destination $Dest -Recurse -Force
        }
        Get-ChildItem -LiteralPath $Dest -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    }
    if ($Progress) { & $Progress 60 }
    $launcher = Join-Path $Dest 'Avvia Piki Optimizer.cmd'
    $ico = Join-Path $Dest 'app\assets\veloxpc.ico'
    $customIco = Join-Path $Dest 'data\custom\logo.ico'
    if (Test-Path -LiteralPath $customIco) { $ico = $customIco }
    $sh = New-Object -ComObject WScript.Shell
    $places = @([Environment]::GetFolderPath('Programs'))
    if ($Desktop) { $places += [Environment]::GetFolderPath('Desktop') }
    foreach ($folder in $places) {
        $lnk = $sh.CreateShortcut((Join-Path $folder 'Piki Optimizer.lnk'))
        $lnk.TargetPath = $launcher
        $lnk.WorkingDirectory = $Dest
        $lnk.IconLocation = $ico
        $lnk.WindowStyle = 7
        $lnk.Description = 'Piki Optimizer'
        $lnk.Save()
    }
    $ver = '1.0.0'
    try { $ver = [string]((Get-Content -Raw -LiteralPath (Join-Path $Dest 'version.json') | ConvertFrom-Json).version) } catch { }
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    New-Item -Path $UninstKey -Force | Out-Null
    $vals = @{
        DisplayName = 'Piki Optimizer'; DisplayVersion = $ver; Publisher = 'Piki'; DisplayIcon = $ico
        InstallLocation = $Dest; UninstallString = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dest\app\Uninstall.ps1`""
        NoModify = 1; NoRepair = 1
    }
    foreach ($k in $vals.Keys) {
        $type = if ($vals[$k] -is [int]) { 'DWord' } else { 'String' }
        New-ItemProperty -Path $UninstKey -Name $k -Value $vals[$k] -PropertyType $type -Force | Out-Null
    }
    try { $size = [int]((Get-ChildItem -LiteralPath $Dest -Recurse -File | Measure-Object Length -Sum).Sum / 1KB); New-ItemProperty -Path $UninstKey -Name EstimatedSize -Value $size -PropertyType DWord -Force | Out-Null } catch { }
    if ($Progress) { & $Progress 100 }
    return $launcher
}

if ($Silent) { $l = Install-Piki -Desktop $true; Start-Process -FilePath $l -WindowStyle Minimized; return }

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Piki Optimizer - Setup" Width="520" Height="430" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#0A0C11" Foreground="#ECEFF6" FontFamily="Segoe UI Variable Text, Segoe UI">
  <Window.Resources>
    <LinearGradientBrush x:Key="G" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#7C5CFF" Offset="0"/><GradientStop Color="#22D3EE" Offset="1"/></LinearGradientBrush>
    <Style x:Key="B" TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="FontSize" Value="15"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="Bd" CornerRadius="12" Background="{StaticResource G}" Padding="26,12"><ContentPresenter HorizontalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="36,30">
    <StackPanel>
      <Border Width="84" Height="84" CornerRadius="24" Background="{StaticResource G}" HorizontalAlignment="Center">
        <TextBlock Text="P" FontSize="50" FontWeight="Black" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="4,0,0,4"/>
      </Border>
      <TextBlock HorizontalAlignment="Center" FontSize="28" FontWeight="Bold" Margin="0,18,0,0"><Run Text="Piki "/><Run Text="Optimizer" Foreground="#22D3EE"/></TextBlock>
      <TextBlock x:Name="Sub" HorizontalAlignment="Center" TextAlignment="Center" Foreground="#8E96AB" TextWrapping="Wrap" Margin="0,6,0,22"/>
      <CheckBox x:Name="ChkDesk" IsChecked="True" Foreground="#ECEFF6" HorizontalAlignment="Center" Margin="0,0,0,18"/>
      <Border Height="6" CornerRadius="3" Background="#1E2433" Margin="0,0,0,22"><Border x:Name="Bar" HorizontalAlignment="Left" Width="0" CornerRadius="3" Background="{StaticResource G}"/></Border>
      <Button x:Name="Go" Style="{StaticResource B}" HorizontalAlignment="Center"/>
    </StackPanel>
  </Grid>
</Window>
"@
$w = [Windows.Markup.XamlReader]::Parse($xaml)
$sub = $w.FindName('Sub'); $chk = $w.FindName('ChkDesk'); $bar = $w.FindName('Bar'); $go = $w.FindName('Go')
$sub.Text = Tx "Ottimizzazione, check-up e ping basso per il tuo PC.`nSi installa in pochi secondi, solo per il tuo utente." "Optimization, check-up and low ping for your PC.`nInstalls in seconds, for your user only."
$chk.Content = Tx 'Crea icona sul desktop' 'Create desktop icon'
$go.Content = Tx 'Installa' 'Install'
$script:Launcher = $null
$go.add_Click({
    if ($script:Launcher) { Start-Process -FilePath $script:Launcher -WindowStyle Minimized; $w.Close(); return }
    $go.IsEnabled = $false; $chk.IsEnabled = $false
    try {
        $script:Launcher = Install-Piki -Desktop ([bool]$chk.IsChecked) -Progress { param($p) $bar.Width = 448 * $p / 100; $w.Dispatcher.Invoke([Action] {}, 'Background') }
        $sub.Text = Tx "Installato! Lo trovi nel menu Start e sul desktop.`nPer disinstallarlo: Impostazioni > App." "Installed! Find it in the Start menu and on the desktop.`nTo uninstall: Settings > Apps."
        $go.Content = Tx 'Avvia Piki Optimizer' 'Launch Piki Optimizer'
        $go.IsEnabled = $true
    } catch {
        $sub.Text = (Tx 'Errore: ' 'Error: ') + $_.Exception.Message
        $go.IsEnabled = $true
    }
})
[void]$w.ShowDialog()
