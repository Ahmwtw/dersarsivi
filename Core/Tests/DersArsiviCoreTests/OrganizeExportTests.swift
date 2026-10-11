import XCTest
@testable import DersArsiviCore

/// Klasörler, "sadece görsel" sayfalar, işaretli ve el yazısı satırların dışa aktarımı.
final class OrganizeExportTests: XCTestCase {
    private func addSource(_ archive: inout Archive, title: String, hash: String) -> (SourceAsset, Page) {
        let source = SourceAsset(mediaType: .image, originalFilename: "\(hash).png", sourceTitle: title,
                                 contentHash: hash, localAssetRef: "originals/\(hash).png",
                                 importedAt: Date(timeIntervalSince1970: Double(archive.sources.count)))
        archive.importSource(source, pageSizes: [(2650, 1665)])
        return (source, archive.pages(of: source.id)[0])
    }

    private func read(_ archive: inout Archive, _ page: Page, _ blocks: [ExtractedBlock]) throws {
        let run = ExtractionRun(pageID: page.id, sourceContentHash: "h", engine: "t", engineVersion: "1",
                                configHash: "c", startedAt: Date(), finishedAt: Date())
        try archive.applyExtraction(blocks, run: run)
    }

    private func box(_ x: Double, _ y: Double, _ w: Double = 0.3, _ h: Double = 0.03) -> BoundingBox {
        BoundingBox(x: x, y: y, width: w, height: h)
    }

