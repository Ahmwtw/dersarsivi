import Foundation
import XCTest
@testable import DersArsiviCore

final class SHA256Tests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(SHA256Hasher.hexDigest(Data()),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Hasher.hexDigest(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            SHA256Hasher.hexDigest(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }
}

final class PageSelectionTests: XCTestCase {
    func testParsesPagesAndRangesToZeroBasedIndices() throws {
        let s = try PageSelection.parse("3, 7-9", pageCount: 12)
        XCTAssertEqual(s.indices, [2, 6, 7, 8])
        XCTAssertEqual(s.displayText, "3, 7–9")
    }

    func testDeduplicatesAndSortsAndAcceptsEnDash() throws {
        let s = try PageSelection.parse("9; 7–8, 3, 8", pageCount: 9)
        XCTAssertEqual(s.indices, [2, 6, 7, 8])
    }

    func testRejectsInvalidInput() {
        XCTAssertThrowsError(try PageSelection.parse("", pageCount: 5)) {
            XCTAssertEqual($0 as? PageSelection.ParseError, .empty)
        }
        XCTAssertThrowsError(try PageSelection.parse("0", pageCount: 5)) {
            XCTAssertEqual($0 as? PageSelection.ParseError, .outOfRange(page: 0, pageCount: 5))
        }
        XCTAssertThrowsError(try PageSelection.parse("4-6", pageCount: 5)) {
            XCTAssertEqual($0 as? PageSelection.ParseError, .outOfRange(page: 6, pageCount: 5))
        }
        XCTAssertThrowsError(try PageSelection.parse("5-3", pageCount: 5)) {
            XCTAssertEqual($0 as? PageSelection.ParseError, .reversedRange("5-3"))
        }
        XCTAssertThrowsError(try PageSelection.parse("a", pageCount: 5))
    }
}

/// Testlerde ortak arşiv kurulumu.
private func makeArchive(pageCount: Int = 1, mediaType: MediaType = .image,
                         title: String = "Kalp siklusu slaytı") -> (Archive, SourceAsset) {
    var archive = Archive()
    let source = SourceAsset(mediaType: mediaType, originalFilename: "IMG_0001.jpg", sourceTitle: title,
                             contentHash: SHA256Hasher.hexDigest(Data(title.utf8)),
                             localAssetRef: "originals/x.jpg", importedAt: Date(timeIntervalSince1970: 0))
    archive.importSource(source, pageSizes: Array(repeating: (width: 1000.0, height: 1400.0), count: pageCount))
    return (archive, source)
}

private func makeRun(for page: Page, hash: String) -> ExtractionRun {
    ExtractionRun(pageID: page.id, sourceContentHash: hash, engine: "test-ocr", engineVersion: "1",
                  configHash: "c1", startedAt: Date(timeIntervalSince1970: 1),
                  finishedAt: Date(timeIntervalSince1970: 2))
}

final class ArchiveTests: XCTestCase {
    func testDuplicateImportIsDetectedByContentHashNotFilename() {
        var (archive, source) = makeArchive()
        var copy = source
        copy.id = UUID()
        copy.originalFilename = "baska-ad.jpg"
        XCTAssertEqual(archive.importSource(copy, pageSizes: [(1, 1)]), .duplicate(existing: source))
        XCTAssertEqual(archive.sources.count, 1)
    }

    func testCorrectionIsRecordedAsNewRevision() throws {
        var (archive, source) = makeArchive()
        let page = archive.pages(of: source.id)[0]
        try archive.applyExtraction([ExtractedBlock(text: "Sistol: ventrikül kasılır", confidence: 0.9)],
                                    run: makeRun(for: page, hash: source.contentHash))
        let block = archive.blocks(of: page.id)[0]

        try archive.correct(blockID: block.id, newText: "Sistol: ventriküller kasılır",
                            at: Date(timeIntervalSince1970: 10))

        let updated = archive.blocks(of: page.id)[0]
        XCTAssertEqual(updated.acceptedText, "Sistol: ventriküller kasılır")
        XCTAssertEqual(updated.rawText, "Sistol: ventrikül kasılır")
        XCTAssertEqual(updated.origin, .user)
        XCTAssertEqual(updated.revision, 2)
        XCTAssertEqual(updated.reviewStatus, .humanVerified)
        XCTAssertEqual(archive.corrections(of: block.id).map(\.previousText), ["Sistol: ventrikül kasılır"])
    }

    func testReExtractionNeverOverwritesUserCorrection() throws {
        var (archive, source) = makeArchive()
        let page = archive.pages(of: source.id)[0]
        try archive.applyExtraction([ExtractedBlock(text: "Metoprolol 5O mg"), ExtractedBlock(text: "ikinci")],
                                    run: makeRun(for: page, hash: source.contentHash))
        let first = archive.blocks(of: page.id)[0]
        try archive.correct(blockID: first.id, newText: "Metoprolol 50 mg", at: Date())

        try archive.applyExtraction([ExtractedBlock(text: "Metoprolol 5O mq"), ExtractedBlock(text: "ikinci yeni")],
                                    run: makeRun(for: page, hash: source.contentHash))

        let blocks = archive.blocks(of: page.id)
        XCTAssertEqual(blocks[0].acceptedText, "Metoprolol 50 mg")
        XCTAssertEqual(blocks[0].rawText, "Metoprolol 5O mq")
        XCTAssertEqual(blocks[0].reviewStatus, .conflict)
        XCTAssertEqual(blocks[1].acceptedText, "ikinci yeni")
        XCTAssertEqual(archive.pages(of: source.id)[0].status, .needsReview)
    }

    func testCorrectedBlockMissingFromNewExtractionIsKeptAsConflict() throws {
        var (archive, source) = makeArchive()
        let page = archive.pages(of: source.id)[0]
        try archive.applyExtraction([ExtractedBlock(text: "a"), ExtractedBlock(text: "b")],
                                    run: makeRun(for: page, hash: source.contentHash))
        let second = archive.blocks(of: page.id)[1]
        try archive.correct(blockID: second.id, newText: "B düzeltildi", at: Date())

        try archive.applyExtraction([ExtractedBlock(text: "a")], run: makeRun(for: page, hash: source.contentHash))

        let blocks = archive.blocks(of: page.id)
        XCTAssertEqual(blocks.map(\.acceptedText), ["a", "B düzeltildi"])
        XCTAssertEqual(blocks[1].reviewStatus, .conflict)
    }

    func testCachedRunIsFoundBySameKey() throws {
        var (archive, source) = makeArchive()
        let page = archive.pages(of: source.id)[0]
        let r = makeRun(for: page, hash: source.contentHash)
        try archive.applyExtraction([ExtractedBlock(text: "x")], run: r)
        XCTAssertEqual(archive.cachedRun(cacheKey: r.cacheKey)?.id, r.id)
        XCTAssertNil(archive.cachedRun(cacheKey: r.cacheKey + "-baska-ayar"))
    }

    func testRemovingSourceDeletesEverythingItOwnsAndReturnsItsFiles() throws {
        var (archive, source) = makeArchive()
        let page = archive.pages(of: source.id)[0]
        archive.jobQueue.enqueue(pageID: page.id, at: Date())
        try archive.applyExtraction([ExtractedBlock(text: "Aort")], run: makeRun(for: page, hash: source.contentHash))
        try archive.correct(blockID: archive.blocks(of: page.id)[0].id, newText: "Aorta", at: Date())
        archive.setWorkingImage("pages/p.jpg", forPage: page.id)
        archive.applyFigureSuggestions([FigureSuggestion(bbox: BoundingBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5))],
                                       pageID: page.id, at: Date())
        let figureID = try XCTUnwrap(archive.figures(of: page.id).first?.id)
        try archive.acceptFigure(figureID, bbox: BoundingBox(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                                 imageRef: "figures/f.jpg")

        let (_, otherSource) = makeArchive(title: "Başka slayt")
        archive.importSource(otherSource, pageSizes: [(10, 10)])

        let files = archive.removeSource(source.id)
        XCTAssertEqual(Set(files), ["originals/x.jpg", "pages/p.jpg", "figures/f.jpg"])
        XCTAssertEqual(archive.sources.map(\.id), [otherSource.id])
        XCTAssertTrue(archive.pages(of: source.id).isEmpty)
        XCTAssertTrue(archive.blocks.isEmpty)
        XCTAssertTrue(archive.corrections.isEmpty)
        XCTAssertTrue(archive.extractionRuns.isEmpty)
        XCTAssertTrue(archive.figures.isEmpty)
        XCTAssertTrue(archive.jobQueue.jobs.isEmpty)
        // Silinen görsel aynı içerikle yeniden eklenebilir.
        XCTAssertEqual(archive.importSource(source, pageSizes: [(1, 1)]), .added(source))
    }
}

final class StoreTests: XCTestCase {
    func testArchiveAndCorrectionSurviveSaveAndReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileArchiveStore(rootURL: dir)

        let (ref, hash) = try store.storeOriginal(Data("görsel baytları".utf8), id: UUID(), fileExtension: "JPG")
        XCTAssertTrue(ref.hasPrefix("originals/"))
        XCTAssertTrue(ref.hasSuffix(".jpg"))

        var archive = Archive()
        let source = SourceAsset(mediaType: .image, originalFilename: "a.jpg", sourceTitle: "Spot kutusu",
                                 contentHash: hash, localAssetRef: ref, importedAt: Date(timeIntervalSince1970: 100))
        archive.importSource(source, pageSizes: [(10, 10)])
        let page = archive.pages(of: source.id)[0]
        archive.jobQueue.enqueue(pageID: page.id, at: Date(timeIntervalSince1970: 100))
        try archive.applyExtraction([ExtractedBlock(text: "ışık ğ ü ş İ ö ç")], run: makeRun(for: page, hash: hash))
        try archive.correct(blockID: archive.blocks(of: page.id)[0].id, newText: "Işık ĞÜŞİÖÇ",
                            at: Date(timeIntervalSince1970: 200))
        try store.save(archive)

        let reloaded = try FileArchiveStore(rootURL: dir).load()
        XCTAssertEqual(reloaded, archive)
        XCTAssertEqual(reloaded.blocks(of: page.id)[0].acceptedText, "Işık ĞÜŞİÖÇ")
        XCTAssertEqual(reloaded.jobQueue.pending.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(forRef: ref).path))
    }

    func testRemoveFileStaysInsideArchiveFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileArchiveStore(rootURL: dir)
        let (ref, _) = try store.storeOriginal(Data("x".utf8), id: UUID(), fileExtension: "png")
        let outside = dir.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".txt")
        try Data("dışarıda".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        store.removeFile(ref: "../" + outside.lastPathComponent)
        store.removeFile(ref: outside.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        store.removeFile(ref: ref)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(forRef: ref).path))
    }

    func testMissingArchiveLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(try FileArchiveStore(rootURL: dir).load(), Archive())
    }
}

