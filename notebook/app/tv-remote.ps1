# ============================================================
#  MyTV - switch the Samsung TV to the notebook's HDMI input over the network
#  (Samsung "IP Remote" / SmartThings local remote API, port 8002)
#  Started in the background by the switcher when the iPhone sends "TV an".
#  Settings (written by VPN-Install.bat):  tv-ip.txt, tv-hdmi.txt
#  First run: the TV asks once "Allow MyTV?" -> choose Allow with the TV remote.
#  The TV's pairing token is then kept in tv-token.txt.
# ============================================================
$ErrorActionPreference = 'Stop'
$Dir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log   = Join-Path $Dir 'agent.log'
function Write-Log($m) { "$(Get-Date -Format s)  tv: $m" | Out-File -FilePath $Log -Append -Encoding utf8 }
$IpFile = Join-Path $Dir 'tv-ip.txt'
if (-not (Test-Path $IpFile)) { exit 0 }
$Ip   = (Get-Content $IpFile -Raw).Trim()
$Hdmi = if (Test-Path (Join-Path $Dir 'tv-hdmi.txt')) { (Get-Content (Join-Path $Dir 'tv-hdmi.txt') -Raw).Trim() } else { 'auto' }
# 1-4 = direct HDMI key (older models); auto = general HDMI key (newer models; jumps to the connected HDMI device)
$TvKey = if ($Hdmi -match '^[1-4]$') { "KEY_HDMI$Hdmi" } else { 'KEY_HDMI' }
$TokenFile = Join-Path $Dir 'tv-token.txt'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.WebSockets;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

public static class MyTvSamsungRemote {
    static string tvHost;
    // The TV uses a self-signed certificate: accept it ONLY for the TV's own IP address.
    static bool CheckCert(object sender, X509Certificate cert, X509Chain chain, SslPolicyErrors errors) {
        if (errors == SslPolicyErrors.None) return true;
        HttpWebRequest r = sender as HttpWebRequest;
        return r != null && r.RequestUri.Host == tvHost;
    }
    public static string Send(string ip, string tokenFile, string[] keys) {
        tvHost = ip;
        ServicePointManager.ServerCertificateValidationCallback = CheckCert;
        string name = Convert.ToBase64String(Encoding.UTF8.GetBytes("MyTV"));
        string token = File.Exists(tokenFile) ? File.ReadAllText(tokenFile).Trim() : "";
        string url = "wss://" + ip + ":8002/api/v2/channels/samsung.remote.control?name=" + name + (token.Length > 0 ? "&token=" + token : "");
        using (ClientWebSocket ws = new ClientWebSocket()) {
            CancellationTokenSource cts = new CancellationTokenSource(45000);   // time to press "Allow" on first use
            ws.ConnectAsync(new Uri(url), cts.Token).Wait();
            byte[] buf = new byte[16384];
            string msg = "";
            while (true) {
                WebSocketReceiveResult res = ws.ReceiveAsync(new ArraySegment<byte>(buf), cts.Token).Result;
                msg = Encoding.UTF8.GetString(buf, 0, res.Count);
                if (msg.Contains("ms.channel.connect")) break;
                if (msg.Contains("ms.channel.unauthorized")) return "not allowed - accept 'MyTV' on the TV (Settings > General > External Device Manager > Device Connection Manager)";
            }
            Match m = Regex.Match(msg, "\"token\"\\s*:\\s*\"?([0-9]+)");
            if (m.Success) File.WriteAllText(tokenFile, m.Groups[1].Value);
            Thread.Sleep(1000);
            foreach (string k in keys) {
                string cmd = "{\"method\":\"ms.remote.control\",\"params\":{\"Cmd\":\"Click\",\"DataOfCmd\":\"" + k + "\",\"Option\":\"false\",\"TypeOfRemote\":\"SendRemoteKey\"}}";
                byte[] b = Encoding.UTF8.GetBytes(cmd);
                ws.SendAsync(new ArraySegment<byte>(b), WebSocketMessageType.Text, true, cts.Token).Wait();
                Thread.Sleep(500);
            }
            try { ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None).Wait(2000); } catch { }
            return "ok";
        }
    }
}
'@

# wait until the TV is awake and its remote API answers (it was just woken by Wake-on-LAN)
$up = $false
for ($i = 0; $i -lt 30 -and -not $up; $i++) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $up = $c.ConnectAsync($Ip, 8002).Wait(1000) -and $c.Connected } catch { } finally { $c.Close() }
  if (-not $up) { Start-Sleep -Seconds 1 }
}
if (-not $up) { Write-Log "TV $Ip not reachable on port 8002 (is it on? IP Remote enabled?)"; exit 1 }
Start-Sleep -Seconds 3
for ($try = 1; $try -le 3; $try++) {
  try {
    Write-Log "connecting to $Ip, sending $TvKey"
    $r = [MyTvSamsungRemote]::Send($Ip, $TokenFile, @($TvKey))
    Write-Log "$TvKey -> $r"
    if ($r -eq 'ok') { exit 0 } else { exit 1 }
  } catch {
    Write-Log "try $($try): $($_.Exception.GetBaseException().Message)"
    Start-Sleep -Seconds 3
  }
}
exit 1
