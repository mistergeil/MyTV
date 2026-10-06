#!/usr/bin/env python3
"""Build kiosk/MyTV-Windows.zip + kiosk/version.json (the published update the notebook updater downloads)
from the sources in notebook/ (app/, remote/). Zip layout stays as installed on the notebook (vpn\\…, root .bat).

  Normal way (since 1.13): edit notebook/app/VERSION + notebook/app/NOTES.txt and push - the GitHub workflow
  "Release" runs the tests on real Windows PowerShell 5.1 and builds the package (python tools/make_release.py --auto).
  Manual (emergency only): python tools/make_release.py 1.1.0 "Note 1" "Note 2"

Writes the version into notebook/app/VERSION, zips the notebook files and records the zip's
SHA-256 in version.json. The notebook only installs after a tap on "Installieren" in the
iPhone remote settings, and only if the downloaded zip matches this checksum.
Add --installer if the release also needs VPN-Install.bat to be run once on the notebook.
"""
import hashlib, json, sys, zipfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
K = ROOT / "kiosk"            # published release (fixed URL for installed updaters)
N = ROOT / "notebook"
# repo source → path inside the zip (= path on the notebook, C:\\MyTV\\…). Layout unchanged until the notebook migration.
FILES = {
    "app/MyTV-Kiosk.bat": "MyTV-Kiosk.bat", "app/MyTV-Setup.bat": "MyTV-Setup.bat",
    "app/Autostart-Install.bat": "Autostart-Install.bat", "app/Autostart-Remove.bat": "Autostart-Remove.bat",
    "app/VPN-Install.bat": "vpn/VPN-Install.bat", "app/VPN-Uninstall.bat": "vpn/VPN-Uninstall.bat",
    "app/install-vpn.ps1": "vpn/install-vpn.ps1", "app/uninstall-vpn.ps1": "vpn/uninstall-vpn.ps1",
    "app/mytv-vpn-agent.ps1": "vpn/mytv-vpn-agent.ps1", "app/mytv-update.ps1": "vpn/mytv-update.ps1",
    "app/tv-remote.ps1": "vpn/tv-remote.ps1", "app/VERSION": "vpn/VERSION",
    "remote/remote.html": "vpn/remote.html", "remote/watch.html": "vpn/watch.html",
}

def main():
    args = [a for a in sys.argv[1:] if a not in ("--installer", "--auto")]
    if "--auto" in sys.argv:
        # CI mode (release workflow): version from notebook/app/VERSION, notes from notebook/app/NOTES.txt (one per line)
        ver = (N / "app" / "VERSION").read_text(encoding="ascii").strip()
        nf = N / "app" / "NOTES.txt"
        notes = [l.strip() for l in nf.read_text(encoding="utf-8").splitlines() if l.strip()] if nf.exists() else []
        cur = json.loads((K / "version.json").read_text(encoding="utf-8")).get("version") if (K / "version.json").exists() else None
        if cur == ver:
            print(f"version.json already at {ver} - nothing to release"); return
        if cur and tuple(map(int, ver.split("."))) <= tuple(map(int, cur.split("."))):
            sys.exit(f"VERSION {ver} is not newer than the released {cur} - bump notebook/app/VERSION")
    elif not args:
        sys.exit(__doc__)
    else:
        ver, notes = args[0], args[1:]
    vf = N / "app" / "VERSION"
    if not vf.exists() or vf.read_text(encoding="ascii").strip() != ver:   # don't touch it in CI (would leave a change behind)
        vf.write_text(ver, encoding="ascii")
    zp = K / "MyTV-Windows.zip"
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for src, f in FILES.items():
            info = zipfile.ZipInfo(f, date_time=(2026, 1, 1, 0, 0, 0))   # fixed timestamps → same files = same zip
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, (N / src).read_bytes())
    sha = hashlib.sha256(zp.read_bytes()).hexdigest()
    doc = {"version": ver, "date": date.today().strftime("%d.%m.%Y"), "zip": "MyTV-Windows.zip", "sha256": sha,
           "size": zp.stat().st_size, "notes": notes, "installer": "--installer" in sys.argv}
    (K / "version.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"MyTV {ver}: {zp.name} {doc['size']} bytes, sha256 {sha[:16]}…")

if __name__ == "__main__":
    main()
