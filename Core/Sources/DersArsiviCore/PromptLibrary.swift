import Foundation

/// Hazır talimatın doldurulacağı export bilgileri.
public struct PromptContext: Equatable, Sendable {
    /// Anki deste adı; klasörden türetilir (ör. "DersArşivi::Fizyoloji").
    public var deckName: String
    public var sourceCount: Int
    /// Pakette şekil veya sayfa görüntüleri var mı.
    public var includesImages: Bool

    public init(deckName: String = "DersArşivi", sourceCount: Int = 1, includesImages: Bool = false) {
        self.deckName = deckName
        self.sourceCount = sourceCount
        self.includesImages = includesImages
    }
}

/// Markdown paketinin başına konan veya panoya kopyalanan yapay zekâ talimatı.
public struct PromptTemplate: Identifiable, Equatable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case study
        case anki
        case questions
        case review
    }

    /// Kalıcı ASCII kimlik (ör. "anki-tsv").
    public let id: String
    /// Arayüzde gösterilen kısa başlık.
    public let title: String
    /// Arayüzde gösterilen tek satırlık açıklama.
    public let summary: String
    /// SF Symbol adı.
    public let symbol: String
    public let category: Category
    /// Doğruysa arayüz şekil/sayfa görüntülerini varsayılan olarak açar.
    public let recommendsImages: Bool
    /// Kullanıcının yapay zekâdan geri alacağı çıktı.
    public let outputHint: String
    /// Yer tutuculu talimat metni: {DESTE}, {KAYNAK_SAYISI}.
    let body: String

    /// Yer tutucuları doldurur, ortak kuralları ve gerekirse görsel notunu ekler.
    public func instructions(_ context: PromptContext) -> String {
        var text = body
            .replacingOccurrences(of: "{DESTE}", with: context.deckName)
            .replacingOccurrences(of: "{KAYNAK_SAYISI}", with: String(context.sourceCount))
        text += "\n\n### Genel kurallar\n"
        text += PromptLibrary.sharedRules
        if context.includesImages {
            text += "\n\n" + PromptLibrary.imageNote
        }
        return text
    }
}

extension PromptTemplate.Category {
    /// Arayüzde gösterilen Türkçe ad.
    public var title: String {
        switch self {
        case .study: return "Çalışma"
        case .anki: return "Anki"
        case .questions: return "Sorular"
        case .review: return "Kontrol"
        }
    }
}

/// Yerleşik talimatlar. Sıra arayüzdeki sıradır: çalışma, Anki, sorular, kontrol.
public enum PromptLibrary {
    public static let all: [PromptTemplate] = [
        ozet, sonGece, kavramHaritasi, karsilastirma, mekanizma, klinik, hafiza,
        ankiTSV, ankiCloze, ankiGorsel,
        soruTemize, soruCoz, quiz, dogruYanlis, boslukDoldurma,
        elNotu, duzelt, eksikKontrol,
    ]

    public static func template(id: String) -> PromptTemplate? {
        all.first { $0.id == id }
    }

    /// Her talimatın sonuna eklenen ortak kurallar ve paketteki işaretlerin anlamı.
    public static let sharedRules: String = """
        1. Yalnızca ekteki kaynaklardaki bilgileri kullan; kaynakta olmayan bilgi, sayı, doz veya tanım uydurma.
        2. Bir yer belirsiz, okunamıyor ya da eksikse tahmin yürütme; "kaynakta net değil" yaz.
        3. ⭐ ile başlayan satırlar, vurgulu (==...==) ve renkli (⟦...⟧) yazılar ve ✍️ el notları hocanın veya öğrencinin vurgusudur; bunlara öncelik ver. Yine de "hoca kesin sorar" gibi kesin iddialarda bulunma. Kendi çıktında ⭐ ve ✍️ işaretlerini yalnız kaynakta bu işareti taşıyan bilgiler için kullan.
        4. Yararlı olduğu yerde kaynağı "Kaynak adı, Sayfa N" biçiminde belirt.
        5. Metin eksik ya da bozuksa veya sayfa "Bu sayfa görsel olarak aktarıldı" notuyla verilmişse bilgiyi ilgili şekilden ya da sayfa görüntüsünden oku.
        6. Türkçe yanıt ver; tıbbi terimleri kaynakta geçtiği gibi (Türkçe, Latince veya İngilizce) koru.

        Paketteki işaretler:
        - Her kaynak `## Kaynak: <ad>`, her sayfa `### Sayfa N` başlığıyla başlar.
        - `==metin==`: fosforlu kalemle vurgulanmış (sarı değilse rengi yanında yazar). `⟦renk: metin⟧`: renkli yazılmış.
        - Satır başındaki `⭐`: öğrenci bu satırın yanına işaret koymuş (yıldız, ünlem, çarpı, etiket); önemli.
        - `✍️`: öğrencinin el notu. OCR okuması tahmindir; notun görüntüsü varsa "El notu N" adlı şekil olarak eklenmiştir.
        - `| ... |` satırları sayfadaki tablonun Markdown hâlidir; ilk satır başlıktır, hücreler OCR ile okunmuştur.
        - `⚠️ Belirsiz`: OCR'ın emin olmadığı yer. `✏️`: kullanıcı tarafından düzeltilmiş, güvenilir.
        - Şekiller `![Şekil N](figures/...)` biçimindedir ve altlarında etiket listesi bulunur; sayfa görüntüleri `![Sayfa N görüntüsü](pages/...)` biçimindedir.
        """

    /// Pakette görsel olduğunda talimatın sonuna eklenen satır.
    static let imageNote = "Not: Bu pakette şekil ve/veya sayfa görüntüleri de var (figures/ ve pages/ klasörleri); metni bunlarla karşılaştır, şekil etiketlerini, tabloları ve el yazısını görüntüden kontrol et."

    // MARK: - Çalışma

