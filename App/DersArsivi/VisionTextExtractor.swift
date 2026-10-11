import DersArsiviCore
import Foundation
import UIKit
import Vision

/// Bir sayfanın çıkarım sonucu: okuma sırasındaki paragraflar ve şekil önerileri.
struct ExtractionOutput: Sendable {
    var blocks: [ExtractedBlock]
    var figures: [FigureSuggestion]
    /// Satırların ortanca eğimi (derece, saat yönünün tersi pozitif). Eğik fotoğrafı döndürmek için.
    var skewDegrees: Double
    /// Uygulama kenarlıkları hariç sayfa alanı.
    var content: BoundingBox?
    /// Sayfa alanındaki OCR satırları; hata ayıklama paketi ve dokun-kırp için saklanır.
    var lines: [FigureLabel]
    /// Yazı alanının el yazısı payı ve sayfanın metne dökülemeyecek kadar karışık olup olmadığı.
    var handwritingShare: Double = 0
    var looksComplex = false
}

/// Cihaz üstü OCR: Apple Vision. Ağa veri göndermez.
struct VisionTextExtractor {
    static let engineName = "apple-vision"

    /// Tercih sırası. Cihaz desteklemeyenler `usableLanguages` ile elenir.
    static let preferredLanguages = ["tr-TR", "en-US"]

    /// Bu cihazdaki Vision'ın desteklediği tanıma dilleri.
    static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    static func usableLanguages() -> [String] {
        let supported = Set(supportedLanguages())
        let usable = preferredLanguages.filter { supported.contains($0) }
        return usable.isEmpty ? ["en-US"] : usable
    }

    var engineVersion: String { "VNRecognizeTextRequest-r\(VNRecognizeTextRequestRevision3)" }

    /// Ayar özeti; cache anahtarında kullanılır. Ayar değişirse eski çıkarım tekrar kullanılmaz.
    var configHash: String {
        // Tablo okuma yalnız iOS 26'da var; eski sürümde önceki okumalar geçerli kalır.
        let tables = Self.readsTables ? "table-v1|" : ""
        return SHA256Hasher.hexDigest(Data("accurate|langcorr|layout-v1|style-v3|fig-v6|rect-v2|order-v2|hand-v1|\(tables)\(Self.usableLanguages().joined(separator: ","))".utf8))
    }

    func extract(from image: CGImage, orientation: CGImagePropertyOrientation) async throws -> ExtractionOutput {
        let languages = Self.usableLanguages()
        let tables = await Self.tables(in: image, orientation: orientation)
        return try await withCheckedThrowingContinuation { continuation in
            // Vision eşzamanlı çalışır; arayüzü kilitlememek için arka plan kuyruğunda.
            DispatchQueue.global(qos: .userInitiated).async {
                // Vision hata durumunda hem tamamlama bloğunu çağırıp hem hata fırlatabilir; tek sefer devam et.
                let once = ResumeOnce(continuation)
                let pixels = PixelBuffer(image: image)
                let pageBackground = pixels?.pageBackground() ?? ColorAnalysis.RGB(r: 255, g: 255, b: 255)

                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        once.resume(throwing: error)
                        return
                    }
                    let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let lines = observations.compactMap { observation -> ExtractedBlock? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        // Vision kutusu: sol alt orijin, 0...1. Sözleşme: sol üst orijin.
                        let r = observation.boundingBox
                        let box = BoundingBox(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
                        let runs = pixels.flatMap {
                            Self.styledRuns(candidate, pixels: $0, orientation: orientation, pageBackground: pageBackground)
                        }
                        return ExtractedBlock(text: runs.map(TextRuns.plainText) ?? candidate.string, bbox: box,
                                              confidence: Double(candidate.confidence), runs: runs)
                    }
                    // Vision kutuları yönü düzeltilmiş görüntüye göredir; 90° dönüşlerde en/boy yer değiştirir.
                    let rotated = ([.left, .leftMirrored, .right, .rightMirrored] as [CGImagePropertyOrientation])
                        .contains(orientation)
                    let width = Double(rotated ? image.height : image.width)
                    let height = Double(rotated ? image.width : image.height)
                    let skew = Self.medianSkew(observations, width: width, height: height)
                    once.resume(returning: Self.finish(lines: lines, tables: tables, image: image,
                                                       orientation: orientation, width: width, height: height,
                                                       skew: skew))
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = languages

                let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
                do {
                    try handler.perform([request])
                } catch {
                    once.resume(throwing: error)
                }
            }
        }
    }

