import Foundation

/// OCR satırlarını okuma sırasına koyar ve paragraflara birleştirir.
///
/// Okuma sırası basit bir özyinelemeli XY kesimiyle bulunur: önce sütunları ayıran dikey boşluk aranır,
/// yoksa en büyük yatay boşluktan bölünür. Böylece iki sütunlu slaytta önce sol sütun, sonra sağ sütun okunur.
public enum LayoutAnalyzer {
    /// - Parameters:
    ///   - lines: Satır satır OCR sonucu (sırası önemsiz). `bbox` olmayanlar sona, geldiği sırayla eklenir.
    ///   - pageWidth, pageHeight: Sayfanın piksel boyutu; normalleştirilmiş kutuları gerçek orana çevirmek için.
    public static func paragraphs(from lines: [ExtractedBlock], pageWidth: Double, pageHeight: Double) -> [ExtractedBlock] {
        let boxed = lines.indices.filter { lines[$0].bbox != nil }
        let unboxed = lines.indices.filter { lines[$0].bbox == nil }
        guard !boxed.isEmpty, pageWidth > 0, pageHeight > 0 else { return lines }

        let rects = lines.map { line -> Rect in
            guard let b = line.bbox else { return Rect(minX: 0, minY: 0, maxX: 0, maxY: 0) }
            return Rect(minX: b.x * pageWidth, minY: b.y * pageHeight,
                        maxX: (b.x + b.width) * pageWidth, maxY: (b.y + b.height) * pageHeight)
        }
        let heights = boxed.map { rects[$0].height }.sorted()
        let lineHeight = max(heights[heights.count / 2], 1)

        var groups: [[Int]] = []
        cut(boxed, rects: rects, lineHeight: lineHeight, into: &groups)

        var result = mergeParagraphs(groups.flatMap { $0 }, lines: lines, rects: rects,
                                     pageWidth: pageWidth, pageHeight: pageHeight)
        result.append(contentsOf: unboxed.map { lines[$0] })
        return result
    }

    // MARK: XY kesimi

    struct Rect {
        var minX, minY, maxX, maxY: Double
        var height: Double { maxY - minY }
    }

    /// Sütun ayıran dikey boşluğun en az satır yüksekliğinin bu katı olması gerekir.
    static let columnGapFactor = 0.6

    private static func cut(_ items: [Int], rects: [Rect], lineHeight: Double, into groups: inout [[Int]]) {
        guard items.count > 1 else {
            if !items.isEmpty { groups.append(items) }
            return
        }
        // 1) Sütunlar: x ekseninde hiçbir satırın kapsamadığı en geniş boşluk. Sayfa numarası gibi küçük
        //    kutular sütun arasına düşüp boşluğu kapatabildiği için boşluk yalnız geniş satırlarla aranır;
        //    küçükler sonra merkezlerine göre bir tarafa atanır.
        let wide = items.filter { rects[$0].maxX - rects[$0].minX >= lineHeight * 1.5 }
        let gapItems = wide.count >= 2 ? wide : items
        if let split = largestGap(gapItems, lo: { rects[$0].minX }, hi: { rects[$0].maxX }),
           split.size >= lineHeight * columnGapFactor {
            let left = items.filter { (rects[$0].minX + rects[$0].maxX) / 2 < split.at }
            let right = items.filter { (rects[$0].minX + rects[$0].maxX) / 2 >= split.at }
            cut(left, rects: rects, lineHeight: lineHeight, into: &groups)
            cut(right, rects: rects, lineHeight: lineHeight, into: &groups)
            return
        }
        // 2) Satır blokları: y ekseninde en geniş boşluk.
        if let split = largestGap(items, lo: { rects[$0].minY }, hi: { rects[$0].maxY }), split.size > 0 {
            let top = items.filter { rects[$0].maxY <= split.at }
            let bottom = items.filter { rects[$0].minY >= split.at }
            cut(top, rects: rects, lineHeight: lineHeight, into: &groups)
            cut(bottom, rects: rects, lineHeight: lineHeight, into: &groups)
            return
        }
        // 3) Bölünemiyor: satır aralığı dar olduğundan kutular üst üste biniyor ya da yan yana. Kutular, dikeyde
        //    yarıdan çok örtüşenler aynı satır olacak şekilde satırlara ayrılır; satırlar yukarıdan aşağı, satır
        //    içi soldan sağa okunur. (Yalnız soldan sağa dizmek sıkışık paragrafı karıştırıyordu.)
        var rows: [[Int]] = []
        for i in items.sorted(by: { rects[$0].minY < rects[$1].minY }) {
            if let row = rows.last {
                let top = row.map { rects[$0].minY }.max()!, bottom = row.map { rects[$0].maxY }.min()!
                let overlap = min(bottom, rects[i].maxY) - max(top, rects[i].minY)
                let shortest = min(row.map { rects[$0].height }.min()!, rects[i].height)
                if overlap >= 0.5 * shortest {
                    rows[rows.count - 1].append(i)
                    continue
                }
            }
            rows.append([i])
        }
        groups.append(rows.flatMap { $0.sorted { rects[$0].minX < rects[$1].minX } })
    }

