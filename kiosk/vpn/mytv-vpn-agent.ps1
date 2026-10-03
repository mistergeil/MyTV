# ============================================================
#  MyTV switcher (user-approved; starts at logon with admin rights)
#
#  Local only - http://127.0.0.1:8765 (used by the MyTV Bridge script in Chrome):
#    GET /status              -> {"ok":true,"country":"DE"|"CH"|"AT"|"OFF"}
#    GET /vpn?c=DE|CH|AT|OFF  -> switches the WireGuard tunnel
#    GET /vpn/next?c=DE       -> same country, next server (DE.conf, DE-2.conf, DE-3.conf ...) - "VPN erkannt" on Joyn / RTL+
#    GET /cmd/since?seq=N&boot=B -> remote commands newer than N
#    GET /favs                -> favorite channel numbers (MyTV lists them first)
#    GET /rem                 -> reminders (one list for MyTV, the overlay on every channel and the Mediathek)
#    GET /rem/add?ch=&chName=&title=&start=&end=&mode=remind|auto   /rem/del?ch=&start=   /rem/take?ch=&start=&step=
#    GET /pipe/test, /pipe/result?ok=1&where=  -> "Verbindung testen" (remote -> notebook -> MyTV -> notebook)
#    GET /ui?guide=1|0        -> MyTV reports what is on screen (remote shows Jetzt/Morgen/Übermorgen while the guide is open)
#
#  Home network - port 8766, every request needs the secret key from remote.key
#  (user-approved iPhone remote; the Windows firewall rule is added by the user by hand):
#    GET /remote?key=KEY      -> remote control page for the phone
#    GET /cmd?key=KEY&do=on | do=ch&n=22 | do=key&k=ArrowUp
#    GET /ping?key=KEY
#    GET /vpn/next?key=KEY[&c=DE] -> "Anderer Server" button on the remote
#    GET /favs?key=KEY             -> favorite channel numbers (favorites.txt)
#    GET /favs/set?key=KEY&n=22&on=1|0 -> add / remove a favorite (long-press on the remote)
#    GET /update?key=KEY[&force=1] -> installed / latest version (GitHub Pages version.json), state of the last update
#    GET /update/install?key=KEY   -> user tapped "Installieren": starts the task "MyTV Updater" (mytv-update.ps1)
#    GET /update/rollback?key=KEY  -> user tapped "Wiederherstellen": puts the last backup back
#
#  Needs: WireGuard for Windows + DE.conf / CH.conf / AT.conf in this folder
#  More servers per country (optional): DE-2.conf, DE-3.conf ... - used in turn when a server is blocked
#  Remove any time with VPN-Uninstall.bat
# ============================================================
$ErrorActionPreference = 'Stop'
$Dir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$WG      = Join-Path $env:ProgramFiles 'WireGuard\wireguard.exe'
$Port    = 8765
$LanPort = 8766
$Allowed = @('DE', 'CH', 'AT')
$Log     = Join-Path $Dir 'agent.log'
$RunDir  = Join-Path $Dir 'run'
$KeyFile = Join-Path $Dir 'remote.key'
$MacFile = Join-Path $Dir 'tv-mac.txt'
$StFile  = Join-Path $Dir 'st-cli.txt'      # path of Samsung's SmartThings CLI (smartthings.exe)
$SceneFile = Join-Path $Dir 'st-scene.txt'  # id of the SmartThings routine "MyTV" (TV on + HDMI)
$Key     = if (Test-Path $KeyFile) { (Get-Content $KeyFile -Raw).Trim() } else { '' }
$Keys    = @('ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Enter', 'Backspace', 'Escape', 'g', 'h', 'l', 'b', 'm', 'i', '+', '-', 'GuideNow', 'GuideDay1', 'GuideDay2', 'GuidePrime')
$Boot    = [string][DateTime]::UtcNow.Ticks
$FavFile = Join-Path $Dir 'favorites.txt'
$RemFile = Join-Path $Dir 'reminders.json'
$PipeTest = $null                                  # last pipe test result (shown in the remote settings)
$GuideAt = [DateTime]::MinValue                   # last "guide is open" report from MyTV (expires after 12 s)
$VerFile = Join-Path $Dir 'VERSION'
$Version = if (Test-Path $VerFile) { (Get-Content $VerFile -Raw).Trim() } else { '0' }
$UpdUrl  = 'https://mistergeil.github.io/MyTV/kiosk/version.json'
$UpdTask = 'MyTV Updater'
$UpdState = Join-Path $RunDir 'update-state.json'
$UpdInfo = $null; $UpdChecked = [DateTime]::MinValue
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Seq     = 0
$Queue   = New-Object System.Collections.ArrayList

