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
| D15 | 2026-10-11 | Şekil bulma kural tabanlı ve cihaz üstü: zeminden farklı, yazısı silinmiş, yeterince büyük bölge | Model gerektirmez, her cihazda çalışır, belirli bir şablona göre ayarlanmaz. Öneridir; kullanıcı tek dokunuşla kaydeder, ayarlar veya yoksayar | Kabul |
| D16 | 2026-10-11 | Ekran görüntüsünde sayfa alanı dışındaki yazılar atılır | Not uygulamasının araç çubuğu ("50", "33") metne karışıyordu. Satırların %30'undan fazlası dışarıda kalırsa alan güvenilmez sayılır, hiçbir şey atılmaz | Kabul |
| D17 | 2026-10-11 | Şekilli export tek ZIP: `.md` + `figures/*.jpg` + `manifest.json` (etiket kutuları şekle göreli) | AI'a ve ileride Anki image occlusion'a tek dosyayla verilebilir; ZIP yazıcı bağımlılıksız (stored) | Kabul |
| D18 | 2026-10-11 | Eğik sayfa fotoğrafı okumadan önce düzleştirilir (Vision sayfa köşeleri + perspektif düzeltme; köşe yoksa satır eğimine göre döndürme). Türev `pages/` altında, orijinal değişmez | Eğik fotoğrafta satırlar üst üste biniyor, okuma sırası bozuluyordu. Ekran görüntüleri eğik olmadığı için etkilenmez | Kabul |
| D19 | 2026-10-11 | Renk algısında kâğıda göre beyaz dengesi | Sarımsı ışıkta siyah yazı "turuncu" sayılıyordu | Kabul |
| D20 | 2026-10-11 | Şekil bulmada sık görülen düz renkler (metin paneli, tablo satırı, uygulama düğmesi) ikinci zemin sayılır; sayfa genişliğinde ince şeritler şekil değildir; etiketler zincirlenmez, şeklin dışındaki uzun satır etiket olmaz | Kullanıcının ikinci testinde düğmeler, tablo ve beyaz panel şekil sanıldı; paragraf satırları etikete karıştı | Kabul |
| D21 | 2026-10-11 | Şeklin içine düşen uzun metin (40 karakterden uzun) metinde kalır; yalnız kısa etiketler metinden çıkarılır | Yanlış geniş kırpımda metin kayboluyordu | Kabul |
| D22 | 2026-10-11 | Ekran görüntüleri (PNG) düzleştirilmez/döndürülmez; döndürme için satırların %60'ı aynı eğimde olmalı | Fotoğraf kolajı içeren ekran görüntüsü gereksiz döndürülüyordu | Kabul |
| D23 | 2026-10-11 | "Yeniden oku" önbelleği atlar; kaydedilmiş ve yoksayılmış şekiller korunur, yalnız bekleyen öneriler yenilenir | Aynı ayarla yapılmış çıkarım önbellekten döndüğü için düğme hiçbir şey yapmıyordu | Kabul |
| D24 | 2026-10-11 | Kaynak silme: orijinal dahil tüm türevler (sayfa görüntüsü, kırpımlar), bloklar, düzeltmeler ve işler silinir; onay sorulur | Aynı görsel yeniden eklenemiyordu, silme yolu yoktu | Kabul |
| D25 | 2026-10-11 | Şekil bulmada iki zemin renginin sınırındaki hücreler mürekkep sayılmaz; dokulu ve koyu çerçeve olmayan sütunlar içerik alanına girer; içerik kenarına yapışık dar parçalar önerilmez | Koyu slayttaki histoloji görseli kaçıyor, panel kenarı ve kenardan taşan kesit öneriliyordu | Kabul |
| D26 | 2026-10-11 | "Sil" şekli tamamen siler (yeniden okumada tekrar önerilebilir); "Yoksay" yeri hatırlar | Kullanıcı sildiği kırpımın yeniden önerilmemesini hata sandı; iki düğmenin farkı böylece anlamlı | Kabul |
| D27 | 2026-10-11 | Büyük şekil bölgesi genişletmesiz yeniden bölünür; seyrek ve tek doygun renkli bölge (kalem notu) önerilmez | Şema el yazısı ve yıldızla birleşip metin sayılıyor, hiç önerilmiyordu; mor kalem notları şekil sanılıyordu | Kabul |
| D28 | 2026-10-11 | Kırpma algılamasını kusursuzlaştırmak yerine kullanımı hızlandırmak: önerileri onaysız kaydetme ayarı, galeride kutu önizlemesi, "tüm sayfa şekil" düğmesi, isteğe bağlı sayfa görüntüsü dışa aktarımı | Her yeni görsel türü yeni bir kural hatası çıkarıyordu; karışık sayfaları yapay zekâ görüntüden okuyabilir | Kabul |
| D29 | 2026-10-11 | Ölçüm paketi: orijinal/okunan görüntü, OCR satırları (sayfa başına `lines/` dosyası), öneriler ve kararlar | Algılama değişikliklerini cihazdaki girdilerle birebir ölçmek; farklı OCR ile taklit yanıltıyordu | Kabul |
