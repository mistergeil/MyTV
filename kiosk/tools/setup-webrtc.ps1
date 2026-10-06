# ============================================================
#  MyTV - set up MediaMTX for "Mitschauen" over WebRTC (≈0.3 s delay instead of seconds)
#  Run once, elevated, on the MyTV notebook:  powershell -ExecutionPolicy Bypass -File setup-webrtc.ps1
#
#  What it does (and nothing else):
#   1. downloads the latest MediaMTX release for Windows from GitHub (bluenviron/mediamtx), verifies its SHA-256
#   2. installs it to C:\MyTV\tools\mediamtx and writes mediamtx.yml:
#        RTSP only on 127.0.0.1:8554 (FFmpeg publishes there, only from this notebook)
#        WebRTC on :8889 (HTTP/WHEP) + UDP 8189, reading needs user "tv" + the remote key
#        everything else (RTMP, HLS, SRT, API, metrics) off
#   3. registers the scheduled task "MyTV WebRTC" (at logon, hidden, restarts on failure) and starts it
#   4. sets "transport":"webrtc" in C:\MyTV\vpn\cast.json (keeps all other settings)
#   5. self-test
#  It does NOT touch the firewall - add the rule by hand (see the end of the output).
#  Undo: Unregister-ScheduledTask "MyTV WebRTC"; remove C:\MyTV\tools\mediamtx; set "transport":"hls" in cast.json.
# ============================================================
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = 'C:\MyTV'; $Vpn = Join-Path $Root 'vpn'; $Dst = Join-Path $Root 'tools\mediamtx'; $Task = 'MyTV WebRTC'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Please run elevated (as administrator).' }
$keyFile = Join-Path $Vpn 'remote.key'
if (-not (Test-Path $keyFile)) { throw "remote.key not found in $Vpn" }
$Key = (Get-Content $keyFile -Raw).Trim()

# ---- 1. download + verify
Say 'Looking up the latest MediaMTX release ...'
$rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/bluenviron/mediamtx/releases/latest' -Headers @{ 'User-Agent' = 'MyTV-setup' }
$asset = $rel.assets | Where-Object { $_.name -match '_windows_amd64\.zip$' } | Select-Object -First 1
$sums  = $rel.assets | Where-Object { $_.name -match 'checksums' } | Select-Object -First 1
if (-not $asset) { throw 'No Windows build in the latest release.' }
$tmp = Join-Path $env:TEMP ('mytv-mediamtx-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tmp | Out-Null
$zip = Join-Path $tmp $asset.name
Say "Downloading $($asset.name) ($($rel.tag_name)) ..."
Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($sums) {
  $sumTxt = (Invoke-WebRequest -UseBasicParsing -Uri $sums.browser_download_url).Content
  if ($sumTxt -is [byte[]]) { $sumTxt = [Text.Encoding]::UTF8.GetString($sumTxt) }
  $line = ($sumTxt -split "`n") | Where-Object { $_ -match [regex]::Escape($asset.name) } | Select-Object -First 1
  if (-not $line -or $line.Split(' ')[0].Trim().ToLower() -ne $hash) { throw "SHA-256 mismatch for $($asset.name) - aborted, nothing installed." }
  Say "SHA-256 verified: $hash" Green
} else { Say "No checksum file in the release - SHA-256 is $hash (compare on GitHub before continuing)." Yellow; Read-Host 'Enter = continue, Ctrl+C = abort' | Out-Null }

# ---- 2. install + config
Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
Get-Process mediamtx -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $Dst -Force | Out-Null
Expand-Archive -Path $zip -DestinationPath $Dst -Force
Get-ChildItem $Dst -Recurse | Unblock-File
$exe = Join-Path $Dst 'mediamtx.exe'
if (-not (Test-Path $exe)) { throw 'mediamtx.exe missing after unzip.' }
$yml = @"
# MyTV - written by setup-webrtc.ps1
logLevel: warn
logDestinations: [file]
logFile: mediamtx.log
api: no
metrics: no
pprof: no
playback: no
rtsp: yes
rtspAddress: 127.0.0.1:8554
rtspTransports: [tcp]
rtmp: no
hls: no
srt: no
moq: no
webrtc: yes
webrtcAddress: :8889
webrtcEncryption: no
webrtcAllowOrigins: ['*']
webrtcLocalUDPAddress: :8189
webrtcIPsFromInterfaces: yes
authMethod: internal
authInternalUsers:
  - user: any
    ips: ['127.0.0.1', '::1']
    permissions:
      - action: publish
  - user: tv
    pass: '$Key'
    permissions:
      - action: read
paths:
  tv:
    source: publisher
"@
$cfg = Join-Path $Dst 'mediamtx.yml'
Copy-Item $cfg (Join-Path $Dst 'mediamtx.default.yml') -Force -ErrorAction SilentlyContinue
[IO.File]::WriteAllText($cfg, $yml, (New-Object Text.UTF8Encoding $false))
Say "Installed to $Dst" Green

# ---- 3. task (same account/run level as the MyTV switcher, hidden, auto-restart)
$con = Join-Path $env:WINDIR 'System32\conhost.exe'
$action = New-ScheduledTaskAction -Execute $con -Argument "--headless `"$exe`" `"$cfg`"" -WorkingDirectory $Dst
$trig = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$prin = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Unregister-ScheduledTask -TaskName $Task -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $Task -Description 'MyTV: MediaMTX for Mitschauen over WebRTC (iPad). Undo: see C:\MyTV\tools\mediamtx\mediamtx.yml header / setup-webrtc.ps1.' -Action $action -Trigger $trig -Principal $prin -Settings $set | Out-Null
Start-ScheduledTask -TaskName $Task
Say "Task '$Task' registered and started." Green

# ---- 4. cast.json → transport webrtc (keep the rest)
$cj = Join-Path $Vpn 'cast.json'
$c = [ordered]@{}
if (Test-Path $cj) { (Get-Content $cj -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $c[$_.Name] = $_.Value } }
$c['transport'] = 'webrtc'
[IO.File]::WriteAllText($cj, (ConvertTo-Json -InputObject $c -Compress), [Text.Encoding]::ASCII)
Say "cast.json: transport = webrtc" Green

# ---- 5. self-test
Start-Sleep -Seconds 3
$ok = $false
try { $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:8889/tv/' -TimeoutSec 5; $ok = $true } catch { if ($_.Exception.Response) { $ok = $true } }
if ($ok) { Say 'MediaMTX answers on :8889.' Green } else { Say "MediaMTX does not answer - see $Dst\mediamtx.log" Red }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Say ''
Say 'LAST STEP BY HAND - firewall (only your home network):' Yellow
Say '  Windows Defender Firewall -> Advanced settings -> Inbound Rules -> New Rule:'
Say '   1) Port, TCP 8889, Allow, profile Private only, Scope: remote IP = Local subnet, name "MyTV WebRTC TCP"'
Say '   2) Port, UDP 8189, Allow, profile Private only, Scope: remote IP = Local subnet, name "MyTV WebRTC UDP"'
Say '  If Windows showed an "Allow access" prompt for mediamtx.exe, delete that broad rule again:'
Say '   Inbound Rules -> "MediaMTX" (program mediamtx.exe) -> Delete. Only the two port rules above are needed.'
Say 'Then on the iPad: reload the Mitschauen page.'
