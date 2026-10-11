import XCTest
@testable import DersArsiviCore

/// Sayfadaki tabloların Markdown tablosu olarak okunması.
final class TableLayoutTests: XCTestCase {
    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> BoundingBox {
        BoundingBox(x: x, y: y, width: w, height: h)
    }

    /// Sayfanın ortasında 3 satır × 3 sütunluk elektrolit tablosu; her hücre 0.2 × 0.05.
    private func electrolyteTable() -> DetectedTable {
        let texts = [["İyon", "Hücre içi", "Hücre dışı"],
                     ["Na+", "14", "142"],
                     ["K+", "140", "4"]]
        var cells: [DetectedTable.Cell] = []
        for r in 0..<3 {
            for c in 0..<3 {
                cells.append(.init(rows: r...r, columns: c...c, text: texts[r][c],
                                   bbox: box(0.2 + Double(c) * 0.2, 0.4 + Double(r) * 0.05, 0.2, 0.05)))
            }
        }
        return DetectedTable(bbox: box(0.2, 0.4, 0.6, 0.15), cells: cells)
    }

    func testTableBecomesMarkdownAndLinesInsideAreNotRepeated() {
        let lines = [
            ExtractedBlock(text: "Elektrolitler", bbox: box(0.2, 0.1, 0.4, 0.05)),
            // OCR satırı iki hücreye taşıyor: hücre metni olarak kullanılmaz ama tablonun içinde olduğu için atılır.
            ExtractedBlock(text: "Na+ 14", bbox: box(0.22, 0.455, 0.3, 0.04)),
            // Tek hücrenin içindeki satır: belge tanımanın okuması yerine bu kullanılır.
            ExtractedBlock(text: "Hücre dışı", bbox: box(0.62, 0.405, 0.15, 0.04), confidence: 0.9, marked: true),
            ExtractedBlock(text: "Tablonun altındaki açıklama", bbox: box(0.2, 0.7, 0.5, 0.05)),
        ]
        var table = electrolyteTable()
        table.cells[2].text = "Hucre disi"
        let (rest, tables) = TableLayout.split(lines: lines, tables: [table])

        XCTAssertEqual(rest.map(\.text), ["Elektrolitler", "Tablonun altındaki açıklama"])
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables[0].kind, .table)
        XCTAssertTrue(tables[0].marked, "tablodaki işaretli satır tabloyu işaretler")
        XCTAssertEqual(tables[0].text, """
            | İyon | Hücre içi | Hücre dışı |
            | --- | --- | --- |
            | Na+ | 14 | 142 |
            | K+ | 140 | 4 |
            """)

        let ordered = TableLayout.insert(tables, into: rest)
        XCTAssertEqual(ordered.map(\.kind), [.text, .table, .text])
    }

    func testTwoColumnProseAndTinyGridsAreNotTables() {
        let long = String(repeating: "Kalp debisi atım hacmi ile kalp hızının çarpımıdır. ", count: 3)
        XCTAssertFalse(TableLayout.looksLikeTable([[long, long], [long, long]]))
        XCTAssertFalse(TableLayout.looksLikeTable([["Na+", "142"]]), "tek satır tablo değil")
        XCTAssertFalse(TableLayout.looksLikeTable([["Na+"], ["K+"]]), "tek sütun liste")
        XCTAssertFalse(TableLayout.looksLikeTable([["a", "", ""], ["", "", ""], ["", "", "b"]]))
        XCTAssertTrue(TableLayout.looksLikeTable([["Na+", "142"], ["K+", "4"]]))

        // Tablo sayılmayan bölgedeki satırlar düz metin olarak kalır.
        let prose = DetectedTable(bbox: box(0, 0, 1, 1), cells: [
            .init(rows: 0...0, columns: 0...0, text: long), .init(rows: 0...0, columns: 1...1, text: long),
            .init(rows: 1...1, columns: 0...0, text: long), .init(rows: 1...1, columns: 1...1, text: long),
        ])
        let line = ExtractedBlock(text: "Kalp debisi", bbox: box(0.1, 0.1, 0.3, 0.05))
        let (rest, tables) = TableLayout.split(lines: [line], tables: [prose])
        XCTAssertEqual(rest, [line])
        XCTAssertTrue(tables.isEmpty)
    }

    func testMergedCellsPipesAndLineBreaksAreKeptInsideTheGrid() throws {
        let table = DetectedTable(bbox: box(0, 0, 1, 1), cells: [
            .init(rows: 0...0, columns: 0...1, text: "Tip\n(alt grup)"),
            .init(rows: 0...0, columns: 2...2, text: "Örnek"),
            .init(rows: 1...1, columns: 0...0, text: "I"),
            .init(rows: 1...1, columns: 1...1, text: "a|b"),
            .init(rows: 1...1, columns: 2...2, text: "Anafilaksi"),
        ])
        let grid = TableLayout.grid(table)
        XCTAssertEqual(grid, [["Tip (alt grup)", "", "Örnek"], ["I", "a|b", "Anafilaksi"]])
        let md = try XCTUnwrap(TableLayout.markdown(grid))
        XCTAssertTrue(md.contains("| I | a\\|b | Anafilaksi |"))
        XCTAssertEqual(TableLayout.parse(md), grid, "ekranda gösterim için geri okunur")
        XCTAssertNil(TableLayout.parse("Düz bir paragraf"))
    }

    func testTableIsExportedOnItsOwnLinesWithMarkAndCorrectionNotes() throws {
        var archive = Archive()
        let source = SourceAsset(mediaType: .image, originalFilename: "t.png", sourceTitle: "Elektrolitler",
                                 contentHash: "t", localAssetRef: "originals/t.png", importedAt: Date())
        archive.importSource(source, pageSizes: [(2000, 1500)])
        let page = archive.pages(of: source.id)[0]
        let (_, tables) = TableLayout.split(lines: [], tables: [electrolyteTable()])
        var table = tables[0]
        table.marked = true
        let run = ExtractionRun(pageID: page.id, sourceContentHash: "t", engine: "t", engineVersion: "1",
                                configHash: "c", startedAt: Date(), finishedAt: Date())
        try archive.applyExtraction([ExtractedBlock(text: "Elektrolitler", bbox: box(0.2, 0.1, 0.4, 0.05)), table],
                                    run: run)

        var md = try MarkdownExporter()
            .export(archive, selections: [SourceSelection(sourceID: source.id)], mode: .combined, createdAt: Date())
            .files[0].contents
        XCTAssertTrue(md.contains("\nElektrolitler\n\n⭐ İşaretli tablo:\n\n| İyon | Hücre içi | Hücre dışı |\n| --- | --- | --- |\n"))
        XCTAssertTrue(md.contains("| K+ | 140 | 4 |\n"))

        let block = try XCTUnwrap(archive.blocks(of: page.id).first { $0.kind == .table })
        try archive.correct(blockID: block.id, newText: block.acceptedText.replacingOccurrences(of: "140", with: "150"),
                            at: Date())
        md = try MarkdownExporter()
            .export(archive, selections: [SourceSelection(sourceID: source.id)], mode: .combined, createdAt: Date())
            .files[0].contents
        XCTAssertTrue(md.contains("| K+ | 150 | 4 |\n\n_(Tablo düzeltildi ✏️)_\n"))
    }
}
