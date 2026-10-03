#!/usr/bin/env python3
"""Build highlights.json for MyTV: films, sport and big events of the coming week,
plus new films / long documentaries in the public Mediatheken.

Called by build_epg.py (same GitHub Action, same XMLTV download) with the programmes
of the next 8 days. Sources:
  - XMLTV (epgshare01)          → private channels, ZDF, SRF, ORF … (channels with `xmltv:`)
  - programm-api.ard.de         → ARD family (channels with `epg:`)
  - mediathekviewweb.de         → "Neu in der Mediathek"
Only channels that are in channels.js show up. Edit the lists below to tune what counts.

Local test without network:  python tools/build_highlights.py --from-epg
"""
import json, re, sys, time, urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
BERLIN = ZoneInfo("Europe/Berlin")
DAYS = 8

# ---------- what counts as a highlight (edit freely) ----------
SPORT = [  # (regex on title/sub-title, label, weight)
    (r"\bbundesliga\b|\bdfb[- ]pokal\b|supercup", "Fussball", 9),
    (r"champions league|europa league|conference league|uefa", "Fussball", 9),
    (r"nations league|länderspiel|wm[- ]qualifikation|em[- ]qualifikation|fussball[- ]?wm|fußball[- ]?wm|fussball[- ]?em|fußball[- ]?em", "Fussball", 10),
    (r"super league|nati\b|schweizer cup|öfb[- ]cup|admiral bundesliga", "Fussball", 7),
    (r"american football|\bnfl\b", "NFL", 5),
    (r"\bfußball\b|\bfussball\b|calcio|\bfootball\b", "Fussball", 5),
    (r"formel 1|formula 1|\bf1\b|grand prix", "Formel 1", 8),
    (r"ski alpin|weltcup.*(abfahrt|slalom|riesenslalom|super-g)|abfahrt|slalom|skispringen|vierschanzen|biathlon|langlauf", "Wintersport", 7),
    (r"eishockey|hockey|penny del|\bnhl\b|national league.*(hockey|eishockey)", "Eishockey", 6),
    (r"tennis|wimbledon|us open|french open|australian open|atp|wta", "Tennis", 5),
    (r"handball", "Handball", 5),
    (r"leichtathletik-(wm|em)|olympische (sommer|winter)?spiele|paralympi", "Sport-Event", 7),
    (r"tour de france|giro d|vuelta|radsport", "Radsport", 5),
    (r"\bsportschau\b|aktuelle sportstudio|sportstudio", "Sport-Sendung", 4),
]
SPORT_NOT = re.compile(r"magazin|news|flash|\bkompakt\b|aktuell\b|quiz|doku|legenden|geschichte|ninja|fitness|talk\b|-talk|trailer|wetter|"
                       r"mountain ?bike|\bmtb\b|snooker|darts|springreiten|reiten|golf\b|poker", re.I)
# sport we don't list (and must never be mistaken for a film)
SPORT_ANY = re.compile(r"weltcup|world cup|world series|coppa del mondo|coupe du monde|\buci\b|rennen\b|meisterschaft|championship|"
                       r"league of nations|grand slam|\bcup\b|turnier|qualifying|qualifikation|\bgp\b|sport", re.I)
RERUN = re.compile(r"wiederholung|\(wh\)|\bwdh\b|highlights|zusammenfassung|re-live|relive|das ganze rennen|aufzeichnung|rückblick", re.I)
LIVE = re.compile(r"\blive\b|\bdirekt\b|\bin diretta\b|\ben direct\b|\blive-übertragung", re.I)

FILM_DESC = re.compile(r"\b(spielfilm|thriller|komödie|drama|actionfilm|actionthriller|krimi(?:nalfilm)?|western|animationsfilm|liebesfilm|abenteuerfilm|"
                       r"science-fiction|sci-fi|horrorfilm|fantasyfilm|fernsehfilm|tragikomödie|filmdrama|kinofilm|blockbuster|oscar|film von|regie)\b", re.I)
