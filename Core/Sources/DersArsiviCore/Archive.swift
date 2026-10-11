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

    public init(
        kind: BlockKind = .text,
        text: String,
        bbox: BoundingBox? = nil,
        confidence: Double? = nil,
        warnings: [String] = [],
        runs: [TextRun]? = nil
    ) {
        self.kind = kind
        self.text = text
        self.bbox = bbox
        self.confidence = confidence
        self.warnings = warnings
        self.runs = runs
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

    public init() {
        schemaVersion = archiveSchemaVersion
        sources = []
        pages = []
        blocks = []
        corrections = []
        extractionRuns = []
        jobQueue = JobQueue()
        figures = []
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, sources, pages, blocks, corrections, extractionRuns, jobQueue, figures
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

    public mutating func renameSource(_ id: UUID, to title: String) {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[i].sourceTitle = title
    }

    public mutating func setStatus(_ status: PageStatus, forPage pageID: UUID, failureReason: String? = nil) throws {
        guard let i = pages.firstIndex(where: { $0.id == pageID }) else { throw ArchiveError.pageNotFound(pageID) }
        pages[i].status = status
        pages[i].failureReason = failureReason
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
                                  labels: s.labels, createdAt: date))
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

    /// Kaydedilen şekli siler; aynı yer tekrar önerilmesin diye yoksayılmış olarak kalır.
    /// Kırpım dosyasının yolunu döndürür; çağıran siler.
    @discardableResult
    public mutating func removeFigure(_ id: UUID) -> String? {
        guard let i = figures.firstIndex(where: { $0.id == id }) else { return nil }
        let ref = figures[i].imageRef
        figures[i].status = .dismissed
        figures[i].imageRef = nil
        return ref
    }
}
