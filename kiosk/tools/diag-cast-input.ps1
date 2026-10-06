# ============================================================
#  MyTV diagnosis + fix for "Mitschauen" (choppy stream) and mouse mode (clicks)
#  Run elevated on the notebook, with RTL+ (or any web page) open in the kiosk:
#    powershell -ExecutionPolicy Bypass -File C:\MyTV\tools\diag-cast-input.ps1
#  Writes everything to C:\MyTV\diag\report.txt (+ screenshots). Changes only cast.json (fps/bitrate).
# ============================================================
$ErrorActionPreference = 'Continue'
$Root = 'C:\MyTV'; $Vpn = "$Root\vpn"; $Diag = "$Root\diag"
New-Item -ItemType Directory -Path $Diag -Force | Out-Null
$Rep = "$Diag\report.txt"; Set-Content $Rep "MyTV diag $(Get-Date -Format s)" -Encoding utf8
function R($m) { Add-Content $Rep $m -Encoding utf8; Write-Host $m }
$Key = (Get-Content "$Vpn\remote.key" -Raw).Trim()
function Api($p) { try { Invoke-RestMethod -Uri "http://127.0.0.1:8766$p$(if ($p -match '\?') { '&' } else { '?' })key=$Key" -TimeoutSec 15 } catch { "ERR $($_.Exception.Message)" } }

R '--- 1. state'
try { R ("status: " + (Invoke-RestMethod http://127.0.0.1:8765/status -TimeoutSec 5 | ConvertTo-Json -Compress)) } catch { R "status: NOT ANSWERING ($_)" }
Get-ScheduledTask 'MyTV VPN Switcher', 'MyTV WebRTC' -ErrorAction SilentlyContinue | ForEach-Object { R ("task $($_.TaskName): $($_.State)") }
Get-CimInstance Win32_Process | Where-Object { $_.Name -in 'ffmpeg.exe', 'mediamtx.exe' -or $_.CommandLine -like '*mytv-vpn-agent*' } |
  ForEach-Object { R ("proc $($_.Name) pid=$($_.ProcessId) start=$($_.CreationDate)") }
R ("display: " + ((Get-CimInstance Win32_VideoController | Select-Object -First 1 | ForEach-Object { "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)@$($_.CurrentRefreshRate)Hz $($_.Name) drv $($_.DriverVersion)" })))

R '--- 2. stream fix: fps must divide the 60 Hz desktop (30), a bit more bitrate'
Api '/cast/stop' | Out-Null; Start-Sleep 1
Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe'" | Where-Object { $_.ExecutablePath -like "$Root\tools\*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; R "killed orphan ffmpeg $($_.ProcessId)" }
$cj = "$Vpn\cast.json"; $c = [ordered]@{}
(Get-Content $cj -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $c[$_.Name] = $_.Value }
R ("cast.json before: " + (ConvertTo-Json -InputObject $c -Compress))
$c['fps'] = 30; $c['bitrate'] = '6M'
[IO.File]::WriteAllText($cj, (ConvertTo-Json -InputObject $c -Compress), [Text.Encoding]::ASCII)
R ("cast.json now:    " + (ConvertTo-Json -InputObject $c -Compress))

R '--- 3. stream measurement (20 s, play something moving on the TV now)'
Remove-Item "$Vpn\run\cast\ffmpeg.log" -ErrorAction SilentlyContinue
R ("start: " + ((Api '/cast/start') | ConvertTo-Json -Compress)); Start-Sleep 4
$probe = "$Root\tools\ffmpeg\bin\ffmpeg.exe"
$out = & $probe -hide_banner -rtsp_transport tcp -i "rtsp://tv:$Key@127.0.0.1:8554/tv" -t 15 -f null - 2>&1 | Out-String
$fr = [regex]::Matches($out, 'frame=\s*(\d+)') | Select-Object -Last 1
R ("frames received in 15 s: $($fr.Groups[1].Value)  (30 fps = 450)")
$dup = [regex]::Matches($out, 'dup=(\d+)') | Select-Object -Last 1; $drop = [regex]::Matches($out, 'drop=(\d+)') | Select-Object -Last 1
R ("dup=$($dup.Groups[1].Value) drop=$($drop.Groups[1].Value)")
$cpu = (Get-Counter '\Process(ffmpeg*)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples | ForEach-Object { "$($_.InstanceName)=$([math]::Round($_.CookedValue / $env:NUMBER_OF_PROCESSORS,1))%" }
R ("ffmpeg cpu: $($cpu -join ' ')")
R '- ffmpeg.log (last 15):'; Get-Content "$Vpn\run\cast\ffmpeg.log" -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { R "  $_" }
R '- mediamtx.log (last 15):'; Get-Content "$Root\tools\mediamtx\mediamtx.log" -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { R "  $_" }

R '--- 4. mouse mode: click test with screenshots'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
function Shot($n) { $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
  $g = [Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size); $bmp.Save("$Diag\$n.png"); $g.Dispose(); $bmp.Dispose() }
R ("move   : " + ((Api '/input/move?dx=80&dy=0') | ConvertTo-Json -Compress))
$p1 = [Windows.Forms.Cursor]::Position; Start-Sleep -Milliseconds 300
R ("abs    : " + ((Api '/input/abs?x=0.5&y=0.45') | ConvertTo-Json -Compress)); Start-Sleep -Milliseconds 300
$p2 = [Windows.Forms.Cursor]::Position; R "cursor after move: $p1 -> after abs: $p2 (screen center expected)"
Shot 'before-click'
R ("click  : " + ((Api '/input/click?x=0.5&y=0.45') | ConvertTo-Json -Compress)); Start-Sleep 3
Shot 'after-click'
$h1 = (Get-FileHash "$Diag\before-click.png").Hash; $h2 = (Get-FileHash "$Diag\after-click.png").Hash
R ("screen changed after click: $($h1 -ne $h2)   (screenshots in $Diag)")
R '- agent.log (last 20):'; Get-Content "$Vpn\agent.log" -Tail 20 | ForEach-Object { R "  $_" }
Api '/cast/stop' | Out-Null
R "--- done. Send me $Rep"