final class JobQueueTests: XCTestCase {
    func testInterruptedJobIsRequeuedAndRetriesAreBounded() {
        var q = JobQueue(maxAttempts: 2)
        let page = UUID()
        let job = q.enqueue(pageID: page, at: Date())
        XCTAssertEqual(q.enqueue(pageID: page, at: Date()).id, job.id, "aynı sayfa için ikinci iş açılmamalı")

        _ = q.claimNext(at: Date())
        q.recoverInterrupted(at: Date())
        XCTAssertEqual(q.jobs[0].state, .queued)

        _ = q.claimNext(at: Date())
        q.fail(jobID: job.id, error: "zaman aşımı", at: Date())
        XCTAssertEqual(q.jobs[0].state, .failed)
        XCTAssertEqual(q.jobs[0].attempts, 2)
        XCTAssertNil(q.claimNext(at: Date()))
    }

    func testForcedReReadIsMarkedEvenWhenAJobIsAlreadyWaiting() {
        var q = JobQueue()
        let page = UUID()
        XCTAssertNil(q.enqueue(pageID: page, at: Date()).force)
        XCTAssertEqual(q.enqueue(pageID: page, at: Date(), force: true).force, true)
        XCTAssertEqual(q.claimNext(at: Date())?.force, true)
        q.complete(jobID: q.jobs[0].id, at: Date())
        XCTAssertEqual(q.enqueue(pageID: page, at: Date(), force: true).force, true, "biten işten sonra yeni iş açılır")
        q.remove(pageIDs: [page])
        XCTAssertTrue(q.jobs.isEmpty)
    }
}

