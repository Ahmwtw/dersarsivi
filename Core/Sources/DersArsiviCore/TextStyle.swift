import Foundation

/// Vurgu ve yazı renkleri için kaba renk adları. Kesin renk değil; okuyan insana/AI'a anlam taşır.
public enum NamedColor: String, Codable, Sendable, CaseIterable {
    case kirmizi = "kırmızı"
    case turuncu
    case sari = "sarı"
    case yesil = "yeşil"
    case mavi
    case mor
    case pembe
}

/// Aynı biçimdeki ardışık metin parçası.
public struct TextRun: Codable, Equatable, Sendable {
    public var text: String
    /// Fosforlu kalem / arka plan vurgusu.
    public var highlight: NamedColor?
    /// Siyah/gri dışındaki yazı rengi.
    public var color: NamedColor?

    public init(text: String, highlight: NamedColor? = nil, color: NamedColor? = nil) {
        self.text = text
        self.highlight = highlight
        self.color = color
    }

    public var isPlain: Bool { highlight == nil && color == nil }

    func sameStyle(as other: TextRun) -> Bool { highlight == other.highlight && color == other.color }
}

public enum TextRuns {
    /// Ardışık aynı biçimli parçaları birleştirir; biçimsiz tek parça kalırsa nil döner (gereksiz veri saklanmaz).
    public static func normalize(_ runs: [TextRun]) -> [TextRun]? {
        var out: [TextRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = out.last, last.sameStyle(as: run) {
                out[out.count - 1].text += run.text
            } else {
                out.append(run)
            }
        }
        if out.allSatisfy(\.isPlain) { return nil }
        return out
    }

    /// Paragrafın tamamı aynı renkteyse bu bir vurgu değil, şablon biçimidir (ör. mavi başlıklar):
    /// yazı rengi bilgisi atılır. Vurgu (fosforlu kalem) korunur.
    public static func droppingUniformTextColor(_ runs: [TextRun]) -> [TextRun]? {
        let words = runs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = words.first?.color, words.allSatisfy({ $0.color == first }) else {
            return normalize(runs)
        }
        return normalize(runs.map { TextRun(text: $0.text, highlight: $0.highlight, color: nil) })
    }

    public static func plainText(_ runs: [TextRun]) -> String { runs.map(\.text).joined() }
}

/// Bir kelime kutusundaki piksellerden arka plan ve mürekkep rengini bulur.
public enum ColorAnalysis {
    public struct RGB: Equatable, Sendable {
        public var r: Double, g: Double, b: Double
        public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        func distance(to o: RGB) -> Double {
            let dr = r - o.r, dg = g - o.g, db = b - o.b
            return (dr * dr + dg * dg + db * db).squareRoot()
        }

        /// Algılanan parlaklık (0...255).
        var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

        /// (ton 0..<360, doygunluk 0...1, parlaklık 0...1)
        var hsv: (h: Double, s: Double, v: Double) {
            let rr = r / 255, gg = g / 255, bb = b / 255
            let mx = max(rr, gg, bb), mn = min(rr, gg, bb), d = mx - mn
            var h = 0.0
            if d > 0 {
                if mx == rr { h = 60 * ((gg - bb) / d).truncatingRemainder(dividingBy: 6) }
                else if mx == gg { h = 60 * ((bb - rr) / d + 2) }
                else { h = 60 * ((rr - gg) / d + 4) }
            }
            if h < 0 { h += 360 }
            return (h, mx == 0 ? 0 : d / mx, mx)
        }
    }

    /// Renkli sayılmak için en az doygunluk ve parlaklık.
    static let minSaturation = 0.28
    static let minValue = 0.3

    /// Siyah, gri ve beyaz için nil.
    public static func name(_ c: RGB) -> NamedColor? {
        let (h, s, v) = c.hsv
        guard s >= minSaturation, v >= minValue else { return nil }
        switch h {
        case ..<12, 345...: return .kirmizi
        case ..<40: return .turuncu
        case ..<70: return .sari
        case ..<170: return .yesil
        case ..<255: return .mavi
        case ..<290: return .mor
        default: return .pembe
        }
    }

