# ============================================================
#  MyTV VPN switcher (user-approved; starts at logon with admin rights)
#  Listens ONLY on http://127.0.0.1:8765 (not reachable from the network)
#    GET /status          -> {"ok":true,"country":"DE"|"CH"|"AT"|"OFF"}
#    GET /vpn?c=DE|CH|AT|OFF -> switches the WireGuard tunnel
#  Needs: WireGuard for Windows + DE.conf / CH.conf / AT.conf in this folder
#  Remove any time with VPN-Uninstall.bat
# ============================================================
$ErrorActionPreference = 'Stop'
$Dir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$WG      = Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'
$Port    = 8765
$Allowed = @('DE', 'CH', 'AT')
$Log     = Join-Path $Dir 'agent.log'

function Write-Log($m) { "$(Get-Date -Format s)  $m" | Out-File -FilePath $Log -Append -Encoding utf8 }
function Get-Tunnel($c) { Get-Service -Name "WireGuardTunnel`$$c" -ErrorAction SilentlyContinue }
function Get-Active {
  foreach ($c in $Allowed) { $s = Get-Tunnel $c; if ($s -and $s.Status -eq 'Running') { return $c } }
  return 'OFF'
}
function Set-Vpn($c) {
  if ($c -eq (Get-Active)) { return $c }
  foreach ($o in $Allowed) {
    if ($o -ne $c -and (Get-Tunnel $o)) {
      & $WG /uninstalltunnelservice $o | Out-Null
      for ($i = 0; $i -lt 40 -and (Get-Tunnel $o); $i++) { Start-Sleep -Milliseconds 250 }
    }
  }
  if ($c -ne 'OFF') {
    $conf = Join-Path $Dir "$c.conf"
    if (-not (Test-Path $conf)) { throw "$c.conf not found in $Dir" }
    & $WG /installtunnelservice $conf | Out-Null
    for ($i = 0; $i -lt 60; $i++) {
      Start-Sleep -Milliseconds 250
      $s = Get-Tunnel $c; if ($s -and $s.Status -eq 'Running') { break }
    }
    Start-Sleep -Milliseconds 1500
  }
  $now = Get-Active
  Write-Log "switch -> $c (active: $now)"
  return $now
}

if (-not (Test-Path $WG)) { Write-Log "WireGuard not installed"; exit 1 }
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add("http://127.0.0.1:$Port/")
$l.Start()
Write-Log "agent started on 127.0.0.1:$Port"
while ($l.IsListening) {
  $ctx = $l.GetContext(); $req = $ctx.Request; $res = $ctx.Response
  $out = [ordered]@{}
  try {
    switch ($req.Url.AbsolutePath) {
      '/status' { $out.ok = $true; $out.country = Get-Active }
      '/vpn' {
        $c = ([string]$req.QueryString['c']).ToUpper()
        if ($Allowed -notcontains $c -and $c -ne 'OFF') { throw "unknown country '$c'" }
        $out.country = Set-Vpn $c
        $out.ok = ($out.country -eq $c)
      }
      default { $res.StatusCode = 404; $out.ok = $false; $out.error = 'not found' }
    }
  } catch { $out.ok = $false; $out.error = "$_"; Write-Log "error: $_" }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($out | ConvertTo-Json -Compress))
  $res.ContentType = 'application/json'
  $res.Headers.Add('Access-Control-Allow-Origin', 'https://mistergeil.github.io')
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.Close()
}
