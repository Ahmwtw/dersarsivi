import CoreImage
import Foundation
import ImageIO
import Vision

/// Eğik çekilmiş sayfa fotoğraflarını okumadan önce düzleştirir. Orijinal dosya değişmez; sonuç ayrı saklanır.
///
/// Ekran görüntüleri dokunulmadan geçer: düzleştirme yalnız bulunan sayfa dörtgeni belirgin şekilde
/// eğik veya perspektifliyse yapılır (ekran görüntüsündeki dikdörtgenler hiçbir zaman eğik değildir).
enum PagePreparer {
    private static let context = CIContext()

    /// Kenarı yataydan/dikeyden bu kadar dereceden fazla sapan sayfa düzleştirilir.
    static let minSkewDegrees = 2.0

    /// Sayfa dörtgenini bulup perspektifi düzeltir. Gerek yoksa veya bulunamazsa nil.
    static func rectify(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        guard (try? handler.perform([request])) != nil,
              let quad = request.results?.first, quad.confidence >= 0.6 else { return nil }

        let input = CIImage(cgImage: image).oriented(orientation)
        let size = input.extent.size
        // Vision: sol alt orijinli normalleştirilmiş nokta; Core Image de sol alt orijinli.
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        let tl = px(quad.topLeft), tr = px(quad.topRight), bl = px(quad.bottomLeft), br = px(quad.bottomRight)

        let area = abs(polygonArea([tl, tr, br, bl])) / (size.width * size.height)
        guard area >= 0.3 else { return nil }
        let deviation = [angle(tl, tr), angle(bl, br), angle(bl, tl) - 90, angle(br, tr) - 90]
            .map { abs(normalize($0)) }.max() ?? 0
        guard deviation >= minSkewDegrees else { return nil }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(input.translatedToOrigin(), forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
        guard let output = filter.outputImage else { return nil }
        return render(output)
    }

    /// Yönü düzeltilmiş görüntüyü verilen açı kadar döndürür (pozitif: saat yönünün tersi), boşlukları beyazla doldurur.
    static func rotate(_ image: CGImage, orientation: CGImagePropertyOrientation, degrees: Double) -> CGImage? {
        let input = CIImage(cgImage: image).oriented(orientation).translatedToOrigin()
        let rotated = input.transformed(by: CGAffineTransform(rotationAngle: degrees * .pi / 180))
        let background = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: rotated.extent)
        return render(rotated.composited(over: background))
    }

    private static func render(_ image: CIImage) -> CGImage? {
        let extent = image.extent.integral
        guard extent.width >= 16, extent.height >= 16 else { return nil }
        return context.createCGImage(image, from: extent)
    }

    private static func angle(_ a: CGPoint, _ b: CGPoint) -> Double {
        atan2(Double(b.y - a.y), Double(b.x - a.x)) * 180 / .pi
    }

    private static func normalize(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 180)
        if d > 90 { d -= 180 }
        if d < -90 { d += 180 }
        return d
    }

    private static func polygonArea(_ p: [CGPoint]) -> Double {
        var sum = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += Double(a.x * b.y - b.x * a.y)
        }
        return sum / 2
    }
}

private extension CIImage {
    func translatedToOrigin() -> CIImage {
        transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }
}
