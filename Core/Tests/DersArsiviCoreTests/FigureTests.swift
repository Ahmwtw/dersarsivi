import Foundation
import XCTest
@testable import DersArsiviCore

/// Basit RGBA tuval; testlerde sentetik sayfa çizmek için.
private struct Canvas {
    let width: Int, height: Int
    var rgba: [UInt8]

    init(width: Int, height: Int, fill: (UInt8, UInt8, UInt8) = (255, 255, 255)) {
        self.width = width
        self.height = height
        rgba = []
        rgba.reserveCapacity(width * height * 4)
        for _ in 0..<(width * height) { rgba += [fill.0, fill.1, fill.2, 255] }
    }

    /// Fotoğraf dokusu taklidi: iki renk piksel piksel değişir (düz renkli panel değildir).
    mutating func texture(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ a: (UInt8, UInt8, UInt8),
                          _ b: (UInt8, UInt8, UInt8)) {
        for y in max(0, y0)..<min(height, y1) {
            for x in max(0, x0)..<min(width, x1) {
                let c = (x + y) % 2 == 0 ? a : b
                let i = (y * width + x) * 4
                rgba[i] = c.0; rgba[i + 1] = c.1; rgba[i + 2] = c.2
            }
        }
    }

    mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: (UInt8, UInt8, UInt8)) {
        for y in max(0, y0)..<min(height, y1) {
            for x in max(0, x0)..<min(width, x1) {
                let i = (y * width + x) * 4
                rgba[i] = c.0; rgba[i + 1] = c.1; rgba[i + 2] = c.2
            }
        }
    }

    /// Yazı satırı taklidi: koyu çubuk; OCR kutusunu döndürür.
    mutating func textLine(_ text: String, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> FigureDetector.Line {
        rect(x0, y0, x1, y1, (20, 20, 20))
        return (text, box(x0, y0, x1, y1))
    }

    func box(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> BoundingBox {
        BoundingBox(x: Double(x0) / Double(width), y: Double(y0) / Double(height),
                    width: Double(x1 - x0) / Double(width), height: Double(y1 - y0) / Double(height))
    }
}

final class FigureDetectorTests: XCTestCase {
    /// Not uygulamasında ekran görüntüsü: koyu kenarlar, renkli araç çubuğu, solda yazı, sağda fotoğraf.
    func testPhotoNextToTextIsSuggestedAndAppChromeIgnored() {
        var c = Canvas(width: 300, height: 200)
        c.rect(0, 0, 30, 200, (0, 0, 0))
        c.rect(270, 0, 300, 200, (0, 0, 0))
        c.rect(280, 20, 292, 120, (120, 60, 200))   // araç çubuğu düğmeleri
        c.texture(160, 20, 250, 100, (150, 210, 235), (110, 170, 215))  // fotoğraf
        c.rect(190, 40, 220, 80, (30, 30, 30))      // fotoğraftaki nesne
        var lines: [FigureDetector.Line] = []
        for (i, y) in stride(from: 30, to: 180, by: 18).enumerated() {
            lines.append(c.textLine("satır \(i)", 40, y, 140, y + 8))
        }
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: lines)
        XCTAssertEqual(found.count, 1)
        let b = try! XCTUnwrap(found.first?.bbox)
        let photo = c.box(160, 20, 250, 100)
        XCTAssertGreaterThan(photo.fractionInside(b), 0.95)
        XCTAssertLessThan(b.x, 0.54)
        XCTAssertGreaterThan(b.x, 0.45, "soldaki yazı şekle katılmamalı")
        XCTAssertLessThan(b.maxX, 0.9, "araç çubuğu şekle katılmamalı")
        XCTAssertTrue(found[0].labels.isEmpty)
    }

    func testTextOnlyPageHasNoSuggestion() {
        var c = Canvas(width: 300, height: 200)
        var lines: [FigureDetector.Line] = []
        for (i, y) in stride(from: 20, to: 190, by: 14).enumerated() {
            lines.append(c.textLine("satır \(i)", 20, y, i % 3 == 0 ? 180 : 280, y + 8))
        }
        // Fosforlu kalem: yazının etrafında taşan sarı zemin.
        c.rect(15, 44, 200, 58, (250, 235, 140))
        _ = c.textLine("vurgulu", 20, 48, 180, 56)
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: lines)
        XCTAssertEqual(found, [])
    }

    func testDiagramLabelsAreIncludedButTitleAndPageNumberAreNot() {
        var c = Canvas(width: 300, height: 200)
        let title = c.textLine("Kalp Odakları", 100, 4, 220, 24)
        // Şema: kalın çerçeveli bir çizim.
        c.rect(100, 40, 220, 46, (180, 60, 60))
        c.rect(100, 154, 220, 160, (180, 60, 60))
        c.rect(100, 40, 106, 160, (180, 60, 60))
        c.rect(214, 40, 220, 160, (180, 60, 60))
        c.rect(130, 80, 190, 120, (90, 120, 200))
        let inside = c.textLine("Aort", 150, 60, 180, 68)
        let outside = c.textLine("Mitral", 226, 90, 262, 98)
        let pageNumber = c.textLine("29", 155, 170, 165, 178)
        var lines = [title, inside, outside, pageNumber]
        lines.append(c.textLine("dipnot", 10, 186, 120, 194))
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: lines)
        XCTAssertEqual(found.count, 1)
        let figure = try! XCTUnwrap(found.first)
        XCTAssertEqual(figure.labels.map(\.text), ["Aort", "Mitral"])
        XCTAssertGreaterThan(outside.bbox.fractionInside(figure.bbox), 0.99, "yandaki etiket kutuya katılmalı")
        XCTAssertGreaterThan(figure.bbox.y, title.bbox.maxY - 0.01, "başlık şekle katılmamalı")
    }

    /// Koyu slayt zemininde beyaz metin paneli ve dokulu histoloji görseli; ayrıca uygulama düğmeleri.
    func testFlatPanelsAndButtonsAreNotFigures() {
        let navy: (UInt8, UInt8, UInt8) = (10, 30, 90)
        var c = Canvas(width: 300, height: 200, fill: navy)
        c.rect(10, 40, 150, 180, (255, 255, 255))   // metin paneli
        var lines: [FigureDetector.Line] = []
        for (i, y) in stride(from: 50, to: 170, by: 16).enumerated() {
            lines.append(c.textLine("madde \(i)", 20, y, 140, y + 8))
        }
        c.texture(165, 40, 295, 190, (150, 80, 170), (200, 150, 210))  // histoloji
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: lines)
        XCTAssertEqual(found.count, 1)
        let b = try! XCTUnwrap(found.first?.bbox)
        XCTAssertGreaterThan(b.x, 0.5, "beyaz metin paneli şekle katılmamalı")
        XCTAssertGreaterThan(c.box(165, 40, 295, 190).fractionInside(b), 0.95)

        // Mor uygulama zemininde, içinde yazı olan tam genişlik düğmeler.
        var app = Canvas(width: 200, height: 300, fill: (70, 25, 65))
        var buttons: [FigureDetector.Line] = []
        for (i, y) in stride(from: 120, to: 280, by: 40).enumerated() {
            app.rect(0, y, 200, y + 30, (110, 70, 115))
            buttons.append(app.textLine("şık \(i)", 70, y + 10, 130, y + 20))
        }
        XCTAssertEqual(FigureDetector.suggestions(rgba: app.rgba, width: app.width, height: app.height,
                                                  lines: buttons), [])
    }

    /// Beyaz panel sayfanın ana zemini sayılsa da lacivert slayttaki histoloji görseli içerik alanında kalır;
    /// panelin lacivert zemindeki kenarı şekil sanılmaz.
    func testPhotoOnDarkSlideWithLittleBackgroundIsFound() {
        var c = Canvas(width: 300, height: 200, fill: (10, 30, 90))
        c.rect(10, 10, 150, 196, (255, 255, 255))
        var lines: [FigureDetector.Line] = []
        for (i, y) in stride(from: 20, to: 180, by: 16).enumerated() {
            lines.append(c.textLine("madde \(i)", 20, y, 140, y + 8))
        }
        c.texture(160, 20, 300, 196, (150, 80, 170), (200, 150, 210))
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: lines)
        XCTAssertEqual(found.count, 1)
        let b = try! XCTUnwrap(found.first?.bbox)
        XCTAssertGreaterThan(b.x, 0.5, "beyaz metin paneli şekle katılmamalı")
        XCTAssertGreaterThan(c.box(160, 20, 300, 196).fractionInside(b), 0.9)
    }

    /// Slayta mor kalemle yazılmış not önerilmez; yanındaki şema önerilir.
    func testColoredPenNoteIsNotAFigure() {
        var c = Canvas(width: 300, height: 200)
        c.texture(30, 30, 130, 150, (150, 210, 235), (110, 170, 215))
        // El yazısı taklidi: ince mor çizgiler, seyrek.
        for y in stride(from: 60, to: 120, by: 6) {
            c.rect(180, y, 260, y + 1, (120, 40, 200))
            c.rect(180 + (y % 12) * 3, y, 181 + (y % 12) * 3, y + 6, (120, 40, 200))
        }
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: [])
        XCTAssertEqual(found.count, 1)
        XCTAssertLessThan(try! XCTUnwrap(found.first?.bbox).maxX, 0.5, "kalem notu şekil sayılmamalı")
    }

    /// Şemaya neredeyse değen uzak işaret (yıldız, ok) şemayla tek kutuya alınmaz.
    func testNearlyTouchingMarkIsNotMergedIntoFigure() {
        var c = Canvas(width: 300, height: 200)
        c.texture(30, 20, 200, 110, (150, 210, 235), (110, 170, 215))
        c.rect(120, 113, 122, 150, (20, 20, 20))       // şemaya bir hücre kala biten çizgi
        c.rect(110, 150, 150, 190, (20, 20, 20))       // uzak işaret
        c.rect(120, 160, 140, 180, (255, 255, 255))
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: [])
        let main = try! XCTUnwrap(found.max { $0.bbox.area < $1.bbox.area })
        XCTAssertLessThan(main.bbox.maxY, 0.65, "ince çizgiyle bağlı işaret şemaya katılmamalı")
    }

    /// Ekranın kenarından taşan komşu slaytın dar kesiti önerilmez.
    func testNarrowSliverAtContentEdgeIsNotSuggested() {
        var c = Canvas(width: 300, height: 200)
        c.rect(0, 0, 30, 200, (0, 0, 0))
        c.rect(270, 0, 300, 200, (0, 0, 0))
        c.texture(32, 40, 60, 180, (230, 120, 140), (190, 90, 120))
        c.texture(120, 40, 220, 160, (150, 210, 235), (110, 170, 215))
        let found = FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: [])
        XCTAssertEqual(found.count, 1)
        XCTAssertGreaterThan(c.box(120, 40, 220, 160).fractionInside(try! XCTUnwrap(found.first?.bbox)), 0.95)
    }

    /// Tablo slaytı: en sık renk tablo satırlarının açık rengi olsa da beyaz başlık alanı sayfa alanında kalır;
    /// tablonun tek renkli başlık şeridi şekil diye önerilmez.
    func testTableSlideKeepsTitleAndHeaderBandIsNotAFigure() throws {
        var c = Canvas(width: 320, height: 200)
        c.rect(0, 0, 40, 200, (0, 0, 0))
        c.rect(280, 0, 320, 200, (0, 0, 0))
        var lines = [c.textLine("Başlık", 80, 8, 240, 18)]
        c.rect(50, 30, 270, 50, (60, 100, 180))     // başlık şeridi
        lines.append(c.textLine("Sütun 1", 60, 37, 100, 43))
        lines.append(c.textLine("Sütun 2", 170, 37, 210, 43))
        c.rect(40, 50, 280, 195, (233, 235, 245))   // tablo satırları
        for (i, y) in stride(from: 58, to: 190, by: 14).enumerated() {
            lines.append(c.textLine("hücre \(i)", 60, y, 130, y + 6))
            lines.append(c.textLine("açıklama \(i)", 160, y, 260, y + 6))
        }
        let scan = try XCTUnwrap(FigureDetector.scan(rgba: c.rgba, width: c.width, height: c.height))
        XCTAssertLessThan(scan.content.y, 0.05, "slayt başlığı sayfa alanı dışında kalmamalı")
        XCTAssertGreaterThan(scan.content.maxY, 0.95)
        XCTAssertEqual(FigureDetector.suggestions(rgba: c.rgba, width: c.width, height: c.height, lines: lines), [])
    }

    /// Dokun-kırp: dokunulan şeklin kutusu bulunur; yazının üstüne ya da boş yere dokununca şekil yoktur.
    func testTapFindsFigureUnderFinger() throws {
        var c = Canvas(width: 300, height: 200)
        c.texture(160, 30, 260, 150, (150, 210, 235), (110, 170, 215))
        var lines: [FigureDetector.Line] = []
        for (i, y) in stride(from: 30, to: 170, by: 18).enumerated() {
            lines.append(c.textLine("satır \(i)", 20, y, 130, y + 8))
        }
        lines.append(c.textLine("Aort", 190, 60, 220, 68))
        let scan = try XCTUnwrap(FigureDetector.scan(rgba: c.rgba, width: c.width, height: c.height))
        let hit = try XCTUnwrap(FigureDetector.region(at: (x: 0.7, y: 0.5), scan: scan, lines: lines))
        XCTAssertGreaterThan(c.box(160, 30, 260, 150).fractionInside(hit.bbox), 0.95)
        XCTAssertGreaterThan(hit.bbox.x, 0.45, "yandaki yazı katılmamalı")
        XCTAssertEqual(hit.labels.map(\.text), ["Aort"])
        // Etiketin tam üstüne dokunmak da şekli bulur.
        XCTAssertNotNil(FigureDetector.region(at: (x: 0.68, y: 0.32), scan: scan, lines: lines))
        XCTAssertNil(FigureDetector.region(at: (x: 0.25, y: 0.5), scan: scan, lines: lines), "paragrafta şekil yok")
    }

    func testToolbarTextOutsideSlideIsDropped() throws {
        var c = Canvas(width: 300, height: 200)
        c.rect(0, 0, 30, 200, (0, 0, 0))
        c.rect(270, 0, 300, 200, (0, 0, 0))
        let scan = try XCTUnwrap(FigureDetector.scan(rgba: c.rgba, width: c.width, height: c.height))
        XCTAssertEqual(scan.content.x, 0.1, accuracy: 0.03)
        XCTAssertEqual(scan.content.maxX, 0.9, accuracy: 0.03)

        var lines = (0..<6).map { i in
            ExtractedBlock(text: "slayt \(i)", bbox: c.box(40, 20 + i * 20, 200, 28 + i * 20))
        }
        lines.append(ExtractedBlock(text: "50", bbox: c.box(282, 10, 292, 16)))
        lines.append(ExtractedBlock(text: "kutusuz"))
        let kept = FigureDetector.keepingContentLines(lines, scan: scan)
        XCTAssertEqual(kept.map(\.text), (0..<6).map { "slayt \($0)" } + ["kutusuz"])

        // Satırların çoğu dışarıdaysa alan güvenilmez; hiçbir şey atılmaz.
        let outside = (0..<4).map { ExtractedBlock(text: "\($0)", bbox: c.box(275, $0 * 20, 295, $0 * 20 + 8)) }
        XCTAssertEqual(FigureDetector.keepingContentLines(outside, scan: scan).count, 4)
    }

    func testTinyOrEmptyInputIsSafe() {
        XCTAssertEqual(FigureDetector.suggestions(rgba: [], width: 0, height: 0, lines: []), [])
        let c = Canvas(width: 50, height: 50)
        XCTAssertEqual(FigureDetector.suggestions(rgba: c.rgba, width: 50, height: 50, lines: []), [])
    }
}

