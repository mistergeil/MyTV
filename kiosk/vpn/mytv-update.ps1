# ============================================================
#  MyTV updater - started by the switcher (scheduled task "MyTV Updater")
#  only after the user tapped "Installieren" / "Wiederherstellen" on the iPhone remote.
#
#  install : download MyTV-Windows.zip from GitHub Pages, check its SHA-256 against
#            version.json, back up the current files, replace them, restart the switcher.
#            If the new switcher does not answer within 60 s -> automatic rollback.
#  rollback: put the newest backup back (same checks).
#  Settings (*.conf, remote.key, tv-*.txt, st-*.txt, photos) are never touched:
#  only files that are part of the zip are replaced.
# ============================================================
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Dir      = Split-Path -Parent $MyInvocation.MyCommand.Path      # C:\MyTV\vpn
$Root     = Split-Path -Parent $Dir                               # C:\MyTV
$RunDir   = Join-Path $Dir 'run'
$UpdDir   = Join-Path $RunDir 'update'
$BackDir  = Join-Path $Root 'backup'
$State    = Join-Path $RunDir 'update-state.json'
$Request  = Join-Path $RunDir 'update-request.json'
$Log      = Join-Path $Dir 'update.log'
$Agent    = 'MyTV VPN Switcher'
$Base     = 'https://mistergeil.github.io/MyTV/kiosk/'
# never overwritten / restored, even if a zip should ever contain them
$Protect  = '\.conf$|remote\.key$|favorites\.txt$|reminders\.json$|scripts\.json$|tv-[a-z]+\.txt$|st-[a-z]+\.txt$|Remote-Links\.txt$|\.log$|\\run\\|\\photos\\|\\backup\\'

