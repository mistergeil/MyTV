// MyTV - syntax checks for every page script and userscript (runs in CI on Node). Exit 1 = failure.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..');
let fails = 0;
const check = (name, fn) => { try { fn(); console.log('ok    ' + name); } catch (e) { fails++; console.log('FAIL  ' + name + '  ' + e.message); } };
for (const f of ['index.html', 'mediathek.html', 'streamtest.html', 'kiosk/vpn/remote.html', 'kiosk/vpn/watch.html', 'kiosk/index.html']) {
  const p = path.join(root, f); if (!fs.existsSync(p)) continue;
  const html = fs.readFileSync(p, 'utf8');
  const scripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
  scripts.forEach((js, i) => check(`${f} script ${i + 1}`, () => new Function(js)));
}
for (const f of ['channels.js', 'reminders.js']) check(f, () => new Function(fs.readFileSync(path.join(root, f), 'utf8')));
for (const f of fs.readdirSync(path.join(root, 'kiosk')).filter(n => n.endsWith('.user.js')))
  check(f, () => new Function('GM_xmlhttpRequest', 'GM_getValue', 'GM_setValue', 'GM_info', fs.readFileSync(path.join(root, 'kiosk', f), 'utf8')));
// channels.js: unique numbers, required fields
check('channels.js: unique numbers + fields', () => {
  const w = {}; new Function('window', fs.readFileSync(path.join(root, 'channels.js'), 'utf8'))(w);
  const nums = new Set();
  for (const c of w.CHANNELS) {
    if (!c.number || !c.name) throw new Error('channel without number/name');
    if (nums.has(c.number)) throw new Error('duplicate channel ' + c.number); nums.add(c.number);
    if (c.type === 'youtube' ? !(c.yt || []).length : !c.url) throw new Error('channel ' + c.number + ' has no url/yt');
  }
});
// userscripts: @version must be a plain x.y.z
for (const f of fs.readdirSync(path.join(root, 'kiosk')).filter(n => n.endsWith('.user.js')))
  check(f + ' @version', () => { if (!/@version\s+\d+\.\d+\.\d+\s/.test(fs.readFileSync(path.join(root, 'kiosk', f), 'utf8'))) throw new Error('no x.y.z @version'); });
console.log(fails ? `\n${fails} check(s) failed` : '\nall checks passed');
process.exit(fails ? 1 : 0);
