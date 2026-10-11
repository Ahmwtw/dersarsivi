import Foundation

/// Kullanıcının yazdığı "3, 7-9" gibi 1 tabanlı sayfa seçimini 0 tabanlı indekslere çevirir.
public struct PageSelection: Equatable, Sendable {
    /// Sıralı, tekrarsız 0 tabanlı sayfa indeksleri.
    public let indices: [Int]

    public enum ParseError: Error, Equatable {
        case empty
        case invalidToken(String)
        case outOfRange(page: Int, pageCount: Int)
        case reversedRange(String)
    }

    public init(indices: [Int]) {
        self.indices = Array(Set(indices)).sorted()
    }

    /// - Parameters:
    ///   - text: Virgül veya noktalı virgülle ayrılmış sayfalar/aralıklar. Aralık için "-" veya "–".
    ///   - pageCount: Belgedeki toplam sayfa sayısı.
    public static func parse(_ text: String, pageCount: Int) throws -> PageSelection {
        let tokens = text
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { throw ParseError.empty }

        var result: [Int] = []
        for token in tokens {
            let normalized = token.replacingOccurrences(of: "–", with: "-")
            let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            switch parts.count {
            case 1:
                guard let page = Int(parts[0]) else { throw ParseError.invalidToken(token) }
                try check(page, pageCount)
                result.append(page - 1)
            case 2:
                guard let start = Int(parts[0]), let end = Int(parts[1]) else {
                    throw ParseError.invalidToken(token)
                }
                guard start <= end else { throw ParseError.reversedRange(token) }
                try check(start, pageCount)
                try check(end, pageCount)
                result.append(contentsOf: (start - 1)...(end - 1))
            default:
                throw ParseError.invalidToken(token)
            }
        }
        return PageSelection(indices: result)
    }

    private static func check(_ page: Int, _ pageCount: Int) throws {
        guard page >= 1, page <= pageCount else {
            throw ParseError.outOfRange(page: page, pageCount: pageCount)
        }
    }

    /// 1 tabanlı, aralıkları sıkıştırılmış gösterim: [2, 6, 7, 8] → "3, 7–9".
    public var displayText: String {
        var parts: [String] = []
        var i = 0
        while i < indices.count {
            var j = i
            while j + 1 < indices.count, indices[j + 1] == indices[j] + 1 { j += 1 }
            parts.append(i == j ? "\(indices[i] + 1)" : "\(indices[i] + 1)–\(indices[j] + 1)")
            i = j + 1
        }
        return parts.joined(separator: ", ")
    }
}
