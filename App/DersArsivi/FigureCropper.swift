import DersArsiviCore
import UIKit

/// Orijinal görselden şekil bölgesini kırpar. Kutu yönü düzeltilmiş görüntüye göredir.
enum FigureCropper {
    static func crop(url: URL, bbox: BoundingBox, maxSide: CGFloat) -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let full = image.size
        let crop = CGRect(x: bbox.x * full.width, y: bbox.y * full.height,
                          width: bbox.width * full.width, height: bbox.height * full.height)
        guard crop.width >= 2, crop.height >= 2 else { return nil }
        let scale = min(1, maxSide / max(crop.width, crop.height))
        let size = CGSize(width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: full.width * scale, height: full.height * scale))
        }
    }
}