    /// PDF'in metin katmanından gelen satırlar: OCR yapılmaz, yalnız düzen, şekil ve işaret çözümlemesi.
    func finish(textLayer lines: [ExtractedBlock], image: CGImage) async -> ExtractionOutput {
        let tables = await Self.tables(in: image, orientation: .up)
        return await Task.detached(priority: .userInitiated) {
            Self.finish(lines: lines, tables: tables, image: image, orientation: .up, width: Double(image.width),
                        height: Double(image.height), skew: 0)
        }.value
    }

    /// Belge tanıma (iOS 26) sayfadaki tabloları satır ve sütunlarıyla bulur. Eski sürümde ve hata olursa boş;
    /// sayfa yine satır satır okunur.
    static var readsTables: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    static func tables(in image: CGImage, orientation: CGImagePropertyOrientation) async -> [DetectedTable] {
        guard #available(iOS 26, *) else { return [] }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = usableLanguages().map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.useLanguageCorrection = true
        guard let observations = try? await request.perform(on: image, orientation: orientation) else { return [] }
        return observations.flatMap { $0.document.tables }.map { table in
            DetectedTable(bbox: topLeft(table.boundingRegion.boundingBox), cells: table.rows.flatMap { $0 }.map { cell in
                DetectedTable.Cell(rows: cell.rowRange, columns: cell.columnRange,
                                   text: cell.content.text.transcript,
                                   bbox: topLeft(cell.content.boundingRegion.boundingBox))
            })
        }
    }

    /// Vision'ın kutusu sol alt orijinli; sözleşme sol üst orijin.
    @available(iOS 26, *)
    private static func topLeft(_ r: NormalizedRect) -> BoundingBox {
        BoundingBox(x: Double(r.origin.x), y: Double(1 - r.origin.y - r.height),
                    width: Double(r.width), height: Double(r.height))
    }

    /// Satırlardan sayfa sonucunu üretir: sayfa alanı, şekil önerileri, el yazısı ve işaretler, paragraflar.
    private static func finish(lines: [ExtractedBlock], tables: [DetectedTable], image: CGImage,
                               orientation: CGImagePropertyOrientation, width: Double, height: Double,
                               skew: Double) -> ExtractionOutput {
        // Not uygulamasının araç çubuğu gibi sayfa dışı yazılar atılır.
        let small = smallImage(image: image, orientation: orientation)
        let scan = small.flatMap { FigureDetector.scan(rgba: $0.bytes, width: $0.width, height: $0.height) }
        var pageLines = FigureDetector.keepingContentLines(lines, scan: scan)
        let boxed = pageLines.compactMap { line in line.bbox.map { (text: line.text, bbox: $0) } }
        let figures = scan.map { FigureDetector.suggestions(scan: $0, lines: boxed) } ?? []
        // El yazısı satırlar ve yanına işaret konmuş satırlar; el notları görüntü olarak saklanır.
        var notes: [FigureSuggestion] = []
        var share = 0.0, complex = false
        if let small {
            let zero = BoundingBox(x: 0, y: 0, width: 0, height: 0)
            let analysisLines = pageLines.map { line in
                PageAnalysis.Line(text: line.text, bbox: line.bbox ?? zero, confidence: line.confidence)
            }
            let analysis = PageAnalysis.analyze(rgba: small.bytes, width: small.width, height: small.height,
                                                lines: analysisLines, figures: figures.map(\.bbox),
                                                content: scan?.content)
            for i in pageLines.indices {
                if analysis.handwriting.contains(i) { pageLines[i].kind = .handwriting }
                if analysis.marked.contains(i) { pageLines[i].marked = true }
            }
            notes = analysis.notes
            share = analysis.handwritingShare
            complex = analysis.looksComplex
        }
        // Tablonun içindeki satırlar paragraf yapılmaz; tablo Markdown tablosu olarak kendi yerine konur. Tablo
        // artık metin olduğundan çizgileri yüzünden önerilen şekil de düşer.
        let (rest, tableBlocks) = TableLayout.split(lines: pageLines, tables: tables)
        let paragraphs = LayoutAnalyzer.paragraphs(from: rest, pageWidth: width, pageHeight: height)
        let blocks = TableLayout.insert(tableBlocks, into: paragraphs)
        let tableBoxes = tableBlocks.compactMap(\.bbox)
        let keptFigures = figures.filter { figure in
            !tableBoxes.contains { figure.bbox.fractionInside($0) >= 0.6 }
        }
        return ExtractionOutput(
            blocks: blocks, figures: keptFigures + notes, skewDegrees: skew, content: scan?.content,
            lines: boxed.map { FigureLabel(text: $0.text, bbox: $0.bbox) },
            handwritingShare: share, looksComplex: complex)
    }

