import DersArsiviCore
import Foundation
import UIKit
import Vision

/// Bir sayfanın çıkarım sonucu: okuma sırasındaki paragraflar ve şekil önerileri.
struct ExtractionOutput {
    var blocks: [ExtractedBlock]
    var figures: [FigureSuggestion]
    /// Satırların ortanca eğimi (derece, saat yönünün tersi pozitif). Eğik fotoğrafı döndürmek için.
    var skewDegrees: Double
    /// Uygulama kenarlıkları hariç sayfa alanı.
    var content: BoundingBox?
    /// Sayfa alanındaki OCR satırları; hata ayıklama paketi ve dokun-kırp için saklanır.
    var lines: [FigureLabel]
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
        SHA256Hasher.hexDigest(Data("accurate|langcorr|layout-v1|style-v3|fig-v4|rect-v2|\(Self.usableLanguages().joined(separator: ","))".utf8))
    }

    func extract(from image: CGImage, orientation: CGImagePropertyOrientation) async throws -> ExtractionOutput {
        let languages = Self.usableLanguages()
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
                    // Not uygulamasının araç çubuğu gibi sayfa dışı yazılar atılır.
                    let scan = Self.pageScan(image: image, orientation: orientation)
                    let pageLines = FigureDetector.keepingContentLines(lines, scan: scan)
                    let blocks = LayoutAnalyzer.paragraphs(from: pageLines, pageWidth: width, pageHeight: height)
                    let boxed = pageLines.compactMap { line in line.bbox.map { (text: line.text, bbox: $0) } }
                    let figures = scan.map { FigureDetector.suggestions(scan: $0, lines: boxed) } ?? []
                    let skew = Self.medianSkew(observations, width: width, height: height)
                    once.resume(returning: ExtractionOutput(
                        blocks: blocks, figures: figures, skewDegrees: skew, content: scan?.content,
                        lines: boxed.map { FigureLabel(text: $0.text, bbox: $0.bbox) }))
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
        guard let cg = small.cgImage, let pixels = PixelBuffer(image: cg, maxSide: Int(maxSide)) else { return nil }
        return FigureDetector.scan(rgba: pixels.bytes, width: pixels.width, height: pixels.height)
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
