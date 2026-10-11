import Foundation

/// Şekil etiketlerinden "görsel kapatma" kartları: her kartta bir etiket sorulur, şeklin tüm etiketleri kapalıdır
/// (Anki'deki "hepsini gizle, birini sor"). Kapatma kutuları görselin üstüne yüzde konumlu kutular olarak çizilir;
/// görselin kendisi değişmez, her şekil için tek görsel gider.
public struct OcclusionCard: Equatable, Sendable {
    /// Aynı şeklin aynı etiketi her dışa aktarımda aynı kimliği alır; Anki yeniden içe aktarımda kartı günceller.
    public var guid: String
    public var header: String
    public var front: String
    public var back: String
    public var answer: String
    public var source: String
    public var mediaName: String
}

/// Kartlarda kullanılan şekil görseli: Anki'deki dosya adı ve arşivdeki kırpım.
public struct OcclusionMedia: Equatable, Sendable {
    public var name: String
    public var imageRef: String
}

public enum ImageOcclusion {
    /// Bundan uzun yazı etiket değil, şeklin içine düşmüş cümledir.
    static let maxLabelLength = 40
    /// Kapatma kutusu yazının biraz dışına taşar; harf uçları görünmesin.
    static let padding = 0.008

    /// Sorulacak etiketler: en az iki harfli, kısa yazılar. Aynı yazı birden çok yerdeyse tek kartta hepsi sorulur.
    /// Kutular şekle göredir (0...1).
    public static func targets(of figure: Figure) -> [(text: String, boxes: [BoundingBox])] {
        var order: [String] = []
        var groups: [String: (text: String, boxes: [BoundingBox])] = [:]
        let sorted = figure.labels.sorted { ($0.bbox.y, $0.bbox.x) < ($1.bbox.y, $1.bbox.x) }
        for label in sorted {
            let text = label.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard text.count <= maxLabelLength, text.filter(\.isLetter).count >= 2 else { continue }
            let box = label.bbox.relative(to: figure.bbox)
                .insetBy(dx: -padding, dy: -padding)
                .clamped(to: BoundingBox(x: 0, y: 0, width: 1, height: 1))
            guard box.area > 0 else { continue }
            let key = text.lowercased()
            if groups[key] == nil {
                order.append(key)
                groups[key] = (text, [])
            }
            groups[key]?.boxes.append(box)
        }
        return order.compactMap { groups[$0] }
    }

    /// Kart yapılabilecek şekiller: kaydedilmiş, el notu olmayan, en az iki etiketli.
    public static func figures(in archive: Archive, sourceIDs: [UUID]) -> [(source: SourceAsset, page: Page, figure: Figure)] {
        sourceIDs.compactMap { archive.source($0) }.flatMap { source in
            archive.pages(of: source.id).flatMap { page in
                archive.figures(of: page.id)
                    .filter { $0.status == .accepted && !$0.isHandwriting && $0.imageRef != nil }
                    .filter { targets(of: $0).count >= 2 }
                    .map { (source, page, $0) }
            }
        }
    }

    public static func cards(in archive: Archive, sourceIDs: [UUID]) -> (cards: [OcclusionCard], media: [OcclusionMedia]) {
        var cards: [OcclusionCard] = []
        var media: [OcclusionMedia] = []
        for (source, page, figure) in figures(in: archive, sourceIDs: sourceIDs) {
            guard let ref = figure.imageRef else { continue }
            let name = "dersarsivi-\(String(figure.id.uuidString.lowercased().filter(\.isHexDigit).prefix(12))).jpg"
            media.append(OcclusionMedia(name: name, imageRef: ref))
            let all = targets(of: figure)
            for (index, target) in all.enumerated() {
                let others = all.enumerated().filter { $0.offset != index }.flatMap(\.element.boxes)
                let masks = { (asked: String) in
                    target.boxes.map { mask($0, kind: asked) } + others.map { mask($0, kind: "") }
                }
                cards.append(OcclusionCard(
                    guid: "da" + String(SHA256Hasher.hexDigest(
                        Data("\(figure.id.uuidString)|\(target.text.lowercased())".utf8)).prefix(16)),
                    header: escape(source.sourceTitle),
                    front: picture(name, masks: masks("q")),
                    back: picture(name, masks: masks("a")),
                    answer: escape(target.text),
                    source: escape("\(source.sourceTitle), Sayfa \(page.pageIndex + 1)"),
                    mediaName: name))
            }
        }
        return (cards, media)
    }

    static func picture(_ name: String, masks: [String]) -> String {
        "<div class=\"io\"><img src=\"\(name)\">" + masks.joined() + "</div>"
    }

    /// `kind`: "q" sorulan, "a" cevapta gösterilen (yalnız çerçeve), boş: kapalı kalan diğer etiket.
    static func mask(_ box: BoundingBox, kind: String) -> String {
        let pct = { (v: Double) in String(format: "%.2f%%", v * 100) }
        let cls = kind.isEmpty ? "m" : "m \(kind)"
        return "<div class=\"\(cls)\" style=\"left:\(pct(box.x));top:\(pct(box.y));"
            + "width:\(pct(box.width));height:\(pct(box.height))\"></div>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
