import DersArsiviCore
import Foundation

/// Kenar çubuğunda seçilen görünüm.
enum LibraryScope: Hashable {
    case all
    case unfiled
    case marked
    case pending
    case folder(UUID)
}

/// Galeri kartında gösterilen özet: sayfa sayısı, okuma durumu, işaretler.
struct SourceSummary {
    var pageCount = 0
    var readCount = 0
    var markedLines = 0
    var notes = 0
    var imageOnlyPages = 0
    var suggestedFigures = 0
    var savedFigures = 0
    /// Okunmamış, sırada veya hatalı sayfası varsa en "dikkat isteyen" durum; hepsi hazırsa nil.
    var attention: PageStatus?
    /// Arama için: kaynağın tüm metni (küçük harfe çevrilmeden; arama yerel karşılaştırma kullanır).
    var text = ""

    var hasHighlights: Bool { markedLines > 0 || notes > 0 }
}

/// Klasör ağacı (kenar çubuğu için).
struct FolderNode: Identifiable, Hashable {
    let folder: Folder
    var children: [FolderNode]?
    var id: UUID { folder.id }
}

struct FolderEntry: Identifiable {
    let folder: Folder
    let depth: Int
    var id: UUID { folder.id }
    /// Menüde girintili ad.
    var indentedName: String { String(repeating: "   ", count: depth) + folder.name }
}

extension AppModel {
    /// Tüm kaynakların özetleri; arşivin üstünden tek geçişte hesaplanır.
    func summaries() -> [UUID: SourceSummary] {
        var result: [UUID: SourceSummary] = [:]
        var pageSource: [UUID: UUID] = [:]
        for page in archive.pages {
            pageSource[page.id] = page.sourceID
            var s = result[page.sourceID, default: SourceSummary()]
            s.pageCount += 1
            if [.ready, .needsReview, .partial].contains(page.status) { s.readCount += 1 }
            if archive.isImageOnly(page) { s.imageOnlyPages += 1 }
            if let status = Self.attentionStatus(page.status) {
                s.attention = Self.moreUrgent(s.attention, status)
            }
            result[page.sourceID] = s
        }
        for block in archive.blocks {
            guard let sourceID = pageSource[block.pageID] else { continue }
            if block.marked == true { result[sourceID]?.markedLines += 1 }
            if block.kind == .handwriting { result[sourceID]?.notes += 1 }
            result[sourceID]?.text += block.acceptedText + "\n"
        }
        for figure in archive.figures {
            guard let sourceID = pageSource[figure.pageID] else { continue }
            switch figure.status {
            case .suggested: result[sourceID]?.suggestedFigures += 1
            case .accepted: result[sourceID]?.savedFigures += 1
            default: break
            }
        }
        return result
    }

    private static func attentionStatus(_ status: PageStatus) -> PageStatus? {
        switch status {
        case .ready, .needsReview, .partial: return nil
        default: return status
        }
    }

    /// Kartta tek rozet gösterilir: hata > okunuyor > sırada > okunmadı.
    private static func moreUrgent(_ a: PageStatus?, _ b: PageStatus) -> PageStatus {
        let rank: (PageStatus) -> Int = {
            switch $0 {
            case .failed: return 4
            case .processing: return 3
            case .queued: return 2
            default: return 1
            }
        }
        guard let a else { return b }
        return rank(b) > rank(a) ? b : a
    }

    /// Görünümdeki kaynaklar, en yeni üstte. Klasör görünümü yalnız o klasörün doğrudan içeriğidir.
    func sources(in scope: LibraryScope, summaries: [UUID: SourceSummary]) -> [SourceAsset] {
        let all = archive.sources.sorted { $0.importedAt > $1.importedAt }
        switch scope {
        case .all: return all
        case .unfiled: return all.filter { $0.folderID == nil }
        case .marked: return all.filter { summaries[$0.id]?.hasHighlights == true }
        case .pending: return all.filter { summaries[$0.id]?.attention != nil }
        case .folder(let id): return all.filter { $0.folderID == id }
        }
    }

    func folderTree(parent: UUID? = nil) -> [FolderNode] {
        archive.subfolders(of: parent).map { folder in
            let children = folderTree(parent: folder.id)
            return FolderNode(folder: folder, children: children.isEmpty ? nil : children)
        }
    }

    /// Taşıma menüsü için girintili düz liste.
    func flatFolders(parent: UUID? = nil, depth: Int = 0) -> [FolderEntry] {
        var result: [FolderEntry] = []
        for folder in archive.subfolders(of: parent) {
            result.append(FolderEntry(folder: folder, depth: depth))
            result += flatFolders(parent: folder.id, depth: depth + 1)
        }
        return result
    }

    func title(of scope: LibraryScope) -> String {
        switch scope {
        case .all: return "Tüm kaynaklar"
        case .unfiled: return "Klasörsüz"
        case .marked: return "İşaretli ve notlu"
        case .pending: return "Okunmayı bekleyen"
        case .folder(let id): return archive.folder(id)?.name ?? "Klasör"
        }
    }
}
