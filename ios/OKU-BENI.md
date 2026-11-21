# Yazboz 101 iPhone projesi (1.0, App Store sürümü)

Apple Vision ile telefonda çalışan yazı tanıma (fotoğrafla sayma), kamera/galeri, yazboz101:// bağlantıları, koyu tema.

## Mac'in yoksa: GitHub derlesin ve yüklesin
Depodaki `.github/workflows/ios.yml`, GitHub'ın bulut Mac'inde Xcode 26 ile derler, imzalar ve App Store Connect'e
(TestFlight) yükler. Adımlar MAGAZA-REHBERI.txt dosyasının 3. bölümünde.

## Mac'in varsa
`Yazboz101.xcodeproj`'u Xcode 26 ile aç › Signing & Capabilities › Team seç › Product › Archive › Distribute App.

## Notlar
- Sürüm 1.0. Derleme numarasını GitHub her çalıştırmada kendiliğinden artırır.
- `PrivacyInfo.xcprivacy`: Apple'ın gizlilik bildirimi (izleme yok; yalnızca canlı paylaşımda masa bilgisi ve isimsiz kimlik).
- QR bağlantılarının doğrudan uygulamada açılması (Universal Links) şimdilik kapalı; QR Safari'de açılır ve
  "Uygulamada aç" düğmesiyle uygulamaya geçer. Açmak için: `Yazboz101.entitlements` dosyasını hedefe bağla
  (CODE_SIGN_ENTITLEMENTS), Apple'da App ID'ye Associated Domains ekle ve sitedeki
  `.well-known/apple-app-site-association` içindeki TAKIM_KIMLIGI'ni Team ID ile değiştir.
