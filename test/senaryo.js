// Yazboz 101 otomatik deneme senaryosu.
// Uygulamanın içinde (Android WebView / iPhone WKWebView) çalışır; ilk açılıştan bir oyunun birkaç eline kadar
// gerçek kullanıcı gibi düğmelere basar, her adımda ekran görüntüsü ister ve sonucu JSON metni olarak döndürür.
// Sürücüler: test/android.mjs (emülatör) ve WebViewController.swift'teki DEBUG bölümü (simülatör).
(function () {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const $ = q => document.querySelector(q);
  const vis = el => !!el && !el.hidden && el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
  const S = '#sheetRoot .ov:not([hidden]) ';

  async function waitFor(fn, ms, label) {
    const t = Date.now();
    while (Date.now() - t < ms) {
      try { const v = fn(); if (v) return v; } catch (e) { /* tekrar dene */ }
      await sleep(100);
    }
    throw new Error('bekleme süresi doldu: ' + label);
  }
  async function tap(q, label) {
    const el = await waitFor(() => { const e = $(q); return vis(e) && e; }, 6000, label || q);
    el.click();
    await sleep(200);
    return el;
  }

  window.__ybShotWait = {};
  window.__ybShotDone = n => { const r = window.__ybShotWait[n]; delete window.__ybShotWait[n]; if (r) r(); };

  window.__ybRun = async function (platform, shotFn) {
    const R = { platform, ok: true, adimlar: [], hatalar: [], bilgi: {} };
    const t0 = performance.now();
    const ce = console.error;
    console.error = function () { R.hatalar.push(Array.prototype.map.call(arguments, String).join(' ')); return ce.apply(console, arguments); };
    window.addEventListener('error', e => R.hatalar.push('hata: ' + e.message + ' @' + e.filename + ':' + e.lineno));

    const adim = (ad, ek) => R.adimlar.push(Object.assign({ ad, ms: Math.round(performance.now() - t0) }, ek || {}));
    const shot = name => new Promise(res => {
      window.__ybShotWait[name] = res;
      try { shotFn(name); } catch (e) { res(); }
      setTimeout(res, 8000);
    });
    const run = async (ad, fn) => {
      try { await fn(); adim(ad); }
      catch (e) { R.ok = false; adim(ad, { hata: String((e && e.message) || e) }); }
    };

    R.bilgi.tarayici = navigator.userAgent;
    R.bilgi.ekran = innerWidth + 'x' + innerHeight + ' @' + devicePixelRatio + 'x';

    await run('ilk ekran geldi', () => waitFor(() => vis($('#onb')) || $('[data-act=newgame]') || $('[data-act=resume]'), 15000, 'ilk ekran'));
    R.bilgi.ilkEkranMs = Math.round(performance.now()); // sayfanın yüklenmeye başlamasından beri
    await shot('01-acilis');

    if (vis($('#onb'))) {
      await run('tanıtım', async () => {
        for (let i = 0; i < 8 && vis($('#onb')); i++) {
          const nx = $('#onb [data-o=next]');
          if (!nx) break;
          nx.click();
          await sleep(350);
          if (i === 0) await shot('02-tanitim');
        }
      });
    }

    await run('ana sayfa', () => waitFor(() => $('[data-act=newgame]'), 6000, 'yeni oyun düğmesi'));
    await shot('03-ana-sayfa');

    await run('yeni oyun kurulumu', async () => {
      await tap('[data-act=newgame]');
      ['Ali', 'Ayşe', 'Mehmet', 'Zeynep'].forEach((n, i) => {
        const f = $('#nm-' + i);
        if (f) { f.value = n; f.dispatchEvent(new Event('input', { bubbles: true })); }
      });
    });
    await shot('04-kurulum');

    await run('oyunu başlat', () => tap('[data-act=start]'));
    await sleep(500);
    if (vis($('#coach'))) {
      await shot('05-ipucu');
      await run('ipucunu geç', () => tap('#coach [data-c=skip]'));
    }

    const eller = [[-101, 87, 202, 54], [63, 0, 41, 118], [-202, 72, 95, 38]];
    for (let h = 0; h < eller.length; h++) {
      await run((h + 1) + '. el girişi', async () => {
        await tap('[data-act=el]');
        for (const v of eller[h]) {
          for (const ch of String(Math.abs(v))) await tap(S + `.kp [data-k="${ch}"]`);
          if (v < 0) await tap(S + '.kp [data-k=pm]');
          await tap(S + '.kp [data-k=go]');
        }
        if (h === 0) await shot('06-el-gir');
        await tap(S + '[data-a=save]');
        await sleep(300);
      });
    }
    await shot('07-oyun');
    await sleep(1500);
    try { R.bilgi.canli = window.ybDurum ? window.ybDurum() : { hata: 'ybDurum yok (eski sürüm)' }; }
    catch (e) { R.bilgi.canli = { hata: 'okunamadı: ' + e.message }; }

    await run('ceza penceresi', async () => {
      await tap('[data-act=ceza]');
      await sleep(300);
      await shot('08-ceza');
      closeAll();
      await sleep(300);
    });

    await run('paylaş penceresi', async () => {
      await tap('[data-act=share]');
      const t = Date.now();
      R.bilgi.canliPaylasim = await waitFor(() => $(S + '.qrbox svg') ? 'açık' : null, 10000, 'QR kodu').catch(() => 'yok');
      R.bilgi.canliPaylasimMs = Date.now() - t;
      await shot('09-paylas');
      closeAll();
      await sleep(300);
    });

    await run('ayarlar', async () => {
      await tap('[data-act=menu]');
      await tap(S + '[data-a=settings]');
      await sleep(300);
      await shot('10-ayarlar');
      closeAll();
    });

    await run('oyunu erken bitir', async () => {
      await tap('[data-act=menu]');
      await tap(S + '[data-a=end]');
      await tap(S + '[data-a=yes]');
      await waitFor(() => vis($('#win')), 4000, 'kazanan ekranı');
      await sleep(900);
      await shot('11-kazanan');
      await tap('#win [data-w=ok]');
      await sleep(400);
      closeAll();
    });

    await run('oyun geçmişi', async () => {
      await tap('[data-act=home]');
      await tap('[data-act=hist]');
      await sleep(300);
      await shot('12-gecmis');
      await tap('[data-act=htab][data-v=stats]');
      await sleep(300);
      await shot('13-istatistik');
      await tap('[data-act=home]');
    });

    R.bilgi.toplamMs = Math.round(performance.now() - t0);
    console.error = ce;
    return JSON.stringify(R);
  };
})();