FILM_TV_SERIES = re.compile(r"^(tatort|polizeiruf 110|der bozen-krimi|der kroatien-krimi|der usedom-krimi|ein starnberger see-krimi|der zürich-krimi|"
                            r"nord bei nordwest|die chefin|wilsberg|steirer|landkrimi|der staatsanwalt|friesland|der alte)\b", re.I)
SERIES_HINT = re.compile(r"infos zur serie|\bfolge\b|\bstaffel\b|episode|doku-soap|reality|teleshopping|show\b|magazin|nachrichten|talk\b|quiz|"
                         r"reportage|dokumentation|\bdoku\b|live\b|gottesdienst|wetter|singer|das große backen|kochen|armes deutschland|"
                         r"snapped|promi|dschungel|bauer sucht|best of|meilleur|semaine|die geissens|auswanderer|sendung|oper\b|konzert|ballett", re.I)
PREMIERE = re.compile(r"free-tv-premiere|tv-premiere|deutschlandpremiere|erstmals im free-tv|erstausstrahlung", re.I)
EVENTS = [  # big shows / events (regex on title, weight)
    (r"^tatort\b|^polizeiruf 110\b", 7),
    (r"wetten,? dass|schlag den|the voice|eurovision|esc\b|grand prix d|let's dance|das supertalent|wer stiehlt mir die show|"
     r"joko & klaas|tv total|bambi|echo\b|goldene kamera|silvester|oktoberfest|zdf-fernsehgarten|sommernachtsparty|musikantenstadl|"
     r"ninja warrior|herzblatt|die höhle der löwen|das große promibacken|duell um die welt|swiss award|sportlerehrung", 6),
    (r"wahl|elefantenrunde|tv-duell|bundestag|nationalrat|abstimmung|regierungserklärung", 5),
]
PRIMARY = {  # channel number → bonus (big channels show the "real" highlights)
    1: 3, 2: 3, 6: 2, 5: 1, 20: 3, 21: 2, 22: 3, 23: 2, 24: 2, 25: 1, 41: 2, 42: 2, 53: 2, 54: 2, 56: 2, 7: 1,
}
KIDS = {11, 38, 39, 59}
FOREIGN = {44, 45, 46, 47, 48, 50, 51, 52}      # French / Italian channels: sport only if no German channel has it
NO_FILM = {3, 4, 8, 10, 29, 32, 33, 35, 36, 40, 43, 49} | FOREIGN   # news / doku / regional channels

# ---------- helpers ----------
def channels():
    js = (ROOT / "channels.js").read_text(encoding="utf-8")
    out = []
    for line in js.splitlines():
        m = re.search(r'number:\s*(\d+),\s*name:\s*"([^"]+)"', line)
        if not m:
            continue
        x = re.search(r'xmltv:\s*"([^"]+)"', line)
        e = re.search(r'epg:\s*"([^"]+)"', line)
        g = re.search(r'geo:\s*(true|"(\w+)")', line)
        out.append({"n": int(m.group(1)), "name": m.group(2), "xmltv": x and x.group(1), "epg": e and e.group(1),
                    "geo": (g.group(2) or "DE") if g else None})
    return out

def get_json(url, body=None, timeout=60):
    req = urllib.request.Request(url, data=body.encode() if body else None,
                                 headers={"User-Agent": "MyTV-Highlights/1.0 (personal use)",
                                          **({"Content-Type": "text/plain"} if body else {})})
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8"))

def berlin(ts):
    return datetime.fromtimestamp(ts, BERLIN)

