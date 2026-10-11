import Foundation

public enum FigureStatus: String, Codable, Sendable {
    /// Uygulamanın önerisi; kullanıcı henüz bakmadı. Yeniden okumada yenilenir.
    case suggested
    /// Kullanıcı kaydetti; kırpılmış görseli var. Yeniden okuma dokunmaz.
    case accepted
    /// Kullanıcı yoksaydı; aynı yer tekrar önerilmez.
    case dismissed
}

/// Şeklin içindeki bir yazı (ör. "Aort"). Kutusu sayfaya göredir; exportta şekle göreli verilir.
public struct FigureLabel: Codable, Equatable, Sendable {
    public var text: String
    public var bbox: BoundingBox

    public init(text: String, bbox: BoundingBox) {
        self.text = text
        self.bbox = bbox
    }
}

/// Sayfadaki şema, grafik veya fotoğraf bölgesi. Kutusu yönü düzeltilmiş sayfaya göredir (bloklarla aynı düzlem).
public struct Figure: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pageID: UUID
    public var bbox: BoundingBox
    public var status: FigureStatus
    /// Uygulama mı buldu, kullanıcı mı çizdi.
    public var isAutoDetected: Bool
    /// Kırpılmış küçük JPEG; arşiv klasörüne göre göreli yol. Yalnız kabul edilen şekillerde.
    public var imageRef: String?
    public var labels: [FigureLabel]
    public var createdAt: Date

    public init(id: UUID = UUID(), pageID: UUID, bbox: BoundingBox, status: FigureStatus, isAutoDetected: Bool,
                imageRef: String? = nil, labels: [FigureLabel] = [], createdAt: Date) {
        self.id = id
        self.pageID = pageID
        self.bbox = bbox
        self.status = status
        self.isAutoDetected = isAutoDetected
        self.imageRef = imageRef
        self.labels = labels
        self.createdAt = createdAt
    }
}

public struct FigureSuggestion: Equatable, Sendable {
    public var bbox: BoundingBox
    public var labels: [FigureLabel]

    public init(bbox: BoundingBox, labels: [FigureLabel] = []) {
        self.bbox = bbox
        self.labels = labels
    }
}

