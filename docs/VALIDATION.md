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
| 2026-10-11 | Yazıldı; bulut çalışma ortamında Swift yok | Henüz çalıştırılmadı. İlk CI koşusu sonucu buraya eklenecek |

## iOS
| Kontrol | Durum |
|---|---|
| Simülatör için derleme (CI) | Henüz çalıştırılmadı |
| Gerçek cihazda içeri alma → OCR → düzeltme → export | Yapılmadı (TestFlight bekleniyor) |
| Vision Türkçe desteği (`tr-TR`) | Yapılmadı; detay ekranındaki dil listesinden okunacak |
| Uygulama kapanıp açılınca kuyruk ve düzeltme | Çekirdekte test var; cihazda yapılmadı |
