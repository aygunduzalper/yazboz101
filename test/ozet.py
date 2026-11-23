"""Deneme sonuçlarından OZET.md ve her cihaz için tek parça bir ekran görüntüsü sayfası (<cihaz>.jpg) üretir.
Kullanım: python test/ozet.py <sonuç klasörü>
Ortam: RUN_URL (çalıştırmanın adresi), ANDROID_SONUC / IOS_SONUC (GitHub iş sonuçları: success/failure/...)."""
import glob
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

root = sys.argv[1]
os.makedirs(root, exist_ok=True)
L = ['# Yazboz 101 · otomatik deneme sonucu', '']
if os.environ.get('RUN_URL'):
    L += [f'Çalıştırma: {os.environ["RUN_URL"]}', '']
for k, ad in (('ANDROID_SONUC', 'Android işi'), ('IOS_SONUC', 'iOS işi')):
    v = os.environ.get(k)
    if v and v != 'success':
        L.append(f'- ⚠️ {ad}: {v} (derleme ya da emülatör adımı başarısız olmuş olabilir, ayrıntı çalıştırma sayfasında)')
L.append('')

try:
    FONT = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 15)
except OSError:
    FONT = ImageFont.load_default()


def sayfa(dosyalar, hedef, gen=240, sutun=6):
    kucuk = []
    for f in dosyalar:
        try:
            im = Image.open(f).convert('RGB')
        except Exception:
            continue
        h = int(im.height * gen / im.width)
        kucuk.append((os.path.splitext(os.path.basename(f))[0], im.resize((gen, h), Image.LANCZOS)))
    if not kucuk:
        return False
    satirlar = [kucuk[i:i + sutun] for i in range(0, len(kucuk), sutun)]
    pay, yazi = 10, 24
    W = pay + sutun * (gen + pay)
    H = pay + sum(max(im.height for _, im in s) + yazi + pay for s in satirlar)
    out = Image.new('RGB', (W, H), (40, 40, 40))
    d = ImageDraw.Draw(out)
    y = pay
    for s in satirlar:
        x = pay
        for ad, im in s:
            out.paste(im, (x, y))
            d.rectangle([x - 1, y - 1, x + im.width, y + im.height], outline=(90, 90, 90))
            d.text((x, y + im.height + 4), ad, fill=(235, 235, 235), font=FONT)
            x += gen + pay
        y += max(im.height for _, im in s) + yazi + pay
    out.save(hedef, quality=80)
    return True


for d in sorted(glob.glob(os.path.join(root, '*', ''))):
    tag = os.path.basename(os.path.dirname(d))
    p = os.path.join(d, 'sonuc.json')
    S = json.load(open(p, encoding='utf-8')) if os.path.exists(p) else {'sorunlar': ['sonuc.json yok']}
    sorun = S.get('sorunlar') or []
    sc = S.get('senaryo') or {}
    L += [f'## {"✅" if not sorun else "❌"} {tag} · {S.get("cihaz", "")}', '']
    if S.get('webview'):
        L.append(f'- WebView: {S["webview"]}')
    L += [f'- ❌ {s}' for s in sorun]
    b = sc.get('bilgi') or {}
    if b:
        L.append(f'- Ekran {b.get("ekran")} · ilk ekran {b.get("ilkEkranMs")} ms · senaryo {b.get("toplamMs")} ms'
                 f' · canlı paylaşım: {b.get("canliPaylasim")} ({b.get("canliPaylasimMs")} ms)')
    if sc.get('hata'):
        L.append(f'- ❌ senaryo: {sc["hata"]}')
    for a in sc.get('adimlar', []):
        if 'hata' in a:
            L.append(f'- ❌ adım "{a["ad"]}": {a["hata"]}')
    for k, v in (S.get('asamalar') or {}).items():
        L.append(f'- {k}: ' + ', '.join(f'{kk}={vv}' for kk, vv in v.items()))
    kons = list(S.get('konsol') or []) + list(sc.get('hatalar') or [])
    if kons:
        L += ['', f'<details><summary>Konsol uyarı ve hataları ({len(kons)})</summary>', '', '```', *kons[:80], '```', '</details>']
    if sayfa(sorted(glob.glob(os.path.join(d, '*.png'))), os.path.join(root, tag + '.jpg')):
        L += ['', f'![{tag}]({tag}.jpg)']
    L.append('')

open(os.path.join(root, 'OZET.md'), 'w', encoding='utf-8').write('\n'.join(L))
print('\n'.join(L))
