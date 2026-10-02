// ==UserScript==
// @name         MyTV VPN Bridge
// @namespace    https://mistergeil.github.io/MyTV/
// @version      1.0.0
// @description  Lets MyTV ask the local MyTV VPN switcher (127.0.0.1:8765) to change the VPN country.
// @match        https://mistergeil.github.io/MyTV/*
// @grant        GM_xmlhttpRequest
// @connect      127.0.0.1
// @run-at       document-start
// @updateURL    https://mistergeil.github.io/MyTV/kiosk/mytv-vpn-bridge.user.js
// @downloadURL  https://mistergeil.github.io/MyTV/kiosk/mytv-vpn-bridge.user.js
// ==/UserScript==

(function () {
  'use strict';
  const AGENT = 'http://127.0.0.1:8765';

  // tell MyTV that the bridge exists (the <html> element may not exist yet at document-start)
  const mark = () => { if (!document.documentElement) return false; document.documentElement.dataset.mytvVpnBridge = '1'; return true; };
  if (!mark()) new MutationObserver((m, o) => { if (mark()) o.disconnect(); }).observe(document, { childList: true });

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

  window.addEventListener('message', async ev => {
    const d = ev.data;
    if (!d || d.mytvVpn !== 1 || ev.origin !== location.origin) return;
    let r;
    if (d.type === 'status') r = await call('/status', 3000);
    else if (d.type === 'set' && /^(DE|CH|OFF)$/.test(d.country)) r = await call('/vpn?c=' + d.country, 30000);
    else return;
    window.postMessage(Object.assign({ mytvVpn: 1, type: 'result', id: d.id }, r), location.origin);
  });
})();
