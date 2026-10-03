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
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Agent`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
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
$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
  $_.IPAddress -notmatch '^(127|169\.254)\.' -and $_.InterfaceAlias -notmatch 'WireGuard|vEthernet|Loopback|^(DE|CH|AT)$' } |
  Sort-Object InterfaceMetric | Select-Object -First 1).IPAddress
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
  "3) For the Shortcut ('Get contents of URL'):",
  "   Wake MyTV:          $base/cmd?key=$Key&do=on",
  "   Channel, e.g. 22:   $base/cmd?key=$Key&do=ch&n=22"
) | Set-Content -Path (Join-Path $Dir 'Remote-Links.txt') -Encoding utf8

Register-ScheduledTask -TaskName $Task -Description 'MyTV: switches the Proton WireGuard tunnel (DE/CH/AT) for MyTV + iPhone remote on port 8766 (secret key). Remove with VPN-Uninstall.bat.' -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $Task
Write-Host "Installed scheduled task '$Task' and started it."
Start-Sleep -Seconds 3
try {
  $s = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 5
  Write-Host "Switcher is running. Current VPN: $($s.country)" -ForegroundColor Green
} catch { Write-Host "Switcher did not answer yet - check $Dir\agent.log" -ForegroundColor Yellow }
Write-Host "`niPhone remote links saved in $Dir\Remote-Links.txt (opening it now)." -ForegroundColor Green
Start-Process notepad.exe (Join-Path $Dir 'Remote-Links.txt')
Write-Host "`nIMPORTANT: quit the Proton VPN app while MyTV runs (two VPNs at once conflict)."
Read-Host "`nPress Enter to close"