def classify(p, ch):
    """→ (kind, label, score) or None. p: {s,e,t,st,d,cat?,date?,live?}"""
    t, st, d = p.get("t", ""), p.get("st", ""), p.get("d", "")
    cats = " ".join(p.get("cat") or []).lower()
    mins = (p["e"] - p["s"]) / 60
    hr = berlin(p["s"]); h = hr.hour + hr.minute / 60
    head = f"{t} {st}"
    n = ch["n"]
    if mins < 25:
        return None

    # --- sport ---
    if "sport" in cats or any(re.search(rx, head, re.I) for rx, _, _ in SPORT):
        if SPORT_NOT.search(head) or (n in KIDS):
            return None
        label, w = "Sport", 3
        for rx, lb, wt in SPORT:
            if re.search(rx, head, re.I):
                label, w = lb, wt; break
        is_live = bool(p.get("live")) or bool(LIVE.search(head)) or bool(LIVE.search(d[:160]))
        if label != "Sport-Sendung" and mins < 55 and not is_live:
            return None
        if RERUN.search(head + " " + d[:120]):
            w -= 6
        if is_live:
            w += 3
        w += PRIMARY.get(n, 0)
        return ("sport", label, w) if w >= 5 else None
    if SPORT_ANY.search(head) or SPORT_NOT.search(t):
        return None
    if n in FOREIGN:
        return None

    # --- big events / shows ---
    for rx, w in EVENTS:
        if re.search(rx, t, re.I):
            if FILM_TV_SERIES.search(t):       # Tatort & Co. = Sunday-night film
                if 19.5 <= h < 22.5 and mins >= 80 and not re.search(r"wiederholung|\(wh\)", d[:80], re.I):
                    return ("film", "Krimi", w + PRIMARY.get(n, 0) + (3 if hr.weekday() == 6 and n in (1, 54, 41) else 0))
                return None
            if 18 <= h < 23.5 and mins >= 50:
                return ("event", "Show", w + PRIMARY.get(n, 0) + (2 if LIVE.search(head + d[:120]) else 0))

    # --- films ---
    is_film_cat = bool(re.search(r"film|movie|spielfilm|kino", cats))
    if not is_film_cat and re.search(r"serie|series|show|magazin|nachrichten|news|doku|reality|talk|sport|kinder", cats):
        return None
    if n in NO_FILM or (n in KIDS and not (19 <= h < 22)):
        return None
    if not (75 <= mins <= 210):
        return None
    if not (19.5 <= h < 23.75):                 # prime time + late films only (daytime = reruns)
        return None
    prem = bool(PREMIERE.search(head + " " + d[:200]))
    looks_film = is_film_cat or bool(FILM_DESC.search(d[:300])) or prem or (not st and not SERIES_HINT.search(head + " " + d[:200]))
    if not looks_film:
        return None
    if st and not is_film_cat and not prem and not FILM_DESC.search(d[:300]):
        return None                              # has an episode title → series
    if SERIES_HINT.search(t) and not is_film_cat:
        return None
    score = 4 + PRIMARY.get(n, 0)
    if prem: score += 6
    yr = p.get("date") or ""
    m = re.search(r"(19|20)\d\d", yr) or re.search(r"\b(19[5-9]\d|20[0-3]\d)\b", d[:400])
    if m:
        y = int(m.group(0))
        score += 3 if y >= datetime.now().year - 2 else (1 if y >= 2010 else 0)
    if abs(h - 20.25) < 0.3: score += 2          # 20:15 slot
    return ("film", "Free-TV-Premiere" if prem else "Spielfilm", score)

# ---------- sources ----------
def from_xmltv(progs_by_id, chans):
    by_x = {c["xmltv"]: c for c in chans if c["xmltv"]}
    for cid, plist in progs_by_id.items():
        ch = by_x.get(cid)
        if ch:
            for p in plist:
                yield ch, p

