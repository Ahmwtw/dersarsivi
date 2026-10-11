import ImageIO
import SwiftUI
import UIKit

/// Orijinali değiştirmeden küçük önizleme üretir. Önizleme OCR girdisi olarak kullanılmaz.
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, UIImage>()

    static func thumbnail(for url: URL, maxPixel: CGFloat) -> UIImage? {
        let key = "\(url.absoluteString)@\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        if let pageIndex = PDFSupport.pageIndex(of: url) {
            let file = URL(fileURLWithPath: url.path)
            guard let image = PDFSupport.thumbnail(url: file, pageIndex: pageIndex, maxSide: maxPixel) else { return nil }
            cache.setObject(image, forKey: key)
            return image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key)
        return image
    }
}

struct ThumbnailView: View {
    let url: URL
    var maxPixel: CGFloat = 400
    /// `.fill`: verilen kutuyu doldurur ve taşanı kırpar (galeri). `.fit`: görselin tamamını gösterir (detay).
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        Group {
            if contentMode == .fill {
                // Boyutu dışarıdaki çerçeve belirler; görsel yalnız kaplama olarak çizilir, böylece taşmaz.
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .overlay { content(fill: true) }
                    .clipped()
                    .contentShape(Rectangle())
            } else {
                content(fill: false)
            }
        }
        .task(id: url) {
            let loaded = await Task.detached(priority: .utility) { [url, maxPixel] in
                ThumbnailLoader.thumbnail(for: url, maxPixel: maxPixel)
            }.value
            image = loaded
            missing = loaded == nil
        }
    }

    @ViewBuilder
    private func content(fill: Bool) -> some View {
        if let image {
            if fill {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(uiImage: image).resizable().scaledToFit()
            }
        } else if missing {
            Label("Orijinal bulunamıyor", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(4)
        } else {
            ProgressView()
        }
    }
}