    private static let ozet = PromptTemplate(
        id: "ozet",
        title: "Konu özeti",
        summary: "Başlıklar, kalın vurgular ve tablolarla düzenli ders özeti",
        symbol: "doc.text",
        category: .study,
        recommendsImages: false,
        outputHint: "Başlıklı Markdown özet",
        body: """
            ## Görev: Konu özeti
            Ekteki {KAYNAK_SAYISI} kaynaktan, sınava çalışırken baştan sona okunabilecek düzenli bir ders özeti hazırla.

            ### Kurallar
            1. Kaynaktaki konu sırasını koru; her ana konu için `##`, alt konular için `###` başlık kullan.
            2. Her başlığın altına kısa maddeler yaz; uzun paragraflardan kaçın.
            3. Önemli bilgileri **kalın** yaz. ⭐ işaretli, vurgulu ve renkli satırlardaki bilgileri ve ✍️ el notlarını mutlaka özete al.
            4. Sınıflamalar, karşılaştırmalar ve sayısal değerler için tablo kullan.
            5. Sayıları, birimleri, dozları ve eşik değerleri kaynaktaki gibi aynen aktar; yuvarlama.
            6. Kaynakta açılımı verilen kısaltmaları ilk geçtikleri yerde açılımıyla yaz.
            7. Her ana başlığın sonunda kaynağı belirt: _(Kaynak adı, Sayfa N–M)_.
            8. En sonda **Net olmayan noktalar** başlığıyla kaynakta eksik, okunamayan veya çelişkili kalan yerleri listele.

            ### Çıktı biçimi
            ```markdown
            ## Konu adı
            - **Ana bilgi**: kısa açıklama
            - ...

            | Özellik | A | B |
            |---|---|---|
            | ... | ... | ... |

            _(Kaynak adı, Sayfa 3–5)_
            ```
            """
    )

    private static let sonGece = PromptTemplate(
        id: "son-gece",
        title: "Son gece tekrarı",
        summary: "Sayılar, tanımlar ve karıştırılanlarla tek sayfalık tekrar kâğıdı",
        symbol: "moon.stars",
        category: .study,
        recommendsImages: false,
        outputHint: "Tek sayfalık tekrar notu",
        body: """
            ## Görev: Son gece tekrar sayfası
            Ekteki kaynaklardan, sınavdan önceki gece 10–15 dakikada okunabilecek tek sayfalık bir tekrar kâğıdı hazırla.

            ### Bölümler (bu sırayla)
            1. **Sayılar ve değerler**: normal değerler, eşikler, dozlar, yüzdeler, süreler. Tablo: | Değer | Ne için | Kaynak |
            2. **Tanımlar**: en fazla birer cümlelik net tanımlar.
            3. **Karıştırılan ikililer**: birbirine benzeyen kavramlar ve aralarındaki belirleyici fark. Tablo: | Kavram 1 | Kavram 2 | Ayırt ettiren fark |
            4. **Mutlaka bil**: ⭐ işaretli, vurgulu ve renkli satırlarda ve ✍️ el notlarında öne çıkan bilgiler; en fazla 15 madde.
            5. **Tuzaklar**: kaynakta "değil", "hariç", "en sık", "ilk" gibi ifadelerle verilen ve kolayca ters hatırlanabilecek bilgiler.

            ### Kurallar
            - Toplam uzunluk yaklaşık bir A4 sayfasını geçmesin; açıklama ve giriş cümlesi yazma.
            - Her madde tek satır olsun; sayıları ve birimleri kaynaktaki gibi aynen yaz.
            - Kaynakta karşılığı olmayan bir bölüm için madde uydurma; o bölüme yalnızca "Kaynakta yok" yaz.
            """
    )

    private static let kavramHaritasi = PromptTemplate(
        id: "kavram-haritasi",
        title: "Kavram haritası",
        summary: "Kavramlar arasındaki ilişkileri gösteren Mermaid şeması",
        symbol: "point.3.connected.trianglepath.dotted",
        category: .study,
        recommendsImages: false,
        outputHint: "Mermaid kavram haritası ve kısa açıklama",
        body: """
            ## Görev: Kavram haritası
            Ekteki kaynaklardaki ana kavramları ve aralarındaki ilişkileri gösteren bir Mermaid kavram haritası çiz.

            ### Kurallar
            1. Haritayı tek bir `mermaid` kod bloğu içinde `flowchart TD` (yukarıdan aşağı) olarak yaz.
            2. Düğüm sayısını 15–35 arasında tut; konu çok genişse alt konular için ayrı haritalar çiz.
            3. Düğüm kimlikleri kısa ve ASCII olsun (A1, B2...); etiketleri çift tırnak içinde yaz: `A1["Böbrek"]`.
            4. Okların üzerine ilişkiyi kısa bir ifadeyle yaz: `A1 -->|"salgılar"| B1`.
            5. ⭐ işaretli, vurgulu veya renkli satırlardan gelen kavramları `:::onemli` sınıfıyla işaretle ve bloğun sonuna `classDef onemli fill:#ffe9a8,stroke:#c99a00` satırını ekle.
            6. Etiketlerde tırnak işareti kullanma; parantez ve iki nokta gibi özel karakterleri yalnızca çift tırnak içinde kullan.
            7. Haritada yalnızca kaynakta geçen kavramlar ve ilişkiler yer alsın.

            ### Çıktı biçimi (yalnızca biçim örneği)
            ```mermaid
            flowchart TD
                A1["Anjiyotensinojen"] -->|"renin ile"| B1["Anjiyotensin I"]
                B1 -->|"ACE ile"| C1["Anjiyotensin II"]:::onemli
                classDef onemli fill:#ffe9a8,stroke:#c99a00
            ```

            Haritanın altına **Açıklama** başlığıyla 3–6 maddelik kısa bir lejant yaz: renklerin anlamı ve haritada gösterilemeyen önemli noktalar (kaynaklarıyla birlikte).
            """
    )

