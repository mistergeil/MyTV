#!/usr/bin/env python3
"""Copy the userscripts (source: userscripts/) to kiosk/, the URL Tampermonkey updates from (@updateURL).
Run after changing a userscript: python tools/sync_published.py  (CI fails if the copies differ)."""
import shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
for f in (ROOT / "userscripts").glob("*.user.js"):
    shutil.copyfile(f, ROOT / "kiosk" / f.name); print("published", f.name)
