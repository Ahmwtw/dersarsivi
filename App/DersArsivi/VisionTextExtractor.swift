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
        SHA256Hasher.hexDigest(Data("accurate|langcorr|\(Self.usableLanguages().joined(separator: ","))".utf8))
    }

    func extract(from image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [ExtractedBlock] {
        try await withCheckedThrowingContinuation { continuation in
            // Vision hata durumunda hem tamamlama bloğunu çağırıp hem hata fırlatabilir; tek sefer devam et.
            let once = ResumeOnce(continuation)
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    once.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let blocks = observations
                    .sorted(by: Self.readingOrder)
                    .compactMap { observation -> ExtractedBlock? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        // Vision kutusu: sol alt orijin, 0...1. Sözleşme: sol üst orijin.
                        let r = observation.boundingBox
                        let box = BoundingBox(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
                        return ExtractedBlock(text: candidate.string, bbox: box,
                                              confidence: Double(candidate.confidence))
                    }
                once.resume(returning: blocks)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = Self.usableLanguages()

            // Vision eşzamanlı çalışır; arayüzü kilitlememek için arka plan kuyruğunda.
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
                do {
                    try handler.perform([request])
                } catch {
                    once.resume(throwing: error)
                }
            }
        }
    }

    /// Basit okuma sırası: yukarıdan aşağı, aynı satırda soldan sağa.
    /// İki sütunlu sayfalar için yetersizdir; düzen analizi sonraki fazda.
    private static func readingOrder(_ a: VNRecognizedTextObservation, _ b: VNRecognizedTextObservation) -> Bool {
        let ay = a.boundingBox.midY, by = b.boundingBox.midY
        if abs(ay - by) > min(a.boundingBox.height, b.boundingBox.height) / 2 {
            return ay > by
        }
        return a.boundingBox.minX < b.boundingBox.minX
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
