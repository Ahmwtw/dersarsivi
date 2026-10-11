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
    func importImage(data: Data, filename: String) {
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
            let source = SourceAsset(id: id, mediaType: .image, originalFilename: filename, sourceTitle: title,
                                     contentHash: stored.hash, localAssetRef: stored.ref, importedAt: Date())
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
            if archive.cachedRun(cacheKey: runRecord.cacheKey) != nil, !archive.blocks(of: page.id).isEmpty {
                archive.jobQueue.complete(jobID: job.id, at: Date())
                try archive.setStatus(.ready, forPage: page.id)
                return
            }
            guard let image = loadImage(ref: source.localAssetRef) else {
                throw ExtractionFailure.originalMissing
            }
            let blocks = try await extractor.extract(from: image.cgImage, orientation: image.orientation)
            runRecord.finishedAt = Date()
            try archive.applyExtraction(blocks, run: runRecord)
            archive.jobQueue.complete(jobID: job.id, at: Date())
        } catch {
            let message = (error as? ExtractionFailure)?.message ?? error.localizedDescription
            archive.jobQueue.fail(jobID: job.id, error: message, at: Date())
            let failed = archive.jobQueue.jobs.first { $0.id == job.id }?.state == .failed
            try? archive.setStatus(failed ? .failed : .queued, forPage: page.id, failureReason: message)
        }
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

    func retry(pageID: UUID) {
        archive.jobQueue.enqueue(pageID: pageID, at: Date())
        try? archive.setStatus(.queued, forPage: pageID)
        persist()
        processQueue()
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

    // MARK: Export

    /// Seçili kaynakları Markdown olarak geçici klasöre yazar; paylaşım sayfasına verilecek URL'leri döndürür.
    func exportMarkdown(sourceIDs: [UUID], mode: ExportMode) -> [URL] {
        do {
            let result = try MarkdownExporter().export(
                archive, selections: sourceIDs.map { SourceSelection(sourceID: $0) }, mode: mode, createdAt: Date())
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("export-\(result.manifest.exportID.uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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

    // MARK: Kalıcılık

    private func persist() {
        do {
            try store.save(archive)
        } catch {
            lastError = "Kaydedilemedi: \(error.localizedDescription)"
        }
    }
}
