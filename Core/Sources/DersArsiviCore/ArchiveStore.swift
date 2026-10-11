import Foundation

/// Arşivi kalıcı saklayan katman. İlk dilimde tek JSON dosyası; arama ve büyük arşiv
/// ihtiyacı doğunca SQLite tabanlı bir uygulama aynı protokolün arkasına geçer (DECISIONS.md, D10).
public protocol ArchiveStore {
    func load() throws -> Archive
    func save(_ archive: Archive) throws
}

public enum ArchiveStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

/// Arşiv klasörü düzeni:
///   archive.json         metadata, bloklar, düzeltmeler
///   originals/<uuid>.<ext>  orijinal dosyalar (değiştirilmez)
///   thumbnails/<uuid>-<sayfa>.jpg
///   figures/<uuid>.jpg   kullanıcının kaydettiği şekil kırpımları
///   pages/<uuid>.jpg     eğik fotoğrafların düzleştirilmiş okuma görüntüsü
public struct FileArchiveStore: ArchiveStore {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public var archiveURL: URL { rootURL.appendingPathComponent("archive.json") }
    public var originalsURL: URL { rootURL.appendingPathComponent("originals", isDirectory: true) }
    public var thumbnailsURL: URL { rootURL.appendingPathComponent("thumbnails", isDirectory: true) }
    public var figuresURL: URL { rootURL.appendingPathComponent("figures", isDirectory: true) }

    public func load() throws -> Archive {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return Archive() }
        let data = try Data(contentsOf: archiveURL)
        let archive = try Self.decoder.decode(Archive.self, from: data)
        guard archive.schemaVersion <= archiveSchemaVersion else {
            throw ArchiveStoreError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        return archive
    }

    /// Atomik yazma: yarıda kalan kayıt eski arşivi bozmaz.
    public func save(_ archive: Archive) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(archive)
        try data.write(to: archiveURL, options: .atomic)
    }

    /// Orijinal dosyayı arşive kopyalar ve içerik hash'ini döndürür. Dosya adı kimlik değildir.
    public func storeOriginal(_ data: Data, id: UUID, fileExtension: String) throws -> (ref: String, hash: String) {
        try FileManager.default.createDirectory(at: originalsURL, withIntermediateDirectories: true)
        let ext = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        let name = ext.isEmpty ? id.uuidString.lowercased() : "\(id.uuidString.lowercased()).\(ext)"
        try data.write(to: originalsURL.appendingPathComponent(name), options: .atomic)
        return ("originals/\(name)", SHA256Hasher.hexDigest(data))
    }

    /// Şekil kırpımını yazar. Her kayıtta yeni ad: eski kırpım silinene kadar geçerli kalır.
    public func storeFigureImage(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: figuresURL, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.lowercased()).jpg"
        try data.write(to: figuresURL.appendingPathComponent(name), options: .atomic)
        return "figures/\(name)"
    }

    /// Sayfanın düzleştirilmiş okuma görüntüsünü yazar.
    public func storePageImage(_ data: Data) throws -> String {
        let dir = rootURL.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.lowercased()).jpg"
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        return "pages/\(name)"
    }

    /// OCR'ın okuduğu satırlar (kutularıyla). Arşiv dosyasını şişirmemek için sayfa başına ayrı dosyadır;
    /// hata ayıklama paketi ve dokun-kırp bunları kullanır.
    public static func linesRef(pageID: UUID) -> String { "lines/\(pageID.uuidString.lowercased()).json" }

    public func storeLines(_ lines: [FigureLabel], pageID: UUID) throws {
        let fileURL = url(forRef: Self.linesRef(pageID: pageID))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(lines).write(to: fileURL, options: .atomic)
    }

    public func loadLines(pageID: UUID) -> [FigureLabel] {
        guard let data = try? Data(contentsOf: url(forRef: Self.linesRef(pageID: pageID))) else { return [] }
        return (try? JSONDecoder().decode([FigureLabel].self, from: data)) ?? []
    }

    /// Kaynak silinirken orijinal dahil arşiv içindeki dosyayı siler. Arşiv klasörü dışına çıkamaz.
    public func removeFile(ref: String) {
        guard !ref.isEmpty, !ref.hasPrefix("/"), !ref.contains("..") else { return }
        try? FileManager.default.removeItem(at: url(forRef: ref))
    }

    /// Yalnız arşivin türetilmiş dosyalarını siler; orijinaller bu yolla silinemez.
    public func removeDerived(ref: String) {
        guard ref.hasPrefix("figures/") || ref.hasPrefix("pages/"), !ref.contains("..") else { return }
        try? FileManager.default.removeItem(at: url(forRef: ref))
    }

    public func url(forRef ref: String) -> URL {
        rootURL.appendingPathComponent(ref)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
