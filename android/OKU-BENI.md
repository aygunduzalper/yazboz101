# Yazboz 101 Android projesi (1.0, Google Play sürümü)

Hedef Android 16 (API 36), Google ML Kit ile telefonda çalışan yazı tanıma (fotoğrafla sayma), kenardan kenara ekran
ve Android 16'nın geri hareketi desteği.

## En kolay yol: GitHub derlesin
Bilgisayarına bir şey kurmana gerek yok. Depodaki `.github/workflows/android.yml` bu klasörü derler ve
Google Play'e yüklenecek `Yazboz101.aab` dosyasını verir. Adımlar MAGAZA-REHBERI.txt dosyasında.

## Android Studio ile (isteğe bağlı)
1. Android Studio'yu kur, **File › Open** ile bu `android` klasörünü aç.
2. İmza anahtarını `imza/yazboz101.p12` olarak bu klasörün içine koy (gizli anahtarlar paketinde). Şifre: `yazboz101`.
   Bu klasörü asla GitHub'a yükleme.
3. **Build › Generate Signed App Bundle or APK › Android App Bundle** → anahtarı seç → release.
   Her yeni yüklemede `app/build.gradle` içindeki versionCode'u bir artır.

## Ayarlar
- `app/build.gradle` › `siteHost`: `yazboz101.com`. QR bağlantıları (`https://yazboz101.com/m/KOD`) uygulama yüklüyse
  doğrudan uygulamada açılır (sitede `.well-known/assetlinks.json` gerekir).
- `app/src/main/assets/config.js`: `siteUrl` yazboz101.com. Uygulama canlı paylaşım ayarlarını oradan kendisi alır.
- `app/src/main/assets/index.html`: uygulamanın kendisi, sitedeki `public/index.html` ile aynı dosya.
