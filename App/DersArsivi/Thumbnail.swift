import ImageIO
import SwiftUI
import UIKit

/// Orijinali değiştirmeden küçük önizleme üretir. Önizleme OCR girdisi olarak kullanılmaz.
enum ThumbnailLoader {
    private static let cache = NSCache<NSURL, UIImage>()

    static func thumbnail(for url: URL, maxPixel: CGFloat) -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct ThumbnailView: View {
    let url: URL
    var maxPixel: CGFloat = 400
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if missing {
                Label("Orijinal bulunamıyor", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(4)
            }
        }
        .clipped()
        .task(id: url) {
            let loaded = await Task.detached(priority: .utility) { [url, maxPixel] in
                ThumbnailLoader.thumbnail(for: url, maxPixel: maxPixel)
            }.value
            image = loaded
            missing = loaded == nil
        }
    }
}
