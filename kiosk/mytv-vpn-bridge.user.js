// ==UserScript==
// @name         MyTV VPN Bridge
// @namespace    https://mistergeil.github.io/MyTV/
// @version      1.5.0
// @description  Connects MyTV with the local MyTV switcher (127.0.0.1:8765): VPN country, favorites, iPhone remote commands; switches to another VPN server when a site says "VPN erkannt".
// @match        https://mistergeil.github.io/MyTV/*
// @match        https://www.livehdtv.net/*
// @match        https://livehdtv.net/*
// @match        https://www.srf.ch/play/*
// @match        https://www.rts.ch/play/*
// @match        https://www.rsi.ch/play/*
// @match        https://on.orf.at/*
// @match        https://www.joyn.de/*
// @match        https://plus.rtl.de/*
// @match        https://www.ardmediathek.de/*
// @match        https://www.zdf.de/*
// @match        https://www.arte.tv/*
// @match        https://www.3sat.de/*
// @grant        GM_xmlhttpRequest
// @grant        GM_getValue
// @grant        GM_setValue
// @connect      127.0.0.1
// @run-at       document-start
// @noframes
// @updateURL    https://mistergeil.github.io/MyTV/kiosk/mytv-vpn-bridge.user.js
// @downloadURL  https://mistergeil.github.io/MyTV/kiosk/mytv-vpn-bridge.user.js
// ==/UserScript==

