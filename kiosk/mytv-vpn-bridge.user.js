// ==UserScript==
// @name         MyTV VPN Bridge
// @namespace    https://mistergeil.github.io/MyTV/
// @version      1.2.0
// @description  Connects MyTV with the local MyTV switcher (127.0.0.1:8765): VPN country + iPhone remote commands.
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
      else return;
      window.postMessage(Object.assign({ mytvVpn: 1, type: 'result', id: d.id }, r), location.origin);
    });
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
