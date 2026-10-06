// ==UserScript==
// @name         MyTV VPN Bridge
// @namespace    https://mistergeil.github.io/MyTV/
// @version      1.9.0
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

  // generic pipe (since 1.9): any path on the local switcher (127.0.0.1:8765 only, never anything else), so new
  // features need no new bridge version. The update / settings endpoints are not here - they live on the LAN port with a key.
  const PIPE_PATH = /^\/[A-Za-z0-9_\-\/]{1,60}(\?[^#\s]{0,1500})?$/;
  const pipeOk = p => typeof p === 'string' && PIPE_PATH.test(p) && !p.includes('..') && !p.includes('//');
  // shared data on the notebook (favorites, reminders) - the only paths MyTV may read/write through the bridge
  const DATA_PATH = /^\/(favs|rem)(\/(add|del|take))?(\?[^#]*)?$/;

  // ---- VPN (MyTV pages only) ----
  if (IS_MYTV) {
    // tell MyTV that the bridge exists (the <html> element may not exist yet at document-start)
    const mark = () => { if (!document.documentElement) return false; const ds = document.documentElement.dataset; ds.mytvVpnBridge = '1'; ds.mytvPipe = '1'; ds.mytvBridgeVersion = '1.9.0'; return true; };
    if (!mark()) new MutationObserver((m, o) => { if (mark()) o.disconnect(); }).observe(document, { childList: true });

    window.addEventListener('message', async ev => {
      const d = ev.data;
      if (!d || d.mytvVpn !== 1 || ev.origin !== location.origin) return;
      let r;
      if (d.type === 'status') r = await call('/status', 3000);
      else if (d.type === 'set' && /^(DE|CH|AT|OFF)$/.test(d.country)) r = await call('/vpn?c=' + d.country, 30000);
      else if (d.type === 'tvon') r = await call('/tv/on', 5000);
      else if (d.type === 'favs') r = await call('/favs', 3000);
      else if (d.type === 'agent' && DATA_PATH.test(d.path || '')) r = await call(d.path, 4000);
      else if (d.type === 'pipe' && pipeOk(d.path)) r = await call(d.path, Math.min(+d.timeout || 8000, 40000));
      else if (d.type === 'state') r = await call('/ui?guide=' + (d.country === 'guide' ? 1 : 0), 2000);
      else return;
      window.postMessage(Object.assign({ mytvVpn: 1, type: 'result', id: d.id }, r), location.origin);
    });
  }

  // ---- MyTV overlay on a provider page (iframe, no bridge inside): relay screen state + favorites ----
  const OV = 'https://mistergeil.github.io';
  async function pushFavs(target) {
    const r = await call('/favs', 3000);
    if (!r.ok) return;
    const frames = target ? [target] : [...document.querySelectorAll('iframe')].map(f => f.contentWindow).filter(Boolean);
    frames.forEach(w => { try { w.postMessage({ mytvFavs: 1, favs: r.favs || [] }, OV); } catch (e) {} });
  }
  if (!IS_MYTV) {
    window.addEventListener('message', ev => {
      const d = ev.data;
      if (!d || ev.origin !== OV) return;
      if (d.mytvState === 1) call('/ui?guide=' + (d.guide ? 1 : 0), 2000);
      if (d.mytvFavsReq === 1) pushFavs(ev.source);
      if (d.mytvPipe === 1 && pipeOk(d.path)) {                       // generic pipe for the MyTV overlay
        call(d.path, Math.min(+d.timeout || 8000, 40000)).then(r => { try { ev.source.postMessage(Object.assign({ mytvPipeRes: 1, id: d.id }, r), OV); } catch (e) {} });
      }
      if (d.mytvAgent === 1 && DATA_PATH.test(d.path || '')) {       // MyTV overlay asks for shared data
        call(d.path, 4000).then(r => { try { ev.source.postMessage(Object.assign({ mytvAgentRes: 1, id: d.id }, r), OV); } catch (e) {} });
      }
    });
  }

  // ---- "VPN erkannt" on Joyn / RTL+ / SRF / ORF → next server of the same country, reload ----
  // Servers: DE.conf, DE-2.conf, DE-3.conf ... on the notebook. Each server is tried once per 10 minutes.
  const SITE_COUNTRY = [[/(^|\.)joyn\.de$|(^|\.)plus\.rtl\.de$|(^|\.)ardmediathek\.de$|(^|\.)zdf\.de$|(^|\.)3sat\.de$|(^|\.)arte\.tv$/, 'DE'],
                        [/(^|\.)(srf|rts|rsi)\.ch$/, 'CH'], [/(^|\.)orf\.at$/, 'AT']];
  const SITE_C = (SITE_COUNTRY.find(([re]) => re.test(location.hostname)) || [])[1];
  const BLOCKED = /(vpn|proxy|anonymi[sz])[\s\S]{0,140}?(erkannt|festgestellt|entdeckt|detected|deaktivier|ausschalten|nicht (verfügbar|erlaubt|möglich))|(erkannt|festgestellt|entdeckt|detected|deaktiviere|schalte)[\s\S]{0,140}?(vpn|proxy)|nur in (deutschland|der schweiz|österreich) verfügbar|only available in (germany|switzerland|austria)/i;
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
    if (c.do === 'reload') {               // "Anderer Server" on the remote → reload what is playing
      if (IS_INDEX) window.postMessage({ mytvRemote: 1, do: 'reload' }, location.origin);
      else location.reload();
      return;
    }
    if (c.do === 'favs') {                 // favorites changed on the iPhone → MyTV re-sorts its lists
      if (IS_MYTV) window.postMessage({ mytvRemote: 1, do: 'favs' }, location.origin);
      else pushFavs();                     // MyTV overlay on Joyn / RTL+ / ORF
      return;
    }
    if (c.do === 'on') {
      if (IS_INDEX) window.postMessage({ mytvRemote: 1, do: 'on' }, location.origin);
      // on a channel / in the Mediathek MyTV is already "on" → nothing to do
      return;
    }
    // generic pipe: anything else from the remote goes straight to MyTV (page or overlay) - new remote buttons need no bridge update
    const msg = Object.assign({}, c, { mytvRemote: 1, pipe: 1 });
    if (IS_MYTV) window.postMessage(msg, location.origin);
    else document.querySelectorAll('iframe').forEach(f => { try { f.contentWindow.postMessage(msg, OV); } catch (e) {} });
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