(function () {
  'use strict';
  const AGENT = 'http://127.0.0.1:8765';
  const MYTV = 'https://mistergeil.github.io/MyTV/';
  const IS_MYTV = location.href.startsWith(MYTV);
  const IS_INDEX = IS_MYTV && /^\/MyTV\/(index\.html)?$/.test(location.pathname);

  function call(path, timeout) {
    return new Promise(resolve => {
      GM_xmlhttpRequest({
        method: 'GET', url: AGENT + path, timeout,
        onload: r => { try { resolve(JSON.parse(r.responseText)); } catch (e) { resolve({ ok: false, error: 'bad response' }); } },
        onerror: () => resolve({ ok: false, error: 'switcher not running' }),
        ontimeout: () => resolve({ ok: false, error: 'timeout' }),
      });
    });
  }

  // ---- VPN (MyTV pages only) ----
  if (IS_MYTV) {
    // tell MyTV that the bridge exists (the <html> element may not exist yet at document-start)
    const mark = () => { if (!document.documentElement) return false; document.documentElement.dataset.mytvVpnBridge = '1'; return true; };
    if (!mark()) new MutationObserver((m, o) => { if (mark()) o.disconnect(); }).observe(document, { childList: true });

    window.addEventListener('message', async ev => {
      const d = ev.data;
      if (!d || d.mytvVpn !== 1 || ev.origin !== location.origin) return;
      let r;
      if (d.type === 'status') r = await call('/status', 3000);
      else if (d.type === 'set' && /^(DE|CH|AT|OFF)$/.test(d.country)) r = await call('/vpn?c=' + d.country, 30000);
      else if (d.type === 'tvon') r = await call('/tv/on', 5000);
      else if (d.type === 'favs') r = await call('/favs', 3000);
      else if (d.type === 'state') r = await call('/ui?guide=' + (d.country === 'guide' ? 1 : 0), 2000);
      else return;
      window.postMessage(Object.assign({ mytvVpn: 1, type: 'result', id: d.id }, r), location.origin);
    });
  }

  // ---- MyTV overlay on a provider page (iframe, no bridge inside): relay what is on screen ----
  if (!IS_MYTV) {
    window.addEventListener('message', ev => {
      const d = ev.data;
      if (!d || d.mytvState !== 1 || ev.origin !== 'https://mistergeil.github.io') return;
      call('/ui?guide=' + (d.guide ? 1 : 0), 2000);
    });
  }

  // ---- "VPN erkannt" on Joyn / RTL+ / SRF / ORF → next server of the same country, reload ----
  // Servers: DE.conf, DE-2.conf, DE-3.conf ... on the notebook. Each server is tried once per 10 minutes.
  const SITE_COUNTRY = [[/(^|\.)joyn\.de$|(^|\.)plus\.rtl\.de$|(^|\.)ardmediathek\.de$|(^|\.)zdf\.de$|(^|\.)3sat\.de$|(^|\.)arte\.tv$/, 'DE'],
                        [/(^|\.)(srf|rts|rsi)\.ch$/, 'CH'], [/(^|\.)orf\.at$/, 'AT']];
  const SITE_C = (SITE_COUNTRY.find(([re]) => re.test(location.hostname)) || [])[1];
  const BLOCKED = /(vpn|proxy|anonymi[sz])[\s\S]{0,140}?(erkannt|festgestellt|entdeckt|detected|deaktivier|ausschalten|nicht (verfügbar|erlaubt|möglich))|(erkannt|festgestellt|entdeckt|detected)[\s\S]{0,140}?(vpn|proxy)|nur in (deutschland|der schweiz|österreich) verfügbar|only available in (germany|switzerland|austria)/i;
  function toast(t) {
    let el = document.getElementById('mytv-vpn-toast');
    if (!el) {
      el = document.createElement('div'); el.id = 'mytv-vpn-toast';
      el.style.cssText = 'position:fixed;left:50%;top:28px;transform:translateX(-50%);z-index:2147483647;max-width:min(760px,calc(100vw - 32px));' +
        'padding:16px 22px;border-radius:16px;background:rgba(12,14,18,.94);border:2px solid #ffcc33;color:#f2f2f2;font:600 18px/1.35 -apple-system,"Segoe UI",Roboto,sans-serif';
      (document.body || document.documentElement).appendChild(el);
    }
    el.textContent = t;
  }
  if (SITE_C && !IS_MYTV) {
    let handled = false;
    const t0 = Date.now();
    const scan = setInterval(async () => {
      if (handled || Date.now() - t0 > 120000) { clearInterval(scan); return; }
      const txt = document.body ? document.body.innerText.slice(0, 20000) : '';
      if (!BLOCKED.test(txt)) return;
      handled = true; clearInterval(scan);
      const st = await call('/status', 3000);
      if (!st.ok || st.country !== SITE_C) return;            // VPN off / other country: MyTV's normal switching handles that
      const of = (st.server && st.server.of) || 1;
      const key = 'vpnblock.' + SITE_C;
      let rec = GM_getValue(key, null);
      if (!rec || Date.now() - rec.t > 10 * 60e3) rec = { n: 0, t: Date.now() };
      if (of < 2) { toast('VPN erkannt – es gibt nur einen ' + SITE_C + '-Server. Weitere Proton-Konfigurationen als ' + SITE_C + '-2.conf, ' + SITE_C + '-3.conf … ablegen.'); return; }
      if (rec.n >= of - 1) { toast('VPN erkannt – alle ' + of + ' ' + SITE_C + '-Server sind gerade blockiert. Später nochmal versuchen oder neue Server-Konfigurationen holen.'); GM_setValue(key, null); return; }
      rec.n++; GM_setValue(key, rec);
      toast('VPN erkannt – wechsle den ' + SITE_C + '-Server (' + rec.n + '/' + (of - 1) + ') …');
      const r = await call('/vpn/next?c=' + SITE_C, 35000);
      if (r.ok) { toast('Neuer Server: ' + ((r.server && r.server.name) || '') + ' – lade neu …'); setTimeout(() => location.reload(), 1200); }
      else toast('Serverwechsel fehlgeschlagen: ' + (r.error || 'unbekannt'));
    }, 2000);
  }

  // ---- iPhone remote: pick up commands from the switcher and act on them ----
  function pressKey(k) {
    const target = (document.activeElement && document.activeElement !== document.body) ? document.activeElement : document;
    target.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
  }
  function run(c) {
    if (c.do === 'key') return pressKey(c.k);
    if (c.do === 'ch') {
      if (IS_INDEX) window.postMessage({ mytvRemote: 1, do: 'ch', n: +c.n }, location.origin);
      else location.replace(MYTV + '?kiosk=1&ch=' + (+c.n));
      return;
    }
    if (c.do === 'favs') {                 // favorites changed on the iPhone → MyTV re-sorts its lists
      if (IS_MYTV) window.postMessage({ mytvRemote: 1, do: 'favs' }, location.origin);
      return;
    }
    if (c.do === 'on') {
      if (IS_INDEX) window.postMessage({ mytvRemote: 1, do: 'on' }, location.origin);
      // on a channel / in the Mediathek MyTV is already "on" → nothing to do
    }
  }
  let busy = false;
  async function poll() {
    if (busy) return; busy = true;
    try {
      const boot = GM_getValue('remote.boot', ''), seq = GM_getValue('remote.seq', 0);
      const r = await call('/cmd/since?seq=' + seq + '&boot=' + encodeURIComponent(boot), 2000);
      if (!r.ok || !r.boot) return;
      if (r.boot !== boot) { GM_setValue('remote.boot', r.boot); GM_setValue('remote.seq', 0); }
      let last = r.boot !== boot ? 0 : seq;
      for (const c of r.cmds || []) {
        if (c.seq <= last) continue;
        last = c.seq; GM_setValue('remote.seq', last);       // remember first → a page change can't run it twice
        if (c.age <= 6) run(c);
      }
      if (r.seq > last) GM_setValue('remote.seq', r.seq);
    } finally { busy = false; }
  }
  const start = () => setInterval(poll, 400);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