    private static let karsilastirma = PromptTemplate(
        id: "karsilastirma",
        title: "Karşılaştırma tabloları",
        summary: "Birbirine benzeyen kavramları yan yana koyar",
        symbol: "tablecells",
        category: .study,
        recommendsImages: false,
        outputHint: "Karşılaştırma tabloları",
        body: """
            ## Görev: Karşılaştırma tabloları
            Ekteki kaynaklarda birbirine benzeyen ve sınavda karıştırılabilecek kavramları (hastalıklar, ilaçlar, yapılar, mekanizmalar, testler) bul ve karşılaştırma tablolarıyla göster.

            ### Kurallar
            1. Her karşılaştırma grubu için ayrı bir başlık ve bir Markdown tablosu yap.
            2. Satırlar özellikler, sütunlar karşılaştırılan kavramlar olsun. Ölçütleri kaynaktaki bilgiye göre seç (ör. etiyoloji, mekanizma, bulgu, tanı, tedavi, yan etki).
            3. Kaynakta bir hücre için bilgi yoksa "—" yaz; hücreyi doldurmak için bilgi uydurma.
            4. Kavramları birbirinden ayıran en belirleyici özelliği **kalın** yaz.
            5. Her tablonun altına tek satırlık bir "Akılda tut:" notu ve kaynağı ekle.
            6. ⭐ işaretli, vurgulu veya renkli satırlarda geçen karşılaştırmalarla başla.

            ### Çıktı biçimi
            ```markdown
            ### X ile Y
            | Özellik | X | Y |
            |---|---|---|
            | Mekanizma | ... | ... |
            | Tipik bulgu | **...** | **...** |

            Akılda tut: ... _(Kaynak adı, Sayfa N)_
            ```
            """
    )

    private static let mekanizma = PromptTemplate(
        id: "mekanizma",
        title: "Mekanizma zincirleri",
        summary: "Neden→sonuç adımlarını oklarla sıralar",
        symbol: "arrow.forward.circle",
        category: .study,
        recommendsImages: false,
        outputHint: "Numaralı mekanizma zincirleri",
        body: """
            ## Görev: Mekanizma zincirleri
            Ekteki kaynaklarda anlatılan mekanizmaları neden→sonuç zincirleri olarak adım adım çıkar (ör. ilaç → reseptör → ikinci haberci → hücresel etki → klinik sonuç).

            ### Kurallar
            1. Her mekanizma için bir başlık yaz.
            2. Önce zinciri oklarla tek satırda özetle, sonra numaralı adımlarla aç; her adım tek kısa cümle olsun.
            3. Artış için ↑, azalış için ↓, sonuç için → kullan.
            4. Kaynakta atlanan bir ara adımı kendin tamamlama; o yere "(ara adım kaynakta net değil)" yaz.
            5. Zincirin sonunda, kaynakta varsa klinik karşılığını yaz.
            6. Her mekanizmanın altına kaynağını ekle.

            ### Çıktı biçimi (yalnızca biçim örneği)
            **β1 agonist etkisi**
            β1 agonist → β1 reseptör → Gs → adenilat siklaz ↑ → cAMP ↑ → PKA → Ca²⁺ girişi ↑ → kasılma gücü ↑
            1. İlaç kalpteki β1 reseptörüne bağlanır.
            2. Gs proteini adenilat siklazı uyarır.
            3. ...
            Klinik karşılığı: ...
            _(Kaynak adı, Sayfa N)_
            """
    )

    private static let klinik = PromptTemplate(
        id: "klinik",
        title: "Klinik bağlantılar",
        summary: "Temel bilgiyi klinik karşılığıyla eşleştirir",
        symbol: "stethoscope",
        category: .study,
        recommendsImages: false,
        outputHint: "Kaynaklı klinik bağlantı listesi",
        body: """
            ## Görev: Klinik bağlantılar
            Ekteki kaynaklardaki temel bilgilerin klinik karşılıklarını çıkar: hangi bilgi hangi hastalığı, bulguyu, tanı testini veya tedaviyi açıklıyor?

            ### Kurallar
            1. Ana bölümde yalnızca kaynakta açıkça geçen klinik bilgileri kullan.
            2. Her maddeyi "Temel bilgi → klinik karşılığı" biçiminde yaz ve kaynağını ekle.
            3. Kaynakta olmayan ama konuyu anlamaya yardımcı olacak bilgileri ana bölüme karıştırma. Bunları en sonda ayrı bir **Kaynak dışı ek bilgi** bölümünde, en fazla 5 kısa madde olarak ver. Genel kurallardaki "yalnızca kaynak" kuralının tek istisnası bu bölümdür.
            4. Kaynak dışı ek bilgide doz, kılavuz önerisi gibi değişebilen veya tartışmalı konulara girme.
            5. ⭐ işaretli, vurgulu ve renkli satırlarla ilgili bağlantılara öncelik ver.

            ### Çıktı biçimi
            ```markdown
            ## Kaynaktaki klinik bağlantılar
            - **Temel bilgi** → klinik karşılığı _(Kaynak adı, Sayfa N)_

            ## Kaynak dışı ek bilgi
            - (kaynak dışı ek bilgi) ...
            ```
            """
    )

