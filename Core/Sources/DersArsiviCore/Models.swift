import Foundation

/// Kalıcı veri sözleşmesinin sürümü. Alan eklendiğinde veya anlamı değiştiğinde artırılır.
public let archiveSchemaVersion = 1

public enum MediaType: String, Codable, Sendable {
    case image
    case pdf
}

public enum SourceType: String, Codable, Sendable {
    case slide
    case book
    case question
    case note
    case unknown
}

/// İçeri alınan orijinal dosya. Orijinal dosyanın kendisi değiştirilmez; ön işleme türev üretir.
public struct SourceAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var mediaType: MediaType
    public var originalFilename: String
    public var sourceTitle: String
    /// Orijinal dosya baytlarının SHA-256 özeti (küçük harf hex). Dosya adı kimlik değildir.
    public var contentHash: String
    /// Arşiv klasörüne göre göreli yol; mutlak cihaz yolu saklanmaz.
    public var localAssetRef: String
    public var importedAt: Date
    public var sourceType: SourceType
    public var tags: [String]
    public var collectionIDs: [UUID]
    /// Bulunduğu klasör; nil ise kök (klasörsüz).
    public var folderID: UUID? = nil
    /// Kullanıcının "sadece görsel" kararı: true ise sayfalar dışa aktarımda metin yerine optimize edilmiş
    /// görüntüyle gider, false ise hep metin. nil: uygulama sayfaya bakıp karar verir (bkz. `Page.looksComplex`).
    public var imageOnly: Bool? = nil

    /// Görselin kendisi; PDF'te sayfa görüntüleri ayrı türev olarak saklanır.
    public var imageRef: String? { mediaType == .image ? localAssetRef : nil }

    public init(
        id: UUID = UUID(),
        mediaType: MediaType,
        originalFilename: String,
        sourceTitle: String,
        contentHash: String,
        localAssetRef: String,
        importedAt: Date,
        sourceType: SourceType = .unknown,
        tags: [String] = [],
        collectionIDs: [UUID] = []
    ) {
        self.id = id
        self.mediaType = mediaType
        self.originalFilename = originalFilename
        self.sourceTitle = sourceTitle
        self.contentHash = contentHash
        self.localAssetRef = localAssetRef
        self.importedAt = importedAt
        self.sourceType = sourceType
        self.tags = tags
        self.collectionIDs = collectionIDs
    }
}

public enum PageStatus: String, Codable, Sendable {
    case imported
    case queued
    case processing
    case needsReview = "needs_review"
    case ready
    case partial
    case failed
    case cancelled
}

/// Bir görselin tek sayfası veya bir PDF sayfası.
public struct Page: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sourceID: UUID
    /// 0 tabanlı PDF/dosya indeksi. Kullanıcıya gösterilen sayfa numarası değildir.
    public var pageIndex: Int
    /// PDF'in kendi sayfa etiketi (ör. "iv", "12"); yoksa nil.
    public var pdfPageLabel: String?
    /// Kaynakta basılı görünen sayfa numarası biliniyorsa.
    public var printedPageNumber: String?
    public var width: Double
    public var height: Double
    public var status: PageStatus
    public var failureReason: String?
    /// Okuma için düzleştirilmiş/döndürülmüş türev görüntü (eğik çekilmiş fotoğraf). Varsa blok ve şekil
    /// kutuları bu görüntüye göredir; orijinal dosya değişmez.
    public var workingImageRef: String? = nil
    /// Ekran görüntüsündeki uygulama kenarlıkları ve araç çubukları hariç sayfa alanı (normalleştirilmiş).
    /// "Tüm sayfa" şekli ve dışa aktarılan sayfa görüntüsü bu alana kırpılır.
    public var contentBox: BoundingBox? = nil
    /// Sayfadaki yazı alanının el yazısı olan payı (0...1); okunmadıysa nil.
    public var handwritingShare: Double? = nil
    /// Okuma sonucu sayfa metne dökülemeyecek kadar karışık (el yazısı ağırlıklı, okunamayan): kaynakta aksi
    /// seçilmedikçe dışa aktarımda görüntü olarak gider.
    public var looksComplex: Bool? = nil

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        pageIndex: Int,
        pdfPageLabel: String? = nil,
        printedPageNumber: String? = nil,
        width: Double,
        height: Double,
        status: PageStatus = .imported,
        failureReason: String? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.pageIndex = pageIndex
        self.pdfPageLabel = pdfPageLabel
        self.printedPageNumber = printedPageNumber
        self.width = width
        self.height = height
        self.status = status
        self.failureReason = failureReason
    }

    /// İnsanın okuyacağı sayfa adı: önce PDF etiketi, yoksa 1 tabanlı indeks.
    public var displayName: String {
        if let label = pdfPageLabel, !label.isEmpty, label != String(pageIndex + 1) {
            return "\(label) (PDF sayfa \(pageIndex + 1))"
        }
        return "\(pageIndex + 1)"
    }
}

