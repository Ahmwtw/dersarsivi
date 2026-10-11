import Foundation

public enum ExportMode: String, Codable, Sendable {
    /// Tüm seçili kaynaklar tek dosyada.
    case combined
    /// Her kaynak ayrı dosyada.
    case perSource = "per_source"
}

public enum ExportProfile: String, Codable, Sendable {
    /// Kaynağa sadık tam metin.
    case faithfulText = "faithful_text"
}

/// Bir kaynaktan hangi sayfaların exporta gireceği. `pageIndices` nil ise bütün sayfalar.
public struct SourceSelection: Equatable, Sendable {
    public var sourceID: UUID
    public var pageIndices: [Int]?

    public init(sourceID: UUID, pageIndices: [Int]? = nil) {
        self.sourceID = sourceID
        self.pageIndices = pageIndices
    }
}

public struct ExportManifest: Codable, Equatable, Sendable {
    public struct MissingPage: Codable, Equatable, Sendable {
        public var pageIndex: Int
        public var status: PageStatus
        public var reason: String?
    }

    public struct SourceEntry: Codable, Equatable, Sendable {
        public var sourceID: UUID
        public var title: String
        public var contentHash: String
        public var selectedPageIndices: [Int]
        public var includedPageIndices: [Int]
        public var missingPages: [MissingPage]
        public var uncertainBlockCount: Int
        public var file: String
    }

    /// Exporttaki bir şekil. Etiket kutuları şekle göreli (0...1, sol üst orijin); Anki image occlusion için.
    public struct FigureEntry: Codable, Equatable, Sendable {
        public struct Label: Codable, Equatable, Sendable {
            public var text: String
            public var bbox: BoundingBox
        }

        public var number: Int
        public var sourceID: UUID
        public var pageIndex: Int
        /// ZIP içindeki görsel yolu; görselsiz exportta nil.
        public var file: String?
        /// Sayfaya göre kutu.
        public var bbox: BoundingBox
        public var labels: [Label]
        /// "handwriting": el notu görüntüsü; nil: şekil.
        public var kind: String? = nil
    }

    public var schemaVersion: Int
    public var exportID: UUID
    public var createdAt: Date
    public var profile: ExportProfile
    public var mode: ExportMode
    public var sources: [SourceEntry]
    public var warnings: [String]
    public var partialExport: Bool
    public var figures: [FigureEntry]?
    /// Dosyanın başına eklenen hazır talimatın kimliği.
    public var prompt: String? = nil
    /// Görüntü olarak aktarılan sayfalar (kaynak kimliği ve sayfa indeksi).
    public var imageOnlyPages: [String]? = nil
}

public struct ExportFile: Equatable, Sendable {
    public var name: String
    public var contents: String
}

/// ZIP'e konacak görsel: arşivdeki dosya ve ZIP içindeki yolu. `crop` varsa görsel bu alana kırpılıp
/// JPEG olarak yazılır (sayfa görüntüsü); yoksa dosya olduğu gibi konur (şekil kırpımı).
public struct ExportAsset: Equatable, Sendable {
    public var path: String
    public var imageRef: String
    public var crop: BoundingBox?

    public init(path: String, imageRef: String, crop: BoundingBox? = nil) {
        self.path = path
        self.imageRef = imageRef
        self.crop = crop
    }
}

public struct ExportResult: Equatable, Sendable {
    public var files: [ExportFile]
    public var manifest: ExportManifest
    public var assets: [ExportAsset]