    private static let hafiza = PromptTemplate(
        id: "hafiza",
        title: "Hafıza ipuçları",
        summary: "Zor ezberler için kısaltmalar ve akılda kalan hikâyeler",
        symbol: "brain.head.profile",
        category: .study,
        recommendsImages: false,
        outputHint: "Etiketli hafıza ipuçları",
        body: """
            ## Görev: Hafıza ipuçları
            Ekteki kaynaklarda ezberlenmesi zor bilgiler (listeler, sıralamalar, sınıflamalar, sayılar) için akılda kalıcı ipuçları üret.

            ### Kurallar
            1. Önce ezberlenecek bilgiyi kaynaktaki haliyle aynen yaz, sonra ipucunu ver.
            2. İpucu türleri: baş harf kısaltması, kafiyeli cümle, görsel hikâye, sayı benzetmesi, karşıtlık. Türkçe kelimelerle kurulan ipuçlarını tercih et.
            3. Her ipucunu **🧠 Uydurma ipucu** etiketiyle işaretle: bunlar bilgi değil, hatırlama aracıdır. İpucunda kaynakta olmayan bir tıbbi bilgiyi ima etme.
            4. Kaynakta zaten verilmiş bir kısaltma veya ipucu varsa onu "Kaynaktaki ipucu" olarak ayrıca belirt.
            5. ⭐ işaretli, vurgulu ve renkli bilgilere öncelik ver; en fazla 15 ipucu üret.
            6. Zorlama, anlamsız ya da bilgiyi yanlış hatırlatabilecek ipuçlarından kaçın.

            ### Çıktı biçimi
            **Ezberlenecek:** <kaynaktaki liste veya bilgi> _(Kaynak adı, Sayfa N)_
            **🧠 Uydurma ipucu:** <ipucu>
            **Nasıl çözülür:** <ipucundaki her parçanın neye karşılık geldiği>
            """
    )

    // MARK: - Anki

    private static let ankiTSV = PromptTemplate(
        id: "anki-tsv",
        title: "Anki kartları (TSV)",
        summary: "Soru-cevap kartları; doğrudan Anki'ye aktarılır",
        symbol: "rectangle.stack",
        category: .anki,
        recommendsImages: false,
        outputHint: "Anki'ye alınabilir .tsv dosyası",
        body: """
            ## Görev: Anki destesi (TSV)
            Ekteki kaynaklardan Anki'ye doğrudan içe aktarılabilecek soru-cevap kartları hazırla. Kullanıcı çıktıyı `.tsv` dosyası olarak kaydedip Anki'de Dosya → İçe Aktar ile açacak.

            ### Dosya biçimi
            1. Desteyi tek bir `tsv` kod bloğu içinde ver; kullanıcı bloğu olduğu gibi kopyalayıp kaydedecek.
            2. Bloğun ilk dört satırı aşağıdaki örnekteki başlık satırlarının tam aynısı olsun (Anki bunları içe aktarma ayarı olarak okur).
            3. Sonraki her satır bir karttır ve 5 alandan oluşur: Front, Back, Tags, Source, Priority.
            4. Alanları yalnızca gerçek TAB karakteriyle ayır; boşluk, virgül veya noktalı virgül kullanma.
            5. Alanların içinde TAB karakteri veya gerçek satır sonu olmasın.

            ### Kart kuralları
            1. Her kart tek bir atomik bilgiyi sorsun; listeleri ve çok parçalı bilgileri ayrı kartlara böl.
            2. Front: açık, tek anlamlı, kısa bir soru. Seçenek gerektiren ("Aşağıdakilerden hangisi") sorular yazma.
            3. Back: 1–3 kısa satır. Satır sonu gerekiyorsa yalnızca `<br>` kullan.
            4. Priority: **A** = slaytta vurgulanmış (⭐, vurgulu, renkli satır veya ✍️ el notu) ya da klinik olarak temel bilgi; **B** = bilinmesi yararlı diğer bilgiler. C önceliğinde kart yazma.
            5. Tags: boşlukla ayrılmış hiyerarşik etiketler. İlk etiket her zaman `{DESTE}::Konu` biçiminde olsun (Konu yerine kısa konu adı; etiketteki tüm boşluklar yerine `_`). Yalnızca uygun olduğunda `TUS::Spot`, `USMLE::Mekanizma` veya `Klinik` gibi etiketler ekle.
            6. Source: "Kaynak adı s.N" biçiminde (ör. `Kardiyovasküler Fizyoloji s.12`).
            7. HTML özel karakterlerini kaçır: `<` yerine `&lt;`, `>` yerine `&gt;`, `&` yerine `&amp;` yaz. Yalnızca `<br>`, `<b>`, `<i>`, `<sub>` ve `<sup>` etiketleri serbesttir.
            8. Tıbbi terimleri, sayıları ve birimleri kaynaktaki gibi aynen kullan.
            9. Kaynaktaki önemli bilgilerin hepsini kapsa; aynı bilgiyi iki kez sorma.

            ### C detaylar
            Kart yapmaya değmeyecek kadar ayrıntılı (C önceliğindeki) bilgileri kart yapma. Bunları kod bloğunun DIŞINDA, bloktan sonra **C detaylar** başlığı altında kısa bir madde listesi olarak ver. En sonda tek satırda kart sayısını yaz (A ve B ayrı ayrı).

            ### Çıktı biçimi (örnek)
            ```tsv
            #separator:tab
            #html:true
            #deck:{DESTE}
            #columns:Front\tBack\tTags\tSource\tPriority
            Kalp debisi nasıl hesaplanır?\tKalp debisi = atım hacmi × kalp hızı\t{DESTE}::Kalp_Fizyolojisi TUS::Spot\tKardiyovasküler Fizyoloji s.4\tA
            Frank-Starling yasası neyi ifade eder?\tVentrikül dolumu (ön yük) arttıkça<br>kasılma gücü ve atım hacmi artar.\t{DESTE}::Kalp_Fizyolojisi USMLE::Mekanizma\tKardiyovasküler Fizyoloji s.7\tA
            ```

            **C detaylar**
            - ...

            Kart sayısı: A ..., B ...
            """
    )