    /// Kâğıt rengi beyaza çekilecek şekilde kanal başına ölçekler (beyaz dengesi). Yalnız kâğıt açık ve
    /// hafif renkliyse; renkli slayt zemini (ör. mavi şablon) olduğu gibi bırakılır.
    static func balanced(_ c: RGB, paper: RGB) -> RGB {
        let (_, s, v) = paper.hsv
        guard s < 0.25, v > 0.5 else { return c }
        return RGB(r: min(255, c.r * 255 / max(paper.r, 1)), g: min(255, c.g * 255 / max(paper.g, 1)),
                   b: min(255, c.b * 255 / max(paper.b, 1)))
    }

    /// RGBA8 piksellerinden baskın renk (arka plan) ve ondan en uzak piksellerin ortalaması (mürekkep).
    public static func backgroundAndInk(rgba: [UInt8]) -> (background: RGB, ink: RGB?)? {
        let count = rgba.count / 4
        guard count > 0 else { return nil }
        var bins: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in 0..<count {
            let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let e = bins[key] ?? (0, 0, 0, 0)
            bins[key] = (e.n + 1, e.r + r, e.g + g, e.b + b)
        }
        let top = bins.values.max { $0.n < $1.n }!
        let bg = RGB(r: Double(top.r) / Double(top.n), g: Double(top.g) / Double(top.n), b: Double(top.b) / Double(top.n))

        var far: [(d: Double, c: RGB)] = []
        for i in 0..<count {
            let c = RGB(r: Double(rgba[i * 4]), g: Double(rgba[i * 4 + 1]), b: Double(rgba[i * 4 + 2]))
            let d = c.distance(to: bg)
            if d > 90 { far.append((d, c)) }
        }
        // Çok az mürekkep pikseli: boş kutu veya gürültü.
        guard far.count >= max(4, count / 100) else { return (bg, nil) }
        // Kenar yumuşatma pikselleri karışık renklidir; en uzak yarıyı kullan.
        far.sort { $0.d > $1.d }
        let core = far.prefix(max(1, far.count / 2))
        let n = Double(core.count)
        let ink = RGB(r: core.map(\.c.r).reduce(0, +) / n, g: core.map(\.c.g).reduce(0, +) / n,
                      b: core.map(\.c.b).reduce(0, +) / n)
        return (bg, ink)
    }

    /// Kelime kutusunun biçimi. `pageBackground` sayfanın genel arka planıdır; renkli şablon arka planı
    /// vurgu sanılmasın diye kelimenin arka planı ondan belirgin farklıysa vurgu sayılır.
    public static func style(rgba: [UInt8], pageBackground: RGB) -> (highlight: NamedColor?, color: NamedColor?) {
        guard let found = backgroundAndInk(rgba: rgba) else { return (nil, nil) }
        // Fotoğrafta kâğıt ışıktan dolayı sarımsı/mavimsi görünür; renkler kâğıda göre dengelenir ki
        // gri-kahve görünen siyah yazı "turuncu" sayılmasın.
        let bg = balanced(found.background, paper: pageBackground)
        let ink = found.ink.map { balanced($0, paper: pageBackground) }
        var highlight: NamedColor?
        // Fosforlu kalem açık renkli zemin üstünde koyu yazıdır. Renkli zemin üstünde açık yazı
        // (tablo başlığı, renkli kutu) vurgu değil, şablon biçimidir.
        let inkIsDarker = ink.map { $0.luminance < bg.luminance } ?? true
        if found.background.distance(to: pageBackground) > 40, bg.hsv.v > 0.55, inkIsDarker, let n = name(bg) {
            highlight = n
        }
        let color = ink.flatMap(name)
        return (highlight, color)
    }
}
