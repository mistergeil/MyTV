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
Register-ScheduledTask -TaskName $Task -Description 'MyTV: switches Proton WireGuard tunnel (DE/CH) on request from MyTV. Remove with VPN-Uninstall.bat.' -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $Task
Write-Host "Installed scheduled task '$Task' and started it."
Start-Sleep -Seconds 3
try {
  $s = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 5
  Write-Host "Switcher is running. Current VPN: $($s.country)" -ForegroundColor Green
} catch { Write-Host "Switcher did not answer yet - check $Dir\agent.log" -ForegroundColor Yellow }
Write-Host "`nIMPORTANT: quit the Proton VPN app while MyTV runs (two VPNs at once conflict)."
Read-Host "`nPress Enter to close"