    private static let ankiCloze = PromptTemplate(
        id: "anki-cloze",
        title: "Anki boşluklu kartlar",
        summary: "Cloze kartlar; cümledeki anahtar terim gizlenir",
        symbol: "ellipsis.rectangle",
        category: .anki,
        recommendsImages: false,
        outputHint: "Cloze not türü için .tsv dosyası",
        body: """
            ## Görev: Anki boşluklu (cloze) kartlar
            Ekteki kaynaklardan Anki'nin Cloze not türüne doğrudan aktarılabilecek boşluk silme kartları hazırla. Kullanıcı çıktıyı `.tsv` dosyası olarak kaydedip Anki'de içe aktaracak.

            ### Dosya biçimi
            1. Desteyi tek bir `tsv` kod bloğu içinde ver.
            2. Bloğun ilk beş satırı aşağıdaki örnekteki başlık satırlarının tam aynısı olsun.
            3. Sonraki her satır bir nottur ve 3 alandan oluşur: Text, Back Extra, Tags. Alanları yalnızca gerçek TAB karakteriyle ayır.
            4. Alanların içinde TAB karakteri veya gerçek satır sonu olmasın.

            ### Kart kuralları
            1. Text: kaynaktaki bilgiyi tam bir cümle olarak yaz ve sorulacak kısmı `{{c1::...}}` ile gizle.
            2. Bir cümlede en fazla 3 boşluk olsun. Birlikte hatırlanması gereken boşluklar aynı numarayı (c1), ayrı ayrı sorulacak boşluklar farklı numaraları (c1, c2, c3) alsın.
            3. Yalnızca anahtar terimi, sayıyı veya ismi gizle; cümlenin tamamını veya "ve", "ile" gibi bağlaçları gizleme.
            4. İpucu gerekiyorsa `{{c1::cevap::ipucu}}` biçimini kullan (ör. `{{c1::aldosteron::hormon}}`).
            5. Back Extra: kısa ek açıklama ve kaynak ("Kaynak adı s.N"); satır sonu için yalnızca `<br>` kullan.
            6. Tags: boşlukla ayrılmış hiyerarşik etiketler. İlk etiket `{DESTE}::Konu` olsun (etiketteki tüm boşluklar yerine `_`). Yalnızca uygun olduğunda `TUS::Spot`, `USMLE::Mekanizma` ekle.
            7. ⭐ işaretli, vurgulu ve renkli satırlardan ve ✍️ el notlarından mutlaka kart yap ve bunlara `Oncelik::A` etiketi ekle.
            8. HTML özel karakterlerini kaçır: `<` yerine `&lt;`, `>` yerine `&gt;`, `&` yerine `&amp;` yaz (`<br>`, `<b>`, `<i>` serbest).

            ### Çıktı biçimi (örnek)
            ```tsv
            #separator:tab
            #html:true
            #notetype:Cloze
            #deck:{DESTE}
            #columns:Text\tBack Extra\tTags
            Böbrekte süzülen sodyumun büyük kısmı {{c1::proksimal tübülde}} geri emilir.\tYaklaşık %65–70.<br>Böbrek Fizyolojisi s.8\t{DESTE}::Böbrek_Fizyolojisi TUS::Spot Oncelik::A
            ```

            Kod bloğundan sonra kullanıcıya kısaca şunu hatırlat: "Anki'de Cloze not türünün adı farklı görünüyorsa (ör. Türkçe arayüzde) içe aktarırken not türünü elle seç."
            """
    )

    private static let ankiGorsel = PromptTemplate(
        id: "anki-gorsel",
        title: "Görselli Anki kartları",
        summary: "Şekillerden ve şekil etiketlerinden kart üretir",
        symbol: "photo.on.rectangle",
        category: .anki,
        recommendsImages: true,
        outputHint: "Görsel bağlantılı .tsv dosyası (görseller Anki'ye ayrıca kopyalanır)",
        body: """
            ## Görev: Görselli Anki kartları
            Ekteki kaynaklardaki şekillerden (figures/ klasöründeki görseller ve altlarındaki etiket listeleri) görsel tabanlı Anki kartları hazırla.

            ### Dosya biçimi
            1. Desteyi tek bir `tsv` kod bloğu içinde ver; ilk dört satır aşağıdaki örnekteki başlık satırlarının tam aynısı olsun.
            2. Her kart 5 alandan oluşur: Front, Back, Tags, Source, Priority. Alanları yalnızca gerçek TAB karakteriyle ayır; alanların içinde TAB veya gerçek satır sonu olmasın.

            ### Kart kuralları
            1. Görseli kartta `<img src="dosya-adı.jpg">` ile göster. `src` içine yalnızca dosya adını yaz (klasör yolu olmadan) ve adı Markdown'daki `![Şekil N](figures/...)` bağlantısından aynen al. Pakette olmayan bir dosya adı uydurma.
            2. Etiketli şekiller için "Bu şekilde X ile gösterilen yapı nedir?" türünde kartlar yap: Front'ta görsel ve soru, Back'te etiketin karşılığı ve kısa açıklama. Etiketler şeklin altındaki listede verilir.
            3. Uygun olduğunda başka kart türleri de yap: "Bu şekil hangi süreci gösteriyor?", "Grafikte X noktasında ne olur?", "Bu görüntüdeki bulgu nedir?". Bunları yalnızca kaynakta açıklaması varsa yaz.
            4. Etiket yazısı belirsizse ya da şekil kaynağın metninde açıklanmıyorsa o şekilden kart yapma; kod bloğundan sonra **Kart yapılamayan şekiller** listesinde nedeniyle belirt.
            5. Back: 1–3 kısa satır; satır sonu için yalnızca `<br>` kullan.
            6. Priority: **A** = vurgulanmış (⭐, vurgulu, renkli, ✍️) veya klinik olarak temel; **B** = diğerleri. C önceliğinde kart yazma.
            7. Tags: ilk etiket `{DESTE}::Konu` (etiketteki tüm boşluklar yerine `_`), ardından `Gorsel`; yalnızca uygun olduğunda `TUS::Spot` ekle.
            8. Source: "Kaynak adı s.N, Şekil N".
            9. `<img>`, `<br>`, `<b>`, `<i>` dışındaki `<`, `>` ve `&` karakterlerini `&lt;`, `&gt;`, `&amp;` olarak yaz.

            ### Çıktı biçimi (örnek)
            ```tsv
            #separator:tab
            #html:true
            #deck:{DESTE}
            #columns:Front\tBack\tTags\tSource\tPriority
            <img src="kalp-anatomisi-1a2b3c4d-sekil-3.jpg"><br>Şekilde 2 numarayla gösterilen yapı nedir?\tSol ventrikül\t{DESTE}::Kalp_Anatomisi Gorsel\tKalp Anatomisi s.5, Şekil 3\tA
            ```

            ### Kullanıcıya not
            Kod bloğundan sonra kullanıcıya şunu hatırlat: "Görsellerin kartlarda görünmesi için paketteki figures/ klasöründen kartlarda kullanılan görselleri Anki'nin medya klasörüne (collection.media) kopyala, sonra .tsv dosyasını içe aktar."
            """
    )

