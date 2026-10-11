import Foundation

/// Bir çıkarım motorunun bir sayfa için döndürdüğü blok. Motor bağımsızdır.
public struct ExtractedBlock: Equatable, Sendable {
    public var kind: BlockKind
    public var text: String
    public var bbox: BoundingBox?
    public var confidence: Double?
    public var warnings: [String]

    public init(
        kind: BlockKind = .text,
        text: String,
        bbox: BoundingBox? = nil,
        confidence: Double? = nil,
        warnings: [String] = []
    ) {
        self.kind = kind
        self.text = text
        self.bbox = bbox
        self.confidence = confidence
        self.warnings = warnings
    }
}

public enum ArchiveError: Error, Equatable {
    case sourceNotFound(UUID)
    case pageNotFound(UUID)
    case blockNotFound(UUID)
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

    public init() {
        schemaVersion = archiveSchemaVersion
        sources = []
        pages = []
        blocks = []
        corrections = []
        extractionRuns = []
        jobQueue = JobQueue()
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
                }
                block.bbox = item.bbox
                block.engineConfidence = item.confidence
                block.warnings = item.warnings
                block.extractionRunID = run.id
                kept.append(block)
            } else {
                kept.append(Block(pageID: run.pageID, kind: item.kind, readingOrder: order, bbox: item.bbox,
                                  rawText: item.text, origin: .ocr, engineConfidence: item.confidence,
                                  warnings: item.warnings, extractionRunID: run.id))
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
        blocks[i].origin = .user
        blocks[i].revision += 1
        blocks[i].reviewStatus = .humanVerified
    }
}
