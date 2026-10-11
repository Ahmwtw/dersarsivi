import XCTest
@testable import DersArsiviCore

/// Şekil etiketlerinden Anki görsel kapatma kartları ve .apkg içeriği.
final class ImageOcclusionTests: XCTestCase {
    private func archiveWithHeartDiagram() throws -> (Archive, SourceAsset, Figure) {
        var archive = Archive()
        let source = SourceAsset(mediaType: .image, originalFilename: "kalp.png", sourceTitle: "Kalp <anatomi>",
                                 contentHash: "k", localAssetRef: "originals/k.png", importedAt: Date())
        archive.importSource(source, pageSizes: [(2000, 1500)])
        let page = archive.pages(of: source.id)[0]
        // Şekil sayfanın sağ yarısında; etiketler sayfaya göre.
        let heart = BoundingBox(x: 0.5, y: 0.2, width: 0.4, height: 0.6)
        let single = BoundingBox(x: 0, y: 0, width: 0.3, height: 0.3)
        archive.applyFigureSuggestions([
            FigureSuggestion(bbox: heart, labels: [
                FigureLabel(text: "Sol  ventrikül", bbox: BoundingBox(x: 0.7, y: 0.6, width: 0.1, height: 0.04)),
                FigureLabel(text: "Aort", bbox: BoundingBox(x: 0.6, y: 0.25, width: 0.06, height: 0.04)),
                FigureLabel(text: "aort", bbox: BoundingBox(x: 0.8, y: 0.3, width: 0.06, height: 0.04)),
                FigureLabel(text: "3", bbox: BoundingBox(x: 0.55, y: 0.5, width: 0.02, height: 0.04)),
                FigureLabel(text: String(repeating: "uzun açıklama ", count: 5),
                            bbox: BoundingBox(x: 0.5, y: 0.75, width: 0.4, height: 0.04)),
            ]),
            // Tek etiketli şekil kart üretmez.
            FigureSuggestion(bbox: single, labels: [
                FigureLabel(text: "Tek", bbox: BoundingBox(x: 0.1, y: 0.1, width: 0.1, height: 0.05)),
            ]),
        ], pageID: page.id, at: Date())
        for suggestion in archive.figures(of: page.id) {
            _ = try archive.acceptFigure(suggestion.id, bbox: suggestion.bbox,
                                         imageRef: suggestion.bbox == heart ? "figures/k.jpg" : "figures/b.jpg")
        }
        let figure = try XCTUnwrap(archive.figures(of: page.id).first { $0.bbox == heart })
        return (archive, source, figure)
    }

    func testLabelsBecomeMasksAndEachLabelIsAskedOnce() throws {
        let (archive, source, figure) = try archiveWithHeartDiagram()
        let targets = ImageOcclusion.targets(of: figure)
        XCTAssertEqual(targets.map(\.text), ["Aort", "Sol ventrikül"], "rakam ve uzun yazı etiket değil")
        XCTAssertEqual(targets[0].boxes.count, 2, "aynı yazı iki yerde: birlikte sorulur")
        let aort = targets[0].boxes[0]
        XCTAssertEqual(aort.x, 0.25 - ImageOcclusion.padding, accuracy: 1e-9, "şekle göre konum")
        XCTAssertEqual(aort.y, 0.25 / 3 - ImageOcclusion.padding, accuracy: 1e-9)

        let (cards, media) = ImageOcclusion.cards(in: archive, sourceIDs: [source.id])
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(media.count, 1)
        XCTAssertEqual(media[0].imageRef, "figures/k.jpg")
        let first = cards[0]
        XCTAssertEqual(first.answer, "Aort")
        XCTAssertEqual(first.header, "Kalp &lt;anatomi&gt;")
        XCTAssertEqual(first.source, "Kalp &lt;anatomi&gt;, Sayfa 1")
        XCTAssertTrue(first.front.hasPrefix("<div class=\"io\"><img src=\"\(media[0].name)\">"))
        XCTAssertEqual(first.front.components(separatedBy: "class=\"m q\"").count - 1, 2, "iki Aort kutusu sorulur")
        XCTAssertEqual(first.front.components(separatedBy: "class=\"m\"").count - 1, 1, "ventrikül kapalı kalır")
        XCTAssertEqual(first.back.components(separatedBy: "class=\"m a\"").count - 1, 2)
        XCTAssertTrue(first.front.contains("left:24.20%;top:7.53%;"))

        // Kimlik sabit: aynı şekil yeniden aktarılınca Anki kartı günceller.
        XCTAssertEqual(ImageOcclusion.cards(in: archive, sourceIDs: [source.id]).cards.map(\.guid), cards.map(\.guid))
        XCTAssertNotEqual(cards[0].guid, cards[1].guid)
    }

    func testPackageRowsMatchAnkiFormat() throws {
        let (archive, source, _) = try archiveWithHeartDiagram()
        let (cards, media) = ImageOcclusion.cards(in: archive, sourceIDs: [source.id])
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let package = AnkiPackage(deckName: "DersArşivi::Fizyoloji::Kalp", cards: cards, media: media, now: now)

        XCTAssertEqual(package.notes.count, 2)
        XCTAssertEqual(package.cards.map(\.nid), package.notes.map(\.id))
        XCTAssertEqual(Set(package.cards.map(\.did)), [package.deckID])
        XCTAssertEqual(package.deckID, AnkiPackage(deckName: "DersArşivi::Fizyoloji::Kalp", cards: [], media: [],
                                                   now: Date()).deckID, "aynı deste aynı kimlik")
        let note = package.notes[0]
        XCTAssertEqual(note.flds.split(separator: "\u{1f}", omittingEmptySubsequences: false).count, 5)
        XCTAssertEqual(note.sfld, "Kalp <anatomi>")
        XCTAssertEqual(note.csum, Int64(SHA1Hasher.hexDigest(Data("Kalp <anatomi>".utf8)).prefix(8), radix: 16))
        XCTAssertEqual(note.mod, 1_760_000_000)

        let manifest = try JSONSerialization.jsonObject(with: Data(package.mediaManifest.utf8)) as? [String: String]
        XCTAssertEqual(manifest, ["0": media[0].name])
        let decks = try JSONSerialization.jsonObject(with: Data(package.collection.decks.utf8)) as? [String: Any]
        XCTAssertEqual((decks?[String(package.deckID)] as? [String: Any])?["name"] as? String,
                       "DersArşivi::Fizyoloji::Kalp")
        XCTAssertNotNil(decks?["1"], "Anki varsayılan desteyi bekler")
        let models = try JSONSerialization.jsonObject(with: Data(package.collection.models.utf8)) as? [String: Any]
        let model = try XCTUnwrap(models?[String(AnkiPackage.modelID)] as? [String: Any])
        let fields = (model["flds"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(fields, AnkiPackage.fieldNames)
        let template = try XCTUnwrap((model["tmpls"] as? [[String: Any]])?.first)
        for name in AnkiPackage.fieldNames {
            let used = ((template["qfmt"] as? String) ?? "") + ((template["afmt"] as? String) ?? "")
            XCTAssertTrue(used.contains("{{\(name)}}"), name)
        }
    }

    func testSHA1KnownVectors() {
        XCTAssertEqual(SHA1Hasher.hexDigest(Data("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(SHA1Hasher.hexDigest(Data()), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(SHA1Hasher.hexDigest(Data(String(repeating: "a", count: 1000).utf8)),
                       "291e9a6c66994949b57ba5e650361e98fc36b1ba")
    }
}