    // MARK: - Sorular

    private static let soruTemize = PromptTemplate(
        id: "soru-temize",
        title: "Soruları temize çek",
        summary: "Çıkmış soruları karalamalardan arındırıp aynen yeniden yazar",
        symbol: "doc.viewfinder",
        category: .questions,
        recommendsImages: true,
        outputHint: "Temiz soru metni ve kaynaktaki cevap anahtarı",
        body: """
            ## Görev: Çıkmış soruları temize çek
            Ekteki kaynaklar fotoğrafı çekilmiş, bir kısmı çözülmüş veya üzerine not alınmış çıkmış sınav sorularıdır. Soruları temiz, okunaklı ve kaynağa birebir sadık biçimde yeniden yaz. Soruları ÇÖZME.

            ### Kurallar
            1. Soru kökünü ve A–E seçeneklerini kaynaktaki gibi aynen yaz; kelime değiştirme, kısaltma veya sadeleştirme yapma. Her seçeneği ayrı satıra yaz.
            2. "değildir", "yanlıştır", "yoktur", "en az", "en sık", "hariç", "olamaz" gibi olumsuz ve sınırlayıcı ifadeleri koru ve **kalın** yaz.
            3. Sayıları, birimleri, laboratuvar değerlerini ve formülleri aynen aktar.
            4. Öğrencinin karalamalarını, altını çizdiği yerleri ve kenar notlarını soru metnine katma.
            5. Öğrencinin işaretlediği bir seçenek varsa (daire, çarpı, tik) sorunun altına ayrı satırda "Öğrencinin işareti: C" diye yaz. Bu resmî cevap değildir; doğru cevap gibi sunma.
            6. Metin bozuk ya da eksikse veya sayfa "Bu sayfa görsel olarak aktarıldı" notuyla verilmişse soruyu sayfa görüntüsünden oku. Yine de okunamayan yerlere [okunamadı] yaz.
            7. Soruda tablo varsa Markdown tablosu olarak yaz; şekil varsa `![Şekil N](figures/...)` bağlantısını aynen koru.
            8. Soruları kaynaktaki numaraları ve sırasıyla ver; numara yoksa 1'den başlayarak numarala.

            ### Çıktı biçimi
            **Soru 12.** Aşağıdakilerden hangisi ... **değildir**?
            A) ...
            B) ...
            C) ...
            D) ...
            E) ...
            _Öğrencinin işareti: C (resmî cevap değildir)_
            _(Kaynak adı, Sayfa N)_

            ### Cevap anahtarı
            En sonda yalnızca kaynakta açıkça yazan cevapları (basılı cevap anahtarı, "Cevap: B" gibi) içeren bir tablo ver: | Soru | Cevap | Nereden |. Kaynakta cevabı olmayan sorular için "kaynakta yok" yaz. Öğrencinin işaretini veya kendi çözümünü cevap anahtarına yazma.
            """
    )

    private static let soruCoz = PromptTemplate(
        id: "soru-coz",
        title: "Soruları çöz",
        summary: "Soruları kısa açıklamalarla çözer, güven düzeyini belirtir",
        symbol: "checkmark.circle",
        category: .questions,
        recommendsImages: false,
        outputHint: "Açıklamalı çözümler",
        body: """
            ## Görev: Soruları çöz ve açıkla
            Ekteki kaynaklardaki soruları sırayla çöz ve her birini kısaca açıkla.

            ### Kurallar
            1. Her sorunun önce kökünü ve seçeneklerini kaynaktaki gibi aynen ver, sonra çözümü ayrı bir **Çözüm** bölümünde yaz. Kaynak metniyle kendi açıklamanı asla karıştırma.
            2. Çözümde doğru seçeneği, 1–3 cümlelik gerekçeyi ve gerekirse diğer seçeneklerin neden yanlış olduğunu (birer kısa cümle) yaz.
            3. Olumsuz kökleri ("değildir", "yanlıştır", "en az") **kalın** yaz ve çözümü buna göre yap.
            4. Gerekçede önce ekteki kaynakları kullan ve dayandığın yeri "Kaynak adı, Sayfa N" olarak belirt. Kaynakta karşılığı yoksa genel tıp bilginle çözebilirsin, ancak bunu "kaynak dışı bilgi" diye işaretle. Genel kurallardaki "yalnızca kaynak" kuralının bu görevdeki tek istisnası budur.
            5. Kaynakta basılı bir cevap anahtarı varsa onu da yaz; senin cevabın onunla çelişiyorsa bunu açıkça belirt.
            6. Öğrencinin işaretlediği seçeneği doğru cevap kabul etme.
            7. Her çözüme güven düzeyi ekle: **Yüksek**, **Orta** veya **Düşük**. Soru metni net okunamıyorsa, seçenekler eksikse ya da birden fazla seçenek savunulabiliyorsa güveni Düşük işaretle ve nedenini yaz.

            ### Çıktı biçimi
            **Soru 3.** <soru kökü>
            A) ...
            B) ...
            C) ...
            D) ...
            E) ...

            > **Çözüm:** C. <gerekçe> _(Kaynak adı, Sayfa N)_
            > Diğerleri: A ...; B ...
            > Güven: Yüksek
            """
    )

