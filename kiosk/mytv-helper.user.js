// ==UserScript==
// @name         MyTV Helper
// @namespace    https://mistergeil.github.io/MyTV/
// @version      1.5.0
// @description  Makes external channels opened from MyTV behave like the TV: full screen, autoplay, remote keys.
// @match        https://www.livehdtv.net/*
// @match        https://livehdtv.net/*
// @match        https://www.srf.ch/play/embed*
// @match        https://www.rts.ch/play/embed*
// @match        https://www.rsi.ch/play/embed*
// @match        https://on.orf.at/*
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

  const IS_SRG = /(^|\.)(srf|rts|rsi)\.ch$/.test(location.hostname);
  const IS_ORF = location.hostname === 'on.orf.at';
  const IS_OFFICIAL = IS_SRG || IS_ORF;            // official broadcaster player pages (plain <video>)

  // ---- Official SRG player (SRF/RTS/RSI) framed inside MyTV (legacy path) ----
  if (IS_SRG && window.top !== window) {
    const MYTV_ORIGIN = new URL(MYTV).origin;
    // Remote keys → MyTV (so ↑/↓, digits, G, L … keep working after a click into the player)
    const PASS = /^(Arrow(Up|Down)|Page(Up|Down)|[0-9]|Backspace|BrowserBack|Escape|Enter|[gGlLiImMvVfF?+=_-])$/;
    window.addEventListener('keydown', e => {
      if (e.ctrlKey || e.altKey || e.metaKey || !PASS.test(e.key)) return;
      window.parent.postMessage({ mytv: 1, type: 'key', key: e.key }, MYTV_ORIGIN);
      e.preventDefault(); e.stopImmediatePropagation();
    }, true);
    // Mouse over the player → show MyTV's remote bar
    let lastWake = 0;
    const wake = () => { const n = Date.now(); if (n - lastWake > 400) { lastWake = n; window.parent.postMessage({ mytv: 1, type: 'wake' }, MYTV_ORIGIN); } };
    ['mousemove', 'mousedown', 'touchstart', 'wheel'].forEach(ev => window.addEventListener(ev, wake, { passive: true, capture: true }));
    // Autoplay — careful: the player's play button is a play/pause TOGGLE, so never click it
    // once the stream has started. Prefer video.play(); click only as a last resort.
    let started = false, clicked = 0, tries = 0, hooked = null;
    const hook = v => {
      if (hooked === v) return; hooked = v;
      v.addEventListener('playing', () => { started = true; });
      // TV never pauses: if the live stream stops by itself, resume it
      v.addEventListener('pause', () => {
        if (!started) return;
        setTimeout(() => { if (v.paused && !v.ended) v.play().catch(() => {}); }, 400);
      });
    };
    const t = setInterval(() => {
      tries++;
      const v = document.querySelector('video');
      if (v) hook(v);
      if (started || (v && !v.paused)) { started = true; clearInterval(t); return; }
      if (v) { v.play().catch(() => { v.muted = true; v.play().catch(() => {}); }); }
      // still nothing after ~4 s: click the big start button once (and once more after ~10 s)
      if ((tries === 8 || tries === 20) && clicked < 2 && (!v || v.paused)) {
        const btn = document.querySelector('button[aria-label*="Play" i], button[aria-label*="Abspielen" i], button[aria-label*="Lire" i], button[aria-label*="Riprodu" i], [class*="big-play" i], [class*="BigPlay" i]');
        if (btn) { btn.click(); clicked++; }
      }
      if (tries > 50) clearInterval(t);
    }, 500);
    return;
  }

  // ---- Are we in a MyTV session? (works in nested same-origin frames too) ----
  let topHash = '';
  try { topHash = window.top.location.hash; } catch (e) { return; }
  const RX = /mytv=(\d+)(?:&n=([^&]*))?/;
  let m = RX.exec(topHash);
  if (IS_ORF && window.top === window) {          // ORF ON drops the hash → remember it for this tab
    try {
      if (m) sessionStorage.setItem('mytv.session', topHash);
      else { const saved = sessionStorage.getItem('mytv.session'); if (saved) m = RX.exec(saved); }
    } catch (e) {}
  }
  if (!m) return;
  const CH = parseInt(m[1], 10);
  const NAME = decodeURIComponent(m[2] || '');
  const isTop = window.top === window;

  // ---- Full-screen styling in every frame ----
  const css = `
    html, body { margin:0 !important; padding:0 !important; width:100% !important; height:100% !important;
                 background:#000 !important; overflow:hidden !important; }
    #mytv-overlay { position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important;
                    border:0 !important; z-index:2147483646 !important; background:transparent !important; color-scheme:normal !important; }
  ` + (IS_ORF ? `
    .player-area-player { position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important;
                          max-width:none !important; max-height:none !important; margin:0 !important; padding:0 !important;
                          z-index:2147483000 !important; background:#000 !important; }
    .player-area-player > div { width:100% !important; height:100% !important; }
    .player-area-player video { width:100% !important; height:100% !important; object-fit:contain !important; }
  ` : '') + (IS_OFFICIAL ? '' : `
    html, body { cursor:none !important; }
    body > a, body > p, body > h1, body > h2, body > h3 { display:none !important; }
    iframe { position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important;
             border:0 !important; z-index:1 !important; }
    .jwplayer { position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important; }
  `);
  function addStyle() {
    const s = document.createElement('style');
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }
  if (document.documentElement) addStyle(); else document.addEventListener('DOMContentLoaded', addStyle);

  // ---- Navigation back into MyTV (always replace → no history pile-up) ----
  function go(q) { window.top.location.replace(MYTV + '?kiosk=1&' + q); }

  // ---- MyTV overlay: the real MyTV interface (remote bar, list, guide, volume, info)
  //      loaded transparently on top of the player. Keys are forwarded to it. ----
  const OV_ORIGIN = new URL(MYTV).origin;
  function overlayWin() {
    try { const f = window.top.__mytvOv; return window.top.__mytvOvReady && f && f.contentWindow; } catch (e) { return null; }
  }

  // ---- Remote / keyboard ----
  let digits = '', digitTimer = null;
  function onKey(e) {
    const k = e.key;
    let handled = true;
    const ov = overlayWin();
    if (ov && !e.ctrlKey && !e.altKey && !e.metaKey && !k.startsWith('Audio')) {
      ov.postMessage({ mytv: 1, type: 'key', key: k }, OV_ORIGIN);
      e.preventDefault(); e.stopImmediatePropagation();
      return;
    }
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
    } else if (k === 'g' || k === 'G' || k === 'Guide') {
      go('back=1&from=' + CH + '&guide=1');
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

  // ---- Find the player: JW Player (livehdtv, any same-origin frame) or a plain <video> (SRG) ----
  function videoAdapter(v) {
    return {
      getState() { if (v.error) return 'error'; if (!v.paused && !v.ended) return v.readyState > 2 ? 'playing' : 'buffering'; return 'paused'; },
      play() { v.play().catch(() => {}); },
      setMute(b) { v.muted = !!b; }, getMute() { return v.muted; },
      setVolume(x) { v.volume = Math.max(0, Math.min(1, x / 100)); }, getVolume() { return Math.round(v.volume * 100); },
    };
  }
  function pickVideo() {
    const vs = [...document.querySelectorAll('video')];
    return vs.find(v => !v.paused) || vs.find(v => v.currentSrc) || vs[0] || null;
  }
  function findPlayer(w) {
    try {
      if (w.jwplayer && w.document.querySelector('.jwplayer')) return w.jwplayer();
      for (let i = 0; i < w.frames.length; i++) { const p = findPlayer(w.frames[i]); if (p) return p; }
      if (IS_OFFICIAL && w === window.top) { const v = pickVideo(); if (v) return videoAdapter(v); }
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
    let wantSound = null;                       // {muted, volume 0..1} from MyTV
    const applySound = p => { if (!wantSound) return; try { p.setMute(!!wantSound.muted); p.setVolume(Math.round(wantSound.volume * 100)); } catch (e) {} };

    const consentOpen = () => IS_ORF && document.body && document.body.classList.contains('didomi-popup-open');
    function mountOverlay() {
      if (window.__mytvOv) return;
      if (consentOpen()) {
        osd(CH, NAME + ' — bitte zuerst die Cookie-Auswahl mit der Maus treffen (nur einmal)', true);
        setTimeout(mountOverlay, 1000);
        return;
      }
      if (osdEl) osdEl.style.opacity = '0';
      const f = document.createElement('iframe');
      f.id = 'mytv-overlay';
      f.src = MYTV + '?overlay=1&ch=' + CH;
      f.setAttribute('allowtransparency', 'true');
      f.allow = 'fullscreen';
      document.body.appendChild(f);
      window.__mytvOv = f;
      // fallback: if the overlay doesn't come up, show the simple badge
      setTimeout(() => { if (!window.__mytvOvReady) osd(CH, NAME); }, 4000);
    }
    if (document.body) mountOverlay(); else document.addEventListener('DOMContentLoaded', mountOverlay);

    window.addEventListener('message', ev => {
      if (ev.origin !== OV_ORIGIN) return;
      const d = ev.data;
      if (!d || d.mytv !== 1) return;
      if (d.type === 'ready') window.__mytvOvReady = true;
      else if (d.type === 'tune') go('ch=' + d.number + '&from=' + CH);
      else if (d.type === 'back') go('back=1&from=' + CH);
      else if (d.type === 'sound') { wantSound = { muted: d.muted, volume: d.volume }; withPlayer(applySound); }
      else if (d.type === 'fullscreen') {
        if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen?.().catch(() => {});
      }
    });

    if (IS_OFFICIAL) { srgWatch(); return; }

    // ---- SRG: let the official player start by itself; only help if nothing happens.
    //      Logs player events; shows the log on screen if the stream stops. ----
    function srgWatch() {
      const t0 = Date.now(), log = [];
      const L = m => { log.push(((Date.now() - t0) / 1000).toFixed(1) + 's  ' + m); if (log.length > 16) log.shift(); };
      let started = false, resumes = 0, logEl = null, logTimer = null;
      const hooked = new WeakSet();
      function showLog(title) {
        if (!logEl) {
          logEl = document.createElement('pre');
          logEl.style.cssText = 'position:fixed;left:16px;bottom:90px;z-index:2147483647;margin:0;padding:10px 12px;max-width:46vw;' +
            'background:rgba(0,0,0,.82);color:#ffcc33;font:12px/1.4 Consolas,monospace;border-radius:8px;white-space:pre-wrap;pointer-events:none';
          document.body.appendChild(logEl);
        }
        logEl.textContent = 'MyTV Diagnose – ' + title + '\n' + log.join('\n');
        logEl.style.display = 'block';
        clearTimeout(logTimer); logTimer = setTimeout(() => { logEl.style.display = 'none'; }, 25000);
      }
      function unmuteOnce(v) {
        try {
          if (wantSound) { v.muted = !!wantSound.muted; v.volume = Math.max(0, Math.min(1, wantSound.volume)); }
          else if (v.muted) v.muted = false;
          L('sound set: ' + (v.muted ? 'muted' : Math.round(v.volume * 100)));
        } catch (e) {}
      }
      function hook(v) {
        if (hooked.has(v)) return; hooked.add(v);
        L('video #' + document.querySelectorAll('video').length + ' found, muted=' + v.muted);
        ['play', 'playing', 'waiting', 'stalled', 'emptied', 'abort', 'ended'].forEach(ev => v.addEventListener(ev, () => L(ev)));
        v.addEventListener('volumechange', () => L('volumechange → ' + (v.muted ? 'muted' : Math.round(v.volume * 100))));
        v.addEventListener('error', () => { L('ERROR code ' + (v.error && v.error.code)); showLog('Player-Fehler'); });
        v.addEventListener('playing', () => { if (!started) { started = true; setTimeout(() => unmuteOnce(v), 300); } });
        v.addEventListener('pause', () => {
          L('pause at ' + v.currentTime.toFixed(1) + 's, muted=' + v.muted);
          if (!started) return;
          setTimeout(() => {
            if (!v.paused || v.ended) return;
            if (resumes < 5) { resumes++; L('resume #' + resumes); v.play().catch(e => L('resume failed: ' + e.name)); }
            showLog('Stream hat gestoppt');
          }, 1500);
        });
      }
      let tries = 0;
      const timer = setInterval(() => {
        if (consentOpen()) return;              // wait for the user's cookie choice
        tries++;
        const v = pickVideo();
        if (v) hook(v);
        if (IS_ORF && !v && (tries === 12 || tries === 30)) {
          const b = document.querySelector('.b-player-area button[aria-label*="abspielen" i], .b-player-area button[aria-label*="play" i], .b-player-area [class*="play-button" i], .player-area-poster');
          if (b) { L('click start (' + b.tagName.toLowerCase() + ')'); b.click(); }
        }
        if (started) { clearInterval(timer); return; }
        // give the SRF player 6 s to start by itself, then nudge (never mute)
        if (v && tries >= 12 && tries % 6 === 0 && v.paused && v.readyState >= 2) {
          L('nudge play()'); v.play().catch(e => L('play failed: ' + e.name));
        }
        if (tries >= 80) {      // ~40 s
          clearInterval(timer);
          osd(CH, NAME + ' — kein Signal (↑/↓ zum Weiterschalten)', true);
          showLog('kein Start');
        }
      }, 500);
    }

    let tries = 0, started = false;
    const timer = setInterval(() => {
      tries++;
      const p = findPlayer(window);
      if (p && typeof p.getState === 'function') {
        const st = p.getState();
        if (st === 'playing' || st === 'buffering') {
          if (!started) {
            started = true;
            if (wantSound) applySound(p);
            else { try { p.setMute(false); if (p.getVolume() < 10) p.setVolume(100); } catch (e) {} }
          }
        } else if (st === 'error') {
          clearInterval(timer);
          osd(CH, NAME + ' — kein Signal (↑/↓ zum Weiterschalten)', true);
        } else if (!started || st === 'idle' || st === 'paused') {
          try { p.setMute(false); p.play(); } catch (e) {}
        }
      }
      if (tries > (IS_OFFICIAL ? 80 : 40)) {           // ~20 s (SRG ~40 s)
        clearInterval(timer);
        if (!started) osd(CH, NAME + ' — kein Signal (↑/↓ zum Weiterschalten)', true);
      }
    }, 500);

  }
})();