def from_ard(chans, now):
    by_e = {c["epg"]: c for c in chans if c["epg"]}
    if not by_e:
        return
    seen = set()
    for off in range(0, DAYS):
        day = (datetime.now(BERLIN) + timedelta(days=off)).strftime("%Y-%m-%d")
        try:
            j = get_json(f"https://programm-api.ard.de/program/api/program?day={day}")
        except Exception as e:
            print("  ARD", day, "failed:", e); continue
        for c in j.get("channels") or []:
            ch = by_e.get(c.get("id"))
            if not ch:
                continue
            slots = []
            for x in c.get("timeSlots") or []:
                slots.extend(x if isinstance(x, list) else [x])
            for sl in slots:
                try:
                    s = int(datetime.fromisoformat(sl["broadcastedOn"].replace("Z", "+00:00")).timestamp())
                    e = int(datetime.fromisoformat(sl["broadcastEnd"].replace("Z", "+00:00")).timestamp())
                except Exception:
                    continue
                key = (ch["n"], s)
                if key in seen or e <= s:
                    continue
                seen.add(key)
                img = find_img(sl)
                yield ch, {"s": s, "e": e, "t": sl.get("coreTitle") or sl.get("title") or "", "st": sl.get("coreSubline") or "",
                           "d": (sl.get("synopsis") or "")[:400], "img": img,
                           "live": bool(sl.get("isLive") or sl.get("live")), "cat": [sl.get("genre")] if isinstance(sl.get("genre"), str) else []}

def find_img(o, depth=0):
    """first usable image URL anywhere in an ARD slot ({width} placeholders → 640)"""
    if depth > 4 or o is None:
        return ""
    if isinstance(o, dict):
        for k in ("aspect16x9", "aspect16x7", "aspect1x1"):
            if isinstance(o.get(k), dict) and isinstance(o[k].get("src"), str):
                return o[k]["src"].replace("{width}", "640")
        for k, v in o.items():
            if k in ("images", "image", "teaserImage") or isinstance(v, (dict, list)):
                r = find_img(v, depth + 1)
                if r:
                    return r
    elif isinstance(o, list):
        for v in o[:3]:
            r = find_img(v, depth + 1)
            if r:
                return r
    elif isinstance(o, str) and o.startswith("http") and re.search(r"\.(jpe?g|png|webp)|image", o, re.I) and "{width}" in o:
        return o.replace("{width}", "640")
    return ""

MVW_CH = {"ARD": "DE", "ZDF": "DE", "ARTE.DE": "DE", "3Sat": "DE", "SRF": "CH", "ORF": "AT", "ZDFneo": "DE", "BR": "DE", "WDR": "DE", "NDR": "DE",
          "SWR": "DE", "MDR": "DE", "HR": "DE", "RBB": "DE", "PHOENIX": "DE"}
MVW_BAD = re.compile(r"audiodeskription|gebärdensprache|hörfassung|\(ad\)|trailer|\(ov\)|originalversion|englische fassung|"
                     r"tagesschau|heute journal|nachrichten|gottesdienst|konzert|oper\b|live\b|talk|sportschau|bundesliga|"
                     r"folge \d|teil \d|staffel|episode|\(s\d+/e\d+\)|klare sprache|leichte sprache", re.I)

def mediathek(now):
    """new long films / documentaries (MediathekViewWeb, last 7 days)"""
    out, seen = [], set()
    for ch in MVW_CH:
        body = json.dumps({"queries": [{"fields": ["channel"], "query": ch}], "sortBy": "timestamp", "sortOrder": "desc",
                           "future": False, "offset": 0, "size": 60, "duration_min": 4800, "duration_max": 12000})
        try:
            res = get_json("https://mediathekviewweb.de/api/query", body)["result"]["results"]
        except Exception as e:
            print("  MVW", ch, "failed:", e); continue
        for r in res:
            if r.get("timestamp", 0) < now - 7 * 86400 or not r.get("url_video"):
                continue
            if MVW_BAD.search(f"{r.get('title','')} {r.get('topic','')}"):
                continue
            key = re.sub(r"\W+", "", (r.get("title") or "").lower())
            if key in seen:
                continue
            seen.add(key)
            d = (r.get("description") or "")[:300]
            film = bool(FILM_DESC.search(d)) or bool(re.search(r"film|kino", r.get("topic") or "", re.I))
            out.append({"title": r.get("title"), "topic": r.get("topic"), "channel": r.get("channel"), "dur": r.get("duration"),
                        "ts": r.get("timestamp", 0) * 1000, "desc": d, "url": r.get("url_video_hd") or r.get("url_video"),
                        "country": MVW_CH.get(r.get("channel"), "DE"), "film": film})
    out.sort(key=lambda x: (not x["film"], -x["ts"]))
    return out[:30]

