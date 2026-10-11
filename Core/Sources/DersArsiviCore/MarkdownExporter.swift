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

    public var schemaVersion: Int
    public var exportID: UUID
    public var createdAt: Date
    public var profile: ExportProfile
    public var mode: ExportMode
    public var sources: [SourceEntry]
    public var warnings: [String]
    public var partialExport: Bool
}

public struct ExportFile: Equatable, Sendable {
    public var name: String
    public var contents: String
}

public struct ExportResult: Equatable, Sendable {
    public var files: [ExportFile]
    public var manifest: ExportManifest
}

/// Seçili kaynakları kaynak referanslı Markdown'a çevirir. İşlenmemiş veya başarısız sayfalar
/// sessizce atlanmaz; hem dosyada hem manifestte eksik olarak görünür.
public struct MarkdownExporter {
    /// Bu değerin altındaki motor güveni "belirsiz" sayılır. Kalibre edilmiş bir eşik değildir.
    public var lowConfidenceThreshold: Double

    public init(lowConfidenceThreshold: Double = 0.5) {
        self.lowConfidenceThreshold = lowConfidenceThreshold
    }

    public func export(_ archive: Archive, selections: [SourceSelection], mode: ExportMode,
                       exportID: UUID = UUID(), createdAt: Date) throws -> ExportResult {
        var sections: [(entry: ExportManifest.SourceEntry, markdown: String)] = []
        for selection in selections {
            sections.append(try section(for: selection, in: archive, mode: mode))
        }

        var warnings: [String] = []
        for (entry, _) in sections where !entry.missingPages.isEmpty {
            warnings.append("\(entry.title): \(entry.missingPages.count) sayfa işlenmediği için metni yok")
        }
        let partial = sections.contains { !$0.entry.missingPages.isEmpty }

        var files: [ExportFile] = []
        var entries: [ExportManifest.SourceEntry] = []
        switch mode {
        case .combined:
            let name = "dersarsivi-\(Self.shortID(exportID)).md"
            var body = header(exportID: exportID, createdAt: createdAt, sourceCount: sections.count, warnings: warnings)
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
                let body = header(exportID: exportID, createdAt: createdAt, sourceCount: 1, warnings: ownWarnings)
                    + "\n" + markdown
                files.append(ExportFile(name: name, contents: body))
                var e = entry
                e.file = name
                entries.append(e)
            }
        }

        let manifest = ExportManifest(schemaVersion: archiveSchemaVersion, exportID: exportID, createdAt: createdAt,
                                      profile: .faithfulText, mode: mode, sources: entries, warnings: warnings,
                                      partialExport: partial)
        return ExportResult(files: files, manifest: manifest)
    }

    // MARK: Parçalar

    private func header(exportID: UUID, createdAt: Date, sourceCount: Int, warnings: [String]) -> String {
        var s = "# DersArşivi dışa aktarımı\n\n"
        s += "Profil: sadık metin · Kaynak sayısı: \(sourceCount) · Tarih: \(Self.isoDate(createdAt)) · "
        s += "Export: \(exportID.uuidString.lowercased())\n\n"
        s += "Metin kaynak görüntüsünden OCR ile çıkarıldı; ✏️ kullanıcı tarafından düzeltilmiş, "
        s += "⚠️ belirsiz bölümleri gösterir. Bu dosya görsel içermez.\n"
        if !warnings.isEmpty {
            s += "\n> **Eksik içerik:**\n"
            for w in warnings { s += "> - \(w)\n" }
        }
        return s
    }

    private func section(for selection: SourceSelection, in archive: Archive,
                         mode: ExportMode) throws -> (ExportManifest.SourceEntry, String) {
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
            let blocks = archive.blocks(of: page.id)
            let processed = [.ready, .needsReview, .partial].contains(page.status)
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
            for block in blocks {
                md += "\n" + Self.escape(block.acceptedText)
                if block.isUserCorrected { md += " ✏️" }
                md += "\n"
                if let note = uncertaintyNote(block) {
                    uncertain += 1
                    md += "> ⚠️ Belirsiz: \(note)\n"
                }
            }
        }

        let entry = ExportManifest.SourceEntry(
            sourceID: source.id, title: source.sourceTitle, contentHash: source.contentHash,
            selectedPageIndices: selected.map(\.pageIndex), includedPageIndices: included,
            missingPages: missing, uncertainBlockCount: uncertain, file: "")
        return (entry, md)
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