    private static let quiz = PromptTemplate(
        id: "quiz",
        title: "Deneme sınavı",
        summary: "Kaynaktan 15 çoktan seçmeli soru üretir",
        symbol: "list.bullet.clipboard",
        category: .questions,
        recommendsImages: false,
        outputHint: "Çoktan seçmeli sorular ve cevap anahtarı",
        body: """
            ## Görev: Çoktan seçmeli deneme sınavı
            Ekteki {KAYNAK_SAYISI} kaynaktan, kullanıcı başka bir sayı belirtmediyse 15 adet beş seçenekli (A–E) çoktan seçmeli soru hazırla.

            ### Kurallar
            1. Her sorunun doğru cevabı kaynakta açıkça bulunsun; kaynağın dışından soru sorma.
            2. Konuları dengeli dağıt; ⭐ işaretli, vurgulu ve renkli bilgilerden ve ✍️ el notlarından daha fazla soru sor.
            3. Zorluk karışık olsun: yaklaşık üçte biri doğrudan bilgi, üçte biri yorum, üçte biri vaka veya mekanizma sorusu.
            4. Çeldiriciler makul, aynı kategoriden ve mümkün olduğunca kaynaktaki kavramlardan seçilsin; "hepsi" ve "hiçbiri" seçeneklerini kullanma.
            5. Olumsuz köklü sorularda olumsuz ifadeyi **kalın** yaz; bu tür soruları toplamın beşte birinden fazla yapma.
            6. Doğru cevapların harflerini sorulara dengeli dağıt.
            7. Cevapları soruların altına yazma; hepsini sonda ver.

            ### Çıktı biçimi
            **1.** <soru kökü>
            A) ...
            B) ...
            C) ...
            D) ...
            E) ...

            (tüm sorulardan sonra)

            **Cevap anahtarı**
            1. **C**: <1–2 satırlık açıklama> _(Kaynak adı, Sayfa N)_
            """
    )

    private static let dogruYanlis = PromptTemplate(
        id: "dogru-yanlis",
        title: "Doğru / yanlış",
        summary: "Kaynaktan 20 doğru-yanlış ifadesi üretir",
        symbol: "plusminus.circle",
        category: .questions,
        recommendsImages: false,
        outputHint: "Doğru/yanlış ifadeleri ve cevaplar",
        body: """
            ## Görev: Doğru / yanlış soruları
            Ekteki kaynaklardan 20 adet doğru/yanlış ifadesi hazırla.

            ### Kurallar
            1. Her ifade kaynaktaki tek bir bilgiye dayansın ve kesin olarak doğru ya da yanlış olsun; yoruma açık ifade yazma.
            2. Yaklaşık yarısı doğru, yarısı yanlış olsun. Yanlış ifadeleri sık karıştırılan bir ayrıntıyı (sayı, yön, artış/azalış, isim) değiştirerek kur.
            3. "Her zaman", "asla" gibi cevabı ele veren kelimeler kullanma.
            4. ⭐ işaretli, vurgulu ve renkli bilgilere ve ✍️ el notlarına öncelik ver.
            5. Cevapları ifadelerin yanına yazma; hepsini sonda ver.

            ### Çıktı biçimi
            1. <ifade> (D / Y)
            2. ...

            **Cevaplar**
            1. **Y**: Doğrusu ... _(Kaynak adı, Sayfa N)_
            2. **D** _(Kaynak adı, Sayfa N)_
            """
    )

    private static let boslukDoldurma = PromptTemplate(
        id: "bosluk-doldurma",
        title: "Boşluk doldurma",
        summary: "Anahtar terimi boş bırakılmış cümleler",
        symbol: "text.cursor",
        category: .questions,
        recommendsImages: false,
        outputHint: "Boşluklu cümleler ve cevaplar",
        body: """
            ## Görev: Boşluk doldurma
            Ekteki kaynaklardan 20 adet boşluk doldurma cümlesi hazırla.

            ### Kurallar
            1. Cümleler kaynaktaki bilgiyi neredeyse aynen kullansın; boşluk anahtar bir terim, sayı veya isim olsun.
            2. Her cümlede bir, en fazla iki boşluk olsun; boşluğu `______` ile göster. İki boşluk varsa (1) ve (2) diye numarala.
            3. Cevap tek ve kesin olsun; birden fazla doğru cevabı olabilecek boşluk bırakma.
            4. ⭐ işaretli, vurgulu ve renkli bilgilere ve ✍️ el notlarına öncelik ver.
            5. Cevapları cümlelerin yanına yazma; hepsini sonda ver.

            ### Çıktı biçimi
            1. Kalp debisi, atım hacmi ile ______ çarpımına eşittir.
            2. ...

            **Cevaplar**
            1. kalp hızı _(Kaynak adı, Sayfa N)_
            """
    )

    // MARK: - Kontrol

    private static let elNotu = PromptTemplate(
        id: "el-notu",
        title: "El notlarını temize çek",
        summary: "El yazısı notları görüntüden okuyup ilgili satıra yerleştirir",
        symbol: "hand.draw",
        category: .review,
        recommendsImages: true,
        outputHint: "El notları yerleştirilmiş temiz metin",
        body: """
            ## Görev: El notlarını temize çek
            Ekteki kaynaklarda ✍️ ile işaretli satırlar öğrencinin el yazısıyla aldığı notlardır. OCR okumaları tahmindir; notların görüntüleri varsa "El notu N" adlı şekiller olarak pakette yer alır. Bu notları görüntülerden okuyup temiz metne çevir.

            ### Kurallar
            1. Her el notunu önce görüntüsünden oku; OCR metnini yalnızca yardımcı olarak kullan. Görüntü yoksa OCR metnini temel al ve bunu belirt.
            2. Notu ilgili olduğu basılı satırın hemen altına yerleştir: önce basılı satırı aynen yaz, altına notu `> ✍️` ile başlayan bir alıntı satırı olarak ekle.
            3. Kısaltmaları ve oklarla gösterilen ilişkileri olduğu gibi bırak (ör. ↑, →, dx, tx); anlamını tahmin ederek açma.
            4. Emin olmadığın kelimelerin yanına [?] koy; tamamen okunamayan kısımlara [okunamadı] yaz.
            5. Notun hangi basılı satırla ilgili olduğu belli değilse onu sayfanın sonunda **Yeri belirsiz notlar** başlığı altında topla.
            6. Notlara yorum ekleme ve içeriklerini düzeltme; öğrencinin yazdığını aktar.
            7. Kaynak ve sayfa yapısını (`## Kaynak:` ve `### Sayfa N` başlıkları) koru.

            ### Çıktı biçimi
            ```markdown
            ### Sayfa 4
            Aldosteron distal tübülde Na⁺ geri emilimini artırır.
            > ✍️ K⁺ atılımı da ↑, hipokalemi [?]
            ```

            En sonda okunması güç olan notları kaynak ve sayfa numaralarıyla listele.
            """
    )