extension BoundingBox {
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(0, width) * max(0, height) }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }

    public func intersection(_ o: BoundingBox) -> BoundingBox? {
        let x0 = max(x, o.x), y0 = max(y, o.y), x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return BoundingBox(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public func union(_ o: BoundingBox) -> BoundingBox {
        let x0 = min(x, o.x), y0 = min(y, o.y)
        return BoundingBox(x: x0, y: y0, width: max(maxX, o.maxX) - x0, height: max(maxY, o.maxY) - y0)
    }

    public func insetBy(dx: Double, dy: Double) -> BoundingBox {
        BoundingBox(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    /// Bu kutunun ne kadarı `o`'nun içinde (0...1).
    public func fractionInside(_ o: BoundingBox) -> Double {
        guard area > 0 else { return 0 }
        return (intersection(o)?.area ?? 0) / area
    }

    public func clamped(to o: BoundingBox) -> BoundingBox {
        let x0 = min(max(x, o.x), o.maxX), y0 = min(max(y, o.y), o.maxY)
        let x1 = max(min(maxX, o.maxX), x0), y1 = max(min(maxY, o.maxY), y0)
        return BoundingBox(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// `container` içindeki göreli konum (0...1).
    public func relative(to container: BoundingBox) -> BoundingBox {
        guard container.width > 0, container.height > 0 else { return self }
        return BoundingBox(x: (x - container.x) / container.width, y: (y - container.y) / container.height,
                           width: width / container.width, height: height / container.height)
    }
}

/// Metin dışı görsel bölgeleri (şema, grafik, fotoğraf) bulur. Belirli bir slayt şablonuna göre ayarlanmamıştır:
/// yalnız "sayfa zemininden farklı, OCR yazısı olmayan, yeterince büyük bölge" kuralını kullanır.
///
/// Adımlar: zemin rengi → içerik alanı (ekran görüntüsündeki uygulama kenarlıkları ve araç çubukları dışarıda kalır)
/// → hücre ızgarasında mürekkep → yazı satırları silinir → bağlı bölgeler → küçük/ince/yazı dolu bölgeler elenir
/// → şeklin etiketleri (yakındaki kısa yazılar) şekle katılır.
public enum FigureDetector {
    /// Izgaranın uzun kenarındaki hücre sayısı.
    static let cellsAcross = 120
    static let inkDistance = 50.0
    static let backgroundDistance = 25.0
    static let maxSuggestions = 4

    public typealias Line = (text: String, bbox: BoundingBox)

    /// Sayfanın hücre ızgarası ve içerik alanı. Hem şekil önerisi hem de kenar/araç çubuğu yazılarını
    /// ayıklamak için kullanılır.
    public struct PageScan: Sendable {
        /// Ekran görüntüsündeki uygulama kenarlıkları ve araç çubukları hariç sayfa alanı (normalleştirilmiş).
        public let content: BoundingBox
        let cols: Int, rows: Int
        let ink: [Bool]
        let c0: Int, c1: Int, r0: Int, r1: Int
    }

    /// - Parameters:
    ///   - rgba: Yönü düzeltilmiş, küçültülmüş görüntü (RGBA8). Birkaç yüz piksel yeter.
    public static func scan(rgba: [UInt8], width: Int, height: Int) -> PageScan? {
        guard width > 8, height > 8, rgba.count >= width * height * 4,
              let background = ColorAnalysis.backgroundAndInk(rgba: rgba)?.background else { return nil }

        let cell = max(1, max(width, height) / cellsAcross)
        let cols = width / cell, rows = height / cell
        guard cols > 4, rows > 4 else { return nil }

        // Hücre başına mürekkep ve zemin oranı.
        let inkSq = inkDistance * inkDistance, bgSq = backgroundDistance * backgroundDistance
        var ink = [Bool](repeating: false, count: cols * rows)
        var isBackground = [Bool](repeating: false, count: cols * rows)
        let perCell = Double(cell * cell)
        for r in 0..<rows {
            for c in 0..<cols {
                var inkCount = 0, bgCount = 0
                for y in (r * cell)..<(r * cell + cell) {
                    var i = (y * width + c * cell) * 4
                    for _ in 0..<cell {
                        let dr = Double(rgba[i]) - background.r
                        let dg = Double(rgba[i + 1]) - background.g
                        let db = Double(rgba[i + 2]) - background.b
                        let d = dr * dr + dg * dg + db * db
                        if d > inkSq { inkCount += 1 } else if d < bgSq { bgCount += 1 }
                        i += 4
                    }
                }
                ink[r * cols + c] = Double(inkCount) / perCell >= 0.1
                isBackground[r * cols + c] = Double(bgCount) / perCell >= 0.5
            }
        }

        // İçerik alanı: zemin rengini yeterince içeren sütun ve satırlar. Koyu kenarlıklar ve araç çubukları elenir.
        guard let colSpan = span(count: cols, minFraction: 0.15, fraction: { c in
            (0..<rows).reduce(0) { $0 + (isBackground[$1 * cols + c] ? 1 : 0) }
        }, total: rows) else { return nil }
        var (c0, c1) = colSpan
        guard let rowSpan = span(count: rows, minFraction: 0.15, fraction: { r in
            (c0..<c1).reduce(0) { $0 + (isBackground[r * cols + $1] ? 1 : 0) }
        }, total: c1 - c0) else { return nil }
        var (r0, r1) = rowSpan
        // Kenar hücreleri yarı içerik yarı çerçevedir; mürekkep sanılmasın.
        if c0 > 0 { c0 += 1 }
        if c1 < cols { c1 -= 1 }
        if r0 > 0 { r0 += 1 }
        if r1 < rows { r1 -= 1 }
        guard c1 - c0 > 4, r1 - r0 > 4 else { return nil }
        let content = BoundingBox(x: Double(c0) / Double(cols), y: Double(r0) / Double(rows),
                                  width: Double(c1 - c0) / Double(cols), height: Double(r1 - r0) / Double(rows))
        return PageScan(content: content, cols: cols, rows: rows, ink: ink, c0: c0, c1: c1, r0: r0, r1: r1)
    }

    /// İçerik alanı dışında kalan yazıları (not uygulamasının araç çubuğu, sayfa dışı menüler) eler.
    /// Satırların çoğu dışarıda kalıyorsa alan yanlış bulunmuştur; o zaman hiçbir şey atılmaz.
    public static func keepingContentLines(_ lines: [ExtractedBlock], scan: PageScan?) -> [ExtractedBlock] {
        guard let content = scan?.content else { return lines }
        let area = content.insetBy(dx: -0.01, dy: -0.01)
        let kept = lines.filter { line in
            guard let b = line.bbox else { return true }
            return area.contains(x: b.x + b.width / 2, y: b.y + b.height / 2)
        }
        return Double(kept.count) >= Double(lines.count) * 0.7 ? kept : lines
    }

    public static func suggestions(rgba: [UInt8], width: Int, height: Int, lines: [Line]) -> [FigureSuggestion] {
        guard let pageScan = scan(rgba: rgba, width: width, height: height) else { return [] }
        return suggestions(scan: pageScan, lines: lines)
    }

    /// - Parameter lines: OCR satırları; sol üst orijinli, normalleştirilmiş kutular.
    public static func suggestions(scan: PageScan, lines: [Line]) -> [FigureSuggestion] {
        let cols = scan.cols, rows = scan.rows, ink = scan.ink, content = scan.content
        let c0 = scan.c0, c1 = scan.c1, r0 = scan.r0, r1 = scan.r1
        var mask = [Bool](repeating: false, count: cols * rows)
        for r in r0..<r1 { for c in c0..<c1 { mask[r * cols + c] = ink[r * cols + c] } }

        // Yazı satırlarını sil (yükseklik kadar payla; fosforlu kalem kenarları da gider).
        for line in lines {
            let pad = line.bbox.height * 0.3
            let x0 = Int(((line.bbox.x - pad) * Double(cols)).rounded(.down))
            let x1 = Int(((line.bbox.maxX + pad) * Double(cols)).rounded(.up))
            let y0 = Int(((line.bbox.y - pad) * Double(rows)).rounded(.down))
            let y1 = Int(((line.bbox.maxY + pad) * Double(rows)).rounded(.up))
            for r in max(0, y0)..<min(rows, max(y1, 0)) {
                for c in max(0, x0)..<min(cols, max(x1, 0)) { mask[r * cols + c] = false }
            }
        }

        // Çizgileri birleştirmek için bir hücre genişlet, sonra bağlı bölgeleri bul.
        var grown = mask
        for r in 0..<rows {
            for c in 0..<cols where mask[r * cols + c] {
                for dr in -1...1 {
                    for dc in -1...1 {
                        let rr = r + dr, cc = c + dc
                        if rr >= 0, rr < rows, cc >= 0, cc < cols { grown[rr * cols + cc] = true }
                    }
                }
            }
        }
        var boxes = components(grown, original: mask, cols: cols, rows: rows)

        // Boyut süzgeci: içerik alanına göre.
        let minW = 0.08 * content.width, minH = 0.08 * content.height
        boxes = boxes.filter { b in
            b.width >= minW && b.height >= minH && b.area >= 0.02 * content.area && b.area <= 0.85 * content.area
        }
        boxes = mergeNearby(boxes, gap: 0.02)

        // Etiketler: şeklin üstündeki ya da hemen yanındaki kısa, normal boy yazılar. Başlıklar (iri yazı) ve
        // uzun paragraf satırları katılmaz.
        let heights = lines.map(\.bbox.height).sorted()
        let typical = heights.isEmpty ? 0 : heights[heights.count / 2]
        let marginX = 0.03 * content.width, marginY = 0.03 * content.height
        var result: [FigureSuggestion] = []
        for var box in boxes {
            let core = box
            var labels: [Int] = []
            for _ in 0..<3 {
                let reach = box.insetBy(dx: -marginX, dy: -marginY)
                var grewBox = false
                for (i, line) in lines.enumerated() where !labels.contains(i) {
                    guard line.bbox.height <= typical * 1.5, line.bbox.width <= box.width * 0.6,
                          line.bbox.intersection(reach) != nil else { continue }
                    // Yalnız rakamdan oluşan yazı (sayfa numarası) şeklin dışındaysa etiket sayılmaz.
                    let digitsOnly = line.text.allSatisfy { $0.isNumber || $0.isWhitespace }
                    if digitsOnly, line.bbox.intersection(core) == nil { continue }
                    labels.append(i)
                    box = box.union(line.bbox)
                    grewBox = true
                }
                if !grewBox { break }
            }
            // Bölgenin çoğu yazıysa bu bir şekil değil, vurgulu/çerçeveli metindir.
            let textArea = lines.reduce(0.0) { $0 + ($1.bbox.intersection(box)?.area ?? 0) }
            guard textArea / max(box.area, 1e-9) <= 0.45 else { continue }
            let padded = box.insetBy(dx: -0.01 * content.width, dy: -0.01 * content.height).clamped(to: content)
            let figureLabels = labels.sorted().map { FigureLabel(text: lines[$0].text, bbox: lines[$0].bbox) }
            result.append(FigureSuggestion(bbox: padded, labels: figureLabels))
        }
        result = Array(result.sorted { $0.bbox.area > $1.bbox.area }.prefix(maxSuggestions))
        return result.sorted { ($0.bbox.y, $0.bbox.x) < ($1.bbox.y, $1.bbox.x) }
    }

    /// Oranı `minFraction` üstündeki ilk ve son indeks (son hariç).
    private static func span(count: Int, minFraction: Double, fraction: (Int) -> Int, total: Int) -> (Int, Int)? {
        guard total > 0 else { return nil }
        let ok = (0..<count).filter { Double(fraction($0)) / Double(total) >= minFraction }
        guard let first = ok.first, let last = ok.last else { return nil }
        return (first, last + 1)
    }

    /// 8 komşulu bağlı bölgeler. Kutu, genişletilmemiş mürekkep hücrelerinden hesaplanır.
    private static func components(_ grid: [Bool], original: [Bool], cols: Int, rows: Int) -> [BoundingBox] {
        var seen = [Bool](repeating: false, count: grid.count)
        var boxes: [BoundingBox] = []
        for start in grid.indices where grid[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var minC = Int.max, minR = Int.max, maxC = -1, maxR = -1
            while let i = stack.popLast() {
                let r = i / cols, c = i % cols
                if original[i] {
                    minC = min(minC, c); maxC = max(maxC, c); minR = min(minR, r); maxR = max(maxR, r)
                }
                for dr in -1...1 {
                    for dc in -1...1 {
                        let rr = r + dr, cc = c + dc
                        guard rr >= 0, rr < rows, cc >= 0, cc < cols else { continue }
                        let j = rr * cols + cc
                        if grid[j], !seen[j] {
                            seen[j] = true
                            stack.append(j)
                        }
                    }
                }
            }
            guard maxC >= 0 else { continue }
            boxes.append(BoundingBox(x: Double(minC) / Double(cols), y: Double(minR) / Double(rows),
                                     width: Double(maxC - minC + 1) / Double(cols),
                                     height: Double(maxR - minR + 1) / Double(rows)))
        }
        return boxes
    }

    private static func mergeNearby(_ boxes: [BoundingBox], gap: Double) -> [BoundingBox] {
        var items = boxes
        var merged = true
        while merged {
            merged = false
            outer: for i in items.indices {
                for j in items.indices where j > i {
                    if items[i].insetBy(dx: -gap, dy: -gap).intersection(items[j]) != nil {
                        items[i] = items[i].union(items[j])
                        items.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        return items
    }
}