    func testFoldersHoldSourcesAndDeletingFolderKeepsSources() throws {
        var archive = Archive()
        let fizyoloji = archive.createFolder(name: "Fizyoloji", at: Date())
        let kalp = archive.createFolder(name: "Kalp", parentID: fizyoloji.id, at: Date())
        let (a, _) = addSource(&archive, title: "A", hash: "a")
        let (b, _) = addSource(&archive, title: "B", hash: "b")
        archive.move(sources: [a.id], toFolder: kalp.id)
        archive.move(sources: [b.id], toFolder: fizyoloji.id)

        XCTAssertEqual(archive.subfolders(of: nil).map(\.name), ["Fizyoloji"])
        XCTAssertEqual(archive.subfolders(of: fizyoloji.id).map(\.name), ["Kalp"])
        XCTAssertEqual(archive.sources(inFolder: kalp.id).map(\.id), [a.id])
        XCTAssertEqual(Set(archive.sources(inFolderTree: fizyoloji.id).map(\.id)), [a.id, b.id])
        XCTAssertEqual(archive.folderPath(kalp.id).map(\.name), ["Fizyoloji", "Kalp"])

        archive.moveFolder(fizyoloji.id, toParent: kalp.id)
        XCTAssertNil(archive.folder(fizyoloji.id)?.parentID, "klasör kendi altına taşınamaz")

        archive.deleteFolder(kalp.id)
        XCTAssertEqual(archive.sources.count, 2)
        XCTAssertEqual(archive.source(a.id)?.folderID, fizyoloji.id, "kaynak üst klasöre geçer")

        // Klasör alanı olmayan eski arşiv açılır.
        let data = try FileArchiveStore.encoder.encode(archive)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "folders")
        let old = try FileArchiveStore.decoder.decode(Archive.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.folders, [])
    }

    func testMarkedAndHandwrittenLinesAreFlaggedInExport() throws {
        var archive = Archive()
        let (source, page) = addSource(&archive, title: "Kalp Odakları", hash: "k")
        try read(&archive, page, [
            ExtractedBlock(text: "Mitral odak", bbox: box(0.1, 0.2), marked: true),
            ExtractedBlock(text: "Normal satır", bbox: box(0.1, 0.3)),
            ExtractedBlock(kind: .handwriting, text: "soru gelebilir", bbox: box(0.5, 0.6)),
        ])
        let md = try MarkdownExporter()
            .export(archive, selections: [SourceSelection(sourceID: source.id)], mode: .combined, createdAt: Date())
            .files[0].contents
        XCTAssertTrue(md.contains("\n⭐ Mitral odak\n"))
        XCTAssertTrue(md.contains("\nNormal satır\n"))
        XCTAssertTrue(md.contains("\n✍️ soru gelebilir\n"))
        XCTAssertTrue(md.contains("⭐ ile başlayan satırların yanına elle işaret"))
        XCTAssertTrue(md.contains("✍️ öğrencinin el notudur"))
    }

    func testHandwritingNoteIsExportedAsImageWithReading() throws {
        var archive = Archive()
        let (source, page) = addSource(&archive, title: "Sınıflandırma", hash: "s")
        let note = box(0.5, 0.1, 0.4, 0.15)
        try read(&archive, page, [
            ExtractedBlock(text: "Enzim sınıfları", bbox: box(0.1, 0.4)),
            ExtractedBlock(kind: .handwriting, text: "SORU GELEBİLİR, bunu mutlaka çalış dedi hocamız",
                           bbox: box(0.52, 0.12, 0.35, 0.08)),
        ])
        archive.applyFigureSuggestions([FigureSuggestion(
            bbox: note, labels: [FigureLabel(text: "SORU GELEBİLİR, bunu mutlaka çalış dedi hocamız",
                                             bbox: box(0.52, 0.12, 0.35, 0.08))],
            kind: .handwriting)], pageID: page.id, at: Date())
        let figure = try XCTUnwrap(archive.figures(of: page.id).first)
        XCTAssertEqual(figure.kind, .handwriting)
        try archive.acceptFigure(figure.id, bbox: note, imageRef: "figures/n.jpg")

        let result = try MarkdownExporter(includeFigureImages: true)
            .export(archive, selections: [SourceSelection(sourceID: source.id)], mode: .combined, createdAt: Date())
        let md = result.files[0].contents
        XCTAssertTrue(md.contains("![El notu 1](figures/"))
        XCTAssertTrue(md.contains("_El notu 1 okunuşu (tahmini): ✍️ SORU GELEBİLİR, bunu mutlaka çalış dedi hocamız_"))
        XCTAssertEqual(md.components(separatedBy: "SORU GELEBİLİR").count - 1, 1, "not metni iki kez yazılmamalı")
        XCTAssertEqual(result.manifest.figures?.first?.kind, "handwriting")
    }

    func testImageOnlyPagesExportPageImageInsteadOfText() throws {
        var archive = Archive()
        let (messy, messyPage) = addSource(&archive, title: "El notları", hash: "m")
        let (clean, cleanPage) = addSource(&archive, title: "Slayt", hash: "c")
        try read(&archive, messyPage, [ExtractedBlock(kind: .handwriting, text: "okunmaz karalama", bbox: box(0.1, 0.1))])
        try read(&archive, cleanPage, [ExtractedBlock(text: "temiz metin", bbox: box(0.1, 0.5))])
        archive.setAnalysis(handwritingShare: 0.9, looksComplex: true, forPage: messyPage.id)
        archive.setAnalysis(handwritingShare: 0, looksComplex: false, forPage: cleanPage.id)

        let selections = [SourceSelection(sourceID: messy.id), SourceSelection(sourceID: clean.id)]
        var result = try MarkdownExporter().export(archive, selections: selections, mode: .combined, createdAt: Date())
        var md = result.files[0].contents
        XCTAssertFalse(md.contains("okunmaz karalama"))
        XCTAssertTrue(md.contains("Bu sayfa görsel olarak aktarıldı"))
        XCTAssertTrue(md.contains("temiz metin"))
        XCTAssertEqual(result.assets.map(\.imageRef), ["originals/m.png"])
        XCTAssertEqual(result.manifest.imageOnlyPages?.count, 1)

        // Kullanıcı kararı uygulamanınkini geçersiz kılar.
        archive.setImageOnly(false, sources: [messy.id])
        archive.setImageOnly(true, sources: [clean.id])
        result = try MarkdownExporter().export(archive, selections: selections, mode: .combined, createdAt: Date())
        md = result.files[0].contents
        XCTAssertTrue(md.contains("okunmaz karalama"))
        XCTAssertFalse(md.contains("temiz metin"))
        XCTAssertEqual(result.assets.map(\.imageRef), ["originals/c.png"])
    }

    func testLogoRepeatedOnEverySlideIsDroppedButTitlesStay() throws {
        var archive = Archive()
        var ids: [UUID] = []
        for i in 0..<4 {
            let (source, page) = addSource(&archive, title: "Slayt \(i)", hash: "s\(i)")
            ids.append(source.id)
            try read(&archive, page, [
                ExtractedBlock(text: "TINAZTEPE", bbox: box(0.79, 0.03, 0.07, 0.02)),
                ExtractedBlock(text: i == 3 ? "ÜNİVERSİTESİ" : "UNIVERSITESI", bbox: box(0.81, 0.055, 0.04, 0.005)),
                ExtractedBlock(text: "Kalp Döngüsü", bbox: box(0.35, 0.07, 0.3, 0.05)),
                ExtractedBlock(text: "İçerik \(i)", bbox: box(0.1, 0.3)),
            ])
        }
        let md = try MarkdownExporter()
            .export(archive, selections: ids.map { SourceSelection(sourceID: $0) }, mode: .combined, createdAt: Date())
            .files[0].contents
        XCTAssertFalse(md.contains("TINAZTEPE"))
        XCTAssertFalse(md.contains("UNIVERSITESI"))
        XCTAssertFalse(md.contains("ÜNİVERSİTESİ"))
        XCTAssertEqual(md.components(separatedBy: "Kalp Döngüsü").count - 1, 4, "ortadaki başlık her slaytta kalır")
        XCTAssertTrue(md.contains("İçerik 3"))
    }

    /// Ölçüm paketindeki PDF: her sayfada "Fizyoloji · Temize geçirilmiş sorular N" alt bilgisi ve sayfa numarası.
    /// Alt bilgi tek bir kaynağın sayfalarında tekrar etse de atılır; sayfa başındaki "Soru N" kalır.
    func testRepeatedPDFFooterAndPageNumbersAreDroppedButQuestionHeadingsStay() throws {
        var archive = Archive()
        let source = SourceAsset(mediaType: .pdf, originalFilename: "sorular.pdf", sourceTitle: "Sorular",
                                 contentHash: "p", localAssetRef: "originals/p.pdf", importedAt: Date())
        archive.importSource(source, pageSizes: Array(repeating: (595, 842), count: 6))
        for (i, page) in archive.pages(of: source.id).enumerated() {
            let footer = i < 3
                ? [ExtractedBlock(text: "Fizyoloji · Temize geçirilmiş sorular \(i + 1)", bbox: box(0.3, 0.96, 0.4, 0.015))]
                : [ExtractedBlock(text: "Fizyoloji · Temize geçirilmiş sorular", bbox: box(0.1, 0.96, 0.18, 0.015)),
                   ExtractedBlock(text: "\(i + 1)", bbox: box(0.91, 0.96, 0.02, 0.015))]
            try read(&archive, page, [
                ExtractedBlock(text: "Soru \(i + 1)", bbox: box(0.1, 0.06, 0.06, 0.02)),
                ExtractedBlock(text: "Soru metni \(i + 1)", bbox: box(0.1, 0.3)),
            ] + footer)
        }
        let md = try MarkdownExporter()
            .export(archive, selections: [SourceSelection(sourceID: source.id)], mode: .combined, createdAt: Date())
            .files[0].contents
        XCTAssertFalse(md.contains("Temize geçirilmiş"))
        XCTAssertFalse(md.contains("\n5\n"))
        for i in 1...6 {
            XCTAssertTrue(md.contains("Soru \(i)\n"), "Soru \(i) başlığı kalmalı")
            XCTAssertTrue(md.contains("Soru metni \(i)"))
        }
    }

    func testAutomaticTitleComesFromFirstReadLineAndStaysUnique() throws {
        var archive = Archive()
        var ids: [UUID] = []
        for i in 0..<2 {
            let (source, page) = addSource(&archive, title: "Görsel 12 Eki 00:57", hash: "t\(i)")
            archive.adoptAutoTitles([source.id])   // henüz okunmadı: başlık değişmez
            XCTAssertEqual(archive.source(source.id)?.sourceTitle, "Görsel 12 Eki 00:57")
            try read(&archive, page, [
                ExtractedBlock(text: "hayan Tamenter", bbox: box(0.04, 0.0, 0.2, 0.03)),       // üst kenarda kesik
                ExtractedBlock(text: "TINAZTEPE", bbox: box(0.79, 0.01, 0.07, 0.03)),           // köşe logosu
                ExtractedBlock(kind: .handwriting, text: "soru gelir", bbox: box(0.1, 0.05)),
                ExtractedBlock(text: "• Hızlı cevap AP'nin dönemleri", bbox: box(0.26, 0.08, 0.5, 0.07)),
                ExtractedBlock(text: "Faz 0: Depolarizasyon", bbox: box(0.16, 0.2)),
            ])
            archive.refreshAutoTitle(source.id)
            ids.append(source.id)
        }
        XCTAssertEqual(archive.source(ids[0])?.sourceTitle, "Hızlı cevap AP'nin dönemleri")
        XCTAssertEqual(archive.source(ids[1])?.sourceTitle, "Hızlı cevap AP'nin dönemleri (2)")

        // Kullanıcının verdiği ad yeniden okumada korunur; aynı adla "yeniden adlandırma" bayrağı silmez.
        archive.renameSource(ids[1], to: "Hızlı cevap AP'nin dönemleri (2)")
        XCTAssertEqual(archive.source(ids[1])?.autoTitle, true)
        archive.renameSource(ids[1], to: "Kalp AP")
        XCTAssertNil(archive.source(ids[1])?.autoTitle)
        archive.refreshAutoTitle(ids[1])
        XCTAssertEqual(archive.source(ids[1])?.sourceTitle, "Kalp AP")
    }

    func testPromptIsPlacedAtTopOfFile() throws {
        var archive = Archive()
        let (source, page) = addSource(&archive, title: "Glikoliz", hash: "g")
        try read(&archive, page, [ExtractedBlock(text: "Hekzokinaz", bbox: box(0.1, 0.3))])
        let template = try XCTUnwrap(PromptLibrary.template(id: "anki-tsv"))
        let result = try MarkdownExporter(prompt: template,
                                          promptContext: PromptContext(deckName: "DersArşivi::Biyokimya"))
            .export(archive, selections: [SourceSelection(sourceID: source.id)], mode: .combined, createdAt: Date())
        let md = result.files[0].contents
        let instruction = try XCTUnwrap(md.range(of: "## Yapay zekâya talimat"))
        let content = try XCTUnwrap(md.range(of: "Hekzokinaz"))
        XCTAssertLessThan(instruction.lowerBound, content.lowerBound)
        XCTAssertTrue(md.contains("#deck:DersArşivi::Biyokimya"))
        XCTAssertEqual(result.manifest.prompt, "anki-tsv")
    }
}