final class FigureArchiveTests: XCTestCase {
    private func makeArchive() -> (Archive, Page) {
        var archive = Archive()
        let source = SourceAsset(mediaType: .image, originalFilename: "kalp.jpg", sourceTitle: "Kalp Odakları",
                                 contentHash: "h1", localAssetRef: "originals/x.jpg",
                                 importedAt: Date(timeIntervalSince1970: 0))
        archive.importSource(source, pageSizes: [(1000, 700)])
        return (archive, archive.pages(of: source.id)[0])
    }

    private let figureBox = BoundingBox(x: 0.3, y: 0.3, width: 0.4, height: 0.5)

    func testNewSuggestionsReplaceOldOnesButKeepDecisions() throws {
        var (archive, page) = makeArchive()
        archive.applyFigureSuggestions([FigureSuggestion(bbox: figureBox)], pageID: page.id, at: Date())
        let suggested = try XCTUnwrap(archive.figures(of: page.id).first)
        XCTAssertEqual(archive.suggestedFigureCount(sourceID: page.sourceID), 1)

        try archive.acceptFigure(suggested.id, bbox: figureBox, imageRef: "figures/a.jpg")
        // Yeniden okuma aynı yeri tekrar önerir; kaydedilmiş şekil çoğaltılmaz.
        let shifted = BoundingBox(x: 0.31, y: 0.3, width: 0.4, height: 0.5)
        let other = BoundingBox(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        archive.applyFigureSuggestions([FigureSuggestion(bbox: shifted), FigureSuggestion(bbox: other)],
                                       pageID: page.id, at: Date())
        XCTAssertEqual(archive.figures(of: page.id).map(\.status), [.suggested, .accepted])

        let otherID = try XCTUnwrap(archive.figures(of: page.id).first { $0.status == .suggested }?.id)
        archive.dismissFigure(otherID)
        archive.applyFigureSuggestions([FigureSuggestion(bbox: other)], pageID: page.id, at: Date())
        XCTAssertEqual(archive.figures(of: page.id).map(\.status), [.accepted], "yoksayılan yer tekrar önerilmez")
        XCTAssertEqual(archive.suggestedFigureCount(sourceID: page.sourceID), 0)
    }

    func testEditingBoxDropsLabelsOutsideAndReturnsOldImage() throws {
        var (archive, page) = makeArchive()
        let aort = FigureLabel(text: "Aort", bbox: BoundingBox(x: 0.35, y: 0.35, width: 0.05, height: 0.03))
        let mitral = FigureLabel(text: "Mitral", bbox: BoundingBox(x: 0.6, y: 0.7, width: 0.05, height: 0.03))
        archive.applyFigureSuggestions([FigureSuggestion(bbox: figureBox, labels: [aort, mitral])],
                                       pageID: page.id, at: Date())
        let id = try XCTUnwrap(archive.figures(of: page.id).first?.id)
        XCTAssertNil(try archive.acceptFigure(id, bbox: figureBox, imageRef: "figures/a.jpg"))
        let smaller = BoundingBox(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        XCTAssertEqual(try archive.acceptFigure(id, bbox: smaller, imageRef: "figures/b.jpg"), "figures/a.jpg")
        XCTAssertEqual(archive.figure(id)?.labels, [aort])

        XCTAssertEqual(archive.removeFigure(id), "figures/b.jpg")
        XCTAssertEqual(archive.figures(of: page.id), [])
        // Silinen yer yoksayılmış sayılmaz; yeniden okuma onu tekrar önerebilir.
        archive.applyFigureSuggestions([FigureSuggestion(bbox: figureBox)], pageID: page.id, at: Date())
        XCTAssertEqual(archive.figures(of: page.id).map(\.status), [.suggested])
    }

    func testOldArchiveWithoutFiguresStillLoads() throws {
        let (archive, _) = makeArchive()
        let data = try FileArchiveStore.encoder.encode(archive)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "figures")
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try FileArchiveStore.decoder.decode(Archive.self, from: old)
        XCTAssertEqual(decoded.sources, archive.sources)
        XCTAssertEqual(decoded.figures, [])
    }

    func testExportPlacesFigureInFlowAndListsLabelsInsteadOfRepeatingThem() throws {
        var (archive, page) = makeArchive()
        let extracted = [
            ExtractedBlock(text: "Giriş paragrafı", bbox: BoundingBox(x: 0.1, y: 0.1, width: 0.8, height: 0.05)),
            ExtractedBlock(text: "Aort", bbox: BoundingBox(x: 0.35, y: 0.4, width: 0.05, height: 0.03)),
            ExtractedBlock(text: "Son paragraf", bbox: BoundingBox(x: 0.1, y: 0.9, width: 0.8, height: 0.05)),
            ExtractedBlock(text: "Şeklin içine düşen uzun bir paragraf metni kaybolmamalı",
                           bbox: BoundingBox(x: 0.32, y: 0.7, width: 0.3, height: 0.05)),
        ]
        let run = ExtractionRun(pageID: page.id, sourceContentHash: "h1", engine: "t", engineVersion: "1",
                                configHash: "c", startedAt: Date(), finishedAt: Date())
        try archive.applyExtraction(extracted, run: run)
        let label = FigureLabel(text: "Aort", bbox: extracted[1].bbox!)
        archive.applyFigureSuggestions([FigureSuggestion(bbox: figureBox, labels: [label])], pageID: page.id,
                                       at: Date())
        let id = try XCTUnwrap(archive.figures(of: page.id).first?.id)
        try archive.acceptFigure(id, bbox: figureBox, imageRef: "figures/a.jpg")

        let selection = [SourceSelection(sourceID: page.sourceID)]
        let result = try MarkdownExporter(includeFigureImages: true)
            .export(archive, selections: selection, mode: .combined, createdAt: Date())
        let md = result.files[0].contents
        let image = try XCTUnwrap(md.range(of: "![Şekil 1](figures/kalp-odaklari-"))
        XCTAssertLessThan(try XCTUnwrap(md.range(of: "Giriş paragrafı")).lowerBound, image.lowerBound)
        XCTAssertLessThan(image.lowerBound, try XCTUnwrap(md.range(of: "Son paragraf")).lowerBound)
        XCTAssertTrue(md.contains("_Şekil 1 etiketleri: Aort_"))
        XCTAssertEqual(md.components(separatedBy: "Aort").count - 1, 1, "etiket metinde tekrar edilmemeli")
        XCTAssertTrue(md.contains("Şeklin içine düşen uzun bir paragraf metni kaybolmamalı"))
        XCTAssertEqual(result.assets.count, 1)
        let entry = try XCTUnwrap(result.manifest.figures?.first)
        XCTAssertEqual(entry.file, result.assets[0].path)
        XCTAssertEqual(entry.labels[0].bbox.x, (0.35 - 0.3) / 0.4, accuracy: 1e-9)

        // Görselsiz exportta yer ve etiket kalır, görsel bağlantısı olmaz.
        let plain = try MarkdownExporter().export(archive, selections: selection, mode: .combined, createdAt: Date())
        XCTAssertTrue(plain.files[0].contents.contains("> 🖼️ Şekil 1 (görsel bu dosyada yok)"))
        XCTAssertEqual(plain.assets, [])

        let zip = try result.zip(imageData: { _ in Data([0xFF, 0xD8, 0xFF]) })
        XCTAssertEqual(Array(zip.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(Array(zip.suffix(22).prefix(4)), [0x50, 0x4B, 0x05, 0x06])
        XCTAssertEqual(zip[zip.count - 22 + 10], 3, "md + görsel + manifest")
        XCTAssertNotNil(zip.range(of: Data(result.assets[0].path.utf8)))
    }

    func testPageImagesAreCroppedToContentAndLinked() throws {
        var (archive, page) = makeArchive()
        let content = BoundingBox(x: 0.1, y: 0, width: 0.8, height: 1)
        archive.setContentBox(content, forPage: page.id)
        archive.setWorkingImage("pages/duz.jpg", forPage: page.id)
        try archive.applyExtraction([ExtractedBlock(text: "Metin")], run: ExtractionRun(
            pageID: page.id, sourceContentHash: "h1", engine: "t", engineVersion: "1", configHash: "c",
            startedAt: Date(), finishedAt: Date()))
        let result = try MarkdownExporter(includePageImages: true)
            .export(archive, selections: [SourceSelection(sourceID: page.sourceID)], mode: .combined, createdAt: Date())
        let asset = try XCTUnwrap(result.assets.first)
        XCTAssertEqual(asset.imageRef, "pages/duz.jpg", "düzleştirilmiş görüntü kullanılmalı")
        XCTAssertEqual(asset.crop, content)
        XCTAssertTrue(asset.path.hasPrefix("pages/"))
        XCTAssertTrue(result.files[0].contents.contains("](\(asset.path))"))
        XCTAssertFalse(result.files[0].contents.contains("görsel içermez"))
        XCTAssertTrue(MarkdownExporter(includePageImages: true).producesZip)
        XCTAssertFalse(MarkdownExporter().producesZip)
    }
}

final class ZipTests: XCTestCase {
    func testCRC32KnownValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    func testStoredEntryLayout() {
        var zip = ZipArchive()
        zip.add(path: "şekil.md", contents: Data("abc".utf8), modified: Date(timeIntervalSince1970: 1_700_000_000))
        let data = zip.finish()
        let name = Data("şekil.md".utf8)
        // Yerel başlık 30 bayt + ad + içerik; ardından merkez dizin.
        XCTAssertEqual(data[30..<(30 + name.count)], name)
        XCTAssertEqual(data[(30 + name.count)..<(33 + name.count)], Data("abc".utf8))
        XCTAssertEqual(data[6], 0x00)
        XCTAssertEqual(data[7], 0x08, "UTF-8 ad bayrağı")
    }
}