    /// Uzun satırların taban çizgisi açısının ortancası. Kısa satırlar (etiket, sayı) gürültülü olduğundan sayılmaz.
    private static func medianSkew(_ observations: [VNRecognizedTextObservation], width: Double,
                                   height: Double) -> Double {
        let angles = observations.compactMap { o -> Double? in
            let dx = Double(o.bottomRight.x - o.bottomLeft.x) * width
            let dy = Double(o.bottomRight.y - o.bottomLeft.y) * height
            guard dx > width * 0.25 else { return nil }
            return atan2(dy, dx) * 180 / .pi
        }.sorted()
        guard angles.count >= 3 else { return 0 }
        let median = angles[angles.count / 2]
        // Satırların çoğu aynı eğimde değilse (el yazısı, karışık görseller) döndürme yapılmaz.
        let agreeing = angles.filter { abs($0 - median) <= 1.5 }.count
        return Double(agreeing) >= Double(angles.count) * 0.6 ? median : 0
    }

    /// Sayfa alanı ve şekil önerileri için görüntünün yönü düzeltilmiş küçük kopyası yeter.
    static func pageScan(image: CGImage, orientation: CGImagePropertyOrientation) -> FigureDetector.PageScan? {
        guard let small = smallImage(image: image, orientation: orientation) else { return nil }
        return FigureDetector.scan(rgba: small.bytes, width: small.width, height: small.height)
    }

    /// Görüntünün yönü düzeltilmiş, en uzun kenarı 480 px kopyası (RGBA).
    static func smallImage(image: CGImage, orientation: CGImagePropertyOrientation) -> PixelBuffer? {
        let maxSide: CGFloat = 480
        let ui = UIImage(cgImage: image, scale: 1, orientation: UIImage.Orientation(orientation))
        let scale = min(1, maxSide / max(ui.size.width, ui.size.height, 1))
        let size = CGSize(width: max(1, (ui.size.width * scale).rounded(.down)),
                          height: max(1, (ui.size.height * scale).rounded(.down)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            ui.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = small.cgImage else { return nil }
        return PixelBuffer(image: cg, maxSide: Int(maxSide))
    }

    /// Satırı kelimelere böler, her kelimenin kutusundaki piksellerden vurgu ve yazı rengini bulur.
    /// Biçimli kelime yoksa nil.
    private static func styledRuns(_ candidate: VNRecognizedText, pixels: PixelBuffer,
                                   orientation: CGImagePropertyOrientation,
                                   pageBackground: ColorAnalysis.RGB) -> [TextRun]? {
        let text = candidate.string
        var runs: [TextRun] = []
        var index = text.startIndex
        while index < text.endIndex {
            let isSpace = text[index].isWhitespace
            var end = index
            while end < text.endIndex, text[end].isWhitespace == isSpace { end = text.index(after: end) }
            let piece = String(text[index..<end])
            if isSpace || !piece.contains(where: { $0.isLetter || $0.isNumber }) {
                // Madde imi gibi işaretlerin rengi anlamsız ve kenar pikselleri yüzünden yanıltıcı.
                runs.append(TextRun(text: piece))
            } else if let observation = try? candidate.boundingBox(for: index..<end) {
                let r = observation.boundingBox
                let oriented = BoundingBox(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
                let raw = PixelBuffer.rawRect(oriented, orientation: orientation)
                let style = ColorAnalysis.style(rgba: pixels.pixels(in: raw), pageBackground: pageBackground)
                runs.append(TextRun(text: piece, highlight: style.highlight, color: style.color))
            } else {
                runs.append(TextRun(text: piece))
            }
            index = end
        }
        // Kelimeler arası boşluk, iki yanı aynı biçimdeyse o biçime katılır.
        for i in runs.indices where runs[i].isPlain && runs[i].text.allSatisfy(\.isWhitespace) {
            guard i > 0, i < runs.count - 1 else { continue }
            let a = runs[i - 1], b = runs[i + 1]
            if a.highlight == b.highlight { runs[i].highlight = a.highlight }
            if a.color == b.color { runs[i].color = a.color }
        }
        return TextRuns.normalize(runs)
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ExtractionOutput, Error>?

    init(_ continuation: CheckedContinuation<ExtractionOutput, Error>) {
        self.continuation = continuation
    }

    private func take() -> CheckedContinuation<ExtractionOutput, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }

    func resume(returning value: ExtractionOutput) { take()?.resume(returning: value) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

extension UIImage.Orientation {
    init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
