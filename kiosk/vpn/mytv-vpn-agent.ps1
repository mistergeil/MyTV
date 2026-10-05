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
#    GET /photos/albums | /photos/list?a= | /photos/img?a=&f=   -> Galerie (pictures in C:\MyTV\photos\<album>)
#    POST /photos/upload?key=KEY&a=&name=  (LAN) -> upload from the remote; GET /photos/create?key=KEY&a= -> new album
#    GET /cmd?key=KEY&do=album&k=<album>  -> start the Galerie (NFC sticker), empty k = back to TV
#    GET /watch?key=KEY (LAN) -> watch the TV picture on the iPad (mirroring via FFmpeg -> HLS)
#    GET /cast/start|stop|status?key=KEY, /cast/index.m3u8?key=KEY, /cast/segNNNNN.ts?key=KEY
#    GET /input/move?dx=&dy= | /input/abs?x=&y= (0..1) | /input/click?[x=&y=][&b=right] | /input/scroll?d= |
#        /input/text?t= | /input/key?k=Enter|Backspace|Escape|Tab|Up|Down|Left|Right   (LAN, key) -> mouse mode
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
$ScriptsFile = Join-Path $Dir 'scripts.json'
$Scripts = [ordered]@{}                            # Tampermonkey versions reported by MyTV (bridge) and the overlay (helper)
try { if (Test-Path $ScriptsFile) { (Get-Content $ScriptsFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $Scripts[$_.Name] = $_.Value } } } catch {}
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
# Windows PowerShell 5.1: ConvertFrom-Json hands back a JSON array as ONE object (not item by item), so it has to be
# flattened explicitly - otherwise the list gets nested ([[...]]) and the reminders vanish in MyTV
function Expand-Items($x) { foreach ($i in $x) { if ($i -is [System.Array]) { Expand-Items $i } elseif ($null -ne $i) { $i } } }
function Get-Rems {
  if (-not (Test-Path $RemFile)) { return @() }
  try { $raw = Get-Content $RemFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return @() }
  $cut = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 15 * 60000
  return @(Expand-Items $raw | Where-Object { $_.PSObject.Properties['ch'] -and $_.PSObject.Properties['start'] -and [int64]$_.end -gt $cut })
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
# ---- Galerie: albums are folders in C:\MyTV\photos, settings per album in album.json ----
$PhotoRoot = Join-Path (Split-Path -Parent $Dir) 'photos'
$ImgRe = '\.(jpe?g|png|webp|gif)$'
function Get-AlbumDir($a) {
  if ([string]$a -notmatch '^[A-Za-z0-9_-]{1,32}$') { throw 'Albumname: nur Buchstaben, Ziffern, - und _' }
  return (Join-Path $PhotoRoot $a)
}
function Get-AlbumSettings($dir) {
  $st = [ordered]@{ title = (Split-Path -Leaf $dir); type = 'photos'; style = 'print'; seconds = 20; order = 'shuffle' }
  $f = Join-Path $dir 'album.json'
  if (Test-Path $f) { try { (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $st[$_.Name] = $_.Value } } catch {} }
  return $st
}
function Get-Albums {
  $def = Join-Path $PhotoRoot 'Allgemein'
  if (-not (Test-Path $def)) { New-Item -ItemType Directory -Path $def -Force | Out-Null }
  return @(Get-ChildItem -Path $PhotoRoot -Directory | Where-Object { $_.Name -match '^[A-Za-z0-9_-]{1,32}$' } | Sort-Object Name | ForEach-Object {
    [ordered]@{ name = $_.Name; count = @(Get-ChildItem -Path $_.FullName -File | Where-Object { $_.Name -match $ImgRe }).Count; settings = (Get-AlbumSettings $_.FullName) }
  })
}
# upload: downscale to max 2560 px, apply the iPhone rotation (EXIF), save as JPEG
Add-Type -AssemblyName System.Drawing
function Save-Photo([byte[]]$bytes, $dir, $name) {
  $ms = New-Object IO.MemoryStream(, $bytes)
  try { $img = [Drawing.Image]::FromStream($ms) } catch { throw 'Kein lesbares Bild (HEIC? iPhone: Einstellungen → Kamera → Formate → Maximale Kompatibilität)' }
  try {
    if ($img.PropertyIdList -contains 0x0112) {
      switch ([int]$img.GetPropertyItem(0x0112).Value[0]) {
        3 { $img.RotateFlip([Drawing.RotateFlipType]::Rotate180FlipNone) }
        6 { $img.RotateFlip([Drawing.RotateFlipType]::Rotate90FlipNone) }
        8 { $img.RotateFlip([Drawing.RotateFlipType]::Rotate270FlipNone) }
        2 { $img.RotateFlip([Drawing.RotateFlipType]::RotateNoneFlipX) }
        4 { $img.RotateFlip([Drawing.RotateFlipType]::RotateNoneFlipY) }
        5 { $img.RotateFlip([Drawing.RotateFlipType]::Rotate90FlipX) }
        7 { $img.RotateFlip([Drawing.RotateFlipType]::Rotate270FlipX) }
      }
    }
    $sc = [Math]::Min(1.0, 2560.0 / [Math]::Max($img.Width, $img.Height))
    $w = [int][Math]::Round($img.Width * $sc); $h = [int][Math]::Round($img.Height * $sc)
    $bmp = New-Object Drawing.Bitmap($w, $h)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($img, 0, 0, $w, $h); $g.Dispose()
    $enc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $ep = New-Object Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [long]86)
    $base = ([IO.Path]::GetFileNameWithoutExtension([string]$name) -replace '[^A-Za-z0-9_-]', '')
    if (-not $base) { $base = 'foto' }
    $file = (Get-Date -Format 'yyyyMMdd-HHmmss') + '_' + $base.Substring(0, [Math]::Min(40, $base.Length)) + '.jpg'
    $stem = [IO.Path]::GetFileNameWithoutExtension($file); $k = 2
    while (Test-Path -LiteralPath (Join-Path $dir $file)) { $file = "${stem}_$k.jpg"; $k++ }
    $bmp.Save((Join-Path $dir $file), $enc, $ep); $bmp.Dispose()
    return $file
  } finally { $img.Dispose(); $ms.Dispose() }
}
# ---- Mitschauen: the notebook records its screen + sound with FFmpeg as HLS, Safari on the iPad plays it ----
# settings in vpn\cast.json (written once on the notebook, e.g. by Claude Code):
#   { "ffmpeg": "C:\\...\\ffmpeg.exe", "encoder": "h264_qsv|h264_nvenc|h264_amf|libx264", "fps": 30,
#     "width": 1920, "height": 1080, "bitrate": "6M", "audio": "<dshow audio device name or empty>" }
$CastDir = Join-Path $RunDir 'cast'
$CastProc = $null; $CastHit = [DateTime]::MinValue
function Get-CastCfg {
  $c = [ordered]@{ ffmpeg = ''; encoder = 'libx264'; fps = 30; width = 1280; height = 720; bitrate = '4M'; audio = ''; capture = 'gdigrab' }
  $f = Join-Path $Dir 'cast.json'
  if (Test-Path $f) { try { (Get-Content $f -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $c[$_.Name] = $_.Value } } catch {} }
  if (-not $c.ffmpeg) {
    foreach ($cand in @((Join-Path (Split-Path -Parent $Dir) 'tools\ffmpeg\bin\ffmpeg.exe'), 'ffmpeg.exe')) {
      $cmd = Get-Command $cand -ErrorAction SilentlyContinue
      if ($cmd) { $c.ffmpeg = $cmd.Source; break }
    }
  }
  return $c
}
function Test-Cast { return ($script:CastProc -and -not $script:CastProc.HasExited) }
function Start-Cast {
  $script:CastHit = [DateTime]::UtcNow
  if (Test-Cast) { return }
  $c = Get-CastCfg
  if (-not $c.ffmpeg -or -not (Test-Path $c.ffmpeg)) { throw 'FFmpeg fehlt auf dem Notebook (cast.json / C:\MyTV\tools\ffmpeg)' }
  if (Test-Path $CastDir) { Remove-Item -Path (Join-Path $CastDir '*') -Force -ErrorAction SilentlyContinue } else { New-Item -ItemType Directory -Path $CastDir -Force | Out-Null }
  $fps = [int]$c.fps
  $enc = [string]$c.encoder
  $vfmt = if ($enc -eq 'libx264') { 'yuv420p' } else { 'nv12' }
  $encOpts = switch ($enc) {
    'libx264'    { '-preset veryfast -tune zerolatency' }
    'h264_qsv'   { '-preset faster -look_ahead 0' }
    'h264_nvenc' { '-preset p4 -tune ll' }
    'h264_amf'   { '-usage lowlatency -quality speed' }
    default      { '' }
  }
  $audioIn = if ($c.audio) { "-thread_queue_size 512 -f dshow -audio_buffer_size 50 -i audio=`"$($c.audio)`"" } else { '' }
  $audioOut = if ($c.audio) { '-c:a aac -b:a 160k -ar 48000' } else { '-an' }
  # capture: ddagrab (Desktop Duplication, much faster on a 4K desktop) or gdigrab (works everywhere, slow)
  if ([string]$c.capture -eq 'ddagrab') {
    $vin = "-thread_queue_size 512 -f lavfi -i ddagrab=output_idx=0:framerate=${fps}:draw_mouse=0"
    $vf  = "hwdownload,format=bgra,scale=$($c.width):$($c.height):flags=fast_bilinear,format=$vfmt"
  } else {
    $vin = "-thread_queue_size 512 -f gdigrab -framerate $fps -draw_mouse 0 -i desktop"
    $vf  = "scale=$($c.width):$($c.height):flags=bicubic,format=$vfmt"
  }
  $scOpt = if ($enc -eq 'libx264') { '-sc_threshold 0' } else { '' }
  $ffArgs = "-hide_banner -loglevel warning $vin $audioIn " +
          "-vf $vf -c:v $enc $encOpts -b:v $($c.bitrate) -maxrate $($c.bitrate) -bufsize $($c.bitrate) " +
          "-g $fps -keyint_min $fps $scOpt $audioOut " +
          "-f hls -hls_time 1 -hls_list_size 4 -hls_flags delete_segments+omit_endlist+independent_segments " +
          "-hls_segment_filename `"$(Join-Path $CastDir 'seg%05d.ts')`" `"$(Join-Path $CastDir 'index.m3u8')`""
  # FFmpeg's messages go to a file (no event handlers: those would run outside PowerShell's thread and crash the switcher)
  $script:CastProc = Start-Process -FilePath $c.ffmpeg -ArgumentList $ffArgs -WindowStyle Hidden -PassThru `
                       -RedirectStandardError (Join-Path $CastDir 'ffmpeg.log') -RedirectStandardOutput (Join-Path $CastDir 'ffmpeg.out')
  Write-Log "cast started: $($c.capture) $enc $($c.width)x$($c.height)@$fps $($c.bitrate) audio='$($c.audio)'"
}
function Stop-Cast($why) {
  if (Test-Cast) { try { $script:CastProc.Kill() } catch {}; Write-Log "cast stopped ($why)" }
  $script:CastProc = $null
}
function Get-CastLogTail { $f = Join-Path $CastDir 'ffmpeg.log'; if (Test-Path $f) { return ((Get-Content $f -Tail 6) -join ' | ') } return '' }
# ---- mouse mode: the remote / iPad moves the real pointer and types into web pages (RTL+, Joyn, …) ----
# (wrapped: if compiling ever fails, only mouse mode is missing - the switcher itself keeps running)
$InputOk = $false
try {
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class MyTVInput {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, int data, UIntPtr extra);
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION u; }
  static void Key(ushort vk, ushort scan, uint flags) {
    INPUT[] a = new INPUT[1]; a[0].type = 1; a[0].u.ki.wVk = vk; a[0].u.ki.wScan = scan; a[0].u.ki.dwFlags = flags;
    SendInput(1, a, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void Text(string s) { foreach (char c in s) { Key(0, c, 4); Key(0, c, 6); } }      // KEYEVENTF_UNICODE (+KEYUP)
  public static void VK(ushort vk) { Key(vk, 0, 0); Key(vk, 0, 2); }
  public static void Move(int dx, int dy) { POINT p; GetCursorPos(out p); SetCursorPos(p.X + dx, p.Y + dy); }
  public static void Abs(double x, double y) { SetCursorPos((int)Math.Round(x * (GetSystemMetrics(0) - 1)), (int)Math.Round(y * (GetSystemMetrics(1) - 1))); }
  public static void Click(bool right) { uint d = right ? 8u : 2u, u = right ? 16u : 4u; mouse_event(d, 0, 0, 0, UIntPtr.Zero); mouse_event(u, 0, 0, 0, UIntPtr.Zero); }
  public static void Wheel(int delta) { mouse_event(0x0800, 0, 0, delta, UIntPtr.Zero); }
}
"@
[void][MyTVInput]::SetProcessDPIAware()          # real screen pixels, also with Windows display scaling
$InputOk = $true
} catch { Write-Log "mouse mode unavailable: $_" }
$InputKeys = @{ Enter = 0x0D; Backspace = 0x08; Escape = 0x1B; Tab = 0x09; Up = 0x26; Down = 0x28; Left = 0x25; Right = 0x27; Space = 0x20 }
function Get-Num($req, $n, $min, $max) {
  $v = 0.0
  if (-not [double]::TryParse([string]$req.QueryString[$n], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { throw "$n missing" }
  return [Math]::Max($min, [Math]::Min($max, $v))
}
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
function Get-BackupNames { $b = Join-Path (Split-Path -Parent $Dir) 'backup'; if (Test-Path $b) { @(Get-ChildItem $b -Directory | Sort-Object LastWriteTime -Descending | ForEach-Object { $_.Name }) } else { @() } }
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
# another switcher already answering on 8765? (watchdog start while one runs outside the task's view) → leave quietly
function Test-OtherAgent {
  try { $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/status" -TimeoutSec 2; return ($r -and $r.ok) } catch { return $false }
}
function Start-Listener {
  if (Test-OtherAgent) { exit 0 }
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $x = New-Object System.Net.HttpListener
      $x.Prefixes.Add("http://127.0.0.1:$Port/")
      if ($Key) { $x.Prefixes.Add("http://+:$LanPort/") }
      $x.Start()
      return $x
    } catch {
      if (Test-OtherAgent) { Write-Log 'another switcher is already running - this one exits'; exit 0 }
      Write-Log "listener start failed (try $($i + 1)): $_"; Start-Sleep -Seconds 2
    }
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
    $page = $null; $rawJson = $null; $bin = $null; $binType = ''
    $lan = $req.LocalEndPoint.Port -eq $LanPort
    # nobody watching for a minute → stop recording (saves the notebook's power)
    if ($CastProc -and ([DateTime]::UtcNow - $CastHit).TotalSeconds -gt 60) { Stop-Cast 'no viewer' }
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
      } elseif ($path -eq '/watch') {
        $page = [IO.File]::ReadAllBytes((Join-Path $Dir 'watch.html'))
      } elseif ($path -like '/input/*') {
        if (-not $InputOk) { throw 'Mausmodus auf dem Notebook nicht verfügbar (siehe agent.log)' }
        switch ($path) {
          '/input/move'   { [MyTVInput]::Move([int](Get-Num $req 'dx' -400 400), [int](Get-Num $req 'dy' -400 400)) }
          '/input/abs'    { [MyTVInput]::Abs((Get-Num $req 'x' 0 1), (Get-Num $req 'y' 0 1)) }
          '/input/click'  {
            if ($req.QueryString['x']) { [MyTVInput]::Abs((Get-Num $req 'x' 0 1), (Get-Num $req 'y' 0 1)); Start-Sleep -Milliseconds 30 }
            [MyTVInput]::Click(([string]$req.QueryString['b'] -eq 'right'))
          }
          '/input/scroll' {
            if ($req.QueryString['x']) { [MyTVInput]::Abs((Get-Num $req 'x' 0 1), (Get-Num $req 'y' 0 1)) }
            [MyTVInput]::Wheel([int](Get-Num $req 'd' -2400 2400))
          }
          '/input/text'   { $t = Get-QS $req 't'; if ($t.Length -gt 200) { throw 'text too long' }; [MyTVInput]::Text($t) }
          '/input/key'    { $vk = $InputKeys[[string]$req.QueryString['k']]; if (-not $vk) { throw 'unknown key' }; [MyTVInput]::VK([uint16]$vk) }
          default { throw 'unknown input' }
        }
        $out.ok = $true
      } elseif ($path -eq '/cast/start') {
        Start-Cast; $out.ok = $true; $out.running = (Test-Cast); $out.ready = (Test-Path (Join-Path $CastDir 'index.m3u8'))
      } elseif ($path -eq '/cast/status') {
        $CastHit = [DateTime]::UtcNow
        $out.ok = $true; $out.running = (Test-Cast); $out.ready = (Test-Path (Join-Path $CastDir 'index.m3u8'))
        if (-not $out.running) { $out.log = Get-CastLogTail }
      } elseif ($path -eq '/cast/stop') {
        Stop-Cast 'remote'; $out.ok = $true
      } elseif ($path -eq '/cast/index.m3u8') {
        $CastHit = [DateTime]::UtcNow
        $f = Join-Path $CastDir 'index.m3u8'
        if (-not (Test-Path $f)) { $res.StatusCode = 404; throw 'not ready' }
        # segments need the key too → append it to every segment line
        $txt = ((Get-Content $f) | ForEach-Object { if ($_ -and -not $_.StartsWith('#')) { $_ + '?key=' + $Key } else { $_ } }) -join "`n"
        $bin = [Text.Encoding]::UTF8.GetBytes($txt + "`n"); $binType = 'application/vnd.apple.mpegurl'
      } elseif ($path -match '^/cast/(seg\d{5}\.ts)$') {
        $CastHit = [DateTime]::UtcNow
        $f = Join-Path $CastDir $Matches[1]
        if (-not (Test-Path $f)) { $res.StatusCode = 404; throw 'segment gone' }
        $bin = [IO.File]::ReadAllBytes($f); $binType = 'video/mp2t'
      } elseif ($path -eq '/ping') {
        $out.ok = $true; $out.vpn = Get-Active; $out.version = $Version
        if ($out.vpn -ne 'OFF') { $out.server = Get-ServerInfo $out.vpn }
        $out.guide = (([DateTime]::UtcNow - $GuideAt).TotalSeconds -lt 12)
      } elseif ($path -eq '/vpn/next') {
        $c = ([string]$req.QueryString['c']).ToUpper(); if (-not $c) { $c = Get-Active }
        if ($Allowed -notcontains $c) { throw 'VPN ist aus - erst einen Sender mit VPN wählen' }
        $out.country = Switch-Server $c; $out.server = Get-ServerInfo $c; $out.ok = ($out.country -eq $c)
        if ($out.ok) { Add-Cmd 'reload' '' '' }          # the channel on the TV reloads with the new server
      } elseif ($path -eq '/photos/albums') {
        $out.ok = $true; $out.albums = @(Get-Albums)
      } elseif ($path -eq '/photos/create') {
        $d = Get-AlbumDir ([string]$req.QueryString['a'])
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null; Write-Log "album created: $d" }
        $out.ok = $true; $out.albums = @(Get-Albums)
      } elseif ($path -eq '/photos/upload') {
        if ($req.HttpMethod -ne 'POST') { throw 'POST needed' }
        $d = Get-AlbumDir ([string]$req.QueryString['a'])
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        if ($req.ContentLength64 -gt 60MB) { throw 'Bild zu gross (max 60 MB)' }
        $buf = New-Object IO.MemoryStream; $req.InputStream.CopyTo($buf)
        $out.file = Save-Photo $buf.ToArray() $d (Get-QS $req 'name'); $buf.Dispose()
        Write-Log "photo uploaded: $($out.file) -> $(Split-Path -Leaf $d)"
        $out.ok = $true
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
        $out.state = Get-UpdateState; $out.backups = @(Get-BackupNames); $out.pipe = $PipeTest; $out.scripts = $Scripts
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
        elseif ($do -eq 'album') { if ($k -and $k -notmatch '^[A-Za-z0-9_-]{1,32}$') { throw 'album name: letters, digits, - and _ only' } }
        elseif ($do -ne 'on') { throw "unknown command '$do'" }
        if ($do -eq 'on' -or $do -eq 'album') {
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
        $rl = @(Get-Rems)
        if ($path -eq '/rem/add') {
          $end = [int64]0; [void][int64]::TryParse([string]$q['end'], [ref]$end)
          $mode = if ([string]$q['mode'] -eq 'auto') { 'auto' } else { 'remind' }
          $rl = @($rl | Where-Object { -not ([int]$_.ch -eq $ch -and [int64]$_.start -eq $start) })
          $rl += [pscustomobject][ordered]@{ ch = $ch; chName = (Get-QS $req 'chName'); title = (Get-QS $req 'title'); start = $start; end = $end; mode = $mode }
          Save-Rems $rl
        } elseif ($path -eq '/rem/del') {
          $rl = @($rl | Where-Object { -not ([int]$_.ch -eq $ch -and [int64]$_.start -eq $start) })
          Save-Rems $rl
        } else {
          # each step (tvOn / done) happens exactly once, whichever page asks first
          $step = [string]$q['step']; if ($step -notmatch '^(tvOn|done)$') { throw 'bad step' }
          $r = Find-Rem $rl $ch $start | Select-Object -First 1
          $out.took = $false
          if ($r -and -not $r.PSObject.Properties[$step]) { $r | Add-Member -NotePropertyName $step -NotePropertyValue ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()); Save-Rems $rl; $out.took = $true }
        }
        $out.ok = $true; $out.list = @(Get-Rems)
      } elseif ($path -eq '/photos/albums') {
        $out.ok = $true; $out.albums = @(Get-Albums)
      } elseif ($path -eq '/photos/list') {
        $d = Get-AlbumDir ([string]$req.QueryString['a'])
        if (-not (Test-Path $d)) { throw "Album '$([string]$req.QueryString['a'])' gibt es nicht" }
        $out.ok = $true; $out.settings = Get-AlbumSettings $d
        $out.files = @(Get-ChildItem -Path $d -File | Where-Object { $_.Name -match $ImgRe } | Sort-Object Name | ForEach-Object { $_.Name })
      } elseif ($path -eq '/photos/img') {
        $d = Get-AlbumDir ([string]$req.QueryString['a']); $f = [string]$req.QueryString['f']
        if ($f -notmatch '^[^\\/:*?"<>|]{1,120}$' -or $f -notmatch $ImgRe) { throw 'bad file' }
        $fp = Join-Path $d $f
        if (-not (Test-Path -LiteralPath $fp)) { throw 'not found' }
        $ext = [IO.Path]::GetExtension($f).ToLower()
        $out.mime = if ($ext -eq '.png') { 'image/png' } elseif ($ext -eq '.webp') { 'image/webp' } elseif ($ext -eq '.gif') { 'image/gif' } else { 'image/jpeg' }
        # built by hand: ConvertTo-Json on a multi-MB base64 string takes seconds in PS 5.1 and blocks everything else
        $rawJson = '{"ok":true,"mime":"' + $out.mime + '","data":"' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($fp)) + '"}'
      } elseif ($path -eq '/ver/set') {
        foreach ($n in @('bridge', 'helper')) {
          $v = [string]$req.QueryString[$n]
          if ($v -match '^[0-9.]{1,12}$') { $Scripts[$n] = [ordered]@{ v = $v; t = (Get-Date).ToString('s') } }
        }
        try { ConvertTo-Json -InputObject $Scripts -Compress -Depth 4 | Set-Content -Path $ScriptsFile -Encoding ascii } catch {}
        $out.ok = $true
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
    elseif ($rawJson) { Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes($rawJson)) 'application/json' }
    elseif ($bin) { Send-Bytes $res $bin $binType }
    else { Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $out -Compress -Depth 4))) 'application/json' }
  } catch { Write-Log "send failed: $_" }
}
