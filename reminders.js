// MyTV reminders — shared by MyTV (index.html, also as overlay on Joyn/RTL+/ORF/livehdtv) and the Mediathek.
// The list lives on the notebook (switcher: reminders.json), reached through the MyTV Bridge:
// Chrome keeps separate browser storage per website, so the MyTV overlay on every channel page
// would otherwise have its own private list. A local copy is kept only as a cache / offline fallback.
//   item: { ch, chName, title, start, end, mode: 'remind' | 'auto' }
//   remind → 1 min before: banner "OK = umschalten"
//   auto   → switches by itself shortly before the start
//   MyTV in standby (or mode auto) → the TV is switched on first (SmartThings routine via the switcher)
(function () {
  'use strict';
  const KEY = 'mytv.reminders';
  const same = (a, b) => a.ch === b.ch && a.start === b.start;
  let hooks = {}, banner = null, bannerRem = null, bannerT = null;
  let cache = []; try { cache = JSON.parse(localStorage.getItem(KEY) || '[]'); } catch (e) {}
  const saveCache = l => { cache = l; try { localStorage.setItem(KEY, JSON.stringify(l)); } catch (e) {} };

  // ---- talk to the notebook: directly via the bridge (top-level MyTV) or through the provider page (overlay) ----
  const inOverlay = window.parent !== window && /[?&]overlay=1/.test(location.search);
  const hasBridge = () => document.documentElement.dataset.mytvVpnBridge === '1';
  let seq = 0; const pending = new Map();
  window.addEventListener('message', ev => {
    const d = ev.data; if (!d) return;
    if ((d.mytvAgentRes === 1 && ev.source === window.parent) || (d.mytvVpn === 1 && d.type === 'result' && ev.origin === location.origin)) {
      const f = pending.get(d.id); if (f) { pending.delete(d.id); f(d); }
    }
  });
  function agent(path) {
    return new Promise(res => {
      const id = 'r' + (++seq) + '_' + Date.now();
      if (inOverlay) { pending.set(id, res); window.parent.postMessage({ mytvAgent: 1, id, path }, '*'); }
      else if (hasBridge()) { pending.set(id, res); window.postMessage({ mytvVpn: 1, type: 'agent', path, id }, location.origin); }
      else return res(null);
      setTimeout(() => { if (pending.has(id)) { pending.delete(id); res(null); } }, 5000);
    });
  }
  let online = false;      // true once the notebook answered → it is the source of truth
  async function sync() {
    const r = await agent('/rem');
    if (!r || !r.ok) return false;
    let list = r.list || [];
    if (!online) {
      // first contact: move reminders that were only stored in this page's browser storage to the notebook
      const local = cache.filter(x => x.start > Date.now() - 15 * 60e3 && !list.some(y => same(x, y)));
      for (const x of local) { const a = await add(x, true); if (a) list = a; }
      online = true;
    }
    saveCache(list);
    if (hooks.changed) hooks.changed();
    return true;
  }
  const q = r => `ch=${r.ch}&start=${r.start}`;
  async function add(r, quiet) {
    const a = await agent(`/rem/add?${q(r)}&end=${r.end}&mode=${r.mode}&chName=${encodeURIComponent(r.chName || '')}&title=${encodeURIComponent(r.title || '')}`);
    return a && a.ok ? a.list : null;
  }

  const R = window.MyTVReminders = {
    list() { return cache.slice(); },
    get(ch, start) { return cache.find(r => r.ch === ch && r.start === start) || null; },
    add(r) {
      saveCache(cache.filter(x => !same(x, r)).concat([r]));          // show it right away
      add(r).then(l => { if (l) { online = true; saveCache(l); if (hooks.changed) hooks.changed(); } });
    },
    remove(ch, start) {
      saveCache(cache.filter(x => !(x.ch === ch && x.start === start)));
      agent(`/rem/del?ch=${ch}&start=${start}`).then(a => { if (a && a.ok) { saveCache(a.list || []); if (hooks.changed) hooks.changed(); } });
    },
    sync,
    // each step (tvOn / done) runs exactly once, whichever page asks first (decided on the notebook)
    async take(r, step) {
      if (online) {
        const a = await agent(`/rem/take?${q(r)}&step=${step}`);
        if (a && a.ok) { saveCache(a.list || []); return !!a.took; }
      }
      const l = cache, x = l.find(y => same(y, r));                   // offline fallback: this page only
      if (!x || x[step]) return false;
      x[step] = Date.now(); saveCache(l); return true;
    },
    // pages call this first in their key handler; true = key was used by the reminder banner
    bannerKey(k) {
      if (!banner || banner.style.display === 'none') return false;
      if (k === 'Enter') { const r = bannerRem; hideBanner(); if (hooks.switchTo) hooks.switchTo(r); return true; }
      if (k === 'Escape' || k === 'Backspace' || k === 'BrowserBack') { hideBanner(); return true; }
      return false;
    },
    start(h) { hooks = h || {}; setTimeout(sync, 800); setInterval(sync, 30000); setTimeout(tick, 1500); setInterval(tick, 5000); },
  };

  const hm = t => new Date(t).toLocaleTimeString('de-CH', { hour: '2-digit', minute: '2-digit' });
  function showBanner(r) {
    if (!banner) {
      banner = document.createElement('div');
      banner.style.cssText = 'position:fixed;left:50%;top:max(24px,5vh);transform:translateX(-50%);z-index:2147483647;max-width:min(60vw,1100px);min-width:min(420px,90vw);' +
        'padding:1.4vw 1.8vw;border-radius:28px;background:rgba(24,24,28,.82);-webkit-backdrop-filter:blur(40px) saturate(180%);backdrop-filter:blur(40px) saturate(180%);' +
        'border:1px solid rgba(255,255,255,.08);color:#fff;font:600 clamp(16px,1.2vw,32px)/1.35 Inter,-apple-system,"Segoe UI",Roboto,sans-serif;box-shadow:0 2vw 5vw rgba(0,0,0,.6)';
      banner.addEventListener('click', () => R.bannerKey('Enter'));
      document.body.appendChild(banner);
    }
    const esc = s => String(s || '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
    banner.innerHTML = `<div style="color:#ff9f0a;font-size:.8em;font-weight:700">🔔 Erinnerung · ${hm(r.start)}</div>
      <div style="font-size:1.45em;font-weight:800;letter-spacing:-.02em;margin:.15em 0">${esc(r.title)}</div>
      <div style="color:rgba(235,235,245,.62);font-size:.85em">${r.ch} ${esc(r.chName)} · <b style="color:#fff">OK</b> umschalten · Zurück schliessen</div>`;
    banner.style.display = 'block';
    bannerRem = r;
    clearTimeout(bannerT); bannerT = setTimeout(hideBanner, 45000);
  }
  function hideBanner() { if (banner) banner.style.display = 'none'; bannerRem = null; clearTimeout(bannerT); }

  let ticking = false;
  async function tick() {
    if (ticking) return; ticking = true;
    try {
      const now = Date.now();
      const l = cache.filter(r => r.start > now - 15 * 60e3);
      const standby = !!(hooks.isStandby && hooks.isStandby());
      for (const r of l) {
        if (now > r.start + 10 * 60e3) continue;
        const wake = r.mode === 'auto' || standby;
        // 1) TV on (≈ 90 s before, so it has time to start)
        if (wake && now >= r.start - 90e3 && !r.tvOn && hooks.tvOn && await R.take(r, 'tvOn')) hooks.tvOn(r);
        // 2) switch / remind
        if (wake) {
          if (now >= r.start - 20e3 && !r.done && await R.take(r, 'done') && hooks.switchTo) hooks.switchTo(r);
        } else if (now >= r.start - 60e3 && !r.done && await R.take(r, 'done')) {
          showBanner(r);
        }
      }
    } finally { ticking = false; }
  }
})();