final class MarkdownExporterTests: XCTestCase {
    func testExportUsesCorrectionAndMarksUncertainty() throws {
        var (archive, source) = makeArchive()
        let page = archive.pages(of: source.id)[0]
        try archive.applyExtraction([ExtractedBlock(text: "Mitral kapak kapanır", confidence: 0.95),
                                     ExtractedBlock(text: "S1 ses?", confidence: 0.3)],
                                    run: makeRun(for: page, hash: source.contentHash))
        try archive.correct(blockID: archive.blocks(of: page.id)[0].id, newText: "Mitral ve triküspit kapanır",
                            at: Date())

        let result = try MarkdownExporter().export(archive, selections: [SourceSelection(sourceID: source.id)],
                                                   mode: .combined, createdAt: Date(timeIntervalSince1970: 0))
        let md = result.files[0].contents
        XCTAssertTrue(md.contains("## Kaynak: Kalp siklusu slaytı"))
        XCTAssertTrue(md.contains(source.id.uuidString.lowercased()))
        XCTAssertTrue(md.contains("Mitral ve triküspit kapanır ✏️"))
        XCTAssertFalse(md.contains("Mitral kapak kapanır"))
        XCTAssertTrue(md.contains("> ⚠️ Belirsiz: OCR güveni düşük (%30)"))
        XCTAssertEqual(result.manifest.sources[0].uncertainBlockCount, 1)
        XCTAssertFalse(result.manifest.partialExport)
    }

