import DersArsiviCore
import Foundation
import ImageIO
import UIKit

/// Uygulamanın tek durum kaynağı. Arşivi diske yazar, çıkarım kuyruğunu ön planda işler.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var archive = Archive()
    @Published var lastError: String?
    @Published private(set) var isProcessing = false

    let store: FileArchiveStore
    private let extractor = VisionTextExtractor()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = FileArchiveStore(rootURL: base.appendingPathComponent("DersArsivi", isDirectory: true))
        do {
            archive = try store.load()
        } catch {
            lastError = "Arşiv açılamadı: \(error.localizedDescription)"
        }
        // Uygulama işlem sırasında kapandıysa yarım kalan işler yeniden sıraya girer.
        archive.jobQueue.recoverInterrupted(at: Date())
        persist()
    }

    // MARK: İçeri alma

    /// Görseli orijinal baytlarıyla saklar, sayfa olarak ekler ve OCR kuyruğuna koyar.
    func importImage(data: Data, filename: String, folderID: UUID? = nil) {
        guard let image = UIImage(data: data) else {
            lastError = "\(filename) bir görsel olarak açılamadı."
            return
        }
        let id = UUID()
        do {
            let hash = SHA256Hasher.hexDigest(data)
            if let existing = archive.source(withContentHash: hash) {
                lastError = "Bu görsel zaten arşivde: \(existing.sourceTitle)"
                return
            }
            let ext = (filename as NSString).pathExtension.isEmpty ? "jpg" : (filename as NSString).pathExtension
            let stored = try store.storeOriginal(data, id: id, fileExtension: ext)
            let title = Self.defaultTitle(for: filename)
            var source = SourceAsset(id: id, mediaType: .image, originalFilename: filename, sourceTitle: title,
                                     contentHash: stored.hash, localAssetRef: stored.ref, importedAt: Date())
            source.folderID = folderID
            archive.importSource(source, pageSizes: [(Double(image.size.width), Double(image.size.height))])
            for page in archive.pages(of: id) {
                archive.jobQueue.enqueue(pageID: page.id, at: Date())
                try archive.setStatus(.queued, forPage: page.id)
            }
            persist()
            processQueue()
        } catch {
            lastError = "İçeri alma başarısız: \(error.localizedDescription)"
        }
    }

    /// PDF'i saklar ve sayfalarını ekler. `pages` verilirse yalnız o sayfalar okunur; diğerleri sonra okunabilir.
    func importPDF(data: Data, filename: String, pages wanted: [Int]? = nil, folderID: UUID? = nil) {
        guard let info = PDFSupport.info(data: data) else {
            lastError = "\(filename) bir PDF olarak açılamadı (şifreli veya bozuk olabilir)."
            return
        }
        let id = UUID()
        do {
            let hash = SHA256Hasher.hexDigest(data)
            if let existing = archive.source(withContentHash: hash) {
                lastError = "Bu PDF zaten arşivde: \(existing.sourceTitle)"
                return
            }
            let stored = try store.storeOriginal(data, id: id, fileExtension: "pdf")
            var source = SourceAsset(id: id, mediaType: .pdf, originalFilename: filename,
                                     sourceTitle: Self.defaultTitle(for: filename), contentHash: stored.hash,
                                     localAssetRef: stored.ref, importedAt: Date())
            source.folderID = folderID
            archive.importSource(source, pageSizes: info.sizes, pdfPageLabels: info.labels)
            let selected = wanted.map(Set.init)
            for page in archive.pages(of: id) where selected?.contains(page.pageIndex) ?? true {
                archive.jobQueue.enqueue(pageID: page.id, at: Date())
                try archive.setStatus(.queued, forPage: page.id)
            }
            persist()
            processQueue()
        } catch {
            lastError = "İçeri alma başarısız: \(error.localizedDescription)"
        }
    }

    /// Okunmamış sayfaları (PDF'te seçilmeyenler) sıraya koyar.
    func readPages(_ pageIDs: [UUID]) {
        for id in pageIDs {
            archive.jobQueue.enqueue(pageID: id, at: Date())
            try? archive.setStatus(.queued, forPage: id)
        }
        persist()
        processQueue()
    }

    private static func defaultTitle(for filename: String) -> String {
        let base = (filename as NSString).deletingPathExtension
        if base.isEmpty || base.hasPrefix("IMG_") || base.hasPrefix("image") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "tr_TR")
            f.dateFormat = "d MMM HH:mm"
            return "Görsel \(f.string(from: Date()))"
        }
        return base
    }

    // MARK: Kuyruk

    /// Bekleyen işleri sırayla işler. Arka planda çalışma garanti edilmediği için
    /// uygulama her öne geldiğinde tekrar çağrılır.
    func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            defer { isProcessing = false }
            while let job = archive.jobQueue.claimNext(at: Date()) {
                persist()
                await run(job)
                persist()
            }
        }
    }

    private func run(_ job: ExtractionJob) async {
        guard let page = archive.pages.first(where: { $0.id == job.pageID }),
              let source = archive.source(page.sourceID) else {
            archive.jobQueue.cancel(jobID: job.id, at: Date())
            return
        }
        try? archive.setStatus(.processing, forPage: page.id)

        let started = Date()
        var runRecord = ExtractionRun(pageID: page.id, sourceContentHash: source.contentHash,
                                      engine: VisionTextExtractor.engineName,
                                      engineVersion: extractor.engineVersion,
                                      configHash: extractor.configHash, startedAt: started)
        do {
            // "Yeniden oku" (force) aynı ayarla yapılmış eski sonucu kullanmaz, görüntüyü baştan okur.
            if job.force != true, archive.cachedRun(cacheKey: runRecord.cacheKey) != nil,
               !archive.blocks(of: page.id).isEmpty {
                archive.jobQueue.complete(jobID: job.id, at: Date())
                try archive.setStatus(.ready, forPage: page.id)
                return
            }
            if source.mediaType == .pdf {
                try await runPDF(page: page, source: source, job: job, run: &runRecord)
                return
            }
            guard let image = loadImage(ref: source.localAssetRef) else {
                throw ExtractionFailure.originalMissing
            }
            var input = image
            var working: CGImage?
            // Ekran görüntüleri (PNG) zaten düzdür; içlerindeki eğik fotoğraflar yüzünden döndürülmez.
            let isScreenshot = (source.originalFilename as NSString).pathExtension.lowercased() == "png"
            // Eğik çekilmiş sayfa fotoğrafı: önce sayfa köşelerinden perspektif düzeltilir.
            if !isScreenshot, let flat = await Task.detached(priority: .userInitiated, operation: {
                PagePreparer.rectify(image.cgImage, orientation: image.orientation)
            }).value {
                working = flat
                input = (flat, .up)
            }
            var output = try await extractor.extract(from: input.cgImage, orientation: input.orientation)
            // Köşeler bulunamadıysa ama satırlar hâlâ eğikse görüntü döndürülüp bir kez daha okunur.
            let skew = output.skewDegrees
            if !isScreenshot, abs(skew) >= PagePreparer.minSkewDegrees {
                let current = input
                if let straight = await Task.detached(priority: .userInitiated, operation: {
                    PagePreparer.rotate(current.cgImage, orientation: current.orientation,
                                        degrees: -skew)
                }).value {
                    working = straight
                    input = (straight, .up)
                    output = try await extractor.extract(from: straight, orientation: .up)
                }
            }
            // Okuma sürerken kaynak silindiyse sonuç bırakılır.
            guard archive.pages.contains(where: { $0.id == page.id }) else {
                archive.jobQueue.cancel(jobID: job.id, at: Date())
                return
            }
            try storeWorkingImage(working, pageID: page.id)
            try await apply(output, page: page, job: job, run: &runRecord)
        } catch {
            let message = (error as? ExtractionFailure)?.message ?? error.localizedDescription
            archive.jobQueue.fail(jobID: job.id, error: message, at: Date())
            let failed = archive.jobQueue.jobs.first { $0.id == job.id }?.state == .failed
            try? archive.setStatus(failed ? .failed : .queued, forPage: page.id, failureReason: message)
        }
    }

    /// Okuma sonucunu arşive yazar: metin, sayfa alanı, satırlar, çözümleme ve şekil önerileri.
    private func apply(_ output: ExtractionOutput, page: Page, job: ExtractionJob, run runRecord: inout ExtractionRun) async throws {
        scanCache[page.id] = nil
        runRecord.finishedAt = Date()
        try archive.applyExtraction(output.blocks, run: runRecord)
        archive.setContentBox(output.content, forPage: page.id)
        archive.setAnalysis(handwritingShare: output.handwritingShare, looksComplex: output.looksComplex,
                            forPage: page.id)
        try? store.storeLines(output.lines, pageID: page.id)
        archive.applyFigureSuggestions(output.figures, pageID: page.id, at: Date())
        // Ayar açıksa öneriler onay beklemeden kaydedilir; kullanıcı yalnız hatalıları düzeltir. El notları
        // her zaman görüntü olarak saklanır: metne dökülmeleri güvenilir değildir.
        let autoSave = UserDefaults.standard.bool(forKey: Self.autoSaveFiguresKey)
        for figure in archive.figures(of: page.id) where figure.status == .suggested {
            if autoSave || figure.isHandwriting { await saveFigure(figure.id, bbox: figure.bbox) }
        }
        archive.jobQueue.complete(jobID: job.id, at: Date())
    }

    /// PDF sayfası: önce görüntüsü üretilir (galeri, şekiller, dışa aktarım için). Metin katmanı varsa metin
    /// oradan alınır; taranmış sayfa OCR ile okunur.
    private func runPDF(page: Page, source: SourceAsset, job: ExtractionJob, run runRecord: inout ExtractionRun) async throws {
        let pdfURL = store.url(forRef: source.localAssetRef)
        guard FileManager.default.fileExists(atPath: pdfURL.path) else { throw ExtractionFailure.originalMissing }
        let index = page.pageIndex
        var image: CGImage?
        if let ref = page.workingImageRef { image = loadImage(ref: ref)?.cgImage }
        if image == nil {
            image = await Task.detached(priority: .userInitiated) { PDFSupport.render(url: pdfURL, pageIndex: index) }.value
            guard let rendered = image else { throw ExtractionFailure.originalMissing }
            try storeWorkingImage(rendered, pageID: page.id)
        }
        guard let image else { throw ExtractionFailure.originalMissing }
        let textLayer = await Task.detached(priority: .userInitiated) {
            PDFSupport.textLines(url: pdfURL, pageIndex: index)
        }.value
        let output = textLayer.isEmpty
            ? try await extractor.extract(from: image, orientation: .up)
            : await extractor.finish(textLayer: textLayer, image: image)
        guard archive.pages.contains(where: { $0.id == page.id }) else {
            archive.jobQueue.cancel(jobID: job.id, at: Date())
            return
        }
        try await apply(output, page: page, job: job, run: &runRecord)
    }

    /// Düzleştirilmiş görüntüyü saklar (nil ise sayfa orijinali kullanır); eskisini siler.
    private func storeWorkingImage(_ image: CGImage?, pageID: UUID) throws {
        var ref: String?
        if let image, let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) {
            ref = try store.storePageImage(data)
        }
        if let old = archive.setWorkingImage(ref, forPage: pageID) { store.removeDerived(ref: old) }
    }

    enum ExtractionFailure: Error {
        case originalMissing
        var message: String { "Orijinal dosya bulunamıyor" }
    }

    private func loadImage(ref: String) -> (cgImage: CGImage, orientation: CGImagePropertyOrientation)? {
        guard let image = UIImage(contentsOfFile: store.url(forRef: ref).path), let cg = image.cgImage else {
            return nil
        }
        return (cg, CGImagePropertyOrientation(image.imageOrientation))
    }

    /// Kullanıcının "Yeniden oku" isteği: önbellek atlanır, sayfa baştan okunur.
    /// Kaydedilmiş ve yoksayılmış şekiller korunur; yalnız bekleyen öneriler yenilenir.
    func retry(pageID: UUID) {
        archive.jobQueue.enqueue(pageID: pageID, at: Date(), force: true)
        try? archive.setStatus(.queued, forPage: pageID)
        persist()
        processQueue()
    }

    /// Kaynağı ve ona ait tüm dosyaları (orijinal, düzleştirilmiş sayfa, kırpımlar) siler.
    func deleteSources(_ ids: [UUID]) {
        for id in ids {
            for ref in archive.removeSource(id) { store.removeFile(ref: ref) }
        }
        persist()
    }

    // MARK: Düzeltme ve başlık

    func correct(blockID: UUID, text: String) {
        do {
            try archive.correct(blockID: blockID, newText: text, at: Date())
            persist()
        } catch {
            lastError = "Düzeltme kaydedilemedi: \(error.localizedDescription)"
        }
    }

    func rename(sourceID: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        archive.renameSource(sourceID, to: trimmed)
        persist()
    }

    func originalURL(for source: SourceAsset) -> URL {
        store.url(forRef: source.localAssetRef)
    }

    /// Sayfanın okunan görüntüsü: düzleştirilmiş türev varsa o, yoksa orijinal. Kutular bu görüntüye göredir.
    /// Okunmamış PDF sayfasında PDF'in kendisi, sayfa numarası URL parçasında (`#page=N`) döner;
    /// `ThumbnailLoader` bunu tanır.
    func pageImageURL(for page: Page) -> URL? {
        if let ref = page.workingImageRef { return store.url(forRef: ref) }
        guard let source = archive.source(page.sourceID) else { return nil }
        let url = originalURL(for: source)
        return source.mediaType == .pdf ? PDFSupport.pageURL(url, pageIndex: page.pageIndex) : url
    }

    // MARK: Klasörler ve görsel olarak aktarma

    @discardableResult
    func createFolder(name: String, parentID: UUID? = nil) -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = archive.createFolder(name: trimmed, parentID: parentID, at: Date())
        persist()
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        archive.renameFolder(id, to: trimmed)
        persist()
    }

    /// Klasörü siler; içindekiler (alt klasörler ve kaynaklar) bir üst klasöre geçer, hiçbir dosya silinmez.
    func deleteFolder(_ id: UUID) {
        archive.deleteFolder(id)
        persist()
    }

    func move(sources ids: [UUID], toFolder folderID: UUID?) {
        archive.move(sources: ids, toFolder: folderID)
        persist()
    }

    func moveFolder(_ id: UUID, toParent parentID: UUID?) {
        archive.moveFolder(id, toParent: parentID)
        persist()
    }

    /// true: sayfalar metin yerine görüntü olarak aktarılır; false: her zaman metin; nil: uygulama karar verir.
    func setImageOnly(_ value: Bool?, sources ids: [UUID]) {
        archive.setImageOnly(value, sources: ids)
        persist()
    }

    // MARK: Şekiller

    static let autoSaveFiguresKey = "autoSaveFigures"
    private var scanCache: [UUID: FigureDetector.PageScan] = [:]

    /// Dokun-kırp: sayfada dokunulan noktadaki şeklin kutusu.
    func findFigure(pageID: UUID, x: Double, y: Double) async -> BoundingBox? {
        guard let page = archive.pages.first(where: { $0.id == pageID }),
              let source = archive.source(page.sourceID) else { return nil }
        var lines: [FigureDetector.Line] = store.loadLines(pageID: pageID).map { ($0.text, $0.bbox) }
        if lines.isEmpty {
            // Bu sürümden önce okunmuş sayfa: satırlar yerine paragraf kutuları kullanılır.
            lines = archive.blocks(of: pageID).compactMap { b in b.bbox.map { (b.acceptedText, $0) } }
        }
        let scan: FigureDetector.PageScan
        if let cached = scanCache[pageID] {
            scan = cached
        } else {
            guard let image = loadImage(ref: page.workingImageRef ?? source.localAssetRef),
                  let made = await Task.detached(priority: .userInitiated, operation: {
                      VisionTextExtractor.pageScan(image: image.cgImage, orientation: image.orientation)
                  }).value else { return nil }
            scanCache[pageID] = made
            scan = made
        }
        let point = (x: x, y: y)
        let found = await Task.detached(priority: .userInitiated) { [lines] in
            FigureDetector.region(at: point, scan: scan, lines: lines)
        }.value
        return found?.bbox
    }

    /// Sayfadaki bekleyen önerilerin hepsini olduğu gibi kaydeder.
    func saveSuggestions(pageID: UUID) async {
        for figure in archive.figures(of: pageID) where figure.status == .suggested {
            await saveFigure(figure.id, bbox: figure.bbox)
        }
    }

    /// Arşivdeki bütün bekleyen önerileri kaydeder.
    func saveAllSuggestions() async {
        for page in archive.pages { await saveSuggestions(pageID: page.id) }
    }

    /// Sayfanın tamamını (uygulama kenarlıkları hariç) tek şekil olarak kaydeder. Karışık sayfalar için.
    func addWholePage(pageID: UUID) async {
        guard let page = archive.pages.first(where: { $0.id == pageID }) else { return }
        await addFigure(pageID: pageID, bbox: page.contentBox ?? BoundingBox(x: 0, y: 0, width: 1, height: 1))
    }

    func figureImageURL(_ figure: Figure) -> URL? {
        figure.imageRef.map { store.url(forRef: $0) }
    }

    /// Öneriyi verilen kutuyla kaydeder (veya kaydedilmiş şeklin kutusunu değiştirir): orijinalden kırpar.
    func saveFigure(_ figureID: UUID, bbox: BoundingBox) async {
        guard let figure = archive.figure(figureID) else { return }
        guard let ref = await cropAndStore(pageID: figure.pageID, bbox: bbox) else { return }
        do {
            if let old = try archive.acceptFigure(figureID, bbox: bbox, imageRef: ref) {
                store.removeDerived(ref: old)
            }
            persist()
        } catch {
            store.removeDerived(ref: ref)
            lastError = "Şekil kaydedilemedi: \(error.localizedDescription)"
        }
    }

    /// Kullanıcının kendi çizdiği şekil.
    func addFigure(pageID: UUID, bbox: BoundingBox) async {
        guard let ref = await cropAndStore(pageID: pageID, bbox: bbox) else { return }
        archive.addFigure(pageID: pageID, bbox: bbox, imageRef: ref, at: Date())
        persist()
    }

    func dismissFigure(_ id: UUID) {
        archive.dismissFigure(id)
        persist()
    }

    func removeFigure(_ id: UUID) {
        if let ref = archive.removeFigure(id) { store.removeDerived(ref: ref) }
        persist()
    }

    private func cropAndStore(pageID: UUID, bbox: BoundingBox) async -> String? {
        guard let page = archive.pages.first(where: { $0.id == pageID }), let url = pageImageURL(for: page) else {
            return nil
        }
        let data = await Task.detached(priority: .userInitiated) {
            FigureCropper.crop(url: url, bbox: bbox, maxSide: 1400)?.jpegData(compressionQuality: 0.8)
        }.value
        guard let data else {
            lastError = "Şekil kırpılamadı: orijinal görsel açılamadı."
            return nil
        }
        do {
            return try store.storeFigureImage(data)
        } catch {
            lastError = "Şekil kaydedilemedi: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Export

    /// Seçili kaynakları geçici klasöre yazar; paylaşım sayfasına verilecek URL'leri döndürür.
    /// Pakette görsel varsa (şekiller, sayfa görüntüleri, "sadece görsel" sayfalar) Markdown, görseller ve
    /// manifest tek ZIP olur. `prompt` verilirse dosyanın başına o talimat konur.
    func exportFiles(sourceIDs: [UUID], mode: ExportMode, withFigures: Bool, withPages: Bool,
                     prompt: PromptTemplate? = nil) -> [URL] {
        do {
            let context = PromptContext(deckName: deckName(for: sourceIDs), sourceCount: sourceIDs.count,
                                        includesImages: withFigures || withPages)
            let exporter = MarkdownExporter(includeFigureImages: withFigures, includePageImages: withPages,
                                            prompt: prompt, promptContext: context)
            let result = try exporter.export(
                archive, selections: sourceIDs.map { SourceSelection(sourceID: $0) }, mode: mode, createdAt: Date())
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("export-\(result.manifest.exportID.uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if exporter.producesZip || !result.assets.isEmpty {
                let zip = try result.zip(imageData: { [store] asset in
                    let url = store.url(forRef: asset.imageRef)
                    guard let crop = asset.crop else { return try? Data(contentsOf: url) }
                    return FigureCropper.crop(url: url, bbox: crop, maxSide: 2400)?.jpegData(compressionQuality: 0.85)
                })
                let short = result.manifest.exportID.uuidString.lowercased().prefix(8)
                let url = dir.appendingPathComponent("dersarsivi-\(short).zip")
                try zip.write(to: url, options: .atomic)
                return [url]
            }
            return try result.files.map { file in
                let url = dir.appendingPathComponent(file.name)
                try Data(file.contents.utf8).write(to: url, options: .atomic)
                return url
            }
        } catch {
            lastError = "Dışa aktarma başarısız: \(error.localizedDescription)"
            return []
        }
    }

    /// Anki deste adı: kaynakların ortak klasör yolu ("DersArşivi::Fizyoloji::Kalp"); ortak klasör yoksa "DersArşivi".
    func deckName(for sourceIDs: [UUID]) -> String {
        let paths = sourceIDs.compactMap { archive.source($0) }.map { source -> [Folder] in
            source.folderID.map { archive.folderPath($0) } ?? []
        }
        guard var common = paths.first else { return "DersArşivi" }
        for path in paths.dropFirst() {
            common = Swift.zip(common, path).prefix(while: { $0.0.id == $0.1.id }).map(\.0)
        }
        return (["DersArşivi"] + common.map(\.name)).joined(separator: "::")
    }

    /// Talimatı panoya kopyalar (dosyasız kullanım: talimat sohbete yapıştırılır, dosya ayrıca eklenir).
    func copyPrompt(_ template: PromptTemplate, sourceIDs: [UUID], includesImages: Bool) {
        let context = PromptContext(deckName: deckName(for: sourceIDs), sourceCount: max(1, sourceIDs.count),
                                    includesImages: includesImages)
        UIPasteboard.general.string = template.instructions(context)
    }

    /// Hata ayıklama paketi: orijinal ve okunan görüntüler, OCR satırları, şekil önerileri ve kullanıcının
    /// kararları. Algılamayı cihazdakiyle birebir aynı girdilerle tekrar çalıştırıp ölçmek içindir.
    func debugPack(sourceIDs: [UUID]) -> URL? {
        struct PageInfo: Encodable {
            var file: String
            var pageIndex: Int
            var width: Double
            var height: Double
            var status: String
            var readImage: String
            var contentBox: BoundingBox?
            var lines: [FigureLabel]
            var blocks: [FigureLabel]
            var figures: [FigureInfo]
        }
        struct FigureInfo: Encodable {
            var status: String
            var auto: Bool
            var bbox: BoundingBox
        }
        struct PackInfo: Encodable {
            var configHash: String
            var engine: String
            var createdAt: Date
            var pages: [PageInfo]
        }
        var zip = ZipArchive()
        var infos: [PageInfo] = []
        for (n, id) in sourceIDs.enumerated() {
            guard let source = archive.source(id) else { continue }
            let ext = (source.localAssetRef as NSString).pathExtension
            let folder = String(format: "%03d", n + 1)
            if let data = try? Data(contentsOf: originalURL(for: source)) {
                zip.add(path: "\(folder)/original.\(ext)", contents: data)
            }
            for page in archive.pages(of: id) {
                var readImage = "\(folder)/original.\(ext)"
                if let ref = page.workingImageRef, let data = try? Data(contentsOf: store.url(forRef: ref)) {
                    readImage = "\(folder)/okunan-\(page.pageIndex + 1).jpg"
                    zip.add(path: readImage, contents: data)
                }
                infos.append(PageInfo(
                    file: source.originalFilename, pageIndex: page.pageIndex, width: page.width, height: page.height,
                    status: page.status.rawValue, readImage: readImage, contentBox: page.contentBox,
                    lines: store.loadLines(pageID: page.id),
                    blocks: archive.blocks(of: page.id).compactMap { b in
                        b.bbox.map { FigureLabel(text: b.acceptedText, bbox: $0) }
                    },
                    figures: archive.figures.filter { $0.pageID == page.id }.map {
                        FigureInfo(status: $0.status.rawValue, auto: $0.isAutoDetected, bbox: $0.bbox)
                    }))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let info = PackInfo(configHash: extractor.configHash, engine: extractor.engineVersion, createdAt: Date(),
                            pages: infos)
        do {
            zip.add(path: "paket.json", contents: try encoder.encode(info))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dersarsivi-olcum-\(UUID().uuidString.prefix(8).lowercased()).zip")
            try zip.finish().write(to: url, options: .atomic)
            return url
        } catch {
            lastError = "Paket hazırlanamadı: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Kalıcılık

    private func persist() {
        do {
            try store.save(archive)
        } catch {
            lastError = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }
}
