import CoreGraphics
import DersArsiviCore
import Foundation
import ImageIO

/// Renk analizi için görüntünün (gerekirse küçültülmüş) RGBA kopyası. Ham, yönü düzeltilmemiş piksellerdir.
struct PixelBuffer {
    let width: Int
    let height: Int
    /// RGBA8, satır satır.
    let bytes: [UInt8]

    init?(image: CGImage, maxSide: Int = 2000) {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        bytes = buffer
    }

    /// Normalleştirilmiş, sol üst orijinli ham dikdörtgendeki pikseller (RGBA).
    func pixels(in r: BoundingBox) -> [UInt8] {
        let x0 = clamp(Int((r.x * Double(width)).rounded(.down)), width)
        let x1 = clamp(Int(((r.x + r.width) * Double(width)).rounded(.up)), width)
        let y0 = clamp(Int((r.y * Double(height)).rounded(.down)), height)
        let y1 = clamp(Int(((r.y + r.height) * Double(height)).rounded(.up)), height)
        guard x1 > x0, y1 > y0 else { return [] }
        var out: [UInt8] = []
        out.reserveCapacity((x1 - x0) * (y1 - y0) * 4)
        for y in y0..<y1 {
            let row = y * width * 4
            out.append(contentsOf: bytes[(row + x0 * 4)..<(row + x1 * 4)])
        }
        return out
    }

    /// Sayfanın genel arka plan rengi (seyrek örnekle).
    func pageBackground() -> ColorAnalysis.RGB {
        var sample: [UInt8] = []
        let step = max(1, Int((Double(width * height) / 40_000).squareRoot()))
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let i = (y * width + x) * 4
                sample.append(contentsOf: bytes[i..<(i + 4)])
            }
        }
        return ColorAnalysis.backgroundAndInk(rgba: sample)?.background ?? ColorAnalysis.RGB(r: 255, g: 255, b: 255)
    }

    private func clamp(_ v: Int, _ limit: Int) -> Int { min(max(v, 0), limit) }

    /// Vision'ın yönü düzeltilmiş görüntüdeki kutusunu ham piksel düzlemine çevirir.
    static func rawRect(_ r: BoundingBox, orientation: CGImagePropertyOrientation) -> BoundingBox {
        switch orientation {
        case .down, .downMirrored:
            return BoundingBox(x: 1 - r.x - r.width, y: 1 - r.y - r.height, width: r.width, height: r.height)
        case .right, .rightMirrored:
            // Görüntülenen = ham saat yönünde 90° döndürülmüş.
            return BoundingBox(x: r.y, y: 1 - r.x - r.width, width: r.height, height: r.width)
        case .left, .leftMirrored:
            return BoundingBox(x: 1 - r.y - r.height, y: r.x, width: r.height, height: r.width)
        default:
            return r
        }
    }
}