    private static let duzelt = PromptTemplate(
        id: "duzelt",
        title: "OCR düzeltme",
        summary: "Türkçe karakter ve okuma hatalarını anlamı bozmadan düzeltir",
        symbol: "text.magnifyingglass",
        category: .review,
        recommendsImages: false,
        outputHint: "Düzeltilmiş Markdown ve değişiklik listesi",
        body: """
            ## Görev: OCR metnini düzelt
            Ekteki metin görüntülerden OCR ile çıkarıldı ve okuma hataları içerebilir. Metni anlamını değiştirmeden düzelt.

            ### Kurallar
            1. Yalnızca bariz OCR hatalarını düzelt: Türkçe karakter karışıklıkları (ı/i, ş/s, ğ/g, ç/c, ö/o, ü/u, İ/I), birleşmiş veya bölünmüş kelimeler, satır sonunda bölünmüş heceler, yanlış okunmuş harf ve rakamlar (0/O, 1/l/I, rn/m).
            2. Anlamı, cümle yapısını ve sırayı değiştirme; içerik ekleme veya çıkarma, üslubu güzelleştirme.
            3. Tıbbi terimleri kaynakta geçtiği dilde (Türkçe, Latince, İngilizce) bırak; yalnızca açıkça yanlış okunmuşlarsa düzelt.
            4. Sayılardan, birimlerden ve dozlardan emin değilsen değiştirme; yanına [?] koy ve sayfa görüntüsü varsa oradan kontrol et.
            5. ✏️ ile işaretli satırları kullanıcı zaten düzeltti; onlara dokunma.
            6. Markdown yapısını aynen koru: başlıklar, listeler, tablolar, `==...==` ve `⟦...⟧` işaretleri, ⭐, ✍️ ve ⚠️ işaretleri, şekil ve sayfa görüntüsü bağlantıları yerinde kalsın.
            7. ⚠️ Belirsiz notlu bir yeri sayfa görüntüsünden kesin okuyabildiysen düzelt ve notu kaldır; okuyamadıysan notu bırak.

            ### Çıktı biçimi
            1. Düzeltilmiş metnin tamamını, aynı yapıda, tek bir `markdown` kod bloğu içinde ver; kullanıcı kopyalayıp kaydedebilsin.
            2. Ardından **Değişiklikler** başlığı altında bir tablo ver: | Yer (Kaynak, Sayfa) | Önce | Sonra |. Çok sayıdaki benzer harf düzeltmesini tek satırda özetleyebilirsin.
            3. Emin olamadığın için değiştirmediğin yerleri ayrı bir listede belirt.
            """
    )

    private static let eksikKontrol = PromptTemplate(
        id: "eksik-kontrol",
        title: "Eksik ve çelişki kontrolü",
        summary: "Çelişkileri, eksikleri ve yeniden çekilecek sayfaları bulur",
        symbol: "exclamationmark.triangle",
        category: .review,
        recommendsImages: false,
        outputHint: "Sorun raporu ve yeniden çekilecek sayfa listesi",
        body: """
            ## Görev: Eksik ve çelişki kontrolü
            Ekteki {KAYNAK_SAYISI} kaynağı birlikte incele ve çalışmaya başlamadan önce giderilmesi gereken sorunları raporla. İçeriği özetleme; yalnızca sorunları bul.

            ### Kontrol edilecekler
            1. **Çelişkiler**: kaynaklar arasında veya aynı kaynağın farklı sayfalarında birbirini tutmayan bilgiler (sayılar, tanımlar, sınıflamalar, isimler).
            2. **Eksik veya yarım kalan yerler**: yarıda kesilen cümle, liste veya tablolar; metinde anılan ama pakette olmayan şekil veya tablolar; sayfa numaralarındaki atlamalar.
            3. **Okunamayan veya bozuk metin**: anlamsız karakter dizileri, ⚠️ Belirsiz notlu yerler, çok sayıda OCR hatası içeren sayfalar.
            4. **Görüntüden okunması gereken sayfalar**: "Bu sayfa görsel olarak aktarıldı" notlu sayfalar ve metni çıkarılamamış tablo veya şekiller. Görüntüsü varsa oku ve sorun olup olmadığını yaz; yoksa belirt.
            5. **Yeniden çekilmesi gereken sayfalar**: bulanık, eğik, kesik, karanlık veya parlama yüzünden okunamayan sayfalar.
            6. **Açıklaması olmayan vurgular**: ⭐ işaretli, vurgulu veya ✍️ el notlu olup kaynakta açıklaması bulunmayan bilgiler.

            ### Çıktı biçimi
            Her bölüm için bir tablo ver: | # | Kaynak, Sayfa | Sorun | Öneri |. Bir bölümde sorun yoksa "Sorun bulunmadı" yaz.
            Öneri sütununa yalnızca yapılacak işi yaz (ör. "sayfayı yeniden çek", "hocaya sor", "kitaptan kontrol et"); çelişkiyi kendin çözmeye çalışma.
            En sonda **Yeniden çekilecek sayfalar** başlığıyla kısa bir liste ver: `Kaynak adı: Sayfa 3, 7, 12`.
            """
    )
}
