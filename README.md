# Yazboz 101

101 Okey skor uygulaması: https://yazboz101.com

- `android/` Google Play sürümü (Android Studio projesi)
- `ios/` App Store sürümü (Xcode projesi)
- `.github/workflows/android.yml` → Actions sekmesinden **Android paketi**: Google Play'e yüklenecek `.aab`
- `.github/workflows/ios.yml` → Actions sekmesinden **iOS - TestFlight'a yükle**: Mac olmadan derler ve App Store Connect'e yükler

Gizli anahtarlar (imza dosyası, şifreler, API anahtarları) bu depoya konmaz; yalnızca
Settings › Secrets and variables › Actions bölümüne eklenir.
