import XCTest
@testable import DersArsiviCore

/// `background` ile dolu, ortasında `ink` renginde bir "harf" bloğu olan RGBA kutusu.
private func box(background: (UInt8, UInt8, UInt8), ink: (UInt8, UInt8, UInt8)?,
                 width: Int = 40, height: Int = 20) -> [UInt8] {
    var px: [UInt8] = []
    for y in 0..<height {
        for x in 0..<width {
            let isInk = ink != nil && (8..<32).contains(x) && (6..<14).contains(y) && x % 3 != 0
            let c = isInk ? ink! : background
            px += [c.0, c.1, c.2, 255]
        }
    }
    return px
}

private let white = ColorAnalysis.RGB(r: 255, g: 255, b: 255)

final class ColorAnalysisTests: XCTestCase {
    func testColorNames() {
        XCTAssertEqual(ColorAnalysis.name(.init(r: 255, g: 236, b: 140)), .sari)      // fosforlu sarı
        XCTAssertEqual(ColorAnalysis.name(.init(r: 237, g: 125, b: 49)), .turuncu)    // slayttaki turuncu yazı
        XCTAssertEqual(ColorAnalysis.name(.init(r: 0, g: 112, b: 192)), .mavi)
        XCTAssertEqual(ColorAnalysis.name(.init(r: 200, g: 30, b: 30)), .kirmizi)
        XCTAssertEqual(ColorAnalysis.name(.init(r: 60, g: 170, b: 80)), .yesil)
        XCTAssertNil(ColorAnalysis.name(.init(r: 20, g: 20, b: 20)))                  // siyah
        XCTAssertNil(ColorAnalysis.name(.init(r: 128, g: 128, b: 130)))               // gri
        XCTAssertNil(ColorAnalysis.name(white))
    }

    func testBlackTextOnYellowHighlight() {
        let s = ColorAnalysis.style(rgba: box(background: (255, 236, 140), ink: (10, 10, 10)), pageBackground: white)
        XCTAssertEqual(s.highlight, .sari)
        XCTAssertNil(s.color)
    }

    func testOrangeTextOnWhite() {
        let s = ColorAnalysis.style(rgba: box(background: (255, 255, 255), ink: (237, 125, 49)), pageBackground: white)
        XCTAssertNil(s.highlight)
        XCTAssertEqual(s.color, .turuncu)
    }

    func testColoredSlideBackgroundIsNotAHighlight() {
        let blueSlide = ColorAnalysis.RGB(r: 170, g: 225, b: 240)
        let s = ColorAnalysis.style(rgba: box(background: (170, 225, 240), ink: (10, 10, 10)), pageBackground: blueSlide)
        XCTAssertNil(s.highlight)
        XCTAssertNil(s.color)
    }

    func testEmptyBoxHasNoInk() {
        let found = ColorAnalysis.backgroundAndInk(rgba: box(background: (255, 255, 255), ink: nil))
        XCTAssertNotNil(found)
        XCTAssertNil(found?.ink)
    }
}

final class TextRunsTests: XCTestCase {
    func testNormalizeMergesSameStyleAndDropsAllPlain() {
        XCTAssertNil(TextRuns.normalize([TextRun(text: "a "), TextRun(text: "b")]))
        XCTAssertEqual(TextRuns.normalize([TextRun(text: "Kısmi ", highlight: .sari),
                                           TextRun(text: "tıkanıklık", highlight: .sari),
                                           TextRun(text: " (aort")]),
                       [TextRun(text: "Kısmi tıkanıklık", highlight: .sari), TextRun(text: " (aort")])
    }

    func testUniformTextColorIsTemplateNotEmphasis() {
        XCTAssertNil(TextRuns.droppingUniformTextColor([TextRun(text: "• ", color: .mavi),
                                                        TextRun(text: "NEDENLERİ;", color: .mavi)]))
        let partial = [TextRun(text: "damarlardaki "), TextRun(text: "türbülan kan", color: .turuncu)]
        XCTAssertEqual(TextRuns.droppingUniformTextColor(partial), partial)
    }
}

final class StyledLayoutAndExportTests: XCTestCase {
    func testRunsSurviveParagraphMergeAndRenderAsMarkup() throws {
        let w = 2000.0, h = 1257.0
        func bb(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> BoundingBox {
            BoundingBox(x: x0 / w, y: y0 / h, width: (x1 - x0) / w, height: (y1 - y0) / h)
        }
        let l1 = ExtractedBlock(text: "damarlardaki türbülan kan", bbox: bb(360, 272, 910, 325),
                                runs: [TextRun(text: "damarlardaki "), TextRun(text: "türbülan kan", color: .turuncu)])
        let l2 = ExtractedBlock(text: "akımının oluşturduğu sestir.", bbox: bb(360, 327, 930, 380),
                                runs: [TextRun(text: "akımı", color: .turuncu), TextRun(text: "nın oluşturduğu sestir.")])
        let merged = LayoutAnalyzer.paragraphs(from: [l1, l2], pageWidth: w, pageHeight: h)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "damarlardaki türbülan kan akımının oluşturduğu sestir.")
        XCTAssertEqual(TextRuns.plainText(merged[0].runs!), merged[0].text)
        XCTAssertEqual(MarkdownExporter.render(merged[0].runs!),
                       "damarlardaki ⟦turuncu: türbülan kan akımı⟧nın oluşturduğu sestir.")

        let hl = [TextRun(text: "• "), TextRun(text: "Kısmi tıkanıklık", highlight: .sari), TextRun(text: " (aort stenozu)")]
        XCTAssertEqual(MarkdownExporter.render(hl), "• ==Kısmi tıkanıklık== (aort stenozu)")
        XCTAssertEqual(MarkdownExporter.render([TextRun(text: "VSD", highlight: .yesil)]), "==VSD== (yeşil vurgu)")
    }

    func testCorrectionDropsRunsAndExportUsesPlainCorrectedText() throws {
        var archive = Archive()
        let source = SourceAsset(mediaType: .image, originalFilename: "a.png", sourceTitle: "Üfürümler",
                                 contentHash: "h", localAssetRef: "originals/a.png", importedAt: Date())
        archive.importSource(source, pageSizes: [(width: 10.0, height: 10.0)])
        let page = archive.pages(of: source.id)[0]
        let run = ExtractionRun(pageID: page.id, sourceContentHash: "h", engine: "t", engineVersion: "1",
                                configHash: "c", startedAt: Date(), finishedAt: Date())
        try archive.applyExtraction([ExtractedBlock(text: "Akımın artması (anemi)",
                                                    runs: [TextRun(text: "Akımın artması", highlight: .sari),
                                                           TextRun(text: " (anemi)")])], run: run)

        var md = try MarkdownExporter().export(archive, selections: [SourceSelection(sourceID: source.id)],
                                               mode: .combined, createdAt: Date()).files[0].contents
        XCTAssertTrue(md.contains("==Akımın artması== (anemi)"))
        XCTAssertTrue(md.contains("fosforlu kalemle vurgulanmış"))

        try archive.correct(blockID: archive.blocks(of: page.id)[0].id, newText: "Akımın artması (anemi, gebelik)",
                            at: Date())
        XCTAssertNil(archive.blocks(of: page.id)[0].runs)
        md = try MarkdownExporter().export(archive, selections: [SourceSelection(sourceID: source.id)],
                                           mode: .combined, createdAt: Date()).files[0].contents
        XCTAssertTrue(md.contains("Akımın artması (anemi, gebelik) ✏️"))
        XCTAssertFalse(md.contains("fosforlu"))
    }
}