function Write-Log($m) { "$(Get-Date -Format s)  $m" | Out-File -FilePath $Log -Append -Encoding utf8 }
# NB: parameter must not be called $state - PowerShell names are case-insensitive, it would hide $State (the file path)
function Set-State($st, $msg, $extra) {
  $o = [ordered]@{ state = $st; msg = $msg; t = (Get-Date).ToString('s') }
  if ($extra) { foreach ($k in $extra.Keys) { $o[$k] = $extra[$k] } }
  ConvertTo-Json $o -Compress | Set-Content -Path $State -Encoding utf8
  Write-Log "$st - $msg"
}
function Get-Installed { $f = Join-Path $Dir 'VERSION'; if (Test-Path $f) { (Get-Content $f -Raw).Trim() } else { '0' } }
function Stop-Agent {
  Stop-ScheduledTask -TaskName $Agent -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*mytv-vpn-agent.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 2
}
function Start-AgentAndWait($want) {
  Start-ScheduledTask -TaskName $Agent
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    try {
      $s = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/status' -TimeoutSec 3
      if ($s.ok -and (-not $want -or $s.version -eq $want)) { return $true }
    } catch {}
  }
  return $false
}
# copy every file below $from into $Root (same relative path), except protected ones
function Copy-Tree($from) {
  $n = 0
  Get-ChildItem -Path $from -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($from.Length).TrimStart('\')
    if (('\' + $rel) -match $Protect) { return }
    $dst = Join-Path $Root $rel
    $dd = Split-Path -Parent $dst
    if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
    Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    Unblock-File -LiteralPath $dst -ErrorAction SilentlyContinue
    $n++
  }
  return $n
}
# newest backup first (by date, whatever the folder is called)
function Get-Backups { if (Test-Path $BackDir) { @(Get-ChildItem -Path $BackDir -Directory | Sort-Object LastWriteTime -Descending) } else { @() } }

$req = @{ action = 'install' }
try { if (Test-Path $Request) { $req = Get-Content $Request -Raw | ConvertFrom-Json; Remove-Item $Request -Force } } catch {}
$from = Get-Installed
New-Item -ItemType Directory -Path $UpdDir, $BackDir -Force | Out-Null

try {
  if ($req.action -eq 'rollback') {
    # ---------------- rollback ----------------
    $b = Get-Backups | Select-Object -First 1
    if (-not $b) { Set-State 'failed' 'Keine Sicherung vorhanden'; exit 1 }
    Set-State 'running' "Stelle $($b.Name) wieder her ..." @{ from = $from }
    Stop-Agent
    [void](Copy-Tree $b.FullName)
    $ver = Get-Installed
    if (Start-AgentAndWait $null) {
      Remove-Item -LiteralPath $b.FullName -Recurse -Force     # used up: the next rollback goes one further back
      Set-State 'ok' "Version $ver wiederhergestellt" @{ from = $from; to = $ver }
    } else { Set-State 'failed' "Wiederhergestellt, aber der Umschalter antwortet nicht - Notebook neu starten" @{ from = $from; to = $ver } }
    exit 0
  }

  # ---------------- install ----------------
  Set-State 'running' 'Suche Update ...' @{ from = $from }
  $v = Invoke-RestMethod -Uri ($Base + 'version.json?t=' + [DateTime]::UtcNow.Ticks) -TimeoutSec 20
  if (-not $v.version -or -not $v.sha256) { throw 'version.json unvollständig' }
  if ($v.version -eq $from) { Set-State 'ok' "Schon aktuell ($from)" @{ from = $from; to = $from }; exit 0 }

  Set-State 'running' "Lade $($v.version) herunter ..." @{ from = $from; to = $v.version }
  $zip = Join-Path $UpdDir 'MyTV-Windows.zip'
  Invoke-WebRequest -UseBasicParsing -Uri ($Base + $v.zip + '?v=' + $v.sha256.Substring(0, 12)) -OutFile $zip -TimeoutSec 120
  $hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
  if ($hash -ne $v.sha256.ToLower()) { throw "Prüfsumme stimmt nicht ($($hash.Substring(0,12)) statt $($v.sha256.Substring(0,12))) - nichts geändert" }

  $x = Join-Path $UpdDir 'x'
  if (Test-Path $x) { Remove-Item $x -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $x -Force
  if (-not (Test-Path (Join-Path $x 'vpn\mytv-vpn-agent.ps1'))) { throw 'Zip ohne vpn\mytv-vpn-agent.ps1 - nichts geändert' }
  $newVer = (Get-Content (Join-Path $x 'vpn\VERSION') -Raw).Trim()

  # backup: exactly the files the update will replace
  Set-State 'running' 'Sichere aktuelle Version ...' @{ from = $from; to = $newVer }
  $bk = Join-Path $BackDir ((Get-Date -Format 'yyyyMMdd-HHmmss') + '_' + $from)
  Get-ChildItem -Path $x -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($x.Length).TrimStart('\')
    $cur = Join-Path $Root $rel
    if ((Test-Path $cur) -and -not (('\' + $rel) -match $Protect)) {
      $dst = Join-Path $bk $rel; New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
      Copy-Item -LiteralPath $cur -Destination $dst -Force
    }
  }
  $bv = Join-Path $bk 'vpn\VERSION'
  if (-not (Test-Path $bv)) { New-Item -ItemType Directory -Path (Split-Path -Parent $bv) -Force | Out-Null; Set-Content -Path $bv -Value $from -Encoding ascii -NoNewline }
  Get-Backups | Select-Object -Skip 3 | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }   # keep the last 3

  Set-State 'running' "Installiere $newVer ..." @{ from = $from; to = $newVer }
  Stop-Agent
  $n = Copy-Tree $x
  Write-Log "copied $n files"
  if (Start-AgentAndWait $newVer) {
    $note = if ($v.installer) { ' - bitte einmal VPN-Install.bat am Notebook ausführen' } else { '' }
    Set-State 'ok' "Aktualisiert auf $newVer$note" @{ from = $from; to = $newVer }
    try { $p = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
          if ($p) { [void](New-Object -ComObject WScript.Shell).AppActivate($p.Id) } } catch {}
  } else {
    # new switcher did not come up -> put the old files back
    Write-Log 'new version did not answer - rolling back'
    Stop-Agent
    [void](Copy-Tree $bk)
    $ok = Start-AgentAndWait $null
    Set-State 'rolled_back' ("$newVer startete nicht - $from wiederhergestellt" + $(if ($ok) { '' } else { ' (Umschalter antwortet nicht, Notebook neu starten)' })) @{ from = $from; to = $from }
  }
} catch {
  Set-State 'failed' "$_" @{ from = $from }
  # make sure the switcher runs again, whatever happened
  try { if (-not (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*mytv-vpn-agent.ps1*' })) { Start-ScheduledTask -TaskName $Agent } } catch {}
  exit 1
}
