import Foundation

/// Okunan satırların piksel incelemesi: el yazısı satırlar, el notu bölgeleri, yanına işaret konmuş satırlar ve
/// metne dökülemeyecek kadar karışık sayfa kararı. Girdi, sayfanın yönü düzeltilmiş küçük kopyasıdır (RGBA,
/// en uzun kenar ~480 px); kutular sol üst orijinli, normalleştirilmiş.
///
/// Eşikler üç ölçüm paketindeki (54 ekran görüntüsü ve fotoğraf) gerçek satırlarla ayarlandı.
public enum PageAnalysis {
    public struct Line: Equatable, Sendable {
        public var text: String
        public var bbox: BoundingBox
        /// OCR motorunun güveni; bilinmiyorsa nil.
        public var confidence: Double?

        public init(text: String, bbox: BoundingBox, confidence: Double? = nil) {
            self.text = text
            self.bbox = bbox
            self.confidence = confidence
        }
    }

    public struct Result: Equatable, Sendable {
        /// El yazısı sayılan satırların indeksleri.
        public var handwriting: Set<Int>
        /// Yanında işaret olan satırların indeksleri.
        public var marked: Set<Int>
        /// El notu bölgeleri; görüntü olarak saklanmak üzere.
        public var notes: [FigureSuggestion]
        /// Yazı alanının el yazısı payı.
        public var handwritingShare: Double
        /// Sayfa metin olarak güvenilir değil; görüntüyle aktarılmalı.
        public var looksComplex: Bool
    }

    /// Satır kutusundaki mürekkebin yoğunluğu ve doygun (renkli) payı.
    public struct Ink: Equatable, Sendable {
        public var coverage: Double
        public var saturated: Double
    }

    public static func analyze(rgba: [UInt8], width: Int, height: Int, lines: [Line],
                               figures: [BoundingBox] = [], content: BoundingBox? = nil) -> Result {
        let empty = Result(handwriting: [], marked: [], notes: [], handwritingShare: 0, looksComplex: false)
        guard width > 8, height > 8, rgba.count >= width * height * 4, !lines.isEmpty,
              let background = ColorAnalysis.backgroundAndInk(rgba: rgba)?.background else { return empty }
        let image = Image(rgba: rgba, width: width, height: height, background: background)

        var handwriting = Set<Int>()
        for (i, line) in lines.enumerated() {
            let ink = image.ink(in: line.bbox)
            if isHandwriting(ink, confidence: line.confidence) { handwriting.insert(i) }
        }
        let marked = markedLines(image, lines: lines, exclude: figures)

        let totalArea = lines.reduce(0.0) { $0 + $1.bbox.area }
        let handArea = handwriting.reduce(0.0) { $0 + lines[$1].bbox.area }
        let share = totalArea > 0 ? handArea / totalArea : 0
        let confidences = lines.compactMap(\.confidence)
        let meanConfidence = confidences.isEmpty ? 1 : confidences.reduce(0, +) / Double(confidences.count)
        let complex = (share >= 0.4 && handwriting.count >= 3) || (lines.count >= 8 && meanConfidence < 0.45)

        let notes = noteRegions(lines: lines, handwriting: handwriting, figures: figures, content: content)
        return Result(handwriting: handwriting, marked: marked, notes: notes, handwritingShare: share,
                      looksComplex: complex)
    }

    /// İnce kalem çizgisi seyrek mürekkep bırakır ve çoğu renklidir. Basılı renkli yazı daha yoğundur ve OCR
    /// motoru ona tam güvenir.
    public static func isHandwriting(_ ink: Ink, confidence: Double?) -> Bool {
        if ink.coverage < 0.15, ink.saturated >= 0.7 { return true }
        return ink.coverage < 0.25 && ink.saturated >= 0.5 && (confidence ?? 0) < 0.9
    }

    // MARK: El notu bölgeleri

