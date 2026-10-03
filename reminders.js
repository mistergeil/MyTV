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
      banner.style.cssText = 'position:fixed;left:50%;top:28px;transform:translateX(-50%);z-index:2147483647;max-width:min(760px,calc(100vw - 32px));' +
        'padding:16px 22px;border-radius:16px;background:rgba(12,14,18,.94);border:2px solid #ffcc33;color:#f2f2f2;' +
        'font:600 17px/1.35 -apple-system,"Segoe UI",Roboto,sans-serif;box-shadow:0 12px 40px rgba(0,0,0,.6)';
      banner.addEventListener('click', () => R.bannerKey('Enter'));
      document.body.appendChild(banner);
    }
    const esc = s => String(s || '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
    banner.innerHTML = `<div style="color:#ffcc33;font-size:13px;font-weight:800;letter-spacing:.06em">🔔 ERINNERUNG · ${hm(r.start)}</div>
      <div style="font-size:21px;font-weight:800;margin:4px 0 2px">${esc(r.title)}</div>
      <div style="color:#9aa0a6">${r.ch} ${esc(r.chName)} · <b style="color:#f2f2f2">OK</b> = umschalten · Zurück = schliessen</div>`;
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
