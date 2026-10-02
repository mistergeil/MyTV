// ==UserScript==
// @name         MyTV Helper
// @namespace    https://mistergeil.github.io/MyTV/
// @version      1.0.0
// @description  Makes external channels opened from MyTV behave like the TV: full screen, autoplay, remote keys.
// @match        https://www.livehdtv.net/*
// @match        https://livehdtv.net/*
// @run-at       document-start
// @grant        none
// @updateURL    https://mistergeil.github.io/MyTV/kiosk/mytv-helper.user.js
// @downloadURL  https://mistergeil.github.io/MyTV/kiosk/mytv-helper.user.js
// ==/UserScript==

/*
 * Only active when the page was opened by MyTV (top URL has #mytv=<number>&n=<name>).
 * Normal browsing of the site is left untouched.
 * It only restyles the page and presses play — exactly what you'd do by hand.
 */
(function () {
  'use strict';

  const MYTV = 'https://mistergeil.github.io/MyTV/';

  // ---- Are we in a MyTV session? (works in nested same-origin frames too) ----
  let topHash = '';
  try { topHash = window.top.location.hash; } catch (e) { return; }
  const m = /mytv=(\d+)(?:&n=([^&]*))?/.exec(topHash);
  if (!m) return;
  const CH = parseInt(m[1], 10);
  const NAME = decodeURIComponent(m[2] || '');
  const isTop = window.top === window;

  // ---- Full-screen styling in every frame ----
  const css = `
    html, body { margin:0 !important; padding:0 !important; width:100% !important; height:100% !important;
                 background:#000 !important; overflow:hidden !important; cursor:none !important; }
    body > a, body > p, body > h1, body > h2, body > h3 { display:none !important; }
    iframe { position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important;
             border:0 !important; z-index:1 !important; }
    .jwplayer { position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important; }
  `;
  function addStyle() {
    const s = document.createElement('style');
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }
  if (document.documentElement) addStyle(); else document.addEventListener('DOMContentLoaded', addStyle);

  // ---- Navigation back into MyTV (always replace → no history pile-up) ----
  function go(q) { window.top.location.replace(MYTV + '?kiosk=1&' + q); }

  // ---- Remote / keyboard ----
  let digits = '', digitTimer = null;
  function onKey(e) {
    const k = e.key;
    let handled = true;
    if (/^[0-9]$/.test(k)) {
      digits = (digits + k).slice(-3);
      osd(digits, '');
      clearTimeout(digitTimer);
      digitTimer = setTimeout(() => go('ch=' + parseInt(digits, 10) + '&from=' + CH), 1200);
    } else if (k === 'ArrowUp' || k === 'PageUp' || k === 'ChannelUp') {
      go('from=' + CH + '&step=1');
    } else if (k === 'ArrowDown' || k === 'PageDown' || k === 'ChannelDown') {
      go('from=' + CH + '&step=-1');
    } else if (k === 'Backspace' || k === 'BrowserBack' || k === 'Escape') {
      go('back=1&from=' + CH);
    } else if (k === 'l' || k === 'L' || k === 'ContextMenu') {
      go('back=1&from=' + CH + '&list=1');
    } else if (k === 'i' || k === 'I') {
      osd(CH, NAME);
    } else if (k === 'm' || k === 'M') {
      withPlayer(p => p.setMute(!p.getMute()));
    } else if (k === '+' || k === '=' || k === 'ArrowRight' || k === 'AudioVolumeUp') {
      withPlayer(p => { p.setMute(false); p.setVolume(Math.min(100, p.getVolume() + 10)); });
      if (k.startsWith('Audio')) handled = false;
    } else if (k === '-' || k === '_' || k === 'ArrowLeft' || k === 'AudioVolumeDown') {
      withPlayer(p => p.setVolume(Math.max(0, p.getVolume() - 10)));
      if (k.startsWith('Audio')) handled = false;
    } else {
      handled = false;
    }
    if (handled) { e.preventDefault(); e.stopImmediatePropagation(); }
  }
  // capture phase so JW Player's own shortcuts (arrows = seek/volume) don't fire
  window.addEventListener('keydown', onKey, true);

  // ---- Find the JW Player in whichever frame it lives ----
  function findPlayer(w) {
    try {
      if (w.jwplayer && w.document.querySelector('.jwplayer')) return w.jwplayer();
      for (let i = 0; i < w.frames.length; i++) { const p = findPlayer(w.frames[i]); if (p) return p; }
    } catch (e) {}
    return null;
  }
  function withPlayer(fn) { const p = findPlayer(window.top); if (p) try { fn(p); } catch (e) {} }

  // ---- On-screen display (top frame only) ----
  let osdEl = null, osdTimer = null;
  function osd(num, name, sticky) {
    const doc = window.top.document;
    if (!doc.body) return;
    if (!osdEl || !doc.body.contains(osdEl)) {
      osdEl = doc.createElement('div');
      osdEl.style.cssText = 'position:fixed;top:24px;left:24px;z-index:2147483647;display:flex;align-items:center;gap:16px;' +
        'padding:14px 22px 14px 16px;background:rgba(12,14,18,.88);border:1px solid rgba(255,255,255,.1);border-radius:14px;' +
        'font:600 22px -apple-system,Segoe UI,Roboto,sans-serif;color:#f2f2f2;transition:opacity .3s;pointer-events:none';
      doc.body.appendChild(osdEl);
    }
    const time = new Date().toLocaleTimeString('de-CH', { hour: '2-digit', minute: '2-digit' });
    osdEl.innerHTML = `<span style="font-size:44px;font-weight:700;color:#ffcc33;line-height:1">${num}</span>` +
      (name ? `<span style="display:flex;flex-direction:column;gap:4px"><span>${name}</span>` +
              `<span style="font-size:14px;font-weight:400;color:#9aa0a6">${time}</span></span>` : '');
    osdEl.style.opacity = '1';
    clearTimeout(osdTimer);
    if (!sticky) osdTimer = setTimeout(() => { osdEl.style.opacity = '0'; }, 4000);
  }

  // ---- Autoplay with sound (top frame drives it) ----
  if (isTop) {
    const showFirst = () => osd(CH, NAME);
    if (document.body) showFirst(); else document.addEventListener('DOMContentLoaded', showFirst);

    let tries = 0, started = false;
    const timer = setInterval(() => {
      tries++;
      const p = findPlayer(window);
      if (p && typeof p.getState === 'function') {
        const st = p.getState();
        if (st === 'playing' || st === 'buffering') {
          if (!started) { started = true; try { p.setMute(false); if (p.getVolume() < 10) p.setVolume(100); } catch (e) {} }
        } else if (st === 'error') {
          clearInterval(timer);
          osd(CH, NAME + ' — kein Signal (↑/↓ zum Weiterschalten)', true);
        } else if (!started || st === 'idle' || st === 'paused') {
          try { p.setMute(false); p.play(); } catch (e) {}
        }
      }
      if (tries > 40) {           // ~20 s
        clearInterval(timer);
        if (!started) osd(CH, NAME + ' — kein Signal (↑/↓ zum Weiterschalten)', true);
      }
    }, 500);

  }
})();