def similar(a, b):
    wa = {w for w in re.findall(r"\w{4,}", a.lower())}; wb = {w for w in re.findall(r"\w{4,}", b.lower())}
    return len(wa & wb) >= 2

# ---------- build ----------
def build(xmltv_progs, use_network=True):
    now = int(time.time())
    chans = channels()
    items = []
    sources = [from_xmltv(xmltv_progs, chans)]
    if use_network:
        sources.append(from_ard(chans, now))
    for src in sources:
        for ch, p in src:
            if p["e"] < now or p["s"] > now + DAYS * 86400:
                continue
            c = classify(p, ch)
            if not c:
                continue
            kind, label, score = c
            items.append({"kind": kind, "label": label, "score": score, "ch": ch["n"], "chName": ch["name"],
                          "s": p["s"], "e": p["e"], "t": p["t"], "st": p.get("st", ""), "d": p.get("d", "")[:300],
                          **({"img": re.sub(r"^http://", "https://", p["img"])} if p.get("img") else {})})
    # the same film/show shown again later the same week → keep the best/earliest airing
    best = {}
    for it in sorted(items, key=lambda x: (-x["score"], x["s"])):
        key = (it["kind"], re.sub(r"\W+", "", it["t"].lower()), it["st"].lower() if it["kind"] == "sport" else "")
        if key not in best:
            best[key] = it
    items = sorted(best.values(), key=lambda x: x["s"])
    de_sport = [i for i in items if i["kind"] == "sport" and i["ch"] not in FOREIGN]
    items = [i for i in items if not (i["kind"] == "sport" and i["ch"] in FOREIGN and
             any(abs(i["s"] - j["s"]) <= 2700 and i["label"] == j["label"] for j in de_sport))]
    # same event on several German-language channels at the same time (e.g. SRF zwei + ORF 1) → keep the best
    out = []
    for i in sorted(items, key=lambda x: -x["score"]):
        if any(j["kind"] == i["kind"] and j["label"] == i["label"] and abs(j["s"] - i["s"]) <= 1200 and
               j["ch"] != i["ch"] and similar(i["t"] + " " + i["st"], j["t"] + " " + j["st"]) for j in out):
            continue
        out.append(i)
    items = sorted(out, key=lambda x: x["s"])
    caps = {"sport": 60, "film": 60, "event": 25}
    keep = []
    for k, cap in caps.items():
        group = [i for i in items if i["kind"] == k]
        if len(group) > cap:
            cut = sorted(group, key=lambda x: -x["score"])[cap - 1]["score"]
            group = [i for i in group if i["score"] >= cut][:cap]
        keep += group
    keep.sort(key=lambda x: x["s"])
    doc = {"generated": now, "tv": keep, "mediathek": mediathek(now) if use_network else []}
    (ROOT / "highlights.json").write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote highlights.json: {sum(i['kind']=='film' for i in keep)} films, {sum(i['kind']=='sport' for i in keep)} sport, "
          f"{sum(i['kind']=='event' for i in keep)} shows, {len(doc['mediathek'])} mediathek")
    return doc

if __name__ == "__main__":
    if "--from-epg" in sys.argv:          # offline test with the existing epg.json
        j = json.loads((ROOT / "epg.json").read_text(encoding="utf-8"))
        build(j["channels"], use_network=False)
    else:
        print("run via build_epg.py (needs the XMLTV download), or with --from-epg for a quick offline test")
