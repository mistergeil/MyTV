#!/usr/bin/env python3
"""YouTube channels for MyTV (type "youtube" in channels.js, e.g. Zarbex on 60).

For every such channel: resolve the handles in `yt` (e.g. "@zarbex") to channel ids, read their public
upload feeds (no API key), drop Shorts, merge, newest first → youtube.json { "60": [ {id,title,published,by}, ... ] }.
MyTV plays the newest video when you zap in, then the next ones; ← → skip.
"""
import json, re, urllib.request, xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "youtube.json"
UA = {"User-Agent": "Mozilla/5.0 (MyTV personal TV)", "Accept-Language": "de-DE,de;q=0.9"}
NS = {"a": "http://www.w3.org/2005/Atom", "yt": "http://www.youtube.com/xml/schemas/2015", "media": "http://search.yahoo.com/mrss/"}

def fetch(url, timeout=25):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout).read().decode("utf-8", "replace")

def channel_id(handle, cache):
    if handle.startswith("UC"):
        return handle
    if handle.startswith("video:"):                       # channel given by one of its videos
        if handle in cache:
            return cache[handle]
        html = fetch(f"https://www.youtube.com/watch?v={handle[6:]}")
        m = re.search(r'"channelId":"(UC[\w-]{22})"', html)
        if not m:
            raise RuntimeError(f"no channel for {handle}")
        cache[handle] = m.group(1)
        return m.group(1)
    if handle.startswith("v:") and handle in cache:
        return cache[handle]
    if handle.startswith("v:"):                      # "v:<videoId>" = the channel that uploaded this video
        html = fetch(f"https://www.youtube.com/watch?v={handle[2:]}")
        m = re.search(r'"videoDetails":\{.*?"channelId":"(UC[\w-]{22})"', html, re.S) or re.search(r'"channelId":"(UC[\w-]{22})"', html)
        if not m:
            raise RuntimeError(f"no channel for video {handle[2:]}")
        cache[handle] = m.group(1)
        return m.group(1)
    # @handle: the page's OWN id (canonical link / externalId) - "channelId" can belong to a featured channel
    # (Jeff Nippard -> his podcast, Jesse James West -> Jesse James East). Resolved every run; cache = fallback only.
    try:
        html = fetch(f"https://www.youtube.com/{handle}")
        m = (re.search(r'<link rel="canonical" href="https://www\.youtube\.com/channel/(UC[\w-]{22})"', html)
             or re.search(r'"externalId":"(UC[\w-]{22})"', html)
             or re.search(r'"channelId":"(UC[\w-]{22})"', html))
        if not m:
            raise RuntimeError(f"no channel id for {handle}")
        cache[handle] = m.group(1)
    except Exception:
        if handle not in cache:
            raise
    return cache[handle]

def is_short(vid):
    # /shorts/<id> answers 200 for Shorts and redirects (303) to /watch for normal videos
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k): return None
    try:
        r = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(f"https://www.youtube.com/shorts/{vid}", headers=UA, method="HEAD"), timeout=15)
        return r.status == 200
    except urllib.error.HTTPError as e:
        return False
    except Exception:
        return False

def channels():
    js = (ROOT / "channels.js").read_text(encoding="utf-8")
    for line in js.splitlines():
        if 'type: "youtube"' not in line:
            continue
        n = re.search(r"number:\s*(\d+)", line); yt = re.search(r"yt:\s*\[([^\]]*)\]", line)
        m = re.search(r'match:\s*"((?:[^"\\]|\\.)*)"', line)       # optional title filter (regex, case-insensitive)
        if n and yt:
            yield int(n.group(1)), re.findall(r'"([^"]+)"', yt.group(1)), (m.group(1).replace('\\\\', '\\') if m else None)

def main():
    old = json.loads(OUT.read_text(encoding="utf-8")) if OUT.exists() else {}
    cache = old.get("_ids", {})
    shorts = set(old.get("_shorts", []))
    out = {"_ids": cache}
    for num, handles, match in channels():
        rx = re.compile(match, re.I) if match else None
        vids = []
        for h in handles:
            try:
                cid = channel_id(h, cache)
                feed = ET.fromstring(fetch(f"https://www.youtube.com/feeds/videos.xml?channel_id={cid}"))
                for e in feed.findall("a:entry", NS):
                    vid = e.findtext("yt:videoId", namespaces=NS)
                    if not vid:
                        continue
                    if rx and not rx.search(e.findtext("a:title", namespaces=NS) or ""):
                        continue                                  # e.g. only highlights of the Canadian teams
                    if vid in shorts or is_short(vid):
                        shorts.add(vid); continue
                    vids.append({"id": vid, "title": e.findtext("a:title", namespaces=NS) or "", "published": e.findtext("a:published", namespaces=NS) or "",
                                 "by": feed.findtext("a:title", namespaces=NS) or h})
            except Exception as ex:
                print(f"  {h}: {ex}")
        # keep what was found before: busy channels (Sportsnet) push matching videos out of their 15-item feed quickly
        prev = [v for v in old.get(str(num), []) if not rx or rx.search(v.get("title", ""))]
        vids += prev
        seen = set(); vids = [v for v in vids if not (v["id"] in seen or seen.add(v["id"]))]   # same channel listed twice
        vids.sort(key=lambda v: v["published"], reverse=True)
        out[str(num)] = vids[:30]
        print(f"channel {num}: {len(vids)} videos from {', '.join(handles)}")
    out["_shorts"] = sorted(shorts)[-500:]
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")

if __name__ == "__main__":
    main()
