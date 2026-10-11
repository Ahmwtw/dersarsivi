# DersArşivi yol haritası

Son güncelleme: 2026-10-11. Kullanıcının isteklerinden derlenmiş, geliştirilmiş hedef tanımı ve sıralı aşamalar.

## Geliştirilmiş hedef tanımı (ana prompt)

DersArşivi, tıp öğrencisinin slayt ekran görüntülerini, kitap/soru fotoğraflarını ve PDF'lerini tek yerde toplayan,
cihaz üstünde okuyan ve yapay zekâya (ChatGPT, Claude, Gemini) verilmeye hazır, kaynağı belli çalışma
paketlerine dönüştüren bir iPad/iPhone uygulamasıdır.

Değişmez ilkeler:

1. **Hiçbir şey kaybolmaz.** Okunamayan, karışık veya el yazılı içerik metne zorlanmaz; görüntü olarak saklanır ve
   dışa aktarımda görüntüyle gider. Metin ile görüntü birbirinin yerine değil, tamamlayıcısı olarak kullanılır.
2. **Önemli olan işaretlenir.** Fosforlu kalem, renkli yazı, yanına yıldız/ünlem/çarpı/çiçek konmuş satır ve el notları
   dışa aktarımda açıkça belirtilir; yapay zekâ "bu satır vurgulanmış" bilgisini görür.
3. **Kullanıcı tek tek onaylamaz.** Uygulama doğru tahmin eder ve otomatik kaydeder; kullanıcı yalnız yanlışı düzeltir.
   Karar gerektiren yerler toplu işlemle (tümünü seç, toplu etiketle) çözülür.
4. **Cihaz üstü ve gizli.** OCR ve analiz cihazda yapılır; içerik kullanıcı paylaşmadıkça dışarı çıkmaz.
5. **Dışa aktarım ürünün kalbidir.** Her dışa aktarım, seçilen amaca uygun hazır bir talimatla (prompt) birlikte gelir;
   kullanıcı dosyayı yapay zekâya bırakır ve talimatı yapıştırır, ya da talimat dosyanın başında hazırdır.
6. **Özenli arayüz.** Sistem görünümüne uyan, iPad'de geniş ekranı kullanan, iOS 26'da Liquid Glass kullanan, sade
   ve hızlı bir arayüz. Gösteriş için değil, kullanım hızı için tasarım.

## Aşamalar

### Aşama 1: Algılamanın son kontrolü (şimdi)

- [x] Sıkışık satırlarda okuma sırası (satırlar üst üste binince soldan sağa diziliyordu)
- [x] Her slaytta tekrarlanan logo/üniversite yazısını dışa aktarımdan çıkar
- [x] Vurgu işaretleri: satırın yanındaki yıldız, ünlem, çarpı, çiçek gibi işaretler "işaretli" olarak dışa aktarılır
- [x] El yazısı: renkli kalemle yazılmış, düşük güvenle okunan satırlar el notu sayılır; el notu bölgesi görüntü
      olarak kendiliğinden kaydedilir
- [x] "Sadece görsel" modu: karışık sayfalar (el yazısı ağırlıklı, etiket yığını) kendiliğinden bu moda geçer;
      kullanıcı seçtiği görselleri bu moda alabilir. Bu sayfalar dışa aktarımda optimize edilmiş görüntü olarak gider
- [x] Galeride "Tümünü seç"
- [x] PR #1'in birleştirilmesi

### Aşama 2: Kullanılabilir uygulama

- [x] **PDF içe aktarma:** Dosyalar'dan PDF, sayfa küçük resimleri, sayfa aralığı seçimi, metin katmanı varsa doğrudan
      kullanım, yoksa OCR
- [x] **Klasörler:** "Fizyoloji" gibi klasörler; görsel ve PDF aynı klasörde; alt klasör; bir kaynağı taşıma; klasörü
      tek seferde dışa aktarma
- [x] **Hazır talimatlı dışa aktarım (prompt kütüphanesi):** aşağıdaki listeden amaç seçilir, talimat dosyanın başına
      eklenir ve ayrıca kopyalanabilir