/// Normalleştirilmiş sınır kutusu. Koordinat sistemi: sol üst köşe orijin, 0...1 aralığı, yönü düzeltilmiş
/// sayfaya göre (sayfanın düzleştirilmiş türevi varsa ona göre).
public struct BoundingBox: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum BlockKind: String, Codable, Sendable {
    case text
    case heading
    case table
    case figure
    case question
    case handwriting
}

/// Metnin nereden geldiği. Makine metni, kullanıcı düzeltmesi ve AI yorumu ayrı tutulur.
public enum TextOrigin: String, Codable, Sendable {
    case pdfTextLayer = "pdf_text_layer"
    case ocr
    case user
    case aiInterpretation = "ai_interpretation"
}

public enum ReviewStatus: String, Codable, Sendable {
    case unreviewed
    case needsReview = "needs_review"
    case humanVerified = "human_verified"
    /// Kullanıcı düzeltmesinden sonra yeni çıkarım farklı metin getirdi.
    case conflict
}

public struct Block: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pageID: UUID
    public var kind: BlockKind
    public var readingOrder: Int
    public var bbox: BoundingBox?
    /// Son çıkarımın verdiği metin. Yeniden çıkarım yalnız bunu değiştirir.
    public var rawText: String
    /// Export'ta kullanılan metin. Kullanıcı düzeltmişse kullanıcının metnidir.
    public var acceptedText: String
    public var origin: TextOrigin
    public var reviewStatus: ReviewStatus
    /// Motorun verdiği güven değeri (0...1). Kalibre edilmiş doğruluk değildir.
    public var engineConfidence: Double?
    public var warnings: [String]
    public var revision: Int
    /// Bu bloğu üreten çıkarımın kimliği.
    public var extractionRunID: UUID?
    /// Vurgulu/renkli parçalar (yalnız makine metni için; kullanıcı düzeltince silinir).
    public var runs: [TextRun]?
    /// Satırın yanına elle işaret (yıldız, ünlem, çarpı, çıkartma) konmuş.
    public var marked: Bool? = nil

    public init(
        id: UUID = UUID(),
        pageID: UUID,
        kind: BlockKind = .text,
        readingOrder: Int,
        bbox: BoundingBox? = nil,
        rawText: String,
        origin: TextOrigin,
        engineConfidence: Double? = nil,
        warnings: [String] = [],
        extractionRunID: UUID? = nil
    ) {
        self.id = id
        self.pageID = pageID
        self.kind = kind
        self.readingOrder = readingOrder
        self.bbox = bbox
        self.rawText = rawText
        self.acceptedText = rawText
        self.origin = origin
        self.reviewStatus = .unreviewed
        self.engineConfidence = engineConfidence
        self.warnings = warnings
        self.revision = 1
        self.extractionRunID = extractionRunID
    }

    public var isUserCorrected: Bool { origin == .user }
}

/// Bir kullanıcı düzeltmesinin kaydı. Geçmiş silinmez.
public struct Correction: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var blockID: UUID
    public var previousRevision: Int
    public var newRevision: Int
    public var previousText: String
    public var newText: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        blockID: UUID,
        previousRevision: Int,
        newRevision: Int,
        previousText: String,
        newText: String,
        createdAt: Date
    ) {
        self.id = id
        self.blockID = blockID
        self.previousRevision = previousRevision
        self.newRevision = newRevision
        self.previousText = previousText
        self.newText = newText
        self.createdAt = createdAt
    }
}

/// Bir çıkarım çalıştırmasının kaydı; cache anahtarı ve tekrar kullanım için.
public struct ExtractionRun: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pageID: UUID
    public var sourceContentHash: String
    public var engine: String
    public var engineVersion: String
    public var configHash: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var error: String?

    public init(
        id: UUID = UUID(),
        pageID: UUID,
        sourceContentHash: String,
        engine: String,
        engineVersion: String,
        configHash: String,
        startedAt: Date,
        finishedAt: Date? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.pageID = pageID
        self.sourceContentHash = sourceContentHash
        self.engine = engine
        self.engineVersion = engineVersion
        self.configHash = configHash
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.error = error
    }

    /// Aynı kaynak, sayfa, motor ve ayarla yapılmış başarılı çıkarım tekrar kullanılabilir.
    public var cacheKey: String {
        "\(sourceContentHash)|\(pageID.uuidString)|\(engine)@\(engineVersion)|\(configHash)"
    }
}

/// Kaynakları gruplayan klasör ("Fizyoloji"). İç içe olabilir.
public struct Folder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil, createdAt: Date) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
    }
}
