// ==UserScript==
// @name         MyTV Helper
// @namespace    https://mistergeil.github.io/MyTV/
// @version      1.13.0
// @description  Makes external channels opened from MyTV behave like the TV: full screen, autoplay, remote keys.
// @match        https://www.livehdtv.net/*
// @match        https://livehdtv.net/*
// @match        https://www.srf.ch/play/*
// @match        https://www.rts.ch/play/embed*
// @match        https://www.rsi.ch/play/embed*
// @match        https://on.orf.at/*
// @match        https://www.joyn.de/*
// @match        https://www.ardmediathek.de/*
// @match        https://www.zdf.de/*
// @match        https://www.arte.tv/*
// @match        https://www.3sat.de/*
// @match        https://plus.rtl.de/*
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
  const IS_JOYN = location.hostname === 'www.joyn.de';
  const IS_RTL = location.hostname === 'plus.rtl.de';
  const IS_OFFICIAL = IS_SRG || IS_ORF || IS_JOYN || IS_RTL;            // official broadcaster player pages (plain <video>)

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
  const RX = /mytv=(\d+|lib)(?:&n=([^&]*))?/;
  let m = RX.exec(topHash);
  if (window.top === window) {   // SPA / page navigation may drop the hash → remember it for this tab
    try {
      if (m) sessionStorage.setItem('mytv.session', topHash);
      else { const saved = sessionStorage.getItem('mytv.session'); if (saved) m = RX.exec(saved); }
    } catch (e) {}
  }
  if (!m) return;
  if (m[1] === 'lib') { libraryMode(decodeURIComponent(m[2] || '')); return; }
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
    html.mytv-dialog .player-area-player { z-index:auto !important; }
    [aria-label="Bundesland hier wählen"] { display:none !important; }
  ` : '') + (IS_RTL ? `
    .mytv-fs { position:fixed !important; inset:0 !important; width:100vw !important; height:100vh !important;
               max-width:none !important; max-height:none !important; margin:0 !important; padding:0 !important;
               transform:none !important; z-index:2147483000 !important; background:#000 !important; }
    .mytv-fs video { width:100% !important; height:100% !important; object-fit:contain !important; }
    html.mytv-dialog .mytv-fs { z-index:auto !important; }
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
  // hide the mouse pointer on the provider page after 3 s without movement (RTL+, Joyn, ORF … show it in the middle)
  if (isTop) {
    const st = document.createElement('style');
    st.textContent = 'html.mytv-idle, html.mytv-idle * { cursor: none !important; }';
    (document.head || document.documentElement).appendChild(st);
    // the pointer can also sit over the provider's player iframe (ORF, Joyn/SAT.1 …), where our CSS can't reach →
    // while idle, an invisible full-screen sheet without pointer lies on top (below the MyTV overlay); moving the mouse removes it
    const shield = document.createElement('div');
    shield.style.cssText = 'position:fixed;inset:0;z-index:2147483645;cursor:none;background:transparent;display:none';
    let idleT = null;
    const idle = () => {
      clearTimeout(idleT); document.documentElement.classList.remove('mytv-idle'); shield.style.display = 'none';
      idleT = setTimeout(() => {
        document.documentElement.classList.add('mytv-idle');
        if (!shield.isConnected && document.body) document.body.appendChild(shield);
        shield.style.display = 'block';
      }, 3000);
    };
    ['mousemove', 'mousedown'].forEach(ev => window.addEventListener(ev, idle, { capture: true, passive: true }));
    idle();
  }

  // ---- Navigation back into MyTV (always replace → no history pile-up) ----
  function go(q) { window.top.location.replace(MYTV + '?kiosk=1&' + q); }
  // TV turned off with the TV remote? After 4 h without any input go to MyTV standby (stops streaming).
  let lastInput = Date.now();
  if (isTop) setInterval(() => { if (Date.now() - lastInput > 4 * 3600e3) go('standby=1&from=' + CH); }, 60e3);

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
    lastInput = Date.now();
    let handled = true;
    if (IS_OFFICIAL && k === 'Enter' && window.top === window && !overlayWin()) {   // with overlay: MyTV decides (list/guide open → select, else → play)
      clickPlay('OK');
      e.preventDefault(); e.stopImmediatePropagation();
      return;
    }
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
    } else if (k === 'b' || k === 'B') {
      go('back=1&from=' + CH + '&lib=1');
    } else if (k === 'g' || k === 'G' || k === 'Guide') {
      go('back=1&from=' + CH + '&guide=1');
    } else if (k === 'h' || k === 'H') {
      go('back=1&from=' + CH + '&hl=1');
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
      play() { if (v.currentSrc) v.play().catch(() => {}); },
      setMute(b) { v.muted = !!b; }, getMute() { return v.muted; },
      setVolume(x) { v.volume = Math.max(0, Math.min(1, x / 100)); }, getVolume() { return Math.round(v.volume * 100); },
    };
  }
  // all <video> elements, also inside open shadow roots and same-origin iframes (Joyn renders its player in web components)
  function allVideos(root = document, out = [], depth = 0) {
    if (!root || depth > 6) return out;
    root.querySelectorAll('video').forEach(v => out.push(v));
    root.querySelectorAll('*').forEach(e => {
      if (e.shadowRoot) allVideos(e.shadowRoot, out, depth + 1);
      if (e.tagName === 'IFRAME') { try { if (e.contentDocument) allVideos(e.contentDocument, out, depth + 1); } catch (x) {} }
    });
    return out;
  }
  const anyPlaying = () => allVideos().some(x => !x.paused && x.currentTime > 0 && x.readyState >= 2);
  function pickVideo() {
    const vs = allVideos();
    return vs.find(v => !v.paused) || vs.find(v => v.currentSrc) || vs[0] || null;
  }
  function clickPlay(reason) {
    const v = pickVideo();
    if (v && !v.paused) return false;                      // already playing → never touch (play/pause toggles!)
    // ORF ON: exact big play button (label "Wiedergabe starten" is hidden text inside it)
    const orfBtn = document.querySelector('[data-test-id="player-overlay-play-button"]');
    if (orfBtn && !orfBtn.closest('.is-hidden')) {
      (window.__mytvLog || []).push('click ORF play button (' + reason + ')');
      orfBtn.click();
      return true;
    }
    // RTL+ (and others): button/tile labelled "Video abspielen" – match by visible text or label
    if (IS_RTL || IS_JOYN) {
      const rx = /^(video abspielen|abspielen|jetzt abspielen|live ansehen|jetzt live|weiterschauen|wiedergabe starten)$/i;
      const hits = [...document.querySelectorAll('button, [role="button"], a, div[tabindex]')].filter(e => {
        if (e.closest('#mytv-overlay')) return false;
        const txt = ((e.getAttribute('aria-label') || '') + '|' + (e.innerText || '')).split('|').map(x => x.trim()).filter(Boolean);
        if (!txt.some(x => rx.test(x))) return false;
        const r = e.getBoundingClientRect(); return r.width > 10 && r.height > 10;
      });
      const t = hits.find(e => !hits.some(o => o !== e && e.contains(o)));   // innermost match = the real button
      if (t) { (window.__mytvLog || []).push('click "' + (t.innerText || t.getAttribute('aria-label') || '').trim().slice(0, 30) + '" (' + reason + ')'); t.click(); return true; }
    }
    const sel = [
      '[class*="hugeplayback" i]', '[class*="playbacktoggle" i]', '[class*="big-play" i]', '[class*="bigplay" i]',
      '[class*="play-button" i]', '[class*="playbutton" i]', '[class*="vjs-big-play" i]',
      'button[aria-label*="abspielen" i]', 'button[aria-label*="wiedergabe" i]', 'button[aria-label*="play" i]',
      'button[title*="abspielen" i]', 'button[title*="play" i]', '[role="button"][aria-label*="play" i]',
      '.player-area-poster'
    ].join(',');
    const cands = [...document.querySelectorAll(sel)].filter(e => {
      if (e.closest('#mytv-overlay')) return false;
      const r = e.getBoundingClientRect(); return r.width > 10 && r.height > 10;
    });
    // prefer the largest candidate (the big centre play button)
    cands.sort((a, b) => { const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect(); return rb.width * rb.height - ra.width * ra.height; });
    const b = cands[0];
    if (b) {
      (window.__mytvLog || []).push('click play (' + reason + '): ' + b.tagName.toLowerCase() + '.' + String(b.className).slice(0, 40));
      b.click();
      ['pointerdown', 'mousedown', 'pointerup', 'mouseup'].forEach(t => b.dispatchEvent(new MouseEvent(t, { bubbles: true })));
    }
    if (v && v.currentSrc && !IS_ORF) v.play().catch(() => {});
    return !!b;
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

    const visible = el => { const r = el.getBoundingClientRect(); const cs = getComputedStyle(el); return r.width > 40 && r.height > 20 && cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0'; };
    const isRegionHint = e => /Bundesland/i.test((e.getAttribute('aria-label') || '') + ' ' + (e.innerText || '')) &&
      !e.querySelector('video, .player-area-player') && !e.closest('#regional-settings-menu');
    const hideRegionHints = () => {
      if (!IS_ORF || !document.body) return;
      document.querySelectorAll('[role="dialog"], [role="tooltip"], [role="status"], [role="alert"], [aria-live], [class*="tooltip" i], [class*="toast" i], [class*="snackbar" i], [class*="notification" i]')
        .forEach(e => { if (isRegionHint(e) && e.style.display !== 'none') { e.style.setProperty('display', 'none', 'important'); (window.__mytvLog || []).push('hid Bundesland hint'); } });
    };
    if (IS_ORF) setInterval(hideRegionHints, 1000);
    const blocker = () => {
      if (!(IS_ORF || IS_JOYN || IS_RTL) || !document.body) return '';
      hideRegionHints();
      if ((IS_ORF || IS_RTL) && document.body.classList.contains('didomi-popup-open')) return 'Cookie-Auswahl';
      if (IS_RTL) {   // RTL+ cookie wall ("Einwilligen und weiter")
        const b = [...document.querySelectorAll('button, a, [role="button"]')].find(e => /Einwilligen und weiter/i.test(e.textContent || '') && visible(e));
        if (b) return 'Cookie-Auswahl';
      }
      if (IS_JOYN) {
        const cmp = document.querySelector('cmp-banner');
        if (cmp && visible(cmp)) {
          const dlg = cmp.shadowRoot && cmp.shadowRoot.querySelector('cmp-dialog, [role="dialog"]');
          if (!dlg || visible(dlg)) return 'Cookie-Auswahl';
        }
      }
      const el = [...document.querySelectorAll('[role="dialog"], [role="alertdialog"], [aria-modal="true"], dialog[open]')]
        .find(e => !e.closest('#mytv-overlay') && visible(e) && (e.innerText || '').trim().length > 0 && !isRegionHint(e));
      return el ? (el.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 50) : '';
    };
    const consentOpen = () => !!blocker();
    const LOG = window.__mytvLog = window.__mytvLog || [];
    const t0 = Date.now();
    const L0 = m => { LOG.push(((Date.now() - t0) / 1000).toFixed(1) + 's  ' + m); if (LOG.length > 16) LOG.shift(); };
    let lastBlock = '';
    const hint = () => '— Fenster offen: „' + blocker() + '…“ – bitte mit der Maus schliessen';
    function mountOverlay() {
      if (window.__mytvOv) return;
      if (consentOpen()) {
        document.documentElement.classList.add('mytv-dialog');
        const b = blocker(); if (b !== lastBlock) { lastBlock = b; L0('popup: ' + b); }
        osd(CH, NAME + ' ' + hint(), true);
        setTimeout(mountOverlay, 1000);
        return;
      }
      document.documentElement.classList.remove('mytv-dialog');
      if (osdEl) osdEl.style.opacity = '0';
      const f = document.createElement('iframe');
      f.id = 'mytv-overlay';
      f.src = MYTV + '?overlay=1&ch=' + CH;
      f.setAttribute('allowtransparency', 'true');
      f.allow = 'fullscreen';
      document.body.appendChild(f);
      window.__mytvOv = f;
      if (IS_ORF || IS_JOYN || IS_RTL) setInterval(() => {
        const b = blocker(), open = !!b;
        if (b !== lastBlock) { lastBlock = b; L0(open ? 'popup: ' + b : 'popup closed'); }
        document.documentElement.classList.toggle('mytv-dialog', open);
        if (open && f.style.display !== 'none') { f.style.display = 'none'; osd(CH, NAME + ' ' + hint(), true); }
        else if (!open && f.style.display === 'none') { f.style.display = ''; if (osdEl) osdEl.style.opacity = '0'; }
      }, 1000);
      // fallback: if the overlay doesn't come up, show the simple badge
      setTimeout(() => { if (!window.__mytvOvReady) osd(CH, NAME); }, 4000);
    }
    if (document.body) mountOverlay(); else document.addEventListener('DOMContentLoaded', mountOverlay);

    window.addEventListener('message', ev => {
      if (ev.origin !== OV_ORIGIN) return;
      const d = ev.data;
      if (!d || d.mytv !== 1) return;
      if (d.type !== 'ready') lastInput = Date.now();
      if (d.type === 'ready') {
        window.__mytvOvReady = true;
        const v = (typeof GM_info !== 'undefined' && GM_info.script && GM_info.script.version) || '';
        try { ev.source.postMessage({ mytv: 1, type: 'helperVersion', version: v }, OV_ORIGIN); } catch (e) {}   // shown in the remote settings
      }
      else if (d.type === 'tune') go('ch=' + d.number + '&from=' + CH);
      else if (d.type === 'back') go('back=1&from=' + CH);
      else if (d.type === 'ok') { if (IS_OFFICIAL && !clickPlay('OK')) L0('OK: nothing to click'); }
      else if (d.type === 'lib') go('back=1&from=' + CH + '&lib=1');
      else if (d.type === 'hl') go('back=1&from=' + CH + '&hl=1');
      else if (d.type === 'go' && typeof d.q === 'string') {
        // generic pipe for future overlay features: only MyTV's own short parameters (name=value, letters/digits), never a URL
        const q = new URLSearchParams(d.q), out = new URLSearchParams();
        for (const [k, v] of q) if (/^[a-z][a-z0-9]{0,15}$/i.test(k) && /^[A-Za-z0-9_-]{0,32}$/.test(v) && !/^(kiosk|overlay)$/i.test(k)) out.set(k, v);
        if (!out.has('ch')) { out.set('back', '1'); out.set('from', CH); }
        go(out.toString());
      }
      else if (d.type === 'sound') { wantSound = { muted: d.muted, volume: d.volume }; withPlayer(applySound); }
      else if (d.type === 'fullscreen') {
        if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen?.().catch(() => {});
      }
    });

    if (IS_RTL) setInterval(() => {
      const v = pickVideo(); if (!v || document.querySelector('.mytv-fs')) return;
      const r = v.getBoundingClientRect(); if (r.width < 50) return;
      // biggest ancestor that still has (about) the video's size = the player box with its controls
      let box = v, e = v.parentElement;
      while (e && e !== document.body) { const q = e.getBoundingClientRect(); if (q.width > r.width * 1.05 + 4 || q.height > r.height * 1.25 + 4) break; box = e; e = e.parentElement; }
      box.classList.add('mytv-fs'); (window.__mytvLog || []).push('fullscreen player: ' + box.tagName + '.' + String(box.className).slice(0, 40));
    }, 1000);

    if (IS_OFFICIAL) { srgWatch(); return; }

    // ---- SRG: let the official player start by itself; only help if nothing happens.
    //      Logs player events; shows the log on screen if the stream stops. ----
    function srgWatch() {
      const log = LOG, L = L0;
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
        L('video #' + allVideos().length + ' found, muted=' + v.muted);
        ['play', 'playing', 'waiting', 'stalled', 'emptied', 'abort', 'ended'].forEach(ev => v.addEventListener(ev, () => L(ev)));
        v.addEventListener('volumechange', () => L('volumechange → ' + (v.muted ? 'muted' : Math.round(v.volume * 100))));
        v.addEventListener('error', () => {
          const c = v.error && v.error.code;
          L('ERROR code ' + c + (c === 4 ? ' (Quelle nicht abspielbar' + (v.currentSrc ? '' : ', noch keine Quelle') + ')' : '') + (v.error && v.error.message ? ' – ' + v.error.message : ''));
          if (navigator.requestMediaKeySystemAccess) {
            navigator.requestMediaKeySystemAccess('com.widevine.alpha', [{ initDataTypes: ['cenc'], videoCapabilities: [{ contentType: 'video/mp4; codecs="avc1.42E01E"' }] }])
              .then(() => { L('Widevine DRM: OK'); showLog('Player-Fehler'); })
              .catch(e => { L('Widevine DRM: NICHT verfügbar (' + e.name + ')'); showLog('Player-Fehler'); });
          } else showLog('Player-Fehler');
        });
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
        allVideos().forEach(hook);
        const v = pickVideo();
        // video may already be running before we hooked it (fast autoplay, e.g. Joyn) → count as started
        if (!started && ((v && !v.paused && v.readyState >= 3) || anyPlaying())) { started = true; L('already playing'); if (v) setTimeout(() => unmuteOnce(v), 300); }
        if ((IS_ORF || IS_RTL) && (tries === 4 || tries === 10 || tries === 20 || tries === 32 || tries === 50) && (!v || v.paused)) {
          if (!clickPlay('auto')) L('no play button found');
        }
        if (started) { clearInterval(timer); return; }
        // give the SRF player 6 s to start by itself, then nudge (never mute)
        if (v && tries >= 12 && tries % 6 === 0 && v.paused && v.readyState >= 2) {
          L('nudge play()'); v.play().catch(e => L('play failed: ' + e.name));
        }
        if (tries >= 80) {      // ~40 s
          clearInterval(timer);
          if (anyPlaying()) { L('playing (late check)'); return; }
          osd(CH, NAME + ' — kein Signal (↑/↓ zum Weiterschalten)', true);
          // stream may still come up (long ads, slow start) → remove the warning as soon as anything plays
          const late = setInterval(() => { if (anyPlaying()) { clearInterval(late); L('playing (late)'); if (osdEl) osdEl.style.opacity = '0'; } }, 2000);
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

  // ---- Mediathek mode: the provider's own library, normal mouse/keyboard use.
  //      Small "⌂ MyTV" button + B key (outside text fields) return to MyTV's Mediathek menu. ----
  function libraryMode(name) {
    if (window.top !== window) return;
    const back = () => window.top.location.replace(MYTV + '?kiosk=1&back=1&lib=1');
    let lastInput = Date.now();
    ['keydown', 'mousemove', 'mousedown', 'wheel'].forEach(ev => window.addEventListener(ev, () => { lastInput = Date.now(); }, { capture: true, passive: true }));
    setInterval(() => { if (Date.now() - lastInput > 4 * 3600e3) window.top.location.replace(MYTV + '?kiosk=1&back=1&standby=1'); }, 60e3);
    const mount = () => {
      if (document.getElementById('mytv-home')) return;
      const b = document.createElement('button');
      b.id = 'mytv-home';
      b.textContent = '⌂ MyTV';
      b.title = 'Zurück zu MyTV (B)';
      b.style.cssText = 'position:fixed;left:14px;bottom:14px;z-index:2147483647;padding:9px 16px;border-radius:999px;border:1px solid rgba(255,255,255,.25);' +
        'background:rgba(10,12,16,.85);color:#ffcc33;font:700 15px/1 -apple-system,"Segoe UI",Roboto,sans-serif;cursor:pointer;opacity:.75';
      b.onmouseenter = () => { b.style.opacity = '1'; }; b.onmouseleave = () => { b.style.opacity = '.75'; };
      b.onclick = e => { e.preventDefault(); e.stopPropagation(); back(); };
      document.body.appendChild(b);
    };
    if (document.body) mount(); else document.addEventListener('DOMContentLoaded', mount);
    setInterval(mount, 2000);           // SPAs sometimes rebuild <body>
    window.addEventListener('keydown', e => {
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      const t = e.target, typing = t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
      if (typing) return;
      if (e.key === 'b' || e.key === 'B' || e.key === 'BrowserHome') { e.preventDefault(); e.stopImmediatePropagation(); back(); }
    }, true);
  }
})();