    /// Markdown dosyaları, görseller ve manifest tek ZIP'te. `imageData` görselin baytlarını üretir.
    public func zip(imageData: (ExportAsset) -> Data?, modified: Date = Date()) throws -> Data {
        var archive = ZipArchive()
        for file in files { archive.add(path: file.name, contents: Data(file.contents.utf8), modified: modified) }
        for asset in assets {
            if let data = imageData(asset) {
                archive.add(path: asset.path, contents: data, modified: modified)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        archive.add(path: "manifest.json", contents: try encoder.encode(manifest), modified: modified)
        return archive.finish()
    }
}

/// Seçili kaynakları kaynak referanslı Markdown'a çevirir. İşlenmemiş veya başarısız sayfalar
/// sessizce atlanmaz; hem dosyada hem manifestte eksik olarak görünür.
public struct MarkdownExporter {
    /// Bu değerin altındaki motor güveni "belirsiz" sayılır. Kalibre edilmiş bir eşik değildir.
    public var lowConfidenceThreshold: Double
    /// Şekiller `figures/` klasöründeki görsellere bağlanır (ZIP export). Kapalıyken yalnız yer ve etiketler yazılır.
    public var includeFigureImages: Bool
    /// Her sayfanın (düzleştirilmiş, kenarlıkları atılmış) görüntüsü `pages/` klasörüne eklenir. Karışık sayfalarda
    /// (el yazısı, tablo) yapay zekâ görüntüyü kendisi okuyabilsin diye.
    public var includePageImages: Bool
    /// Dosyanın başına konacak hazır talimat (özet, Anki destesi...). nil: yalnız kaynak paketi.
    public var prompt: PromptTemplate?
    public var promptContext: PromptContext

    public init(lowConfidenceThreshold: Double = 0.5, includeFigureImages: Bool = false,
                includePageImages: Bool = false, prompt: PromptTemplate? = nil,
                promptContext: PromptContext = PromptContext()) {
        self.lowConfidenceThreshold = lowConfidenceThreshold
        self.includeFigureImages = includeFigureImages
        self.includePageImages = includePageImages
        self.prompt = prompt
        self.promptContext = promptContext
    }

    /// Ayarlar gereği ZIP gerekiyor mu. "Sadece görsel" sayfalar varsa sonuç yine görsel taşır;
    /// kesin karar için `ExportResult.assets` boş mu diye bakılır.
    public var producesZip: Bool { includeFigureImages || includePageImages }

    public func export(_ archive: Archive, selections: [SourceSelection], mode: ExportMode,
                       exportID: UUID = UUID(), createdAt: Date) throws -> ExportResult {
        var sections: [(entry: ExportManifest.SourceEntry, markdown: String)] = []
        var figures = FigureCollector()
        figures.boilerplate = Self.boilerplate(in: archive)
        for selection in selections {
            sections.append(try section(for: selection, in: archive, mode: mode, figures: &figures))
        }

        var warnings: [String] = []
        for (entry, _) in sections where !entry.missingPages.isEmpty {
            warnings.append("\(entry.title): \(entry.missingPages.count) sayfa işlenmediği için metni yok")
        }
        let partial = sections.contains { !$0.entry.missingPages.isEmpty }
        let hasStyles = selections.contains { sel in
            archive.pages(of: sel.sourceID).contains { page in
                archive.blocks(of: page.id).contains { $0.runs != nil && !$0.isUserCorrected }
            }
        }

        var files: [ExportFile] = []
        var entries: [ExportManifest.SourceEntry] = []
        switch mode {
        case .combined:
            let name = "dersarsivi-\(Self.shortID(exportID)).md"
            var body = header(exportID: exportID, createdAt: createdAt, sourceCount: sections.count, warnings: warnings,
                              hasStyles: hasStyles, figures: figures)
            for (entry, markdown) in sections {
                body += "\n" + markdown
                var e = entry
                e.file = name
                entries.append(e)
            }
            files.append(ExportFile(name: name, contents: body))
        case .perSource:
            var usedNames = Set<String>()
            for (entry, markdown) in sections {
                var name = "\(Self.slug(entry.title))-\(Self.shortID(entry.sourceID)).md"
                var n = 2
                while usedNames.contains(name) {
                    name = "\(Self.slug(entry.title))-\(Self.shortID(entry.sourceID))-\(n).md"
                    n += 1
                }
                usedNames.insert(name)
                let ownWarnings = warnings.filter { $0.hasPrefix(entry.title + ":") }
                let body = header(exportID: exportID, createdAt: createdAt, sourceCount: 1, warnings: ownWarnings,
                                  hasStyles: hasStyles, figures: figures)
                    + "\n" + markdown
                files.append(ExportFile(name: name, contents: body))
                var e = entry
                e.file = name
                entries.append(e)
            }
        }

        let manifest = ExportManifest(schemaVersion: archiveSchemaVersion, exportID: exportID, createdAt: createdAt,
                                      profile: .faithfulText, mode: mode, sources: entries, warnings: warnings,
                                      partialExport: partial, figures: figures.entries.isEmpty ? nil : figures.entries,
                                      prompt: prompt?.id,
                                      imageOnlyPages: figures.imageOnlyPages.isEmpty ? nil : figures.imageOnlyPages)
        return ExportResult(files: files, manifest: manifest, assets: figures.assets + figures.pageAssets)
    }

    // MARK: Parçalar

    private func header(exportID: UUID, createdAt: Date, sourceCount: Int, warnings: [String],
                        hasStyles: Bool, figures: FigureCollector) -> String {
        let figureCount = figures.entries.count
        var s = "# DersArşivi dışa aktarımı\n\n"
        if let prompt {
            var context = promptContext
            context.sourceCount = sourceCount
            context.includesImages = context.includesImages || !figures.assets.isEmpty || !figures.pageAssets.isEmpty
            s += "## Yapay zekâya talimat: \(prompt.title)\n\n"
            s += prompt.instructions(context) + "\n\n---\n\n## Kaynak paketi\n\n"
        }
        s += "Profil: sadık metin · Kaynak sayısı: \(sourceCount) · Tarih: \(Self.isoDate(createdAt)) · "
        s += "Export: \(exportID.uuidString.lowercased())\n\n"
        s += "Metin kaynak görüntüsünden OCR ile çıkarıldı; ✏️ kullanıcı tarafından düzeltilmiş, "
        s += "⚠️ belirsiz bölümleri gösterir. "
        if figureCount == 0 {
            if !includePageImages { s += "Bu dosya görsel içermez.\n" }
        } else if includeFigureImages {
            s += "Şekiller `figures/` klasöründedir; şekil içindeki yazılar şeklin altında etiket olarak listelenir, "
            s += "etiket konumları `manifest.json` içindedir.\n"
        } else {
            s += "Şekillerin yeri ve etiketleri yazılıdır; görselleri bu dosyada yok (ZIP ile dışa aktarınca eklenir).\n"
        }
        if includePageImages {
            s += "Her sayfanın görüntüsü `pages/` klasöründedir; el yazısı, tablo ve şekilleri görüntüden kontrol edebilirsin.\n"
        }
        if hasStyles {
            s += "Kaynaktaki biçim: ==metin== fosforlu kalemle vurgulanmış (sarı dışındaysa rengi yanında), "
            s += "⟦renk: metin⟧ renkli yazılmış. Renkler görüntüden otomatik tahmin edildi.\n"
        }
        if figures.hasMarks {
            s += "⭐ ile başlayan satırların yanına elle işaret (yıldız, ünlem, çarpı, çıkartma) konmuş; önemli sayılmalı.\n"
        }
        if figures.hasHandwriting {
            s += "✍️ öğrencinin el notudur; okunuşu tahminidir, notun görüntüsü \"El notu\" olarak eklenmiştir.\n"
        }
        if !figures.imageOnlyPages.isEmpty {
            s += "Bazı sayfalar karışık veya el yazısı ağırlıklı olduğu için yalnız görüntü olarak aktarıldı; "
            s += "bu sayfaların içeriğini görüntüden oku.\n"
        }
        if !warnings.isEmpty {
            s += "\n> **Eksik içerik:**\n"
            for w in warnings { s += "> - \(w)\n" }
        }
        return s
    }

    private func section(for selection: SourceSelection, in archive: Archive, mode: ExportMode,
                         figures collector: inout FigureCollector) throws -> (ExportManifest.SourceEntry, String) {
        guard let source = archive.source(selection.sourceID) else {
            throw ArchiveError.sourceNotFound(selection.sourceID)
        }
        let allPages = archive.pages(of: source.id)
        let selected: [Page]
        if let wanted = selection.pageIndices {
            let set = Set(wanted)
            selected = allPages.filter { set.contains($0.pageIndex) }
        } else {
            selected = allPages
        }

        var md = "## Kaynak: \(Self.inline(source.sourceTitle))\n\n"
        md += "- Kimlik: `\(source.id.uuidString.lowercased())`\n"
        md += "- Dosya: \(Self.inline(source.originalFilename)) (\(source.mediaType == .pdf ? "PDF" : "görsel"))\n"
        if source.mediaType == .pdf {
            let selection = PageSelection(indices: selected.map(\.pageIndex))
            md += "- Seçili sayfalar: \(selection.displayText) / \(allPages.count)\n"
        }

        var included: [Int] = []
        var missing: [ExportManifest.MissingPage] = []
        var uncertain = 0
        for page in selected {
            if source.mediaType == .pdf || selected.count > 1 {
                md += "\n### Sayfa \(page.displayName)\n"
            }
            let processed = [.ready, .needsReview, .partial].contains(page.status)
            let imageOnly = processed && archive.isImageOnly(page)
            if includePageImages || imageOnly, let ref = page.workingImageRef ?? source.imageRef {
                let path = "pages/\(Self.slug(source.sourceTitle))-\(Self.shortID(source.id))-sayfa-\(page.pageIndex + 1).jpg"
                let crop = page.contentBox ?? BoundingBox(x: 0, y: 0, width: 1, height: 1)
                collector.pageAssets.append(ExportAsset(path: path, imageRef: ref, crop: crop))
                md += "\n![Sayfa \(page.displayName) görüntüsü](\(path))\n"
            }
            if imageOnly {
                md += "\n> 🖼️ Bu sayfa görsel olarak aktarıldı (el yazısı ağırlıklı veya karışık); içeriği görüntüden oku.\n"
                included.append(page.pageIndex)
                collector.imageOnlyPages.append("\(source.id.uuidString.lowercased())#\(page.pageIndex)")
                continue
            }
            let blocks = archive.blocks(of: page.id)
            guard processed, !blocks.isEmpty else {
                if processed {
                    md += "\n_(Bu sayfada metin bulunamadı.)_\n"
                    included.append(page.pageIndex)
                } else {
                    let reason = page.failureReason.map { ": \($0)" } ?? ""
                    md += "\n> ⚠️ Bu sayfa işlenmedi (durum: \(page.status.rawValue)\(reason)); metni bu dosyada yok.\n"
                    missing.append(.init(pageIndex: page.pageIndex, status: page.status, reason: page.failureReason))
                }
                continue
            }
            included.append(page.pageIndex)
            let accepted = archive.figures(of: page.id).filter { $0.status == .accepted }
            var pending = accepted
            for block in blocks {
                // Şeklin içindeki kısa yazılar (etiketler) şeklin altında listelenir; metinde tekrarlanmaz.
                // Uzun metin şeklin içine düşse bile metinde kalır: yazı kaybolmasın. El notu bölgesindeki el yazısı
                // ise notun altında okunuşuyla verilir.
                if let box = block.bbox, accepted.contains(where: { figure in
                    box.fractionInside(figure.bbox) >= 0.8
                        && (block.acceptedText.count <= Self.maxLabelBlockLength
                            || (figure.isHandwriting && block.kind == .handwriting && !block.isUserCorrected))
                }) {
                    continue
                }
                // Her slaytta tekrarlanan logo, kurum yazısı, alt bilgi ve sayfa numarası.
                if !block.isUserCorrected, let box = block.bbox,
                   Self.isPageNumber(block.acceptedText, box)
                    || collector.boilerplate.contains(Self.boilerplateKey(block.acceptedText, box)) {
                    continue
                }
                if let box = block.bbox {
                    while let next = pending.first, next.bbox.y <= box.y {
                        md += figureMarkdown(next, source: source, page: page, collector: &collector)
                        pending.removeFirst()
                    }
                }
                // Tablo kendi satırlarında durmalı; işaret ve düzeltme notu ayrı satıra yazılır.
                if block.kind == .table {
                    md += "\n"
                    if block.marked == true {
                        md += "⭐ İşaretli tablo:\n\n"
                        collector.hasMarks = true
                    }
                    md += Self.escape(block.acceptedText) + "\n"
                    if block.isUserCorrected { md += "\n_(Tablo düzeltildi ✏️)_\n" }
                    if let note = uncertaintyNote(block) {
                        uncertain += 1
                        md += "\n> ⚠️ Belirsiz: \(note)\n"
                    }
                    continue
                }
                md += "\n"
                if block.marked == true {
                    md += "⭐ "
                    collector.hasMarks = true
                }
                if block.kind == .handwriting {
                    md += "✍️ "
                    collector.hasHandwriting = true
                }
                if let runs = block.runs, !block.isUserCorrected {
                    md += Self.render(runs)
                } else {
                    md += Self.escape(block.acceptedText)
                }
                if block.isUserCorrected { md += " ✏️" }
                md += "\n"
                if let note = uncertaintyNote(block) {
                    uncertain += 1
                    md += "> ⚠️ Belirsiz: \(note)\n"
                }
            }
            for figure in pending {
                md += figureMarkdown(figure, source: source, page: page, collector: &collector)
            }
        }

        let entry = ExportManifest.SourceEntry(
            sourceID: source.id, title: source.sourceTitle, contentHash: source.contentHash,
            selectedPageIndices: selected.map(\.pageIndex), includedPageIndices: included,
            missingPages: missing, uncertainBlockCount: uncertain, file: "")
        return (entry, md)
    }

    private func figureMarkdown(_ figure: Figure, source: SourceAsset, page: Page,
                                collector: inout FigureCollector) -> String {
        let number = collector.entries.count + 1
        var file: String?
        if includeFigureImages, let ref = figure.imageRef {
            let path = "figures/\(Self.slug(source.sourceTitle))-\(Self.shortID(source.id))-sekil-\(number).jpg"
            collector.assets.append(ExportAsset(path: path, imageRef: ref))
            file = path
        }
        collector.entries.append(.init(
            number: number, sourceID: source.id, pageIndex: page.pageIndex, file: file, bbox: figure.bbox,
            labels: figure.labels.map { .init(text: $0.text, bbox: $0.bbox.relative(to: figure.bbox)) },
            kind: figure.isHandwriting ? FigureKind.handwriting.rawValue : nil))

        let name = figure.isHandwriting ? "El notu \(number)" : "Şekil \(number)"
        if figure.isHandwriting { collector.hasHandwriting = true }
        var md = "\n"
        if let file {
            md += "![\(name)](\(file))\n"
        } else {
            md += "> 🖼️ \(name) (görsel bu dosyada yok)\n"
        }
        if !figure.labels.isEmpty {
            if figure.isHandwriting {
                let text = figure.labels.map { Self.inline($0.text) }.joined(separator: " / ")
                md += "\n_\(name) okunuşu (tahmini): ✍️ \(text)_\n"
            } else {
                let names = figure.labels.map { Self.inline($0.text) }.joined(separator: " · ")
                md += "\n_\(name) etiketleri: \(names)_\n"
            }
        }
        return md
    }

    private func uncertaintyNote(_ block: Block) -> String? {
        var notes: [String] = []
        if block.reviewStatus == .conflict {
            notes.append("yeni okuma kullanıcı düzeltmesinden farklı (\"\(Self.inline(block.rawText))\")")
        }
        if !block.isUserCorrected, let c = block.engineConfidence, c < lowConfidenceThreshold {
            notes.append("OCR güveni düşük (%\(Int((c * 100).rounded())))")
        }
        notes.append(contentsOf: block.warnings)
        return notes.isEmpty ? nil : notes.joined(separator: "; ")
    }

    // MARK: Yardımcılar

    /// OCR metnindeki satır başı Markdown işaretlerini ve HTML'i etkisizleştirir.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.drop { $0 == " " }
                if let first = trimmed.first, "#=".contains(first) || trimmed.hasPrefix("---") {
                    return "\\" + line
                }
                return String(line)
            }
            .joined(separator: "\n")
    }

