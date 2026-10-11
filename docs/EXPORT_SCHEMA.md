# Export şeması (sürüm 1)

## Markdown (`.md`)

```markdown
# DersArşivi dışa aktarımı

Profil: sadık metin · Kaynak sayısı: 1 · Tarih: 2026-10-11T18:00:00Z · Export: 6f1c…

Metin kaynak görüntüsünden OCR ile çıkarıldı; ✏️ kullanıcı tarafından düzeltilmiş, ⚠️ belirsiz bölümleri gösterir. Bu dosya görsel içermez.

> **Eksik içerik:**
> - Biyokimya PDF: 3 sayfa işlenmediği için metni yok

## Kaynak: Biyokimya PDF

- Kimlik: `0d6e…`
- Dosya: glikoliz.pdf (PDF)
- Seçili sayfalar: 3, 7–9 / 10

### Sayfa 3

Glikoliz sitoplazmada gerçekleşir ✏️

Hekzokinaz
> ⚠️ Belirsiz: OCR güveni düşük (%42)

### Sayfa 7

> ⚠️ Bu sayfa işlenmedi (durum: failed: zaman aşımı); metni bu dosyada yok.
```

Kurallar:
- Tek görselde sayfa başlığı yazılmaz; PDF veya çok sayfada `### Sayfa N` (1 tabanlı; PDF etiketi farklıysa ikisi birden).
- OCR metnindeki `<`, `>`, `&` kaçırılır; satır başındaki `#`, `=`, `---` etkisizleştirilir.
- Biçim: `==metin==` fosforlu kalem vurgusu (sarı değilse `==metin== (yeşil vurgu)`), `⟦turuncu: metin⟧` renkli yazı. Renkler kelime kutusundaki piksellerden tahmin edilir; paragrafın tamamı aynı renkteyse (ör. mavi şablon başlıkları) renk yazılmaz. Kullanıcı düzelttiği blokta biçim düşer.
- `✏️` kullanıcı düzeltmesi, `⚠️ Belirsiz` düşük güven (< 0,5, kalibre değil), çatışma veya motor uyarısı.

## Manifest (JSON, `ExportManifest`)

```json
{
  "schemaVersion": 1,
  "exportID": "…",
  "createdAt": "2026-10-11T18:00:00Z",
  "profile": "faithful_text",
  "mode": "combined",
  "partialExport": true,
  "warnings": ["Biyokimya PDF: 3 sayfa işlenmediği için metni yok"],
  "sources": [{
    "sourceID": "…", "title": "Biyokimya PDF", "contentHash": "sha256 hex",
    "selectedPageIndices": [2, 6, 7, 8], "includedPageIndices": [2],
    "missingPages": [{"pageIndex": 6, "status": "imported"}],
    "uncertainBlockCount": 1, "file": "dersarsivi-6f1c….md"
  }]
}
```
Sayfa indeksleri 0 tabanlıdır. Manifest şu an uygulama içinde üretilir ama paylaşılmaz; JSON export P1.
