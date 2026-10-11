import Foundation

/// Bir çıkarım motorunun bir sayfa için döndürdüğü blok. Motor bağımsızdır.
public struct ExtractedBlock: Equatable, Sendable {
    public var kind: BlockKind
    public var text: String
    public var bbox: BoundingBox?
    public var confidence: Double?
    public var warnings: [String]
    /// Vurgulu veya renkli kelimeler varsa biçimli parçalar; düz metinde nil. Birleşimi `text`'e eşittir.
    public var runs: [TextRun]?
    /// Satırın yanında elle konmuş işaret var.
    public var marked: Bool

    public init(
        kind: BlockKind = .text,
        text: String,
        bbox: BoundingBox? = nil,
        confidence: Double? = nil,
        warnings: [String] = [],
        runs: [TextRun]? = nil,
        marked: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.bbox = bbox
        self.confidence = confidence
        self.warnings = warnings
        self.runs = runs
        self.marked = marked
    }
}

public enum ArchiveError: Error, Equatable {
    case sourceNotFound(UUID)
    case pageNotFound(UUID)
    case blockNotFound(UUID)
    case figureNotFound(UUID)
}

/// Arşivin tüm kalıcı durumu. Kaynak, çıkarım, düzeltme katmanları ayrı tutulur.
public struct Archive: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public private(set) var sources: [SourceAsset]
    public private(set) var pages: [Page]
    public private(set) var blocks: [Block]
    public private(set) var corrections: [Correction]
    public private(set) var extractionRuns: [ExtractionRun]
    /// Çıkarım işleri arşivle birlikte saklanır; uygulama kapanınca kaybolmaz.
    public var jobQueue: JobQueue
    /// Şekil önerileri ve kaydedilen şekil kırpımları.
    public private(set) var figures: [Figure]
    public private(set) var folders: [Folder]

    public init() {
        schemaVersion = archiveSchemaVersion
        sources = []
        pages = []
        blocks = []
        corrections = []
        extractionRuns = []
        jobQueue = JobQueue()
        figures = []
        folders = []
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, sources, pages, blocks, corrections, extractionRuns, jobQueue, figures, folders
    }

    /// Sonradan eklenen alanlar eski arşiv dosyalarında yoktur; boş kabul edilir.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        sources = try c.decode([SourceAsset].self, forKey: .sources)
        pages = try c.decode([Page].self, forKey: .pages)
        blocks = try c.decode([Block].self, forKey: .blocks)
        corrections = try c.decode([Correction].self, forKey: .corrections)
        extractionRuns = try c.decode([ExtractionRun].self, forKey: .extractionRuns)
        jobQueue = try c.decode(JobQueue.self, forKey: .jobQueue)
        figures = try c.decodeIfPresent([Figure].self, forKey: .figures) ?? []
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
    }

    // MARK: Sorgular

    public func source(_ id: UUID) -> SourceAsset? { sources.first { $0.id == id } }

    public func source(withContentHash hash: String) -> SourceAsset? {
        sources.first { $0.contentHash == hash }
    }

    public func pages(of sourceID: UUID) -> [Page] {
        pages.filter { $0.sourceID == sourceID }.sorted { $0.pageIndex < $1.pageIndex }
    }

    public func blocks(of pageID: UUID) -> [Block] {
        blocks.filter { $0.pageID == pageID }.sorted { $0.readingOrder < $1.readingOrder }
    }

    public func corrections(of blockID: UUID) -> [Correction] {
        corrections.filter { $0.blockID == blockID }.sorted { $0.newRevision < $1.newRevision }
    }

    // MARK: İçeri alma

    public enum ImportResult: Equatable {
        case added(SourceAsset)
        /// Aynı içerik hash'i zaten arşivde; yeni kayıt açılmadı.
        case duplicate(existing: SourceAsset)
    }

    /// Yeni kaynak ve sayfalarını ekler. Aynı içerik daha önce alınmışsa tekrar eklemez.
    @discardableResult
    public mutating func importSource(_ source: SourceAsset, pageSizes: [(width: Double, height: Double)],
                                      pdfPageLabels: [String?] = []) -> ImportResult {
        if let existing = self.source(withContentHash: source.contentHash) {
            return .duplicate(existing: existing)
        }
        sources.append(source)
        for (index, size) in pageSizes.enumerated() {
            let label = index < pdfPageLabels.count ? pdfPageLabels[index] : nil
            pages.append(Page(sourceID: source.id, pageIndex: index, pdfPageLabel: label,
                              width: size.width, height: size.height))
        }
        return .added(source)
    }

    /// Kaynağı ve ona ait her şeyi (sayfalar, bloklar, düzeltmeler, çıkarımlar, işler, şekiller) siler.
    /// Silinmesi gereken dosyaların arşiv içi yollarını döndürür (orijinal, düzleştirilmiş sayfa, kırpımlar).
    @discardableResult
    public mutating func removeSource(_ id: UUID) -> [String] {
        guard let source = source(id) else { return [] }
        let pageIDs = Set(pages.filter { $0.sourceID == id }.map(\.id))
        let blockIDs = Set(blocks.filter { pageIDs.contains($0.pageID) }.map(\.id))
        var files = [source.localAssetRef]
        files += pages.filter { pageIDs.contains($0.id) }.compactMap(\.workingImageRef)
        files += figures.filter { pageIDs.contains($0.pageID) }.compactMap(\.imageRef)
        files += pageIDs.map(FileArchiveStore.linesRef(pageID:))

        sources.removeAll { $0.id == id }
        pages.removeAll { pageIDs.contains($0.id) }
        blocks.removeAll { pageIDs.contains($0.pageID) }
        corrections.removeAll { blockIDs.contains($0.blockID) }
        extractionRuns.removeAll { pageIDs.contains($0.pageID) }
        figures.removeAll { pageIDs.contains($0.pageID) }
        jobQueue.remove(pageIDs: pageIDs)
        return files
    }

    public mutating func renameSource(_ id: UUID, to title: String) {
        guard let i = sources.firstIndex(where: { $0.id == id }), sources[i].sourceTitle != title else { return }
        sources[i].sourceTitle = title
        sources[i].autoTitle = nil
    }

    /// Kaynakların başlığını geçici sayar ve okunmuş ilk sayfalarından başlık verir (eski arşivlerdeki
    /// "Görsel 12 Eki 00:57" başlıkları için).
    public mutating func adoptAutoTitles(_ ids: [UUID]) {
        for id in ids {
            guard let i = sources.firstIndex(where: { $0.id == id }) else { continue }
            sources[i].autoTitle = true
            refreshAutoTitle(id)
        }
    }

    /// Başlığı geçici olan kaynağa ilk sayfasında okunan başlığı verir; aynı adlı kaynak varsa "(2)" eklenir.
    /// Uygun satır yoksa (henüz okunmadı, yalnız şekil) başlık değişmez.
    public mutating func refreshAutoTitle(_ sourceID: UUID) {
        guard let i = sources.firstIndex(where: { $0.id == sourceID }), sources[i].autoTitle == true,
              let page = pages(of: sourceID).first,
              let base = Self.titleCandidate(blocks(of: page.id),
                                             figures: figures(of: page.id).filter { $0.status != .dismissed }.map(\.bbox))
        else { return }
        let others = Set(sources.filter { $0.id != sourceID }.map(\.sourceTitle))
        var title = base
        var n = 2
        while others.contains(title) {
            title = "\(base) (\(n))"
            n += 1
        }
        sources[i].sourceTitle = title
    }

    /// Sayfanın üst kısmındaki ilk düzgün satır: şekil, el yazısı, kenar şeridi ve köşe yazısı (logo) değil,
    /// en az 4 harf, en fazla 80 karakter. Baştaki madde işareti atılır, 60 karakterden uzunsa kelimede kesilir.
    static func titleCandidate(_ blocks: [Block], figures: [BoundingBox]) -> String? {
        for block in blocks {
            guard let box = block.bbox, box.y < 0.35, block.kind != .handwriting,
                  (block.engineConfidence ?? 1) >= 0.5 else { continue }
            let cx = box.x + box.width / 2, cy = box.y + box.height / 2
            if cy < 0.03 || cy > 0.97 { continue }
            var text = block.acceptedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if (cx < 0.25 || cx > 0.75) && cy < 0.12 && text.count <= 25 { continue }
            if figures.contains(where: { box.fractionInside($0) >= 0.5 }) { continue }
            text = String(text.drop { "•-–·*▪●○◦ ".contains($0) })
            guard text.count <= 80, text.filter(\.isLetter).count >= 4 else { continue }
            if text.count > 60 {
                let cut = text.prefix(60)
                text = (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
            }
            return text
        }
        return nil
    }

    /// Sayfanın okuma görüntüsünü değiştirir; eski türev dosyanın yolunu döndürür (çağıran siler).
    @discardableResult
    public mutating func setWorkingImage(_ ref: String?, forPage pageID: UUID) -> String? {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return nil }
        let old = pages[i].workingImageRef
        pages[i].workingImageRef = ref
        return old == ref ? nil : old
    }

    public mutating func setContentBox(_ box: BoundingBox?, forPage pageID: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[i].contentBox = box
    }

    public mutating func setStatus(_ status: PageStatus, forPage pageID: UUID, failureReason: String? = nil) throws {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { throw ArchiveError.pageNotFound(pageID) }
        pages[i].status = status
        pages[i].failureReason = failureReason
    }

    /// Okuma sonrası sayfa çözümlemesi: el yazısı payı ve karışık sayfa kararı.
    public mutating func setAnalysis(handwritingShare: Double?, looksComplex: Bool?, forPage pageID: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[i].handwritingShare = handwritingShare
        pages[i].looksComplex = looksComplex
    }

    /// Kaynakların "sadece görsel" kararı; nil uygulamanın sayfa bazlı kararına bırakır.
    public mutating func setImageOnly(_ value: Bool?, sources ids: [UUID]) {
        let set = Set(ids)
        for i in sources.indices where set.contains(sources[i].id) { sources[i].imageOnly = value }
    }

    /// Sayfa dışa aktarımda metin yerine görüntüyle mi gider: kaynakta kullanıcı kararı, yoksa sayfanın durumu.
    public func isImageOnly(_ page: Page) -> Bool {
        source(page.sourceID)?.imageOnly ?? page.looksComplex ?? false
    }

    // MARK: Klasörler

    public func folder(_ id: UUID) -> Folder? { folders.first { $0.id == id } }

    /// Klasörün (nil: kök) doğrudan alt klasörleri, ada göre.
    public func subfolders(of parentID: UUID?) -> [Folder] {
        folders.filter { $0.parentID == parentID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Klasördeki (nil: klasörsüz) kaynaklar, en yeni önce.
    public func sources(inFolder folderID: UUID?) -> [SourceAsset] {
        sources.filter { $0.folderID == folderID }.sorted { $0.importedAt > $1.importedAt }
    }

    /// Klasör ve bütün alt klasörlerindeki kaynaklar.
    public func sources(inFolderTree folderID: UUID) -> [SourceAsset] {
        var ids: Set<UUID> = [folderID]
        var frontier = [folderID]
        while let next = frontier.popLast() {
            for child in folders where child.parentID == next && !ids.contains(child.id) {
                ids.insert(child.id)
                frontier.append(child.id)
            }
        }
        return sources.filter { s in s.folderID.map { ids.contains($0) } ?? false }.sorted { $0.importedAt > $1.importedAt }
    }

    /// Kökten klasöre giden yol ("Fizyoloji › Kalp").
    public func folderPath(_ id: UUID) -> [Folder] {
        var path: [Folder] = []
        var current = folder(id)
        while let f = current, !path.contains(where: { $0.id == f.id }) {
            path.insert(f, at: 0)
            current = f.parentID.flatMap { folder($0) }
        }
        return path
    }

    @discardableResult
    public mutating func createFolder(name: String, parentID: UUID? = nil, at date: Date) -> Folder {
        let folder = Folder(name: name, parentID: parentID.flatMap { self.folder($0)?.id }, createdAt: date)
        folders.append(folder)
        return folder
    }

    public mutating func renameFolder(_ id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
    }

    /// Klasörü siler; içindeki kaynaklar ve alt klasörler bir üst klasöre taşınır, hiçbir kaynak silinmez.
    public mutating func deleteFolder(_ id: UUID) {
        guard let removed = folder(id) else { return }
        for i in sources.indices where sources[i].folderID == id { sources[i].folderID = removed.parentID }
        for i in folders.indices where folders[i].parentID == id { folders[i].parentID = removed.parentID }
        folders.removeAll { $0.id == id }
    }

    /// Kaynakları klasöre (nil: köke) taşır.
    public mutating func move(sources ids: [UUID], toFolder folderID: UUID?) {
        let target = folderID.flatMap { folder($0)?.id }
        let set = Set(ids)
        for i in sources.indices where set.contains(sources[i].id) { sources[i].folderID = target }
    }

    /// Klasörü başka bir klasörün altına taşır; kendi altına taşınamaz.
    public mutating func moveFolder(_ id: UUID, toParent parentID: UUID?) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        if let parentID, folderPath(parentID).contains(where: { $0.id == id }) { return }
        let target = parentID.flatMap { folder($0)?.id }
        folders[i].parentID = target
    }

    // MARK: Çıkarım

    /// Aynı ayarlarla başarılı bir çıkarım varsa döndürür; yeniden işlemeye gerek kalmaz.
    public func cachedRun(cacheKey: String) -> ExtractionRun? {
        extractionRuns.last { $0.cacheKey == cacheKey && $0.error == nil && $0.finishedAt != nil }
    }

    /// Bir çıkarım sonucunu sayfaya uygular. Kullanıcının düzelttiği bloklar asla ezilmez:
    /// yalnızca `rawText` güncellenir, metin değiştiyse blok `conflict` olarak işaretlenir.
    public mutating func applyExtraction(_ extracted: [ExtractedBlock], run: ExtractionRun) throws {
        guard let pageIdx = pages.firstIndex(where: { $0.id == run.pageID }) else {
            throw ArchiveError.pageNotFound(run.pageID)
        }
        extractionRuns.append(run)
        let existing = blocks(of: run.pageID)

        var kept: [Block] = []
        for (order, item) in extracted.enumerated() {
            if order < existing.count {
                var block = existing[order]
                if block.isUserCorrected {
                    if block.rawText != item.text {
                        block.reviewStatus = .conflict
                    }
                    block.rawText = item.text
                } else {
                    block.rawText = item.text
                    block.acceptedText = item.text
                    block.origin = .ocr
                    block.reviewStatus = .unreviewed
                    block.kind = item.kind
                    block.runs = item.runs
                }
                block.marked = item.marked ? true : nil
                block.bbox = item.bbox
                block.engineConfidence = item.confidence
                block.warnings = item.warnings
                block.extractionRunID = run.id
                kept.append(block)
            } else {
                var block = Block(pageID: run.pageID, kind: item.kind, readingOrder: order, bbox: item.bbox,
                                  rawText: item.text, origin: .ocr, engineConfidence: item.confidence,
                                  warnings: item.warnings, extractionRunID: run.id)
                block.runs = item.runs
                block.marked = item.marked ? true : nil
                kept.append(block)
            }
        }
        // Yeni çıkarımda karşılığı olmayan düzeltilmiş bloklar silinmez, çatışma olarak kalır.
        if existing.count > extracted.count {
            for var orphan in existing[extracted.count...] where orphan.isUserCorrected {
                orphan.reviewStatus = .conflict
                if !orphan.warnings.contains(Self.orphanWarning) { orphan.warnings.append(Self.orphanWarning) }
                kept.append(orphan)
            }
        }

        blocks.removeAll { $0.pageID == run.pageID }
        blocks.append(contentsOf: kept)

        let needsReview = kept.contains { $0.reviewStatus == .conflict || !$0.warnings.isEmpty }
        pages[pageIdx].status = needsReview ? .needsReview : .ready
        pages[pageIdx].failureReason = nil
    }

    public static let orphanWarning = "Yeni çıkarımda bu bloğun karşılığı bulunamadı"

    // MARK: Düzeltme

    /// Kullanıcı düzeltmesini yeni revizyon olarak kaydeder.
    public mutating func correct(blockID: UUID, newText: String, at date: Date) throws {
        guard let i = blocks.firstIndex(where: { $0.id == blockID }) else { throw ArchiveError.blockNotFound(blockID) }
        let old = blocks[i]
        guard old.acceptedText != newText else {
            blocks[i].reviewStatus = .humanVerified
            return
        }
        let correction = Correction(blockID: blockID, previousRevision: old.revision, newRevision: old.revision + 1,
                                    previousText: old.acceptedText, newText: newText, createdAt: date)
        corrections.append(correction)
        blocks[i].acceptedText = newText
        // Biçim parçaları eski metne aitti; düzeltilen metinde konumları bilinmez.
        blocks[i].runs = nil
        blocks[i].origin = .user
        blocks[i].revision += 1
        blocks[i].reviewStatus = .humanVerified
    }

    // MARK: Şekiller

    public func figure(_ id: UUID) -> Figure? { figures.first { $0.id == id } }

    /// Sayfanın yoksayılmamış şekilleri, yukarıdan aşağı.
    public func figures(of pageID: UUID) -> [Figure] {
        figures.filter { $0.pageID == pageID && $0.status != .dismissed }
            .sorted { ($0.bbox.y, $0.bbox.x) < ($1.bbox.y, $1.bbox.x) }
    }

    public func suggestedFigureCount(sourceID: UUID) -> Int {
        let pageIDs = Set(pages(of: sourceID).map(\.id))
        return figures.filter { pageIDs.contains($0.pageID) && $0.status == .suggested }.count
    }

    /// Yeni önerileri uygular. Eski öneriler silinir; kaydedilen veya yoksayılan şekillerle çakışan öneri eklenmez.
    public mutating func applyFigureSuggestions(_ suggestions: [FigureSuggestion], pageID: UUID, at date: Date) {
        figures.removeAll { $0.pageID == pageID && $0.status == .suggested }
        let decided = figures.filter { $0.pageID == pageID }
        for s in suggestions {
            let overlaps = decided.contains { d in
                guard let i = d.bbox.intersection(s.bbox) else { return false }
                return i.area / min(d.bbox.area, s.bbox.area) > 0.5
            }
            guard !overlaps else { continue }
            figures.append(Figure(pageID: pageID, bbox: s.bbox, status: .suggested, isAutoDetected: true,
                                  labels: s.labels, createdAt: date, kind: s.kind))
        }
    }

    /// Öneriyi (gerekirse yeni kutusuyla) kaydeder veya kaydedilmiş şeklin kutusunu değiştirir.
    /// Önceki kırpım dosyası varsa yolunu döndürür; çağıran siler.
    @discardableResult
    public mutating func acceptFigure(_ id: UUID, bbox: BoundingBox, imageRef: String) throws -> String? {
        guard let i = figures.firstIndex(where: { $0.id == id }) else { throw ArchiveError.figureNotFound(id) }
        let previous = figures[i].imageRef
        if figures[i].bbox != bbox {
            // Kutu değiştiyse dışarıda kalan etiketler atılır.
            figures[i].labels = figures[i].labels.filter { $0.bbox.fractionInside(bbox) >= 0.6 }
            figures[i].bbox = bbox
        }
        figures[i].status = .accepted
        figures[i].imageRef = imageRef
        return previous == imageRef ? nil : previous
    }

    /// Kullanıcının elle çizdiği şekil. Etiket olarak içindeki OCR blokları alınır.
    @discardableResult
    public mutating func addFigure(pageID: UUID, bbox: BoundingBox, imageRef: String, at date: Date) -> Figure {
        let labels = blocks(of: pageID).compactMap { b -> FigureLabel? in
            guard let box = b.bbox, box.fractionInside(bbox) >= 0.6 else { return nil }
            return FigureLabel(text: b.acceptedText, bbox: box)
        }
        let figure = Figure(pageID: pageID, bbox: bbox, status: .accepted, isAutoDetected: false,
                            imageRef: imageRef, labels: labels, createdAt: date)
        figures.append(figure)
        return figure
    }

    public mutating func dismissFigure(_ id: UUID) {
        guard let i = figures.firstIndex(where: { $0.id == id }) else { return }
        figures[i].status = .dismissed
    }

    /// Kaydedilen şekli tamamen siler; "Yoksay"dan farklı olarak yeniden okumada aynı yer tekrar önerilebilir.
    /// Kırpım dosyasının yolunu döndürür; çağıran siler.
    @discardableResult
    public mutating func removeFigure(_ id: UUID) -> String? {
        guard let i = figures.firstIndex(where: { $0.id == id }) else { return nil }
        return figures.remove(at: i).imageRef
    }
}
