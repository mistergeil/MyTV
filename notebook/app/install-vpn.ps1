# MyTV VPN switcher - installer (run via VPN-Install.bat, needs admin)
$ErrorActionPreference = 'Stop'
$Dir   = $PSScriptRoot
$WG    = Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'
$Agent = Join-Path $Dir 'mytv-vpn-agent.ps1'
$Task  = 'MyTV VPN Switcher'

Write-Host "`n== MyTV VPN switcher setup ==`n"
if (-not (Test-Path $WG)) {
  Write-Host "WireGuard for Windows is not installed." -ForegroundColor Yellow
  Write-Host "Opening the download page - install it, then run VPN-Install.bat again."
  Start-Process 'https://www.wireguard.com/install/'
  Read-Host "`nPress Enter to close"; exit 1
}
$missing = @('DE', 'CH', 'AT') | Where-Object { -not (Test-Path (Join-Path $Dir "$_.conf")) }
if ($missing) {
  Write-Host ("Missing config file(s): " + (($missing | ForEach-Object { "$_.conf" }) -join ', ')) -ForegroundColor Yellow
  Write-Host "Download them from Proton (see the setup page) and save them in:`n  $Dir`n"
}
# conhost --headless: no console window flashes up and steals the focus from Chrome (taskbar would appear)
$Con = Join-Path $env:WINDIR 'System32\conhost.exe'
$action    = New-ScheduledTaskAction -Execute $Con -Argument "--headless powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Agent`""
$trigger   = @((New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),
               (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2)))   # watchdog
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
# stop a switcher that is still running (otherwise the old version keeps the port)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*mytv-vpn-agent.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1
# close running tunnels once, so they come back with the new routes (iPhone can reach the notebook)
foreach ($c in 'DE', 'CH', 'AT') { if (Get-Service -Name "WireGuardTunnel`$$c" -ErrorAction SilentlyContinue) { & $WG /uninstalltunnelservice $c | Out-Null } }

# ---- iPhone remote: secret key + ready-made links (firewall rule: see setup page, done by hand) ----
$KeyFile = Join-Path $Dir 'remote.key'
if (-not (Test-Path $KeyFile)) {
  $chars = 'abcdefghijkmnpqrstuvwxyz23456789'.ToCharArray()
  (-join (1..16 | ForEach-Object { $chars | Get-Random })) | Set-Content -Path $KeyFile -Encoding ascii -NoNewline
}
$Key = (Get-Content $KeyFile -Raw).Trim()
# Samsung TV MAC address for Wake-on-LAN ("TV an" sticker switches the TV on via the notebook)
$MacFile = Join-Path $Dir 'tv-mac.txt'
$cur = if (Test-Path $MacFile) { (Get-Content $MacFile -Raw).Trim() } else { '' }
$m = Read-Host ("TV MAC address for switching the TV on (e.g. 64:1C:AE:12:34:56)" + $(if ($cur) { " [Enter = keep $cur]" } else { ' [Enter = skip]' }))
if ($m.Trim()) {
  if (($m -replace '[^0-9A-Fa-f]', '').Length -eq 12) { $m.Trim() | Set-Content -Path $MacFile -Encoding ascii -NoNewline }
  else { Write-Host "That doesn't look like a MAC address - skipped." -ForegroundColor Yellow }
}
# TV IP + HDMI port: the notebook switches the TV to MyTV's input over the network (Samsung "IP Remote")
$IpFile = Join-Path $Dir 'tv-ip.txt'; $HdmiFile = Join-Path $Dir 'tv-hdmi.txt'
$cur = if (Test-Path $IpFile) { (Get-Content $IpFile -Raw).Trim() } else { '' }
$v = Read-Host ("TV IP address (e.g. 192.168.1.94)" + $(if ($cur) { " [Enter = keep $cur]" } else { ' [Enter = skip]' }))
if ($v.Trim() -match '^\d{1,3}(\.\d{1,3}){3}$') { $v.Trim() | Set-Content -Path $IpFile -Encoding ascii -NoNewline }
elseif ($v.Trim()) { Write-Host "That doesn't look like an IP address - skipped." -ForegroundColor Yellow }
if (Test-Path $IpFile) {
  $cur = 'auto'
  $v = Read-Host "HDMI: Enter = automatic (recommended) or type the port number 1-4"
  if ($v.Trim() -match '^[1-4]$') { $cur = $v.Trim() }
  $cur | Set-Content -Path $HdmiFile -Encoding ascii -NoNewline
}
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
  $_.IPAddress -notmatch '^(127|169\.254)\.' -and $_.InterfaceAlias -notmatch 'WireGuard|vEthernet|Loopback|^(DE|CH|AT)$' } |
  Sort-Object InterfaceMetric | Select-Object -First 1).IPAddress