- [x] **Yeni arayüz:** kenar çubuklu iPad düzeni (Tümü / Klasörsüz / İşaretli ve notlu / Okunmayı bekleyen / klasörler),
      kartlı galeri, alttaki cam eylem çubuğu, Liquid Glass (iOS 26); iPhone'da aynı yapı tek sütun
- [x] iPad'de sayfa ile metni yan yana gösteren detay; sayfa üstünde satıra dokununca düzeltme
- [x] Ayarlar: vurgu ve işaret renkleri, açık/koyu görünüm, kart boyutu
- [x] Tam metin arama (tüm kaynaklarda)

### Aşama 3: Akıllı özellikler

- [x] Tablo yapısı (Vision RecognizeDocumentsRequest, iOS 26): tablo Markdown tablosu olarak dışa aktarılır (D45)
- [ ] Cihaz üstü şema betimleme (Apple Intelligence olan cihazlarda)
- [ ] Şema etiketlerinden görsel kapatmalı (image occlusion) Anki kartı
- [ ] Paylaş menüsünden doğrudan arşive ekleme, Kestirmeler
- [ ] Yedekleme / geri yükleme, iCloud ile cihazlar arası eşitleme
- [ ] TestFlight dağıtımı (Apple Developer hesabı onaylanınca)

Uygulama içi Anki şimdilik yok (kullanıcı kararı).

## Prompt kütüphanesi

Her şablon: amaç, yapay zekâya talimat, beklenen çıktı biçimi. Hepsi kaynakta olmayan bilgiyi eklememeyi, vurgulu
ve işaretli satırlara öncelik vermeyi, sayfa kaynağını belirtmeyi ister.

| Şablon | Ne üretir |
|---|---|
| Anki destesi (TSV) | Front/Back/Tags/Source/Priority sütunlu, Anki'ye doğrudan alınabilir TSV; A/B öncelik, C detaylar ayrı liste |
| Boşluk doldurmalı Anki (cloze) | `{{c1::...}}` biçiminde cloze kartları |
| Görselli Anki | Şekil dosyalarına bağlı soru kartları (ZIP ile) |
| Özet | Başlıklı, madde madde ders özeti; vurgulu bilgiler kalın |
| Sınav öncesi tekrar notu | Tek sayfalık "son gece" notu: sayılar, tanımlar, sık karıştırılanlar |
| Çıkmış soruları temize geçir | Soru kökü ve şıklar temiz; işaretler ayrı; en sonda cevap anahtarı (kaynakta varsa) |
| Quiz | Kaynaktan çoktan seçmeli sorular, en sonda açıklamalı cevaplar |
| Doğru / yanlış | Hızlı tekrar için D/Y ifadeleri |
| Kavram haritası | Mermaid diyagramı olarak kavram ilişkileri |
| Karşılaştırma tablosu | Benzer kavramları (ör. sempatik/parasempatik) tablo halinde |
| Mekanizma zinciri | Neden-sonuç adımları (ör. ilaç → reseptör → etki) |
| Klinik bağlantılar | Konunun klinik karşılıkları, kaynakta olanla sınırlı |
| Akılda kalıcı ipuçları | Kısaltma ve hafıza teknikleri, kaynak dışı olduğu belirtilerek |
| El notlarını temize çek | El yazısı görüntülerini okunaklı metne çevir, belirsizi işaretle |
| Eksik/çelişki kontrolü | Kaynaklar arasındaki çelişkileri ve eksik görünen yerleri listele |
| Serbest | Yalnız kaynak paketi, talimatsız |

## Çalışma biçimi

- Algılama değişiklikleri önce ölçüm paketlerinde (`olcum/`) ölçülür, sonra cihaza gider.
- Her aşama küçük, test edilmiş adımlarla ilerler; her adımdan sonra yüklenebilir ipa hazırlanır.
- Kararlar `docs/DECISIONS.md`'ye yazılır.
