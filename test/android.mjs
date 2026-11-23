// Android emülatöründe Yazboz 101 denemesi (GitHub Actions'ta çalışır).
// Kullanım: node test/android.mjs <apk> <çıktı klasörü>
// Yaptıkları: ilk açılış + senaryo, kapat-aç, sil-yükle-aç (beyaz ekran kontrolü), gece modu, internetsiz açılış.
// Her aşamada ekran görüntüsü alır; sayfanın içine WebView hata ayıklama bağlantısıyla (CDP) bakar.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [APK, OUT] = process.argv.slice(2);
const PKG = 'com.aygunduz.yazboz101';
const ACT = PKG + '/com.yazboz101.app.MainActivity';
const SENARYO = fs.readFileSync(new URL('./senaryo.js', import.meta.url), 'utf8');
fs.mkdirSync(OUT, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));
const adb = (...a) => {
  const r = spawnSync('adb', a, { encoding: 'utf8', maxBuffer: 64 << 20 });
  return (r.stdout || '') + (r.stderr || '');
};
const S = { platform: 'android', cihaz: '', webview: '', asamalar: {}, senaryo: null, konsol: [], sorunlar: [] };
const kaydet = () => fs.writeFileSync(path.join(OUT, 'sonuc.json'), JSON.stringify(S, null, 2));
const asama = (k, v) => { S.asamalar[k] = v; console.log('●', k, JSON.stringify(v)); kaydet(); };

function shot(name) {
  const r = spawnSync('adb', ['exec-out', 'screencap', '-p'], { maxBuffer: 64 << 20 });
  if (r.stdout && r.stdout.length > 100) fs.writeFileSync(path.join(OUT, name + '.png'), r.stdout);
}
function launch() {
  const o = adb('shell', 'am', 'start', '-W', '-n', ACT);
  const m = o.match(/TotalTime:\s*(\d+)/);
  return m ? +m[1] : null;
}
const stop = () => adb('shell', 'am', 'force-stop', PKG);
function ekrandakiYazilar() {
  adb('shell', 'uiautomator', 'dump', '/sdcard/ui.xml');
  const x = adb('shell', 'cat', '/sdcard/ui.xml');
  return [...x.matchAll(/text="([^"]+)"/g)].map(m => m[1]).filter(Boolean);
}

// ---- WebView hata ayıklama bağlantısı (Chrome DevTools Protocol) ----
function wsAc(url) {
  return new Promise((res, rej) => {
    const ws = new WebSocket(url);
    let id = 0;
    const bekleyen = new Map(), dinleyici = [];
    const c = {
      send: (method, params = {}) => new Promise((ok, no) => {
        const i = ++id;
        bekleyen.set(i, { ok, no });
        ws.send(JSON.stringify({ id: i, method, params }));
      }),
      on: fn => dinleyici.push(fn),
      close: () => { try { ws.close(); } catch (e) { /* önemsiz */ } },
    };
    ws.onopen = () => res(c);
    ws.onerror = () => rej(new Error('WebSocket hatası'));
    ws.onmessage = ev => {
      const m = JSON.parse(ev.data);
      if (m.id && bekleyen.has(m.id)) {
        const w = bekleyen.get(m.id);
        bekleyen.delete(m.id);
        if (m.error) w.no(new Error(m.error.message)); else w.ok(m.result);
      } else if (m.method) dinleyici.forEach(f => f(m));
    };
  });
}

async function baglan(etiket, sureMs = 25000) {
  const t0 = Date.now();
  while (Date.now() - t0 < sureMs) {
    const pid = adb('shell', 'pidof', PKG).trim().split(/\s+/)[0];
    if (pid && /^\d+$/.test(pid)) {
      const sock = 'webview_devtools_remote_' + pid;
      if (adb('shell', 'cat', '/proc/net/unix').includes('@' + sock)) {
        adb('forward', '--remove-all');
        adb('forward', 'tcp:9222', 'localabstract:' + sock);
        try {
          const list = await (await fetch('http://127.0.0.1:9222/json')).json();
          const pg = list.find(x => x.type === 'page' && x.webSocketDebuggerUrl);
          if (pg) {
            const c = await wsAc(pg.webSocketDebuggerUrl);
            c.on(m => {
              const p = m.params || {};
              if (JSON.stringify(p).includes('favicon')) return; // uygulamada site simgesi yok, önemsiz
              if (m.method === 'Runtime.consoleAPICalled' && ['error', 'warning', 'assert'].includes(p.type)) {
                S.konsol.push(`[${etiket}] ${p.type}: ` + (p.args || []).map(a => a.value ?? a.description ?? '').join(' '));
              } else if (m.method === 'Runtime.exceptionThrown') {
                const d = p.exceptionDetails || {};
                S.konsol.push(`[${etiket}] yakalanmamış hata: ` + ((d.exception && d.exception.description) || d.text) + (d.url ? ` @${d.url}:${d.lineNumber}` : ''));
              } else if (m.method === 'Log.entryAdded' && ['error', 'warning'].includes(p.entry.level)) {
                S.konsol.push(`[${etiket}] ${p.entry.source}: ${p.entry.text} ${p.entry.url || ''}`);
              } else if (m.method === 'Runtime.bindingCalled' && p.name === '__ybShot') {
                shot(p.payload);
                c.send('Runtime.evaluate', { expression: `window.__ybShotDone && __ybShotDone(${JSON.stringify(p.payload)})` }).catch(() => {});
              }
            });
            await c.send('Runtime.enable');
            await c.send('Log.enable');
            await c.send('Runtime.addBinding', { name: '__ybShot' });
            return c;
          }
        } catch (e) { /* henüz hazır değil */ }
      }
    }
    await sleep(500);
  }
  return null;
}

