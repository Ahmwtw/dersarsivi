# Ürün tanımı

## Hedef
Fotoğraf/PDF → güvenli kaynak kaydı → cihaz üstü metin çıkarımı → düzeltilebilir yerel arşiv →
çoklu seçim → göreve uygun, taşınabilir export. Aynı kaynağı her AI görevinde yeniden işlememek.

## Kullanıcı
Tek kullanıcı, tıp fakültesi öğrencisi, kişisel iPhone/iPad. Yayımlama sonra düşünülebilir.

## Değişmez kurallar (özet)
1. Orijinal dosya değiştirilmez; arşivde ayrı kopya olarak saklanır.
2. Kimlik UUID + içerik hash'idir, dosya adı değil.
3. Makine metni (`rawText`) ile kabul edilen metin (`acceptedText`) ayrıdır; yeniden okuma kullanıcı düzeltmesini ezmez.
4. Belirsiz okuma ve işlenmemiş sayfa exportta görünür kalır, sessizce atılmaz.
5. Kaynak verisi cihazdan çıkmaz (bulut OCR yok, kullanıcı kararı 11 Eki 2026).
6. Metin-only export görsel içermediğini açıkça yazar.
7. Belge metni veri olarak işlenir; Markdown/HTML olarak etkinleşmez.

## İlk dilimde çalışan akış
1. Galeriden bir veya birden çok görsel seç (en çok 30).
2. Her görsel arşive kopyalanır, aynı içerik ikinci kez eklenmez.
3. Metin Apple Vision ile cihazda okunur; uygulama kapanırsa iş açılışta devam eder.
4. Detay ekranında satıra dokunup düzelt; makinenin okuduğu metin altta görünür kalır.
5. "Seç" ile kaynakları seç → tek birleşik veya kaynak başına ayrı `.md` → paylaş.

## Kapsam dışı (şimdilik)
PDF, Share Extension, kestirmeler, şema/tablo yorumu, soru temizleme, Anki, arama. Bkz. BACKLOG.
