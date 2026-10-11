# Backlog

## P0
- [x] P0-1 Veri modeli, içerik hash'i, kalıcı JSON arşiv (Core)
- [x] P0-2 Düzeltme sürümleme, yeniden çıkarımda koruma (Core)
- [x] P0-3 Kalıcı iş kuyruğu, kesinti sonrası devam (Core + App)
- [x] P0-4 Kaynak referanslı Markdown export, tek/ayrı dosya, eksik sayfa uyarısı (Core + App)
- [x] P0-5 Galeriden görsel içeri alma, galeri, detay, düzeltme ekranı (App, cihazda doğrulanmadı)
- [x] P0-6 Apple Vision ile cihaz üstü OCR (App, cihazda doğrulanmadı)
- [x] P0-7 CI'da testlerin ve simülatör derlemesinin yeşil olması
- [ ] P0-8 TestFlight hattı: iş akışı yazıldı, depo gizli değerleri ve App Store Connect kaydı bekleniyor
- [ ] P0-9 Türkçe OCR doğrulaması; gerekirse Tesseract `tur`
- [ ] P0-10 PDF içeri alma (Files), PDFKit önizleme, sayfa seçimi, metin katmanı + OCR yedeği
- [ ] P0-11 Temel tam metin arama
- [ ] P0-12 Kaynağı silme / çöp kutusu

## P0.5 (kullanıcı isteği, 2026-10-11)
- [x] Yazı rengi ve fosforlu kalem vurgusu (piksel rengi, cihaz üstü, tüm cihazlar; cihazda doğrulanmadı)
- [ ] Kalın yazı tahmini (yaklaşık)
- [ ] Tablo ve liste yapısı: Vision `RecognizeDocumentsRequest` (iOS 26+)
- [ ] Şema/grafik betimleme ve yapılandırılmış ilişkiler: Foundation Models görsel girdisi (Apple Intelligence; iPad Air M3 var, iPhone 13 yok)
- [x] Figür kırpımı: otomatik öneri (metin dışı bölge + yakın etiketler) + elle ayar, küçük JPEG, `.md` + `figures/` + `manifest.json` ZIP export (cihazda doğrulanmadı)
- [x] Not uygulaması araç çubuğu yazılarını ele (sayfa alanı dışı)
- [ ] Tablo okuma sırası: tablolar şu an hücre hücre karışık çıkıyor (RecognizeDocumentsRequest ile)
- [ ] Şema etiketlerinin OCR konumlarıyla Anki image occlusion kartı (kullanıcının önceliği 2)
- [ ] Farklı türlerden 10-20 örnekle düzen/paragraf test seti (kullanıcıdan örnek bekleniyor)
- [ ] Yıldız, daire, el ile işaretler (deneysel)

## Kullanıcı notları (2026-10-11, şimdilik yapılmayacak)
- Pratik kısayollar: tümünü seç vb.
- Klasör oluşturma, görselleri klasörlere ayırma
- Promptlu export şablonları: flashcard, Anki uyumlu kart, özet, çıkmış soruları temize geçirme + en sonda cevap anahtarı, uygulama içi Anki ile uyumlu kart, quiz (çeşitlendirilecek)
- UI tasarımı sonra; önce işlev
- PDF ekleme (P0-10) öncelikli

## P1
Share Extension · App Intent "Arşive ekle" · kestirme doğrulaması · bölge (bbox) ile blok eşleştirme ·
iki sütun okuma sırası · şema/tablo yorumu · JSON round-trip · figürlü ZIP · soru temizleme ·
Anki TSV profili · yedek/geri yükleme · koleksiyon ve etiket · SQLite/GRDB geçişi (D10)

## P2
Uygulama içi Anki (kesin değil) · Semantic search · iCloud/çok cihaz (iPhone'da çekilen şemayı iPad'in betimlemesi) · APKG/image occlusion · gelişmiş tekrar/benzerlik tespiti
- El notlu (yoğun el yazısı) bölgeyi kendiliğinden şekil olarak öner; ikinci ölçüm paketinde kullanıcı bu bölgeleri elle kırptı.
