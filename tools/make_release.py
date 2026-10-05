#!/usr/bin/env python3
"""Build kiosk/MyTV-Windows.zip + kiosk/version.json for the notebook updater.

  python tools/make_release.py 1.1.0 "Fotos-Diashow per NFC-Sticker" "Neue Taste ⚙ in der Fernbedienung"

Writes the version into kiosk/vpn/VERSION, zips the notebook files and records the zip's
SHA-256 in version.json. The notebook only installs after a tap on "Installieren" in the
iPhone remote settings, and only if the downloaded zip matches this checksum.
Add --installer if the release also needs VPN-Install.bat to be run once on the notebook.
"""
import hashlib, json, sys, zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
K = ROOT / "kiosk"
FILES = ["MyTV-Kiosk.bat", "MyTV-Setup.bat", "Autostart-Install.bat", "Autostart-Remove.bat",
         "vpn/VPN-Install.bat", "vpn/VPN-Uninstall.bat", "vpn/install-vpn.ps1", "vpn/uninstall-vpn.ps1",
         "vpn/mytv-vpn-agent.ps1", "vpn/mytv-update.ps1", "vpn/tv-remote.ps1", "vpn/remote.html", "vpn/watch.html", "vpn/VERSION"]

def main():
    args = [a for a in sys.argv[1:] if a != "--installer"]
    if not args:
        sys.exit(__doc__)
    ver, notes = args[0], args[1:]
    (K / "vpn" / "VERSION").write_text(ver, encoding="ascii")
    zp = K / "MyTV-Windows.zip"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for f in FILES:
            info = zipfile.ZipInfo(f, date_time=(2026, 1, 1, 0, 0, 0))   # fixed timestamps → same files = same zip
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, (K / f).read_bytes())
    sha = hashlib.sha256(zp.read_bytes()).hexdigest()
    doc = {"version": ver, "date": date.today().strftime("%d.%m.%Y"), "zip": "MyTV-Windows.zip", "sha256": sha,
           "size": zp.stat().st_size, "notes": notes, "installer": "--installer" in sys.argv}
    (K / "version.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"MyTV {ver}: {zp.name} {doc['size']} bytes, sha256 {sha[:16]}…")

if __name__ == "__main__":
    main()
