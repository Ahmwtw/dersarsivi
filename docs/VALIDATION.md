# Doğrulama

Bu dosya yalnız gerçekten çalıştırılan doğrulamaları kaydeder.

## Otomatik testler (`Core/Tests`)
SHA-256 bilinen vektörler; sayfa seçimi ("3, 7-9", hatalı girişler); aynı içeriğin tekrar içeri alınması;
düzeltme revizyonu; yeniden çıkarımın düzeltmeyi ezmemesi; karşılıksız düzeltilmiş bloğun korunması;
cache anahtarı; kaydet/aç sonrası arşiv ve Türkçe karakterler; kesintide işin yeniden sıraya girmesi ve
sınırlı tekrar; exportta düzeltme, belirsizlik, eksik sayfa, kaynak başına dosya, Markdown/HTML kaçırma,
manifest JSON gidiş-dönüş.

| Tarih | Ortam | Sonuç |
|---|---|---|
| 2026-10-11 | GitHub Actions, ubuntu-24.04 ve macos-15 (Xcode 16.4) | İlk koşu derlenmedi (test yardımcısı `run` adı XCTestCase ile çakıştı); düzeltmeden sonra tüm testler geçti |

## iOS
| Kontrol | Durum |
|---|---|
| Simülatör için derleme (CI) | Geçti: macos-15 / Xcode 16.4 ve macos-26, 2026-10-11. Yalnız derleme; simülatörde çalıştırılmadı |
| Gerçek cihazda içeri alma → OCR → export | 2026-10-11, iPad Air M3 / iPadOS 27, Sideloadly ile: 2 slayt ekran görüntüsü okundu, Türkçe karakterler doğru, birleşik .md üretildi. Sorunlar: galeride küçük resimler üst üste bindi; iki sütunlu slaytta sütunlar satır satır karıştı; her satır ayrı paragraf oldu; not uygulamasının araç çubuğu rakamları ("50", "33") metne girdi. İlk ikisi `LayoutAnalyzer` ve galeri düzeltmesiyle ele alındı, cihazda yeniden doğrulanmadı |
| Vision Türkçe desteği (`tr-TR`) | Yapılmadı; detay ekranındaki dil listesinden okunacak |
| Uygulama kapanıp açılınca kuyruk ve düzeltme | Çekirdekte test var; cihazda yapılmadı |
