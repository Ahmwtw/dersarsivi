# DersArşivi

Ders slaytı, kitap sayfası ve çıkmış soru görsellerini bir kez içeri alıp metnini cihazda okuyan,
düzeltmeleri saklayan ve seçili kaynakları kaynak referanslı Markdown olarak dışa aktaran kişisel
iOS/iPadOS uygulaması. İsim geçicidir.

Durum: ilk dikey dilim (görsel → cihaz üstü OCR → düzeltme → Markdown). Henüz gerçek cihazda
doğrulanmadı; bkz. [docs/VALIDATION.md](docs/VALIDATION.md).

## Depo düzeni

| Klasör | İçerik |
|---|---|
| `Core/` | Platformdan bağımsız Swift paketi: veri modeli, düzeltme sürümleme, iş kuyruğu, Markdown export. Linux'ta da test edilir. |
| `App/DersArsivi/` | SwiftUI uygulaması: galeri, Vision OCR, inceleme/düzeltme, dışa aktarma. |
| `project.yml` | Xcode projesinin tanımı ([XcodeGen](https://github.com/yonaskolb/XcodeGen)). `.xcodeproj` depoda tutulmaz. |
| `.github/workflows/` | Çekirdek testleri (Linux) ve iOS simülatör derlemesi (macOS). |
| `docs/` | Ürün, mimari, kararlar, export şeması, doğrulama ve backlog. |

## Çalıştırma

Mac gerekmez; derleme GitHub Actions'ın macOS makinelerinde yapılır.

- Çekirdek testleri: `swift test --package-path Core` (Swift 5.9+ olan herhangi bir makinede).
- Mac'te uygulama: `brew install xcodegen && xcodegen generate && open DersArsivi.xcodeproj`.
- iPhone/iPad'e kurulum: `main`'e her birleştirmede `.github/workflows/testflight.yml` derleyip TestFlight'a yükler. Depo gizli değerleri gerekir: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.

## Belgeler

[PRODUCT_SPEC](docs/PRODUCT_SPEC.md) · [ARCHITECTURE](docs/ARCHITECTURE.md) · [DECISIONS](docs/DECISIONS.md) ·
[EXPORT_SCHEMA](docs/EXPORT_SCHEMA.md) · [VALIDATION](docs/VALIDATION.md) · [BACKLOG](docs/BACKLOG.md)
