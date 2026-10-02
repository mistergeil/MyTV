# MyTV VPN switcher - remove everything (run via VPN-Uninstall.bat)
$WG = Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'
Unregister-ScheduledTask -TaskName 'MyTV VPN Switcher' -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*mytv-vpn-agent.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
foreach ($c in 'DE', 'CH') { if (Get-Service -Name "WireGuardTunnel`$$c" -ErrorAction SilentlyContinue) { & $WG /uninstalltunnelservice $c } }
Write-Host "MyTV VPN switcher removed and VPN tunnels closed."
Read-Host "Press Enter to close"