    /// Aralıkların birleşiminde kalan en geniş boşluk; boşluğun ortası `at` olarak döner.
    private static func largestGap(_ items: [Int], lo: (Int) -> Double, hi: (Int) -> Double) -> (at: Double, size: Double)? {
        let sorted = items.sorted { lo($0) < lo($1) }
        var best: (at: Double, size: Double)?
        var reach = hi(sorted[0])
        for i in sorted.dropFirst() {
            let start = lo(i)
            if start > reach {
                let size = start - reach
                if best == nil || size > best!.size { best = ((start + reach) / 2, size) }
            }
            reach = max(reach, hi(i))
        }
        return best
    }

    // MARK: Paragraflar

    /// Bu karakterlerle başlayan satır yeni paragraf (madde) başlatır.
    static let bulletPrefixes: [Character] = ["•", "●", "▪", "■", "◦", "-", "–", "*", "►", "➢", "✓"]

    private static func startsNewItem(_ text: String) -> Bool {
        let t = text.drop { $0 == " " }
        guard let first = t.first else { return false }
        if bulletPrefixes.contains(first) { return true }
        // "1)", "2.", "a)" gibi numaralı maddeler
        let head = t.prefix(3)
        if let close = head.firstIndex(where: { $0 == ")" || $0 == "." }), close != head.startIndex {
            let label = head[head.startIndex..<close]
            if label.allSatisfy(\.isNumber) || (label.count == 1 && label.first!.isLetter) { return true }
        }
        return false
    }

    /// Sayfa numarası gibi yalnız rakamdan oluşan kısa satırlar paragrafı bölmesin diye ertelenir.
    static func isArtifact(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.count <= 4 && t.allSatisfy(\.isNumber)
    }

    /// Okuma sırasındaki satırları, geometrik olarak birbirini sürdürenleri birleştirerek paragraflara çevirir.
    private static func mergeParagraphs(_ ordered: [Int], lines: [ExtractedBlock], rects: [Rect],
                                        pageWidth: Double, pageHeight: Double) -> [ExtractedBlock] {
        var paragraphs: [[Int]] = []
        var deferred: [Int] = []
        for index in ordered {
            if isArtifact(lines[index].text) {
                deferred.append(index)
                continue
            }
            if let current = paragraphs.last, let last = current.last,
               continues(previous: last, next: index, firstOfParagraph: current[0], lines: lines, rects: rects) {
                paragraphs[paragraphs.count - 1].append(index)
            } else {
                paragraphs.append(contentsOf: deferred.map { [$0] })
                deferred.removeAll()
                paragraphs.append([index])
            }
        }
        paragraphs.append(contentsOf: deferred.map { [$0] })
        return paragraphs.map { combine($0, lines: lines, rects: rects, pageWidth: pageWidth, pageHeight: pageHeight) }
    }