function Write-Log($m) { "$(Get-Date -Format s)  $m" | Out-File -FilePath $Log -Append -Encoding utf8 }
function Get-Tunnel($c) { Get-Service -Name "WireGuardTunnel`$$c" -ErrorAction SilentlyContinue }
function Get-Active {
  foreach ($c in $Allowed) { $s = Get-Tunnel $c; if ($s -and $s.Status -eq 'Running') { return $c } }
  return 'OFF'
}
# Copy of the Proton config with split default routes (0.0.0.0/1 + 128.0.0.0/1) instead of 0.0.0.0/0:
# all internet traffic still goes through the VPN, but WireGuard's "block untunneled traffic"
# lock stays off, so the iPhone on the home Wi-Fi can still reach the notebook.
# all configs of a country: DE.conf first, then DE-2.conf / DE02.conf ... in name order
function Get-Configs($c) {
  $main = Get-Item -LiteralPath (Join-Path $Dir "$c.conf") -ErrorAction SilentlyContinue
  # DE-2.conf, DE02.conf, DE_berlin.conf ... (country code, then anything that doesn't start with a letter)
  $more = @(Get-ChildItem -Path $Dir -Filter "$c*.conf" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^$c[^A-Za-z.].*\.conf$" } | Sort-Object Name)
  return @(@($main) + $more | Where-Object { $_ })
}
# the server that worked last is remembered by file name (run\server-DE.txt), so adding / removing files doesn't mix it up
function Get-ServerIdx($c) {
  $cfg = Get-Configs $c
  if (-not $cfg.Count) { return 0 }
  $f = Join-Path $RunDir "server-$c.txt"
  if (-not (Test-Path $f)) { return 0 }
  $v = (Get-Content $f -Raw).Trim()
  for ($k = 0; $k -lt $cfg.Count; $k++) { if ($cfg[$k].BaseName -eq $v) { return $k } }
  $i = 0; if ([int]::TryParse($v, [ref]$i)) { return ($i % $cfg.Count) }      # old format: index
  return 0
}
function Set-ServerIdx($c, $i) {
  if (-not (Test-Path $RunDir)) { New-Item -ItemType Directory -Path $RunDir | Out-Null }
  $cfg = Get-Configs $c
  Set-Content -Path (Join-Path $RunDir "server-$c.txt") -Value $cfg[$i].BaseName -Encoding ascii -NoNewline
}
function Get-ServerInfo($c) {
  $cfg = Get-Configs $c; $i = Get-ServerIdx $c
  if (-not $cfg.Count) { return $null }
  return [ordered]@{ name = $cfg[$i].BaseName; n = $i + 1; of = $cfg.Count }
}
# Copy of the Proton config with split default routes (0.0.0.0/1 + 128.0.0.0/1) instead of 0.0.0.0/0:
# all internet traffic still goes through the VPN, but WireGuard's "block untunneled traffic"
# lock stays off, so the iPhone on the home Wi-Fi can still reach the notebook.
# The copy is always called run\<country>.conf, so the tunnel keeps its name whichever server is used.
function Get-RunConf($c) {
  $cfg = Get-Configs $c
  if (-not $cfg.Count) { throw "$c.conf not found in $Dir" }
  $src = $cfg[(Get-ServerIdx $c)].FullName
  if (-not (Test-Path $RunDir)) { New-Item -ItemType Directory -Path $RunDir | Out-Null }
  $lines = Get-Content $src | ForEach-Object {
    if ($_ -match '^\s*AllowedIPs\s*=\s*(.*)$') {
      $ips = $Matches[1] -split '\s*,\s*' | ForEach-Object {
        if ($_ -eq '0.0.0.0/0') { '0.0.0.0/1'; '128.0.0.0/1' } elseif ($_ -eq '::/0') { '::/1'; '8000::/1' } else { $_ }
      }
      'AllowedIPs = ' + ($ips -join ', ')
    } else { $_ }
  }
  $dst = Join-Path $RunDir "$c.conf"
  Set-Content -Path $dst -Value $lines -Encoding ascii
  return $dst
}
# next server of the same country (blocked by a streaming site) - rebuilds the tunnel even if the country is already active
function Switch-Server($c) {
  $cfg = Get-Configs $c
  if (-not $cfg.Count) { throw "$c.conf not found in $Dir" }
  $i = ((Get-ServerIdx $c) + 1) % $cfg.Count
  Set-ServerIdx $c $i
  if ((Get-Active) -eq $c) {
    & $WG /uninstalltunnelservice $c | Out-Null
    for ($k = 0; $k -lt 40 -and (Get-Tunnel $c); $k++) { Start-Sleep -Milliseconds 250 }
  }
  $now = Set-Vpn $c
  Write-Log "server $c -> $($cfg[$i].BaseName) ($($i + 1)/$($cfg.Count)), active: $now"
  return $now
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
    $conf = Get-RunConf $c
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
# Wake-on-LAN for the TV (same signal the SmartThings app sends) - MAC from tv-mac.txt
function Send-Wol {
  if (-not (Test-Path $MacFile)) { return 'no tv-mac.txt' }
  $mac = ((Get-Content $MacFile -Raw) -replace '[^0-9A-Fa-f]', '')
  if ($mac.Length -ne 12) { return 'tv-mac.txt: bad MAC' }
  $mb  = [byte[]](0..5 | ForEach-Object { [Convert]::ToByte($mac.Substring($_ * 2, 2), 16) })
  $pkt = [byte[]]((,0xFF * 6) + ($mb * 16))
  $targets = @('255.255.255.255')
  Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
    $_.IPAddress -notmatch '^(127|169\.254)\.' -and $_.InterfaceAlias -notmatch 'WireGuard|vEthernet|Loopback|^(DE|CH|AT)$' } | ForEach-Object {
    $ip = [Net.IPAddress]::Parse($_.IPAddress).GetAddressBytes(); $bits = [int]$_.PrefixLength
    $bc = for ($i = 0; $i -lt 4; $i++) {
      $b = [Math]::Max(0, [Math]::Min(8, $bits - 8 * $i)); $m = (0xFF -shl (8 - $b)) -band 0xFF
      $ip[$i] -bor ((-bnot $m) -band 0xFF)
    }
    $targets += ($bc -join '.')
  }
  $u = New-Object System.Net.Sockets.UdpClient
  $u.EnableBroadcast = $true
  foreach ($t in ($targets | Select-Object -Unique)) { for ($r = 0; $r -lt 3; $r++) { try { [void]$u.Send($pkt, $pkt.Length, $t, 9) } catch {} } }
  $u.Close()
  return 'sent to ' + (($targets | Select-Object -Unique) -join ', ')
}
# Start the user's SmartThings routine (TV on + HDMI) with Samsung's official SmartThings CLI
function Start-StScene {
  if (-not (Test-Path $StFile) -or -not (Test-Path $SceneFile)) { return $null }
  $exe = (Get-Content $StFile -Raw).Trim(); $id = (Get-Content $SceneFile -Raw).Trim()
  if (-not (Test-Path $exe)) { return 'smartthings.exe not found' }
  if (-not (Test-Path $RunDir)) { New-Item -ItemType Directory -Path $RunDir | Out-Null }
  Start-Process -FilePath $exe -ArgumentList "scenes:execute $id" -NoNewWindow `
    -RedirectStandardOutput (Join-Path $RunDir 'st-out.txt') -RedirectStandardError (Join-Path $RunDir 'st-err.txt')
  return "routine $id started"
}
function Add-Cmd($do, $n, $k) {
  $script:Seq++
  [void]$Queue.Add(@{ seq = $script:Seq; do = $do; n = $n; k = $k; t = [DateTime]::UtcNow })
  while ($Queue.Count -gt 50) { $Queue.RemoveAt(0) }
}
# ---- favorites: channel numbers, comma-separated, in favorites.txt ----
function Get-Favs {
  if (-not (Test-Path $FavFile)) { return @() }
  return @(((Get-Content $FavFile -Raw) -split '[^0-9]+') | Where-Object { $_ } | ForEach-Object { [int]$_ } | Sort-Object -Unique)
}
function Set-Fav([int]$n, [bool]$on) {
  $f = @(Get-Favs | Where-Object { $_ -ne $n })
  if ($on) { $f += $n }
  ($f | Sort-Object -Unique) -join ',' | Set-Content -Path $FavFile -Encoding ascii -NoNewline
  return @(Get-Favs)
}
# ---- reminders: one list on the notebook (browser storage is split per website, so every channel page had its own) ----
function Get-Rems {
  if (-not (Test-Path $RemFile)) { return @() }
  try { $l = @(Get-Content $RemFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return @() }
  $cut = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 15 * 60000
  return @($l | Where-Object { $_ -and [int64]$_.end -gt $cut })
}
function Save-Rems($l) {
  $json = ConvertTo-Json -InputObject @($l) -Depth 4 -Compress
  if (-not $l -or @($l).Count -eq 0) { $json = '[]' }
  [IO.File]::WriteAllText($RemFile, $json, (New-Object Text.UTF8Encoding $false))
}
# query value decoded as UTF-8 (HttpListener's own QueryString may use the ANSI code page → broken umlauts)
function Get-QS($req, $name) {
  foreach ($part in ($req.Url.Query.TrimStart('?') -split '&')) {
    $kv = $part -split '=', 2
    if ($kv[0] -eq $name) { return [Uri]::UnescapeDataString(($kv[1] -replace '\+', ' ')) }
  }
  return ''
}
function Find-Rem($l, $ch, $start) { return @($l | Where-Object { [int]$_.ch -eq $ch -and [int64]$_.start -eq $start }) }
# ---- updates (only ever installed after a tap on the iPhone remote) ----
function Get-UpdateInfo($force) {
  if ($force -or -not $script:UpdInfo -or ([DateTime]::UtcNow - $script:UpdChecked).TotalHours -ge 6) {
    try {
      $script:UpdInfo = Invoke-RestMethod -Uri ($UpdUrl + '?t=' + [DateTime]::UtcNow.Ticks) -TimeoutSec 10
      $script:UpdChecked = [DateTime]::UtcNow
    } catch { if ($force) { throw "GitHub nicht erreichbar: $($_.Exception.Message)" } }
  }
  return $script:UpdInfo
}
function Get-UpdateState { if (Test-Path $UpdState) { try { return (Get-Content $UpdState -Raw | ConvertFrom-Json) } catch {} } return $null }
function Get-BackupNames { $b = Join-Path (Split-Path -Parent $Dir) 'backup'; if (Test-Path $b) { @(Get-ChildItem $b -Directory | Sort-Object Name -Descending | ForEach-Object { $_.Name }) } else { @() } }
function Start-Updater($action) {
  if (-not (Get-ScheduledTask -TaskName $UpdTask -ErrorAction SilentlyContinue)) { throw 'Updater nicht installiert - einmal VPN-Install.bat ausführen' }
  $st = Get-UpdateState
  if ($st -and $st.state -eq 'running' -and ((Get-Date) - [DateTime]$st.t).TotalMinutes -lt 10) { throw 'Update läuft bereits' }
  if (-not (Test-Path $RunDir)) { New-Item -ItemType Directory -Path $RunDir | Out-Null }
  ConvertTo-Json @{ action = $action } -Compress | Set-Content -Path (Join-Path $RunDir 'update-request.json') -Encoding utf8
  ConvertTo-Json ([ordered]@{ state = 'running'; msg = 'Startet ...'; t = (Get-Date).ToString('s'); from = $Version }) -Compress | Set-Content -Path $UpdState -Encoding utf8
  Start-ScheduledTask -TaskName $UpdTask
  Write-Log "update: $action requested (installed $Version)"
}
# ---- keep the TV screen clean: no console windows that pull focus away from Chrome (taskbar would show) ----
function Set-HiddenTasks {
  $ch = Join-Path $env:WINDIR 'System32\conhost.exe'
  foreach ($t in @('MyTV VPN Switcher', 'MyTV Updater')) {
    try {
      $task = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
      if (-not $task -or -not (Test-Path $ch)) { continue }
      $a = $task.Actions[0]
      if ($a.Execute -match 'powershell\.exe$') {
        Set-ScheduledTask -TaskName $t -Action (New-ScheduledTaskAction -Execute $ch -Argument ('--headless powershell.exe ' + $a.Arguments)) | Out-Null
        Write-Log "task '$t' now starts without a window"
      }
    } catch { Write-Log "could not update task '$t': $_" }
  }
}
# watchdog: the switcher task also runs every 2 minutes; if it is already running nothing happens (IgnoreNew),
# if it stopped for whatever reason it comes back by itself
function Set-Watchdog {
  try {
    $task = Get-ScheduledTask -TaskName 'MyTV VPN Switcher' -ErrorAction SilentlyContinue
    if (-not $task) { return }
    $has = @($task.Triggers | Where-Object { $_.Repetition -and $_.Repetition.Interval -eq 'PT2M' }).Count -gt 0
    if ($has -and $task.Settings.MultipleInstances -eq 'IgnoreNew') { return }
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $rep = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2)
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
             -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    Set-ScheduledTask -TaskName 'MyTV VPN Switcher' -Trigger @($logon, $rep) -Settings $set | Out-Null
    Write-Log 'watchdog on: switcher restarts itself within 2 minutes if it ever stops'
  } catch { Write-Log "watchdog setup failed: $_" }
}
function Restore-KioskFocus {
  try {
    $p = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) { [void](New-Object -ComObject WScript.Shell).AppActivate($p.Id); Write-Log 'brought Chrome back to the front' }
  } catch {}
}
function Send-Bytes($res, [byte[]]$bytes, $type) {
  $res.ContentType = $type
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.Close()
}

if (-not (Test-Path $WG)) { Write-Log "WireGuard not installed"; exit 1 }
Set-HiddenTasks
Set-Watchdog
# started by an update a moment ago → give the TV picture back to Chrome
$us = Get-UpdateState
if ($us -and ((Get-Date) - [DateTime]$us.t).TotalMinutes -lt 3) { Start-Sleep -Seconds 1; Restore-KioskFocus }
# the listener survives network changes (VPN switch, Wi-Fi) and aborted requests: on any error it is rebuilt,
# and the switcher never ends by itself. If it does end anyway, the watchdog trigger starts it again within 2 minutes.
function Start-Listener {
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $x = New-Object System.Net.HttpListener
      $x.Prefixes.Add("http://127.0.0.1:$Port/")
      if ($Key) { $x.Prefixes.Add("http://+:$LanPort/") }
      $x.Start()
      return $x
    } catch { Write-Log "listener start failed (try $($i + 1)): $_"; Start-Sleep -Seconds 2 }
  }
  throw 'listener could not be started'
}
$l = Start-Listener
Write-Log ("agent $Version started on 127.0.0.1:$Port" + $(if ($Key) { " + iPhone remote on port $LanPort" } else { ' (no remote.key -> iPhone remote off)' }))
while ($true) {
  try {
    if (-not $l.IsListening) { throw 'listener stopped' }
    $ctx = $l.GetContext(); $req = $ctx.Request; $res = $ctx.Response
    $out = [ordered]@{}
    $page = $null
    $lan = $req.LocalEndPoint.Port -eq $LanPort
  } catch {
    Write-Log "listener error: $_ - restarting listener"
    try { $l.Close() } catch {}
    Start-Sleep -Seconds 1
    $l = Start-Listener
    continue
  }
  try {
    if ($lan) {
      # ---------- home network: iPhone remote (secret key required) ----------
      if (-not $Key -or [string]$req.QueryString['key'] -cne $Key) { $res.StatusCode = 403; throw 'wrong key' }
      $path = $req.Url.AbsolutePath
      if ($path -eq '/remote') {
        $page = [IO.File]::ReadAllBytes((Join-Path $Dir 'remote.html'))
      } elseif ($path -eq '/ping') {
        $out.ok = $true; $out.vpn = Get-Active; $out.version = $Version
        if ($out.vpn -ne 'OFF') { $out.server = Get-ServerInfo $out.vpn }
        $out.guide = (([DateTime]::UtcNow - $GuideAt).TotalSeconds -lt 12)
      } elseif ($path -eq '/vpn/next') {
        $c = ([string]$req.QueryString['c']).ToUpper(); if (-not $c) { $c = Get-Active }
        if ($Allowed -notcontains $c) { throw 'VPN ist aus - erst einen Sender mit VPN wählen' }
        $out.country = Switch-Server $c; $out.server = Get-ServerInfo $c; $out.ok = ($out.country -eq $c)
        if ($out.ok) { Add-Cmd 'reload' '' '' }          # the channel on the TV reloads with the new server
      } elseif ($path -eq '/favs') {
        $out.ok = $true; $out.favs = @(Get-Favs)
      } elseif ($path -eq '/favs/set') {
        $n = [string]$req.QueryString['n']
        if ($n -notmatch '^\d{1,3}$') { throw 'favs/set needs n=<channel number>' }
        $out.favs = @(Set-Fav ([int]$n) ([string]$req.QueryString['on'] -ne '0'))
        Add-Cmd 'favs' '' ''
        Write-Log "favorite $n -> $([string]$req.QueryString['on'] -ne '0')"
        $out.ok = $true
      } elseif ($path -eq '/update') {
        $i = Get-UpdateInfo ([string]$req.QueryString['force'] -eq '1')
        $out.ok = $true; $out.installed = $Version
        if ($i) {
          $out.latest = [string]$i.version; $out.available = ([string]$i.version -ne $Version)
          $out.notes = @($i.notes); $out.date = [string]$i.date; $out.installer = [bool]$i.installer
          $out.checked = $UpdChecked.ToLocalTime().ToString('s')
        }
        $out.state = Get-UpdateState; $out.backups = @(Get-BackupNames); $out.pipe = $PipeTest
      } elseif ($path -eq '/update/install') {
        $i = Get-UpdateInfo $true
        if (-not $i -or [string]$i.version -eq $Version) { throw 'Kein Update verfügbar' }
        Start-Updater 'install'; $out.ok = $true; $out.to = [string]$i.version
      } elseif ($path -eq '/update/rollback') {
        if (-not (Get-BackupNames)) { throw 'Keine Sicherung vorhanden' }
        Start-Updater 'rollback'; $out.ok = $true
      } elseif ($path -eq '/cmd') {
        $do = ([string]$req.QueryString['do']).ToLower()
        $n  = [string]$req.QueryString['n']
        $k  = [string]$req.QueryString['k']
        if ($do -eq 'ch') { if ($n -notmatch '^\d{1,3}$') { throw 'ch needs n=<channel number>' } }
        elseif ($do -eq 'key') { if ($Keys -cnotcontains $k) { throw "key '$k' not allowed" } }
        elseif ($do -eq 'test') { $PipeTest = $null }
        elseif ($do -ne 'on') { throw "unknown command '$do'" }
        if ($do -eq 'on') {
          $out.wol = Send-Wol; Write-Log "wake-on-lan: $($out.wol)"
          # TV on + HDMI: preferably via the SmartThings routine, otherwise the TV's network remote (tv-remote.ps1)
          $st = Start-StScene
          if ($st) { $out.tv = $st; Write-Log "smartthings: $st" }
          elseif (Test-Path (Join-Path $Dir 'tv-ip.txt')) {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Dir 'tv-remote.ps1')`""
            $out.hdmi = 'switching'
          }
        }
        Add-Cmd $do $n $k
        if ($do -ne 'key') { Write-Log "remote: $do $n from $($req.RemoteEndPoint.Address)" }
        $out.ok = $true
      } else { $res.StatusCode = 404; throw 'not found' }
    } else {
      # ---------- local: MyTV in Chrome ----------
      $path = $req.Url.AbsolutePath
      if ($path -eq '/status') {
        $out.ok = $true; $out.country = Get-Active; $out.remote = [bool]$Key; $out.version = $Version
        if ($out.country -ne 'OFF') { $out.server = Get-ServerInfo $out.country }
      } elseif ($path -eq '/vpn') {
        $c = ([string]$req.QueryString['c']).ToUpper()
        if ($Allowed -notcontains $c -and $c -ne 'OFF') { throw "unknown country '$c'" }
        $out.country = Set-Vpn $c
        $out.ok = ($out.country -eq $c)
      } elseif ($path -eq '/favs') {
        $out.ok = $true; $out.favs = @(Get-Favs)
      } elseif ($path -eq '/rem') {
        $out.ok = $true; $out.list = @(Get-Rems)
      } elseif ($path -eq '/rem/add' -or $path -eq '/rem/del' -or $path -eq '/rem/take') {
        $q = $req.QueryString
        $ch = 0; $start = [int64]0
        if (-not [int]::TryParse([string]$q['ch'], [ref]$ch) -or -not [int64]::TryParse([string]$q['start'], [ref]$start)) { throw 'ch / start missing' }
        $l = @(Get-Rems)
        if ($path -eq '/rem/add') {
          $end = [int64]0; [void][int64]::TryParse([string]$q['end'], [ref]$end)
          $mode = if ([string]$q['mode'] -eq 'auto') { 'auto' } else { 'remind' }
          $l = @($l | Where-Object { -not ([int]$_.ch -eq $ch -and [int64]$_.start -eq $start) })
          $l += [pscustomobject][ordered]@{ ch = $ch; chName = (Get-QS $req 'chName'); title = (Get-QS $req 'title'); start = $start; end = $end; mode = $mode }
          Save-Rems $l
        } elseif ($path -eq '/rem/del') {
          $l = @($l | Where-Object { -not ([int]$_.ch -eq $ch -and [int64]$_.start -eq $start) })
          Save-Rems $l
        } else {
          # each step (tvOn / done) happens exactly once, whichever page asks first
          $step = [string]$q['step']; if ($step -notmatch '^(tvOn|done)$') { throw 'bad step' }
          $r = Find-Rem $l $ch $start | Select-Object -First 1
          $out.took = $false
          if ($r -and -not $r.PSObject.Properties[$step]) { $r | Add-Member -NotePropertyName $step -NotePropertyValue ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()); Save-Rems $l; $out.took = $true }
        }
        $out.ok = $true; $out.list = @(Get-Rems)
      } elseif ($path -eq '/pipe/test') {
        $out.ok = $true; $out.pong = $true; $out.version = $Version
      } elseif ($path -eq '/pipe/result') {
        $PipeTest = [ordered]@{ ok = ([string]$req.QueryString['ok'] -eq '1'); where = [string]$req.QueryString['where']; t = (Get-Date).ToString('HH:mm:ss') }
        $out.ok = $true
      } elseif ($path -eq '/ui') {
        $GuideAt = if ([string]$req.QueryString['guide'] -eq '1') { [DateTime]::UtcNow } else { [DateTime]::MinValue }
        $out.ok = $true
      } elseif ($path -eq '/vpn/next') {
        $c = ([string]$req.QueryString['c']).ToUpper()
        if ($Allowed -notcontains $c) { throw "unknown country '$c'" }
        $out.country = Switch-Server $c; $out.server = Get-ServerInfo $c; $out.ok = ($out.country -eq $c)
      } elseif ($path -eq '/tv/on') {
        # reminder in MyTV: switch the TV on via the SmartThings routine
        $st = Start-StScene
        if ($st) { $out.ok = $true; $out.tv = $st; Write-Log "smartthings (reminder): $st" } else { $out.ok = $false; $out.error = 'SmartThings not set up' }
      } elseif ($path -eq '/cmd/since') {
        $after = 0; [void][int]::TryParse([string]$req.QueryString['seq'], [ref]$after)
        if ([string]$req.QueryString['boot'] -ne $Boot) { $after = 0 }
        $now = [DateTime]::UtcNow
        $list = @()
        foreach ($c in $Queue) {
          if ($c.seq -gt $after) { $list += [ordered]@{ seq = $c.seq; do = $c.do; n = $c.n; k = $c.k; age = [math]::Round(($now - $c.t).TotalSeconds, 1) } }
        }
        $out.ok = $true; $out.boot = $Boot; $out.seq = $Seq; $out.cmds = $list
      } else { $res.StatusCode = 404; $out.ok = $false; $out.error = 'not found' }
    }
  } catch { $out.ok = $false; $out.error = "$_"; if ($res.StatusCode -eq 200) { $res.StatusCode = 400 }; Write-Log "error: $_" }
  try {
    if ($lan) { $res.Headers.Add('Cache-Control', 'no-store') }
    else { $res.Headers.Add('Access-Control-Allow-Origin', 'https://mistergeil.github.io') }
    if ($page) { Send-Bytes $res $page 'text/html; charset=utf-8' }
    else { Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $out -Compress -Depth 4))) 'application/json' }
  } catch { Write-Log "send failed: $_" }
}