    /// Biçimli parçaları işaretli metne çevirir. İşaretler boşlukları içine almaz: "==metin== ".
    static func render(_ runs: [TextRun]) -> String {
        var out = ""
        for run in runs {
            let escaped = escape(run.text)
            guard !run.isPlain else {
                out += escaped
                continue
            }
            let core = escaped.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else {
                out += escaped
                continue
            }
            let leading = String(escaped.prefix { $0 == " " })
            let trailing = String(escaped.reversed().prefix { $0 == " " })
            var marked = core
            if let color = run.color { marked = "⟦\(color.rawValue): \(marked)⟧" }
            if let highlight = run.highlight {
                marked = "==\(marked)=="
                if highlight != .sari { marked += " (\(highlight.rawValue) vurgu)" }
            }
            out += leading + marked + trailing
        }
        return out
    }

    static let maxLabelBlockLength = 40

    /// Arşivde çok sayıda kaynakta, sayfanın köşesinde tekrarlanan kısa yazılar (üniversite logosu, kurum adı).
    /// Slayt başlıkları ortada durduğundan sayılmaz.
    static func boilerplate(in archive: Archive) -> Set<String> {
        var pagesByKey: [String: Set<UUID>] = [:]
        for block in archive.blocks where !block.isUserCorrected {
            guard let box = block.bbox else { continue }
            let key = boilerplateKey(block.acceptedText, box)
            guard !key.isEmpty else { continue }
            pagesByKey[key, default: []].insert(block.pageID)
        }
        // Sayfa sayılır: tek bir PDF'in her sayfasındaki alt bilgi de, her slayttaki logo da tekrar eden yazıdır.
        let total = archive.pages.filter { [.ready, .needsReview, .partial].contains($0.status) }.count
        let needed = max(3, Int((Double(total) * 0.25).rounded(.up)))
        return Set(pagesByKey.filter { $0.value.count >= needed }.keys)
    }