    /// Birbirine yakın el yazısı satırları tek bölgede toplanır; bölge, satırların hepsini içeren kutudur.
    static func noteRegions(lines: [Line], handwriting: Set<Int>, figures: [BoundingBox],
                            content: BoundingBox?) -> [FigureSuggestion] {
        var groups: [[Int]] = []
        for i in handwriting.sorted(by: { lines[$0].bbox.y < lines[$1].bbox.y }) {
            let b = lines[i].bbox
            if let g = groups.firstIndex(where: { group in
                group.contains { j in near(lines[j].bbox, b) }
            }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        // Zincirleme yakınlıkla iki grup sonradan birleşebilir.
        var merged = true
        while merged {
            merged = false
            outer: for a in groups.indices {
                for b in groups.indices where b > a {
                    if groups[a].contains(where: { i in groups[b].contains { near(lines[i].bbox, lines[$0].bbox) } }) {
                        groups[a] += groups[b]
                        groups.remove(at: b)
                        merged = true
                        break outer
                    }
                }
            }
        }
        let area = content ?? BoundingBox(x: 0, y: 0, width: 1, height: 1)
        var notes: [FigureSuggestion] = []
        for group in groups {
            let boxes = group.map { lines[$0].bbox }
            var box = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
            let pad = (boxes.map(\.height).max() ?? 0) * 0.3
            box = box.insetBy(dx: -pad, dy: -pad).clamped(to: area)
            // Şeklin içindeki not şekille birlikte zaten saklanır.
            if figures.contains(where: { box.fractionInside($0) >= 0.6 }) { continue }
            let labels = group.sorted { (lines[$0].bbox.y, lines[$0].bbox.x) < (lines[$1].bbox.y, lines[$1].bbox.x) }
                .map { FigureLabel(text: lines[$0].text, bbox: lines[$0].bbox) }
            notes.append(FigureSuggestion(bbox: box, labels: labels, kind: .handwriting))
        }
        return notes.sorted { ($0.bbox.y, $0.bbox.x) < ($1.bbox.y, $1.bbox.x) }
    }

    private static func near(_ a: BoundingBox, _ b: BoundingBox) -> Bool {
        let h = max(a.height, b.height)
        let verticalGap = max(0, max(a.y, b.y) - min(a.maxY, b.maxY))
        let horizontalGap = max(0, max(a.x, b.x) - min(a.maxX, b.maxX))
        return verticalGap <= 1.5 * h && horizontalGap <= 2 * h
    }

    // MARK: İşaretler

    /// Satırın hemen solunda veya sağında, yazıya değmeyen, satır boyunda renkli bir şekil (yıldız, ünlem,
    /// çarpı, yaprak çıkartması) varsa satır işaretlidir. Şekillerin içi ve ekran kenarındaki araç çubuğu
    /// sayılmaz.
    static func markedLines(_ image: Image, lines: [Line], exclude: [BoundingBox]) -> Set<Int> {
        let w = image.width, h = image.height
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where image.isColoredInk(x, y) { mask[y * w + x] = true }
        }
        func clear(_ box: BoundingBox, pad: Double) {
            let x0 = max(0, Int((box.x * Double(w) - pad).rounded(.down)))
            let x1 = min(w, Int((box.maxX * Double(w) + pad).rounded(.up)) + 1)
            let y0 = max(0, Int((box.y * Double(h) - pad).rounded(.down)))
            let y1 = min(h, Int((box.maxY * Double(h) + pad).rounded(.up)) + 1)
            guard x1 > x0, y1 > y0 else { return }
            for y in y0..<y1 { for x in x0..<x1 { mask[y * w + x] = false } }
        }
        let rects = lines.map { line -> (x0: Double, y0: Double, x1: Double, y1: Double) in
            (line.bbox.x * Double(w), line.bbox.y * Double(h), line.bbox.maxX * Double(w), line.bbox.maxY * Double(h))
        }
        for r in rects { clear(BoundingBox(x: r.x0 / Double(w), y: r.y0 / Double(h),
                                           width: (r.x1 - r.x0) / Double(w), height: (r.y1 - r.y0) / Double(h)),
                               pad: 0.1 * (r.y1 - r.y0)) }
        for box in exclude { clear(box, pad: 0) }

        let heights = rects.map { $0.y1 - $0.y0 }.sorted()
        let typical = heights.isEmpty ? 10 : heights[heights.count / 2]
        var result = Set<Int>()
        for c in components(mask, width: w, height: h) {
            let side = Double(max(c.x1 - c.x0, c.y1 - c.y0))
            guard side >= 0.3 * typical, c.count >= 6 else { continue }
            let cx = Double(c.x0 + c.x1) / 2, cy = Double(c.y0 + c.y1) / 2
            guard cx >= 0.035 * Double(w), cx <= 0.965 * Double(w) else { continue }
            var best: (gap: Double, index: Int)?
            for (i, r) in rects.enumerated() {
                let lh = min(r.y1 - r.y0, typical * 1.5)
                guard lh > 0, side >= 0.5 * lh, side <= 3 * lh else { continue }
                guard cy >= r.y0 - 0.6 * lh, cy <= r.y1 + 0.6 * lh else { continue }
                let gap: Double
                if Double(c.x1) <= r.x0 + 0.2 * lh {
                    gap = r.x0 - Double(c.x1)
                } else if Double(c.x0) >= r.x1 - 0.2 * lh {
                    gap = Double(c.x0) - r.x1
                } else {
                    continue
                }
                guard gap >= 0.3 * lh, gap <= 4 * lh else { continue }
                if best == nil || gap < best!.gap { best = (gap, i) }
            }
            if let best { result.insert(best.index) }
        }
        return result
    }

    struct Component {
        var x0: Int, y0: Int, x1: Int, y1: Int, count: Int
    }

    /// 8 komşulu bağlı bileşenler; x1/y1 dahil değil.
    static func components(_ mask: [Bool], width w: Int, height h: Int) -> [Component] {
        var seen = [Bool](repeating: false, count: w * h)
        var out: [Component] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where mask[start] && !seen[start] {
            seen[start] = true
            stack.append(start)
            var c = Component(x0: w, y0: h, x1: 0, y1: 0, count: 0)
            while let p = stack.popLast() {
                let x = p % w, y = p / w
                c.x0 = min(c.x0, x); c.x1 = max(c.x1, x + 1)
                c.y0 = min(c.y0, y); c.y1 = max(c.y1, y + 1)
                c.count += 1
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                        let q = ny * w + nx
                        if mask[q], !seen[q] {
                            seen[q] = true
                            stack.append(q)
                        }
                    }
                }
            }
            out.append(c)
        }
        return out
    }

    // MARK: Piksel erişimi

    struct Image {
        let rgba: [UInt8]
        let width: Int
        let height: Int
        let background: ColorAnalysis.RGB

        /// Zeminden belirgin farklı piksel.
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            let dr = Double(rgba[i]) - background.r, dg = Double(rgba[i + 1]) - background.g
            let db = Double(rgba[i + 2]) - background.b
            return dr * dr + dg * dg + db * db > 80 * 80
        }

        func isSaturated(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            let r = Double(rgba[i]), g = Double(rgba[i + 1]), b = Double(rgba[i + 2])
            let hi = max(r, g, b), lo = min(r, g, b)
            return hi > 60 && (hi - lo) / hi > 0.35
        }

        func isColoredInk(_ x: Int, _ y: Int) -> Bool { isInk(x, y) && isSaturated(x, y) }

        func ink(in box: BoundingBox) -> Ink {
            let x0 = max(0, Int(box.x * Double(width))), x1 = min(width, Int(box.maxX * Double(width)) + 1)
            let y0 = max(0, Int(box.y * Double(height))), y1 = min(height, Int(box.maxY * Double(height)) + 1)
            guard x1 > x0, y1 > y0 else { return Ink(coverage: 0, saturated: 0) }
            var inkCount = 0, colored = 0
            for y in y0..<y1 {
                for x in x0..<x1 where isInk(x, y) {
                    inkCount += 1
                    if isSaturated(x, y) { colored += 1 }
                }
            }
            let total = (x1 - x0) * (y1 - y0)
            guard inkCount >= 5 else { return Ink(coverage: Double(inkCount) / Double(total), saturated: 0) }
            return Ink(coverage: Double(inkCount) / Double(total), saturated: Double(colored) / Double(inkCount))
        }
    }
}
