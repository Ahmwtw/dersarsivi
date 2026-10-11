# Mimari

```
App (SwiftUI, iOS 17+)
 ├─ GalleryView / SourceDetailView / ExportView
 ├─ AppModel  ── tek durum kaynağı, kuyruğu ön planda işler
 └─ VisionTextExtractor ── Apple Vision, cihaz üstü OCR
        │
Core (saf Swift, Foundation dışında bağımlılık yok)
 ├─ Models        SourceAsset, Page, Block, Correction, ExtractionRun
 ├─ Archive       içeri alma, çıkarım uygulama, düzeltme, cache sorgusu
 ├─ JobQueue      kalıcı, idempotent, sınırlı tekrar denemeli kuyruk
 ├─ ArchiveStore  JSON dosyası + originals/ klasörü, atomik yazma
 ├─ PageSelection "3, 7-9" → 0 tabanlı indeksler
 └─ MarkdownExporter + ExportManifest
```

## Katmanlar
- **Kaynak:** `SourceAsset` + `originals/<uuid>.<ext>`. Değişmez.
- **Çıkarım:** `ExtractionRun` (motor, sürüm, ayar hash'i) ve bloklardaki `rawText`.
- **Düzeltme:** `Correction` kayıtları ve bloklardaki `acceptedText`, `origin = user`, `revision`.
- **Türev:** export dosyaları; arşivde saklanmaz, her seferinde üretilir.

## Kalıcılık
Uygulama destek klasöründe `DersArsivi/`:
```
archive.json        metadata, bloklar, düzeltmeler, iş kuyruğu (schemaVersion)
originals/          orijinal dosyalar
```
Her değişiklikten sonra `archive.json` atomik yazılır. Gelecek şema sürümü olan bir arşiv açılmaz
(veri kaybını önlemek için hata verir).

## Koordinatlar
`BoundingBox` 0...1 normalleştirilmiş, sol üst orijinli, döndürülmemiş orijinal sayfaya göre.
Vision'ın sol alt orijinli kutusu çıkarımda dönüştürülür.

## Yeniden çıkarım kuralı
Yeni çıkarım okuma sırasına göre eşleştirilir. Kullanıcı düzeltmesi olan blokta yalnız `rawText`
güncellenir; metin değiştiyse blok `conflict` olur. Yeni çıkarımda karşılığı olmayan düzeltilmiş blok
silinmez. Okuma sırası değişirse eşleştirme yanlış bloğa düşebilir; bölge (bbox) eşleştirmesi BACKLOG'da.

## Cache
Anahtar: kaynak hash'i + sayfa + motor@sürüm + ayar hash'i. Aynı anahtarla başarılı çıkarım varsa
OCR tekrar çalıştırılmaz.