# ---- SmartThings: the notebook starts your routine "MyTV" (TV on + HDMI) when the sticker is tapped ----
$StFile = Join-Path $Dir 'st-cli.txt'; $SceneFile = Join-Path $Dir 'st-scene.txt'
$ans = Read-Host "Set up SmartThings (TV on + HDMI via your SmartThings routine)? [Y/n]"
if ($ans -notmatch '^[nN]') {
  function Find-StCli {
    $c = Get-Command smartthings -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
      if ($root -and (Test-Path $root)) {
        $f = Get-ChildItem -Path $root -Filter 'smartthings.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
      }
    }
    return $null
  }
  $exe = Find-StCli
  if (-not $exe) {
    Write-Host "Downloading Samsung's SmartThings CLI (official, github.com/SmartThingsCommunity/smartthings-cli) ..."
    $msi = Join-Path $env:TEMP 'smartthings.msi'
    try {
      Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/SmartThingsCommunity/smartthings-cli/releases/latest/download/smartthings.msi' -OutFile $msi
      Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn" -Wait
    } catch { Write-Host "Download/installation failed: $_" -ForegroundColor Yellow }
    $exe = Find-StCli
  }
  if (-not $exe) { Write-Host "SmartThings CLI not found - skipped." -ForegroundColor Yellow }
  else {
    $exe | Set-Content -Path $StFile -Encoding ascii -NoNewline
    Write-Host "`nA browser window opens: log in with your Samsung account and allow access." -ForegroundColor Cyan
    & $exe scenes | Out-Host
    $scenes = @()
    try { $scenes = @((& $exe scenes --json) -join "`n" | ConvertFrom-Json) } catch { }
    if (-not $scenes.Count) { Write-Host "No SmartThings routines found. Create the manual routine 'MyTV' in the app, then run VPN-Install.bat again." -ForegroundColor Yellow }
    else {
      $pick = $scenes | Where-Object { $_.sceneName -eq 'MyTV' } | Select-Object -First 1
      if (-not $pick) {
        for ($i = 0; $i -lt $scenes.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $scenes[$i].sceneName) }
        $n = Read-Host "Number of the routine that turns the TV on + HDMI"
        if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $scenes.Count) { $pick = $scenes[[int]$n - 1] }
      }
      if ($pick) { $pick.sceneId | Set-Content -Path $SceneFile -Encoding ascii -NoNewline; Write-Host "Sticker will start the routine '$($pick.sceneName)'." -ForegroundColor Green }
    }
  }
}

$base = "http://$($ip):8766"
@(
  "MyTV iPhone remote",
  "Notebook IP: $ip  - give it a fixed IP in your router so these links keep working.",
  "",
  "1) Test in Safari on the iPhone (must show ok:true):",
  "   $base/ping?key=$Key",
  "",
  "2) Remote page (Safari -> Share -> Add to Home Screen):",
  "   $base/remote?key=$Key",
  "",
  "NFC sticker link (write with the app 'NFC Tools' -> Write -> URL) - any iPhone: tap sticker -> TV on + remote:",
  "   $base/remote?key=$Key&on=1",
  "",
  "3) For the Shortcut ('Get contents of URL'):",
  "   Wake MyTV:          $base/cmd?key=$Key&do=on",
  "   Channel, e.g. 22:   $base/cmd?key=$Key&do=ch&n=22"
) | Set-Content -Path (Join-Path $Dir 'Remote-Links.txt') -Encoding utf8

Register-ScheduledTask -TaskName $Task -Description 'MyTV: switches the Proton WireGuard tunnel (DE/CH/AT) for MyTV + iPhone remote on port 8766 (secret key). Remove with VPN-Uninstall.bat.' -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $Task
Write-Host "Installed scheduled task '$Task' and started it."
# updater: only runs when the user taps "Installieren" / "Wiederherstellen" in the iPhone remote settings
$UpdTask = 'MyTV Updater'
$uAction   = New-ScheduledTaskAction -Execute $Con -Argument "--headless powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $Dir 'mytv-update.ps1')`""
$uSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName $UpdTask -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $UpdTask -Description 'MyTV: installs an update / restores a backup when requested from the iPhone remote settings (checks the SHA-256 from version.json, keeps a backup, rolls back automatically). Remove with VPN-Uninstall.bat.' -Action $uAction -Principal $principal -Settings $uSettings | Out-Null
Write-Host "Installed '$UpdTask' (updates from the iPhone remote: Einstellungen)." -ForegroundColor Green
Start-Sleep -Seconds 3
try {
  $s = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 5
  Write-Host "Switcher is running. Current VPN: $($s.country)" -ForegroundColor Green
} catch { Write-Host "Switcher did not answer yet - check $Dir\agent.log" -ForegroundColor Yellow }
Write-Host "`niPhone remote links saved in $Dir\Remote-Links.txt (opening it now)." -ForegroundColor Green
Start-Process notepad.exe (Join-Path $Dir 'Remote-Links.txt')
Write-Host "`nIMPORTANT: quit the Proton VPN app while MyTV runs (two VPNs at once conflict)."
Read-Host "`nPress Enter to close"
