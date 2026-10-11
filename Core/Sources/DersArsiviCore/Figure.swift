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
    static let maxOutsideLabelLength = 30
    /// Hücre içi renk sapması bunun altındaysa hücre düz renklidir.
    static let flatDeviation = 10.0
    /// Düz renkli hücrelerin bu oranını kaplayan renk ikinci zemin sayılır (panel, tablo satırı, düğme).
    static let secondaryBackgroundShare = 0.08

    public typealias Line = (text: String, bbox: BoundingBox)

    /// Sayfanın hücre ızgarası ve içerik alanı. Hem şekil önerisi hem de kenar/araç çubuğu yazılarını
    /// ayıklamak için kullanılır.
    public struct PageScan: Sendable {
        /// Ekran görüntüsündeki uygulama kenarlıkları ve araç çubukları hariç sayfa alanı (normalleştirilmiş).
        public let content: BoundingBox
        let cols: Int, rows: Int
        let ink: [Bool]
        /// Hücredeki mürekkep pikseli sayısı ve hücre başına piksel sayısı.
        let inkPixels: [Int]
        let pixelsPerCell: Int
        /// Doygun mürekkep piksellerinin renk tonu dağılımı (hücre başına `hueBins` kutu).
        let hues: [UInt16]
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
        var isFlat = [Bool](repeating: false, count: cols * rows)
        var means = [(Double, Double, Double)](repeating: (0, 0, 0), count: cols * rows)
        // Düz renkli hücrelerin kaba renk kutusu; düz değilse -1.
        var flatBin = [Int](repeating: -1, count: cols * rows)
        let perCell = Double(cell * cell)
        var inkPixels = [Int](repeating: 0, count: cols * rows)
        var hues = [UInt16](repeating: 0, count: cols * rows * hueBins)
        for r in 0..<rows {
            for c in 0..<cols {
                var inkCount = 0, bgCount = 0
                var sum = (0.0, 0.0, 0.0), sq = (0.0, 0.0, 0.0)
                for y in (r * cell)..<(r * cell + cell) {
                    var i = (y * width + c * cell) * 4
                    for _ in 0..<cell {
                        let pr = Double(rgba[i]), pg = Double(rgba[i + 1]), pb = Double(rgba[i + 2])
                        let dr = pr - background.r, dg = pg - background.g, db = pb - background.b
                        let d = dr * dr + dg * dg + db * db
                        if d > inkSq {
                            inkCount += 1
                            if let bin = saturatedHueBin(pr, pg, pb) {
                                hues[(r * cols + c) * hueBins + bin] &+= 1
                            }
                        } else if d < bgSq {
                            bgCount += 1
                        }
                        sum = (sum.0 + pr, sum.1 + pg, sum.2 + pb)
                        sq = (sq.0 + pr * pr, sq.1 + pg * pg, sq.2 + pb * pb)
                        i += 4
                    }
                }
                let index = r * cols + c
                inkPixels[index] = inkCount
                ink[index] = Double(inkCount) / perCell >= 0.1
                isBackground[index] = Double(bgCount) / perCell >= 0.5
                let mean = (sum.0 / perCell, sum.1 / perCell, sum.2 / perCell)
                means[index] = mean
                let variance = (sq.0 / perCell - mean.0 * mean.0) + (sq.1 / perCell - mean.1 * mean.1)
                    + (sq.2 / perCell - mean.2 * mean.2)
                if cell > 1, (max(variance, 0) / 3).squareRoot() < flatDeviation {
                    isFlat[index] = true
                    flatBin[index] = ((Int(mean.0) >> 5) << 6) | ((Int(mean.1) >> 5) << 3) | (Int(mean.2) >> 5)
                }
            }
        }
        // Geniş düz renkli alanlar (beyaz metin paneli, tablo satırları, uygulama düğmeleri) şekil değildir:
        // sık görülen düz renkler ikinci zemin sayılır. Fotoğraf ve çizimler dokulu olduğundan etkilenmez.
        var binCounts: [Int: Int] = [:]
        for b in flatBin where b >= 0 { binCounts[b, default: 0] += 1 }
        let frequent = Set(binCounts.filter { Double($0.value) >= secondaryBackgroundShare * Double(cols * rows) }.keys)
        var isSecondary = [Bool](repeating: false, count: cols * rows)
        for i in ink.indices where flatBin[i] >= 0 && frequent.contains(flatBin[i]) {
            isSecondary[i] = true
            ink[i] = false
        }
        ink = removingPanelEdges(ink: ink, isBackground: isBackground, isSecondary: isSecondary,
                                 flatBin: flatBin, means: means, background: background, cols: cols, rows: rows)

        // İçerik alanı: zemin rengini yeterince içeren sütun ve satırlar. Koyu kenarlıklar ve araç çubukları elenir.
        // Koyu zeminli slayttaki fotoğraf (histoloji) sütunlarında sayfa zemini az görünür; bu sütunlar
        // koyu çerçeve değilse, dokulu içerik taşıyorsa ve biraz da sayfa rengi içeriyorsa içerik sayılır.
        func isDarkFrame(_ i: Int) -> Bool {
            guard isFlat[i] else { return false }
            let m = means[i]
            let hi = max(m.0, m.1, m.2), lo = min(m.0, m.1, m.2)
            return hi < 90 && hi - lo < 30
        }
        let rowCount = Double(rows)
        let contentColumn: [Bool] = (0..<cols).map { c in
            var main = 0, frame = 0, textured = 0, page = 0
            for r in 0..<rows {
                let i = r * cols + c
                let dark = isDarkFrame(i)
                if isBackground[i] { main += 1 }
                if dark { frame += 1 }
                if ink[i], !isFlat[i] { textured += 1 }
                if (isBackground[i] || isSecondary[i]) && !dark { page += 1 }
            }
            if Double(main) / rowCount >= 0.15 { return true }
            return Double(frame) / rowCount < 0.5 && Double(textured) / rowCount >= 0.4 && Double(page) / rowCount >= 0.05
        }
        guard let colSpan = span(count: cols, minFraction: 0.5, fraction: { contentColumn[$0] ? 1 : 0 },
                                 total: 1) else { return nil }
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
        return PageScan(content: content, cols: cols, rows: rows, ink: ink, inkPixels: inkPixels,
                        pixelsPerCell: cell * cell, hues: hues, c0: c0, c1: c1, r0: r0, r1: r1)
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
        let cols = scan.cols, rows = scan.rows, content = scan.content
        let c0 = scan.c0, c1 = scan.c1, r0 = scan.r0, r1 = scan.r1
        let (mask, grown) = inkMask(scan: scan, lines: lines)

        // İçerik kenarına yapışık dar parça: ekranın kenarından taşan komşu slaytın veya kenarlığın kesiti.
        func isEdgeSliver(_ b: BoundingBox) -> Bool {
            let x0 = Int((b.x * Double(cols)).rounded()), x1 = Int((b.maxX * Double(cols)).rounded())
            let y0 = Int((b.y * Double(rows)).rounded()), y1 = Int((b.maxY * Double(rows)).rounded())
            if x0 <= c0 + 1 || x1 >= c1 - 1, Double(x1 - x0) < 0.15 * Double(c1 - c0) { return true }
            if y0 <= r0 + 1 || y1 >= r1 - 1, Double(y1 - y0) < 0.15 * Double(r1 - r0) { return true }
            return false
        }
        // Boyut süzgeci: içerik alanına göre.
        let minW = 0.08 * content.width, minH = 0.08 * content.height
        func hasFigureSize(_ b: BoundingBox) -> Bool {
            b.width >= minW && b.height >= minH && b.area >= 0.02 * content.area && b.area <= 0.85 * content.area
        }

        var boxes: [BoundingBox] = []
        for region in regions(grown, original: mask, cols: cols, rows: rows) where !isEdgeSliver(region.box) {
            // Büyük bölge çoğu zaman şekle ince çizgilerle (el yazısı, ok, yıldız) yapışmış başka şeylerdir.
            // Genişletmeden yeniden bölünür; ana parça(lar) belirgin biçimde küçükse onlar kullanılır.
            if hasFigureSize(region.box), region.box.area > 0.3 * content.area {
                var own = [Bool](repeating: false, count: cols * rows)
                for i in region.cells { own[i] = true }
                let parts = regions(own, original: own, cols: cols, rows: rows).map(\.box)
                    .filter { !isEdgeSliver($0) && hasFigureSize($0) }
                if let first = parts.first {
                    let covered = parts.dropFirst().reduce(first) { $0.union($1) }
                    if parts.count >= 2 || covered.area < 0.7 * region.box.area {
                        boxes += parts
                        continue
                    }
                }
            }
            boxes.append(region.box)
        }
        boxes = boxes.filter(hasFigureSize)
        // Sayfa genişliğinde ince şerit: başlık bandı, menü, düğme, tablo başlığı.
        boxes = boxes.filter { !($0.width >= 0.95 * content.width && $0.height <= 0.15 * content.height) }
        boxes = mergeNearby(boxes, gap: 0.008)

        var result: [FigureSuggestion] = []
        for box in boxes {
            if let suggestion = finished(box, scan: scan, lines: lines) { result.append(suggestion) }
        }
        result = Array(result.sorted { $0.bbox.area > $1.bbox.area }.prefix(maxSuggestions))
        return result.sorted { ($0.bbox.y, $0.bbox.x) < ($1.bbox.y, $1.bbox.x) }
    }

    /// Kullanıcının dokunduğu yerdeki şekil (dokun-kırp). Dokunulan yerin yakınında yazı dışı çizim yoksa nil.
    /// - Parameter point: Normalleştirilmiş, sol üst orijinli nokta.
    public static func region(at point: (x: Double, y: Double), scan: PageScan, lines: [Line]) -> FigureSuggestion? {
        let cols = scan.cols, rows = scan.rows
        let (mask, grown) = inkMask(scan: scan, lines: lines)
        let tc = min(cols - 1, max(0, Int(point.x * Double(cols))))
        let tr = min(rows - 1, max(0, Int(point.y * Double(rows))))
        // Dokunulan hücreye en yakın mürekkep hücresi (parmak tam çizgiye denk gelmeyebilir).
        var nearest: Int?
        var best = Int.max
        let reach = max(4, cols / 25)
        for r in max(0, tr - reach)...min(rows - 1, tr + reach) {
            for c in max(0, tc - reach)...min(cols - 1, tc + reach) where mask[r * cols + c] {
                let d = (r - tr) * (r - tr) + (c - tc) * (c - tc)
                if d < best { best = d; nearest = r * cols + c }
            }
        }
        guard let nearest,
              let region = regions(grown, original: mask, cols: cols, rows: rows)
                .first(where: { $0.cells.contains(nearest) }) else { return nil }
        var box = region.box
        // Şekle ince çizgilerle yapışmış şeyler varsa genişletmeden bölünür; dokunulan parça alınır.
        if box.area > 0.3 * scan.content.area {
            var own = [Bool](repeating: false, count: cols * rows)
            for i in region.cells { own[i] = true }
            if let part = regions(own, original: own, cols: cols, rows: rows)
                .first(where: { $0.cells.contains(nearest) }), part.box.area >= 0.02 * scan.content.area {
                box = part.box
            }
        }
        return finished(box, scan: scan, lines: lines, filtered: false)
    }

    /// Yazı satırları silinmiş mürekkep maskesi ve çizgileri birleştirmek için bir hücre genişletilmiş hali.
    private static func inkMask(scan: PageScan, lines: [Line]) -> (mask: [Bool], grown: [Bool]) {
        let cols = scan.cols, rows = scan.rows, ink = scan.ink
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
        return (mask, grown)
    }

    /// Kutuya yakındaki etiketleri ekler, kenar payı verir. `filtered` açıkken yazı ağırlıklı bölgeler ve
    /// kalem notları elenir (otomatik öneri); kullanıcı kendisi seçtiyse elenmez.
    private static func finished(_ found: BoundingBox, scan: PageScan, lines: [Line],
                                 filtered: Bool = true) -> FigureSuggestion? {
        let content = scan.content
        var box = found
        // Etiketler: şeklin üstündeki ya da hemen yanındaki kısa, normal boy yazılar. Başlıklar (iri yazı) ve
        // uzun paragraf satırları katılmaz. Etiket yalnız şeklin kendisine (zincirleme değil) yakın olmalı;
        // yoksa yanındaki paragraf da satır satır şekle katılır.
        let heights = lines.map(\.bbox.height).sorted()
        let typical = heights.isEmpty ? 0 : heights[heights.count / 2]
        let reach = found.insetBy(dx: -0.03 * content.width, dy: -0.03 * content.height)
        var labels: [Int] = []
        for (i, line) in lines.enumerated() {
            guard line.bbox.height <= typical * 1.5, line.bbox.width <= found.width * 0.6,
                  line.bbox.intersection(reach) != nil else { continue }
            let inside = line.bbox.fractionInside(found) >= 0.8
            // Şeklin dışındaki uzun satır paragraftır, etiket değil.
            if !inside, line.text.count > maxOutsideLabelLength { continue }
            // Yalnız rakamdan oluşan yazı (sayfa numarası) şeklin dışındaysa etiket sayılmaz.
            let digitsOnly = line.text.allSatisfy { $0.isNumber || $0.isWhitespace }
            if digitsOnly, line.bbox.intersection(found) == nil { continue }
            labels.append(i)
            box = box.union(line.bbox)
        }
        if filtered {
            // Bölgenin çoğu yazıysa bu bir şekil değil, vurgulu/çerçeveli metindir. Oran etiketler eklenmeden
            // önceki çizim kutusunda ölçülür: kutucuklu, bol yazılı şemaya yanındaki notlar eklenince oran
            // yapay olarak yükselip şema eleniyordu.
            let textArea = lines.reduce(0.0) { $0 + ($1.bbox.intersection(found)?.area ?? 0) }
            guard textArea / max(found.area, 1e-9) <= 0.45 else { return nil }
            // Slayta kalemle eklenmiş renkli not şekil değildir.
            guard !looksLikePenNote(box, scan: scan) else { return nil }
        }
        let padded = box.insetBy(dx: -0.01 * content.width, dy: -0.01 * content.height).clamped(to: content)
        let figureLabels = labels.map { FigureLabel(text: lines[$0].text, bbox: lines[$0].bbox) }
        return FigureSuggestion(bbox: padded, labels: figureLabels)
    }

    /// İki farklı zemin renginin sınırındaki hücreler (beyaz panelin lacivert zemindeki kenarı gibi) karışık
    /// renklidir ve mürekkep sanılır; panelin çerçevesi şekil diye önerilmesin diye silinir. Aynı zemin
    /// üstündeki çizgi (grafik eğrisi) iki yanında aynı renk olduğundan korunur.
    private static func removingPanelEdges(ink: [Bool], isBackground: [Bool], isSecondary: [Bool], flatBin: [Int],
                                           means: [(Double, Double, Double)], background: ColorAnalysis.RGB,
                                           cols: Int, rows: Int) -> [Bool] {
        // Her zemin hücresine renk etiketi: 0 ana zemin, diğerleri ikinci zeminin renk kutusu.
        var label = [Int](repeating: -1, count: cols * rows)
        for i in label.indices where !ink[i] {
            if isBackground[i] {
                label[i] = 0
            } else if isSecondary[i] {
                let m = means[i]
                let nearMain = abs(m.0 - background.r) < 20 && abs(m.1 - background.g) < 20 && abs(m.2 - background.b) < 20
                label[i] = nearMain ? 0 : flatBin[i] + 1
            }
        }
        func firstLabel(_ r: Int, _ c: Int, _ dr: Int, _ dc: Int) -> Int {
            for k in 1...2 {
                let rr = r + dr * k, cc = c + dc * k
                guard rr >= 0, rr < rows, cc >= 0, cc < cols else { return -1 }
                if !ink[rr * cols + cc] { return label[rr * cols + cc] }
            }
            return -1
        }
        var result = ink
        for r in 0..<rows {
            for c in 0..<cols where ink[r * cols + c] {
                for (dr, dc) in [(0, 1), (1, 0)] {
                    let a = firstLabel(r, c, -dr, -dc), b = firstLabel(r, c, dr, dc)
                    if a >= 0, b >= 0, a != b {
                        result[r * cols + c] = false
                        break
                    }
                }
            }
        }
        return result
    }

    /// Oranı `minFraction` üstündeki ilk ve son indeks (son hariç).
    private static func span(count: Int, minFraction: Double, fraction: (Int) -> Int, total: Int) -> (Int, Int)? {
        guard total > 0 else { return nil }
        let ok = (0..<count).filter { Double(fraction($0)) / Double(total) >= minFraction }
        guard let first = ok.first, let last = ok.last else { return nil }
        return (first, last + 1)
    }

    /// 8 komşulu bağlı bölgeler. Kutu ve hücre listesi genişletilmemiş mürekkep hücrelerinden hesaplanır.
    private static func regions(_ grid: [Bool], original: [Bool], cols: Int,
                                rows: Int) -> [(box: BoundingBox, cells: [Int])] {
        var seen = [Bool](repeating: false, count: grid.count)
        var result: [(box: BoundingBox, cells: [Int])] = []
        for start in grid.indices where grid[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var cells: [Int] = []
            var minC = Int.max, minR = Int.max, maxC = -1, maxR = -1
            while let i = stack.popLast() {
                let r = i / cols, c = i % cols
                if original[i] {
                    cells.append(i)
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
            let box = BoundingBox(x: Double(minC) / Double(cols), y: Double(minR) / Double(rows),
                                  width: Double(maxC - minC + 1) / Double(cols),
                                  height: Double(maxR - minR + 1) / Double(rows))
            result.append((box, cells))
        }
        return result
    }

    /// Kalemle eklenmiş not mu: mürekkep seyrek (ince çizgi) ve neredeyse tamamı tek bir doygun renkte.
    /// Çizim ve fotoğraflar ya daha yoğun ya da çok renklidir.
    static func looksLikePenNote(_ box: BoundingBox, scan: PageScan) -> Bool {
        let cols = scan.cols, rows = scan.rows
        let x0 = max(0, Int((box.x * Double(cols)).rounded(.down)))
        let x1 = min(cols, Int((box.maxX * Double(cols)).rounded(.up)))
        let y0 = max(0, Int((box.y * Double(rows)).rounded(.down)))
        let y1 = min(rows, Int((box.maxY * Double(rows)).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return false }
        var inkTotal = 0
        var histogram = [Int](repeating: 0, count: hueBins)
        for r in y0..<y1 {
            for c in x0..<x1 {
                let i = r * cols + c
                inkTotal += scan.inkPixels[i]
                for b in 0..<hueBins { histogram[b] += Int(scan.hues[i * hueBins + b]) }
            }
        }
        guard inkTotal > 0 else { return false }
        let coverage = Double(inkTotal) / Double((x1 - x0) * (y1 - y0) * scan.pixelsPerCell)
        var dominant = 0
        for b in 0..<hueBins {
            let previous: Int = histogram[(b + hueBins - 1) % hueBins]
            let next: Int = histogram[(b + 1) % hueBins]
            dominant = max(dominant, previous + histogram[b] + next)
        }
        return coverage < 0.3 && Double(dominant) / Double(inkTotal) >= 0.5
    }

    static let hueBins = 24

    /// Doygun pikselin ton kutusu; gri, siyah ve soluk pikseller için nil.
    static func saturatedHueBin(_ r: Double, _ g: Double, _ b: Double) -> Int? {
        let hi = max(r, g, b), lo = min(r, g, b)
        guard hi > 0, (hi - lo) / hi > 0.35 else { return nil }
        let delta = hi - lo
        var hue: Double
        if hi == r {
            hue = (g - b) / delta
        } else if hi == g {
            hue = 2 + (b - r) / delta
        } else {
            hue = 4 + (r - g) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return min(hueBins - 1, Int(hue * Double(hueBins)))
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