    /// Tekrar eden kenar yazısının karşılaştırma anahtarı; değilse boş. İki tür yer:
    /// köşedeki kısa yazı (logo, kurum adı) ve sayfanın en üst/en alt şeridindeki alt/üst bilgi. Şeritte rakamlar
    /// anahtara girmez ("... sorular 7" her sayfada aynı sayılır); köşede girer ki sayfa başındaki "Soru 7"
    /// gibi numaralı başlıklar tekrar sayılmasın.
    static func boilerplateKey(_ text: String, _ box: BoundingBox) -> String {
        let cx = box.x + box.width / 2, cy = box.y + box.height / 2
        let band = (cy < 0.06 || cy > 0.94) && text.count <= 60
        let corner = (cx < 0.3 || cx > 0.7) && (cy < 0.15 || cy > 0.85) && text.count <= 25
        guard band || corner else { return "" }
        let folded = text.replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let kept: CharacterSet = band ? .letters : .alphanumerics
        let key = String(folded.unicodeScalars.filter { kept.contains($0) }.map(Character.init))
        let letters = key.filter(\.isLetter).count
        return letters >= (band ? 8 : 3) ? (band ? "b:" : "c:") + key : ""
    }

    /// Sayfanın en üst/en alt şeridinde tek başına duran 1–3 haneli sayı: sayfa veya slayt numarası.
    static func isPageNumber(_ text: String, _ box: BoundingBox) -> Bool {
        let cy = box.y + box.height / 2
        let t = text.trimmingCharacters(in: .whitespaces)
        return (cy < 0.06 || cy > 0.94) && (1...3).contains(t.count) && t.allSatisfy(\.isNumber)
    }

    static func inline(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\n", with: " ")
    }

    static func shortID(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    /// Dosya adı için güvenli parça. Türkçe harfler ASCII karşılığına çevrilir.
    static func slug(_ title: String) -> String {
        let map: [Character: String] = ["ç": "c", "ğ": "g", "ı": "i", "İ": "i", "ö": "o", "ş": "s", "ü": "u",
                                        "Ç": "c", "Ğ": "g", "Ö": "o", "Ş": "s", "Ü": "u"]
        var out = ""
        for ch in title {
            if let m = map[ch] {
                out += m
            } else if ch.isASCII, ch.isLetter || ch.isNumber {
                out += ch.lowercased()
            } else if !out.hasSuffix("-") {
                out += "-"
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let limited = String(trimmed.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return limited.isEmpty ? "kaynak" : limited
    }

    static func isoDate(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

struct FigureCollector {
    var entries: [ExportManifest.FigureEntry] = []
    var assets: [ExportAsset] = []
    var pageAssets: [ExportAsset] = []
    var boilerplate: Set<String> = []
    var imageOnlyPages: [String] = []
    var hasMarks = false
    var hasHandwriting = false
}