    func testUnprocessedSelectedPagesAreReportedNotDropped() throws {
        var (archive, source) = makeArchive(pageCount: 10, mediaType: .pdf, title: "Biyokimya PDF")
        let pages = archive.pages(of: source.id)
        try archive.applyExtraction([ExtractedBlock(text: "Glikoliz")], run: makeRun(for: pages[2], hash: source.contentHash))
        try archive.setStatus(.failed, forPage: pages[7].id, failureReason: "zaman aşımı")

        let selection = try PageSelection.parse("3, 7-9", pageCount: 10)
        let result = try MarkdownExporter().export(
            archive, selections: [SourceSelection(sourceID: source.id, pageIndices: selection.indices)],
            mode: .combined, createdAt: Date())
        let md = result.files[0].contents
        let entry = result.manifest.sources[0]

        XCTAssertTrue(md.contains("- Seçili sayfalar: 3, 7–9 / 10"))
        XCTAssertTrue(md.contains("### Sayfa 3\n\nGlikoliz"))
        XCTAssertFalse(md.contains("### Sayfa 4"))
        XCTAssertTrue(md.contains("durum: failed: zaman aşımı"))
        XCTAssertEqual(entry.includedPageIndices, [2])
        XCTAssertEqual(entry.missingPages.map(\.pageIndex), [6, 7, 8])
        XCTAssertTrue(result.manifest.partialExport)
        XCTAssertTrue(md.contains("> **Eksik içerik:**"))
    }

    func testPerSourceExportCreatesOneFilePerSourceWithSafeNames() throws {
        var (archive, a) = makeArchive(title: "Kalp siklusu slaytı")
        let b = SourceAsset(mediaType: .image, originalFilename: "b.png", sourceTitle: "Çıkmış soru / 2024",
                            contentHash: "h2", localAssetRef: "originals/b.png", importedAt: Date())
        archive.importSource(b, pageSizes: [(1, 1)])

        let result = try MarkdownExporter().export(
            archive, selections: [SourceSelection(sourceID: a.id), SourceSelection(sourceID: b.id)],
            mode: .perSource, createdAt: Date())
        XCTAssertEqual(result.files.count, 2)
        XCTAssertTrue(result.files[0].name.hasPrefix("kalp-siklusu-slayti-"))
        XCTAssertTrue(result.files[1].name.hasPrefix("cikmis-soru-2024-"))
        XCTAssertEqual(result.manifest.sources.map(\.file), result.files.map(\.name))
    }

    func testOCRTextCannotInjectMarkdownHeadingsOrHTML() {
        XCTAssertEqual(MarkdownExporter.escape("# Başlık değil\n<script>x</script>"),
                       "\\# Başlık değil\n&lt;script&gt;x&lt;/script&gt;")
    }

    func testManifestRoundTripsAsJSON() throws {
        let (archive, source) = makeArchive()
        let result = try MarkdownExporter().export(archive, selections: [SourceSelection(sourceID: source.id)],
                                                   mode: .combined, createdAt: Date(timeIntervalSince1970: 0))
        let data = try FileArchiveStore.encoder.encode(result.manifest)
        XCTAssertEqual(try FileArchiveStore.decoder.decode(ExportManifest.self, from: data), result.manifest)
    }
}
