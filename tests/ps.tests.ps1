# ============================================================
#  MyTV - checks for the notebook scripts. Runs in CI on windows-latest with Windows PowerShell 5.1
#  (the same PowerShell as on the notebook). Exit code 1 = at least one check failed → no release.
# ============================================================
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$script:fails = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { Write-Host "ok    $name" } else { Write-Host "FAIL  $name  $detail" -ForegroundColor Red; $script:fails++ }
}
Write-Host "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

# ---- 1. every script parses
$files = @(Get-ChildItem (Join-Path $Root 'kiosk') -Recurse -Filter *.ps1) + @(Get-ChildItem (Join-Path $Root 'tests') -Filter *.ps1)
$asts = @{}
foreach ($f in $files) {
  $e = $null; $t = $null
  $asts[$f.FullName] = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
  Check "parse $($f.Name)" ($e.Count -eq 0) (($e | ForEach-Object { "$($_.Message) @$($_.Extent.StartLineNumber)" }) -join '; ')
  # non-ASCII text needs a BOM, else Windows PowerShell 5.1 reads it as ANSI (broken umlauts)
  $b = [IO.File]::ReadAllBytes($f.FullName)
  $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
  $nonAscii = @($b | Where-Object { $_ -gt 127 }).Count -gt 0
  Check "encoding $($f.Name)" ($bom -or -not $nonAscii) 'non-ASCII characters but no UTF-8 BOM'
}

# ---- 2. lint: function names hidden by built-in aliases (the "R" = Invoke-History bug)
foreach ($k in $asts.Keys) {
  foreach ($fn in $asts[$k].FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    $alias = Get-Alias -Name $fn.Name -ErrorAction SilentlyContinue
    Check "no alias clash: $($fn.Name) ($(Split-Path -Leaf $k))" (-not $alias) "is the built-in alias for $($alias.Definition)"
  }
}
# ---- 3. lint: function parameter with the name of a script variable (the Set-State $state / $State bug)
foreach ($k in $asts.Keys) {
  $a = $asts[$k]
  $scriptVars = @{}
  foreach ($as in $a.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] }) {
    if ($as.Left -is [System.Management.Automation.Language.VariableExpressionAst]) { $scriptVars[$as.Left.VariablePath.UserPath.ToLower()] = $as.Left.VariablePath.UserPath }
  }
  foreach ($fn in $a.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    $ps = @(); if ($fn.Parameters) { $ps += $fn.Parameters }; if ($fn.Body.ParamBlock) { $ps += $fn.Body.ParamBlock.Parameters }
    foreach ($p in $ps) {
      $n = $p.Name.VariablePath.UserPath
      $clash = $scriptVars[$n.ToLower()]
      Check "param `$$n of $($fn.Name) doesn't hide a script variable ($(Split-Path -Leaf $k))" (-not $clash) "hides `$$clash"
    }
  }
}

# ---- 4. behaviour of the switcher's helpers (loaded from the real file)
$agentPath = Join-Path $Root 'kiosk\vpn\mytv-vpn-agent.ps1'
$agent = $asts[(Get-Item $agentPath).FullName]
foreach ($fn in $agent.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in @('Get-Num', 'Get-QS', 'Expand-Items', 'Get-Rems', 'Save-Rems', 'Find-Rem', 'Get-Configs', 'Get-ServerIdx', 'Set-ServerIdx', 'Get-ServerInfo', 'Get-Favs', 'Set-Fav') }, $true)) {
  . ([ScriptBlock]::Create($fn.Extent.Text))
}
function Req($q) { [pscustomobject]@{ QueryString = $q; Url = [Uri]('http://127.0.0.1:8766/x?' + (($q.Keys | ForEach-Object { "$_=$([Uri]::EscapeDataString([string]$q[$_]))" }) -join '&')) } }
Check 'Get-Num keeps 0.5'      ((Get-Num (Req @{ x = '0.5' }) 'x' 0 1) -eq 0.5)
Check 'Get-Num clamps 1.7 → 1' ((Get-Num (Req @{ x = '1.7' }) 'x' 0 1) -eq 1)
Check 'Get-Num -250'           ((Get-Num (Req @{ d = '-250' }) 'd' -400 400) -eq -250)
Check 'Get-QS umlauts'         ((Get-QS (Req @{ t = 'Südpark & Co' }) 't') -eq 'Südpark & Co')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('mytv-test-' + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $tmp | Out-Null
$RemFile = Join-Path $tmp 'reminders.json'
$f = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 3600000
Set-Content $RemFile "[[{`"ch`":37,`"start`":$f,`"end`":$($f + 1000),`"title`":`"a`"},{`"ch`":2,`"start`":$f,`"end`":$($f + 1000)}]]"
$r = @(Get-Rems)
Check 'reminders: nested list read flat' ($r.Count -eq 2 -and $r[0].ch -eq 37)
Save-Rems $r
Check 'reminders: saved flat' ((Get-Content $RemFile -Raw).Trim().StartsWith('[{'))
Save-Rems @($r[0]); $r1 = @(Get-Rems)
Check 'reminders: single item stays a list' ($r1.Count -eq 1 -and (Get-Content $RemFile -Raw).Trim().StartsWith('[{'))

$Dir = $tmp; $RunDir = Join-Path $tmp 'run'
'DE.conf', 'DE02.conf', 'DE-berlin.conf', 'DEBUG.conf', 'CH.conf' | ForEach-Object { Set-Content (Join-Path $tmp $_) 'x' }
Check 'VPN configs: DE.conf first, DEBUG.conf ignored' (((Get-Configs 'DE') | ForEach-Object Name) -join ',' -eq 'DE.conf,DE-berlin.conf,DE02.conf')
Set-ServerIdx 'DE' 2; Check 'VPN server remembered by name' ((Get-ServerInfo 'DE').name -eq 'DE02')
Set-Content (Join-Path $tmp 'DE-a.conf') 'x'; Check 'VPN server still right after a new file' ((Get-ServerInfo 'DE').name -eq 'DE02')

$FavFile = Join-Path $tmp 'favorites.txt'
Check 'favorites add/remove' (((Set-Fav 22 $true) -join ',') -eq '22' -and ((Set-Fav 2 $true) -join ',') -eq '2,22' -and ((Set-Fav 22 $false) -join ',') -eq '2')
Remove-Item $tmp -Recurse -Force

# ---- 5. mouse-mode C# compiles here and has the right struct size
$src = Get-Content $agentPath -Raw
$a = $src.IndexOf('Add-Type -TypeDefinition @"'); $b = $src.IndexOf('"@', $a + 30)
try { Add-Type -TypeDefinition ($src.Substring($a + 27, $b - $a - 27).Trim()); Check 'mouse mode C# compiles' $true } catch { Check 'mouse mode C# compiles' $false "$_" }
try { Check 'INPUT struct size 40 (x64)' ([Runtime.InteropServices.Marshal]::SizeOf([type]'MyTVInput+INPUT') -eq 40) } catch { Check 'INPUT struct size' $false "$_" }

Write-Host ''
if ($script:fails) { Write-Host "$($script:fails) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'all checks passed' -ForegroundColor Green
