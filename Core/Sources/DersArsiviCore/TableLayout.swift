import Foundation

/// Belge tanımanın bulduğu tablo: hücreler, kapladıkları satır/sütun aralıkları ve sayfadaki yerleri.
/// Motor bağımsızdır; kutular sol üst orijinli, 0...1.
public struct DetectedTable: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        public var rows: ClosedRange<Int>
        public var columns: ClosedRange<Int>
        public var text: String
        public var bbox: BoundingBox?

        public init(rows: ClosedRange<Int>, columns: ClosedRange<Int>, text: String, bbox: BoundingBox? = nil) {
            self.rows = rows
            self.columns = columns
            self.text = text
            self.bbox = bbox
        }
    }

    public var bbox: BoundingBox
    public var cells: [Cell]

    public init(bbox: BoundingBox, cells: [Cell]) {
        self.bbox = bbox
        self.cells = cells
    }
}

/// Tabloları Markdown tablosuna çevirir ve sayfanın satırlarıyla birleştirir: tablonun içindeki satırlar
/// paragraf olarak tekrar edilmez, tablo okuma sırasında kendi yerine konur.
public enum TableLayout {
    /// Hücre metni çok uzunsa bulunan şey tablo değil, iki sütunlu düz yazıdır.
    static let maxCellLength = 200
    static let maxAverageCellLength = 80.0

    /// Hücrelerden satır × sütun ızgarası. Birleşik hücrenin metni ilk gözüne yazılır, diğer gözleri boş kalır.
    public static func grid(_ table: DetectedTable) -> [[String]] {
        let rowCount = (table.cells.map(\.rows.upperBound).max() ?? -1) + 1
        let columnCount = (table.cells.map(\.columns.upperBound).max() ?? -1) + 1
        guard rowCount > 0, columnCount > 0 else { return [] }
        var grid = Array(repeating: Array(repeating: "", count: columnCount), count: rowCount)
        // Birleşik hücre her satırın listesinde yeniden görünebilir; bir kez yazılır.
        var seen = Set<[Int]>()
        for cell in table.cells where cell.rows.lowerBound >= 0 && cell.columns.lowerBound >= 0 {
            guard seen.insert([cell.rows.lowerBound, cell.rows.upperBound,
                               cell.columns.lowerBound, cell.columns.upperBound]).inserted else { continue }
            let text = clean(cell.text)
            guard !text.isEmpty else { continue }
            let r = cell.rows.lowerBound, c = cell.columns.lowerBound
            grid[r][c] = grid[r][c].isEmpty ? text : grid[r][c] + " " + text
        }
        // Tamamen boş satır ve sütunlar atılır.
        grid.removeAll { $0.allSatisfy(\.isEmpty) }
        let usedColumns = (0..<columnCount).filter { c in grid.contains { !$0[c].isEmpty } }
        return grid.map { row in usedColumns.map { row[$0] } }
    }

    /// Izgaranın gerçekten tablo olup olmadığı: en az 2 × 2, gözlerin yarısı dolu, hücreler kısa.
    public static func looksLikeTable(_ grid: [[String]]) -> Bool {
        guard grid.count >= 2, let columns = grid.first?.count, columns >= 2 else { return false }
        let cells = grid.flatMap { $0 }
        let filled = cells.filter { !$0.isEmpty }
        guard Double(filled.count) >= Double(cells.count) * 0.5 else { return false }
        guard filled.allSatisfy({ $0.count <= maxCellLength }) else { return false }
        let average = Double(filled.map(\.count).reduce(0, +)) / Double(max(filled.count, 1))
        return average <= maxAverageCellLength
    }

    /// Markdown tablosu; ilk satır başlık kabul edilir. Tablo değilse nil.
    public static func markdown(_ grid: [[String]]) -> String? {
        guard looksLikeTable(grid) else { return nil }
        let row = { (cells: [String]) in "| " + cells.map(escapeCell).joined(separator: " | ") + " |" }
        var lines = [row(grid[0])]
        lines.append("|" + Array(repeating: " --- |", count: grid[0].count).joined())
        lines.append(contentsOf: grid.dropFirst().map(row))
        return lines.joined(separator: "\n")
    }