    private static func continues(previous p: Int, next n: Int, firstOfParagraph f: Int,
                                  lines: [ExtractedBlock], rects: [Rect]) -> Bool {
        let a = rects[p], b = rects[n]
        let h = max(a.height, b.height)
        guard h > 0 else { return false }
        // Yazı boyu belirgin farklıysa (başlık / gövde) ayrı paragraf.
        guard min(a.height, b.height) / h > 0.75 else { return false }
        // Hemen altında olmalı: üst üste binmeden, en fazla yarım satırlık boşlukla.
        let gap = b.minY - a.maxY
        guard gap > -0.3 * h, gap < 0.6 * h else { return false }
        // Madde işaretiyle başlayan satır yeni paragraftır.
        guard !startsNewItem(lines[n].text) else { return false }
        // Sol kenar: aynı hizada veya madde işaretinden sonraki metin hizasında.
        let anchor = rects[f].minX
        return b.minX >= anchor - 0.5 * h && b.minX <= anchor + 2.0 * h
    }

    private static func combine(_ indices: [Int], lines: [ExtractedBlock], rects: [Rect],
                                pageWidth: Double, pageHeight: Double) -> ExtractedBlock {
        if indices.count == 1 {
            var single = lines[indices[0]]
            single.runs = single.runs.flatMap(TextRuns.droppingUniformTextColor)
            return single
        }
        var text = ""
        var runs: [TextRun] = []
        for i in indices {
            let piece = lines[i].text.trimmingCharacters(in: .whitespaces)
            var pieceRuns = lines[i].runs ?? [TextRun(text: lines[i].text)]
            trimRuns(&pieceRuns)
            if text.isEmpty {
                text = piece
            } else if text.hasSuffix("-"), let first = piece.first, first.isLowercase {
                text.removeLast()   // satır sonu tirelemesi
                if !runs.isEmpty, runs[runs.count - 1].text.hasSuffix("-") { runs[runs.count - 1].text.removeLast() }
                text += piece
            } else {
                text += " " + piece
                runs.append(separator(between: runs.last, and: pieceRuns.first))
            }
            runs.append(contentsOf: pieceRuns)
        }
        let r = indices.map { rects[$0] }
        let minX = r.map(\.minX).min()!, minY = r.map(\.minY).min()!
        let maxX = r.map(\.maxX).max()!, maxY = r.map(\.maxY).max()!
        let confidences = indices.compactMap { lines[$0].confidence }
        var warnings: [String] = []
        for i in indices { for w in lines[i].warnings where !warnings.contains(w) { warnings.append(w) } }
        let styled = indices.contains { lines[$0].runs != nil } ? TextRuns.droppingUniformTextColor(runs) : nil
        return ExtractedBlock(kind: lines[indices[0]].kind, text: text,
                              bbox: BoundingBox(x: minX / pageWidth, y: minY / pageHeight,
                                                width: (maxX - minX) / pageWidth, height: (maxY - minY) / pageHeight),
                              confidence: confidences.min(), warnings: warnings, runs: styled)
    }

    /// Satır başı/sonu boşluklarını parçalardan da kırpar ki birleşim `text` ile aynı kalsın.
    private static func trimRuns(_ runs: inout [TextRun]) {
        while let first = runs.first, first.text.hasPrefix(" ") || first.text.isEmpty {
            runs[0].text = String(first.text.drop { $0 == " " })
            if runs[0].text.isEmpty { runs.removeFirst() } else { break }
        }
        while let last = runs.last, last.text.hasSuffix(" ") || last.text.isEmpty {
            var t = last.text
            while t.hasSuffix(" ") { t.removeLast() }
            runs[runs.count - 1].text = t
            if t.isEmpty { runs.removeLast() } else { break }
        }
    }

    /// Satırlar arası boşluk, iki taraf aynı biçimdeyse o biçimin içinde kalır ("türbülan kan / akımı").
    private static func separator(between a: TextRun?, and b: TextRun?) -> TextRun {
        guard let a, let b else { return TextRun(text: " ") }
        return TextRun(text: " ", highlight: a.highlight == b.highlight ? a.highlight : nil,
                       color: a.color == b.color ? a.color : nil)
    }
}