const DURUM = `JSON.stringify((() => {
  const v = e => !!e && !e.hidden && e.getClientRects().length > 0;
  return { yuklenme: document.readyState, tanitim: v(document.querySelector('#onb')),
    anaSayfa: !!document.querySelector('[data-act=newgame]'), devamEt: !!document.querySelector('[data-act=resume]'), oyunEkrani: !!document.querySelector('[data-act=el]'),
    yaziUzunlugu: (document.body && document.body.innerText.length) || 0, sayfaSuresiMs: Math.round(performance.now()),
    tema: document.documentElement.dataset.theme || document.body.className || '' };
})())`;
async function durum(c) {
  if (!c) return { baglanti: 'kurulamadı' };
  try {
    const r = await c.send('Runtime.evaluate', { expression: DURUM, returnByValue: true });
    return JSON.parse(r.result.value);
  } catch (e) { return { hata: String(e.message || e) }; }
}
const bos = d => !d || d.baglanti || (!d.tanitim && !d.anaSayfa && !d.oyunEkrani);

async function main() {
  adb('wait-for-device');
  S.cihaz = adb('shell', 'getprop', 'ro.product.model').trim() + ' · Android ' + adb('shell', 'getprop', 'ro.build.version.release').trim() + ' · ' + adb('shell', 'wm', 'size').trim().replace('Physical size: ', '');
  const wv = adb('shell', 'dumpsys', 'webviewupdate').match(/Current WebView package \(name, version\): \(([^)]*)\)/);
  S.webview = wv ? wv[1] : '?';
  adb('shell', 'settings', 'put', 'global', 'window_animation_scale', '0');
  adb('uninstall', PKG);
  const kur = adb('install', '-g', APK);
  if (!/Success/.test(kur)) { S.sorunlar.push('APK kurulamadı: ' + kur.trim()); kaydet(); return; }
  adb('logcat', '-c');

  // 1) İlk açılış ve tam senaryo
  let ms = launch();
  await sleep(1500);
  shot('a-ilk-acilis-1sn');
  let c = await baglan('ilk açılış');
  asama('1 ilk açılış', { acilisMs: ms, ...(await durum(c)) });
  if (c) {
    try {
      const r = await c.send('Runtime.evaluate', {
        expression: SENARYO + `\n;window.__ybRun('android', n => __ybShot(n))`,
        awaitPromise: true, returnByValue: true,
      });
      S.senaryo = r.result && typeof r.result.value === 'string' ? JSON.parse(r.result.value) : { ok: false, hata: JSON.stringify(r.exceptionDetails || r.result) };
    } catch (e) { S.senaryo = { ok: false, hata: String(e.message || e) }; }
    // Uygulamanın açtığı masa gerçekten sunucuya yazıldı mı? (izleyicilerin "masa bulunamadı" sorunu)
    try {
      const r = await c.send('Runtime.evaluate', { expression: "localStorage.getItem('yb.cfg')", returnByValue: true });
      const cfg = JSON.parse(r.result.value || 'null');
      const kod = S.senaryo && S.senaryo.bilgi && S.senaryo.bilgi.canli && S.senaryo.bilgi.canli.kod;
      if (cfg && kod) {
        S.db = cfg.firebase.databaseURL.replace(/\/+$/, '');
        S.masaKodu = kod;
        const t = await (await fetch(`${S.db}/tables/${kod}.json`)).json();
        asama('1b masa sunucuda', { kod, var: !!t });
        if (!t) S.sorunlar.push('Uygulamanın açtığı masa sunucuya yazılmamış (izleyiciler "masa bulunamadı" görür)');
      } else asama('1b masa sunucuda', { kod: kod || null, ayar: !!cfg, not: 'canlı paylaşım ayarı yok' });
    } catch (e) { asama('1b masa sunucuda', { hata: String(e.message || e) }); }
    c.close();
  } else S.sorunlar.push('İlk açılışta sayfaya bağlanılamadı (beyaz ekran olabilir)');
  if (S.senaryo && !S.senaryo.ok) S.sorunlar.push('Senaryoda başarısız adım var');
  kaydet();

  // 2) Kapat-aç: oyun geri gelmeli
  stop();
  ms = launch();
  await sleep(3000);
  shot('b-kapat-ac');
  c = await baglan('kapat-aç');
  let d = await durum(c);
  asama('2 kapat-aç', { acilisMs: ms, ...d });
  if (!d.devamEt) S.sorunlar.push('Kapatıp açınca ana menüde "Devam et" görünmedi (oyun kaybolmuş olabilir)');
  if (c) c.close();

  // 3) Sil-yükle-aç: Play'deki beyaz ekran sorununun denemesi
  adb('uninstall', PKG);
  adb('install', '-g', APK);
  ms = launch();
  await sleep(2000);
  shot('c-yeniden-kurulum-2sn');
  await sleep(6000);
  shot('c-yeniden-kurulum-8sn');
  c = await baglan('yeniden kurulum');
  d = await durum(c);
  const yazilar = ekrandakiYazilar();
  const diyalog = yazilar.some(t => /açılamadı/.test(t));
  asama('3 sil-yükle-aç', { acilisMs: ms, ...d, uyariPenceresi: diyalog });
  if (bos(d) || diyalog) S.sorunlar.push('Silip yükleyince uygulama açılmadı (beyaz ekran / uyarı penceresi)');
  if (c) c.close();
  await sleep(6000);
  shot('c-yeniden-kurulum-14sn');

  // 4) Gece modu
  adb('shell', 'cmd', 'uimode', 'night', 'yes');
  stop();
  launch();
  await sleep(3500);
  shot('d-gece-modu');
  c = await baglan('gece modu');
  asama('4 gece modu', await durum(c));
  if (c) c.close();
  adb('shell', 'cmd', 'uimode', 'night', 'no');

  // 4b) Başka bir telefon gibi masaya katıl: veriyi sil, QR bağlantısıyla aç, masa görünmeli
  if (S.masaKodu) {
    adb('shell', 'pm', 'clear', PKG);
    adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.VIEW', '-d', `yazboz101://masa/${S.masaKodu.toLowerCase()}?s=yazboz101.com`, '-n', ACT);
    c = await baglan('izleyici');
    let v = null;
    for (let i = 0; i < 20 && c; i++) {
      await sleep(500);
      try {
        const r = await c.send('Runtime.evaluate', { expression: "JSON.stringify(window.ybDurum ? window.ybDurum() : {})", returnByValue: true });
        v = JSON.parse(r.result.value);
        if (v.izleyici === 'ok') break;
      } catch (e) { /* sayfa yenileniyor */ }
    }
    shot('f-izleyici-qr-ile');
    asama('4b QR ile katılma', v || { baglanti: 'kurulamadı' });
    if (!v || v.izleyici !== 'ok') S.sorunlar.push('QR bağlantısıyla masaya katılınamadı (durum: ' + (v && v.izleyici) + ')');
    if (c) c.close();
  }

  // 5) İnternetsiz açılış
  adb('shell', 'svc', 'wifi', 'disable');
  adb('shell', 'svc', 'data', 'disable');
  stop();
  ms = launch();
  await sleep(4000);
  shot('e-internetsiz');
  c = await baglan('internetsiz');
  d = await durum(c);
  asama('5 internetsiz açılış', { acilisMs: ms, ...d });
  if (bos(d)) S.sorunlar.push('İnternetsiz açılışta ekran boş kaldı');
  if (c) c.close();
  adb('shell', 'svc', 'wifi', 'enable');
  adb('shell', 'svc', 'data', 'enable');
}

try { await main(); }
catch (e) { S.sorunlar.push('Deneme yarıda kaldı: ' + (e.stack || e)); }
finally {
  const log = adb('logcat', '-d', '-v', 'time', '*:W').split('\n');
  fs.writeFileSync(path.join(OUT, 'logcat.txt'), log.slice(-600).join('\n'));
  const cokme = log.filter(l => /FATAL EXCEPTION|AndroidRuntime/.test(l));
  if (cokme.length) S.sorunlar.push('Uygulama çöktü (logcat.txt içinde AndroidRuntime satırları)');
  kaydet();
  console.log(S.sorunlar.length ? '✗ Sorunlar:\n- ' + S.sorunlar.join('\n- ') : '✓ Sorun bulunmadı');
}
