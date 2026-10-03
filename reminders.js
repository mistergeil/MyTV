// MyTV reminders — shared by MyTV (index.html, also as overlay on Joyn/RTL+/ORF) and the Mediathek.
// Stored on this device in localStorage: [{ ch, chName, title, start, end, mode: 'remind' | 'auto' }]
//   remind → 1 min before: banner "OK = umschalten" (30 s)
//   auto   → switches by itself shortly before the start
//   MyTV in standby (or mode auto) → the TV is switched on first (SmartThings routine via the switcher)
(function () {
  'use strict';
  const KEY = 'mytv.reminders';
  const same = (a, b) => a.ch === b.ch && a.start === b.start;
  let hooks = {}, banner = null, bannerRem = null, bannerT = null;

  const R = window.MyTVReminders = {
    list() { try { return JSON.parse(localStorage.getItem(KEY) || '[]'); } catch (e) { return []; } },
    save(l) { try { localStorage.setItem(KEY, JSON.stringify(l)); } catch (e) {} },
    get(ch, start) { return R.list().find(r => r.ch === ch && r.start === start) || null; },
    add(r) { R.save(R.list().filter(x => !same(x, r)).concat([r])); },
    remove(ch, start) { R.save(R.list().filter(x => !(x.ch === ch && x.start === start))); },
    // mark a step as done in the shared list → each step runs only once, even across page changes
    take(r, step) {
      const l = R.list(), x = l.find(y => same(y, r));
      if (!x || x[step]) return false;
      x[step] = Date.now(); R.save(l); return true;
    },
    // pages call this first in their key handler; true = key was used by the reminder banner
    bannerKey(k) {
      if (!banner || banner.style.display === 'none') return false;
      if (k === 'Enter') { const r = bannerRem; hideBanner(); if (hooks.switchTo) hooks.switchTo(r); return true; }
      if (k === 'Escape' || k === 'Backspace' || k === 'BrowserBack') { hideBanner(); return true; }
      return false;
    },
    start(h) { hooks = h || {}; setTimeout(tick, 1500); setInterval(tick, 5000); },
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

  function tick() {
    const now = Date.now();
    let l = R.list();
    const keep = l.filter(r => r.start > now - 15 * 60e3);           // forget old ones
    if (keep.length !== l.length) { R.save(keep); l = keep; }
    const standby = !!(hooks.isStandby && hooks.isStandby());
    for (const r of l) {
      if (now > r.start + 10 * 60e3) continue;
      const wake = r.mode === 'auto' || standby;
      // 1) TV on (≈ 90 s before, so it has time to start)
      if (wake && now >= r.start - 90e3 && hooks.tvOn && R.take(r, 'tvOn')) hooks.tvOn(r);
      // 2) switch / remind
      if (wake) {
        if (now >= r.start - 20e3 && R.take(r, 'done') && hooks.switchTo) hooks.switchTo(r);
      } else if (now >= r.start - 60e3 && R.take(r, 'done')) {
        showBanner(r);
      }
    }
  }
})();
