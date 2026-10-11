import DersArsiviCore
import Foundation
import UIKit
import Vision

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
        SHA256Hasher.hexDigest(Data("accurate|langcorr|layout-v1|style-v1|\(Self.usableLanguages().joined(separator: ","))".utf8))
    }

    func extract(from image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [ExtractedBlock] {
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
                    once.resume(returning: LayoutAnalyzer.paragraphs(from: lines, pageWidth: width, pageHeight: height))
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
            if isSpace {
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
    private var continuation: CheckedContinuation<[ExtractedBlock], Error>?

    init(_ continuation: CheckedContinuation<[ExtractedBlock], Error>) {
        self.continuation = continuation
    }

    private func take() -> CheckedContinuation<[ExtractedBlock], Error>? {
        lock.lock()
        defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }

    func resume(returning value: [ExtractedBlock]) { take()?.resume(returning: value) }
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
