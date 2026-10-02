#!/usr/bin/env python3
"""Build epg.json for MyTV from the public epgshare01 German XMLTV guide.

Only keeps the channels listed in channels.js under `xmltv:` and a window of
yesterday .. +2 days, so the file stays small. Run by .github/workflows/epg.yml.
"""
import gzip, io, json, re, sys, time, urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

SOURCE = "https://epgshare01.online/epgshare01/epg_ripper_DE1.xml.gz"
ROOT = __import__("pathlib").Path(__file__).resolve().parent.parent

def wanted_ids():
    js = (ROOT / "channels.js").read_text(encoding="utf-8")
    return sorted(set(re.findall(r'xmltv:\s*"([^"]+)"', js)))

def parse_time(s):
    # "20261002201500 +0200"
    s = s.strip()
    dt = datetime.strptime(s[:14], "%Y%m%d%H%M%S")
    off = s[14:].strip() or "+0000"
    sign = 1 if off[0] == "+" else -1
    secs = sign * (int(off[1:3]) * 3600 + int(off[3:5]) * 60)
    return int(dt.replace(tzinfo=timezone.utc).timestamp()) - secs

def main():
    ids = set(wanted_ids())
    if not ids:
        print("no xmltv ids in channels.js"); return
    print("wanted:", ", ".join(sorted(ids)))
    req = urllib.request.Request(SOURCE, headers={"User-Agent": "MyTV-EPG/1.0 (personal use)"})
    raw = urllib.request.urlopen(req, timeout=120).read()
    data = gzip.decompress(raw)
    now = time.time()
    lo, hi = now - 24 * 3600, now + 48 * 3600
    out = {i: [] for i in ids}
    seen_channels = set()
    for ev, el in ET.iterparse(io.BytesIO(data), events=("end",)):
        if el.tag == "channel":
            seen_channels.add(el.get("id"))
            el.clear(); continue
        if el.tag != "programme":
            continue
        cid = el.get("channel")
        if cid in ids:
            try:
                s, e = parse_time(el.get("start")), parse_time(el.get("stop"))
            except Exception:
                el.clear(); continue
            if e > lo and s < hi and e > s:
                t = (el.findtext("title") or "").strip()
                st = (el.findtext("sub-title") or "").strip()
                d = (el.findtext("desc") or "").strip()
                if len(d) > 400: d = d[:397].rstrip() + "…"
                out[cid].append({"s": s, "e": e, "t": t, "st": st, "d": d})
        el.clear()
    missing = [i for i in ids if i not in seen_channels]
    if missing:
        print("WARNING: ids not in source:", ", ".join(missing))
        # help fix channels.js: show similar ids
        for m in missing:
            key = re.sub(r"[^a-z0-9]", "", m.lower().replace(".de", ""))
            near = [c for c in seen_channels if key and key in re.sub(r"[^a-z0-9]", "", c.lower())]
            print(f"  {m}: candidates {near[:8]}")
    for k in out:
        out[k].sort(key=lambda p: p["s"])
        print(f"{k}: {len(out[k])} programmes")
    doc = {"generated": int(now), "source": "epgshare01.online (DE1)", "channels": out}
    (ROOT / "epg.json").write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print("wrote epg.json", (ROOT / "epg.json").stat().st_size, "bytes")

if __name__ == "__main__":
    main()
