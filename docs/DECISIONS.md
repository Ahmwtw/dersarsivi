# Karar kaydı

| # | Tarih | Karar | Gerekçe | Durum |
|---|---|---|---|---|
| D1 | 2026-10-11 | Kendi OCR modeli eğitilmeyecek | Plan bunu kapsam dışı bırakıyor | Kabul |
| D2 | 2026-10-11 | Kimlik = UUID + SHA-256 içerik hash'i | Yeniden adlandırma ilişkiyi bozmasın, tekrar içeri alma yakalansın | Kabul |
| D3 | 2026-10-11 | İlk export biçimi Markdown | Her AI aracı okuyabilir; JSON/ZIP P1 | Kabul |
| D4 | 2026-10-11 | OCR: Apple Vision, cihaz üstü | Ücretsiz, çevrimdışı, veri cihazdan çıkmaz; kullanıcı ücretli bulut istemiyor | Kabul, benchmark ile ölçülecek |
| D5 | 2026-10-11 | Native iOS (SwiftUI, iOS 17+) | Kullanıcı native istedi; Mac şart değil | Kabul |
| D6 | 2026-10-11 | Kişisel kullanım öncelikli | Kullanıcı cevabı | Kabul |
| D7 | 2026-10-11 | Bulut OCR yok | Kullanıcı ücret ödemek istemiyor, cihaz üstünü tercih ediyor | Kabul |
| D8 | 2026-10-11 | Derleme GitHub Actions macOS, dağıtım TestFlight | Kullanıcının Mac'i yok; ücretli Apple Developer hesabı var; TestFlight 7 günlük yeniden imza derdini kaldırır | Kabul |
| D9 | 2026-10-11 | Türkçe OCR desteği cihazda kontrol edilecek | Bulunan Vision dil listelerinde `tr-TR` yok; uygulama cihazın desteklediği dilleri detay ekranında gösterir. Yoksa yedek: cihaz üstü Tesseract (`tur`) | Açık |
| D10 | 2026-10-11 | İlk dilimde kalıcılık tek JSON dosyası, `ArchiveStore` protokolü arkasında | Bağımlılıksız, Linux'ta test edilebilir, ilk dilim için yeterli. Arama (FTS) ve büyük arşiv gelince SQLite/GRDB'ye geçiş | Geçici |
| D11 | 2026-10-11 | Depo herkese açık | Açık depoda macOS derleme dakikası ücretsiz; kişisel veri depoya girmez | Kabul |
| D12 | 2026-10-11 | Xcode projesi XcodeGen ile üretilir | Mac olmadan `.xcodeproj` elle düzenlenemez; `project.yml` okunabilir ve birleştirme dostu | Kabul |
| D13 | 2026-10-11 | SHA-256 çekirdekte saf Swift | CryptoKit Linux'ta yok; bağımlılık eklememek için | Kabul |
| D14 | 2026-10-11 | Bundle ID `com.ahmwtw.dersarsivi` | GitHub kullanıcı adına göre varsayılan; App Store Connect kaydında değiştirilebilir | Varsayım |