    /// Markdown tablosunu tekrar ızgaraya çevirir (ekranda göstermek için). Tablo değilse nil.
    public static func parse(_ markdown: String) -> [[String]]? {
        let lines = markdown.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2, lines.allSatisfy({ $0.hasPrefix("|") }) else { return nil }
        var rows: [[String]] = []
        for (i, line) in lines.enumerated() {
            let cells = splitRow(line)
            if i == 1, cells.allSatisfy({ cell in !cell.isEmpty && cell.allSatisfy { "-: ".contains($0) } }) { continue }
            rows.append(cells)
        }
        let width = rows.map(\.count).max() ?? 0
        guard width >= 1 else { return nil }
        return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
    }

    /// Tabloları sayfanın satırlarıyla birleştirir. Tablo olarak kabul edilmeyenler yok sayılır; o bölgedeki
    /// satırlar düz metin olarak kalır.
    /// - Returns: tablonun dışında kalan satırlar ve tablo blokları (yukarıdan aşağı).
    public static func split(lines: [ExtractedBlock], tables: [DetectedTable])
        -> (lines: [ExtractedBlock], tables: [ExtractedBlock]) {
        var remaining = lines
        var blocks: [ExtractedBlock] = []
        for table in tables.sorted(by: { ($0.bbox.y, $0.bbox.x) < ($1.bbox.y, $1.bbox.x) }) {
            let inside = { (line: ExtractedBlock) -> Bool in
                guard let box = line.bbox else { return false }
                return box.fractionInside(table.bbox) >= 0.6
            }
            let filled = preferringLines(table, lines: remaining.filter(inside))
            guard let text = markdown(grid(filled)) else { continue }
            let covered = remaining.filter(inside)
            remaining.removeAll(where: inside)
            let confidences = covered.compactMap(\.confidence)
            var block = ExtractedBlock(kind: .table, text: text, bbox: table.bbox,
                                       confidence: confidences.min())
            block.marked = covered.contains { $0.marked }
            blocks.append(block)
        }
        return (remaining, blocks)
    }

    /// Hücreyi tam içine alan satırlar varsa hücre metni onlardan alınır: PDF metin katmanı ve sayfanın asıl
    /// OCR'ı (Türkçe dil ayarı, vurgular) belge tanımanın kendi okumasından daha güvenilirdir. Birden çok
    /// hücreye taşan satır kullanılmaz.
    static func preferringLines(_ table: DetectedTable, lines: [ExtractedBlock]) -> DetectedTable {
        var table = table
        for i in table.cells.indices {
            guard let cellBox = table.cells[i].bbox else { continue }
            let own = lines.filter { line in
                guard let box = line.bbox else { return false }
                return box.fractionInside(cellBox.insetBy(dx: -0.004, dy: -0.004)) >= 0.85
            }
            guard !own.isEmpty else { continue }
            table.cells[i].text = own
                .sorted { ($0.bbox?.y ?? 0, $0.bbox?.x ?? 0) < ($1.bbox?.y ?? 0, $1.bbox?.x ?? 0) }
                .map(\.text).joined(separator: " ")
        }
        return table
    }

    /// Tablo bloklarını okuma sırasındaki paragrafların arasına yerleştirir: tablonun üst kenarından aşağıda
    /// başlayan ve tabloyla yatayda çakışan ilk paragraftan önce.
    public static func insert(_ tables: [ExtractedBlock], into blocks: [ExtractedBlock]) -> [ExtractedBlock] {
        var result = blocks
        for table in tables {
            guard let t = table.bbox else {
                result.append(table)
                continue
            }
            let index = result.firstIndex { block in
                guard block.kind != .table, let b = block.bbox else { return false }
                let overlaps = min(b.x + b.width, t.x + t.width) > max(b.x, t.x)
                return overlaps && b.y >= t.y
            }
            result.insert(table, at: index ?? result.endIndex)
        }
        return result
    }

    /// Hücredeki satır sonları boşluğa çevrilir; tablo satırı tek satır kalmalı.
    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func escapeCell(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "|", with: "\\|")
    }

    /// `\|` kaçışını dikkate alarak satırı hücrelere böler.
    static func splitRow(_ line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") && !body.hasSuffix("\\|") { body = body.dropLast() }
        var cells: [String] = []
        var current = ""
        var escaping = false
        for ch in body {
            if escaping {
                current.append(ch)
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
