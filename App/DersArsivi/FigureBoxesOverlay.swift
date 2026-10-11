import DersArsiviCore
import ImageIO
import SwiftUI

/// Galeri küçük resminin üstünde şekil kutuları: kaydedilenler düz, öneriler kesikli çizgi.
/// Küçük resim kutuyu doldurduğu (taşanı kırptığı) için kutular aynı ölçek ve kaydırmayla çizilir.
struct FigureBoxesOverlay: View {
    struct Item: Equatable {
        let box: BoundingBox
        let saved: Bool
    }

    let url: URL
    let boxes: [Item]
    @State private var imageSize: CGSize?

    var body: some View {
        GeometryReader { geo in
            if let imageSize, imageSize.width > 0, imageSize.height > 0 {
                let scale = max(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
                let w = imageSize.width * scale, h = imageSize.height * scale
                let ox = (geo.size.width - w) / 2, oy = (geo.size.height - h) / 2
                ForEach(boxes.indices, id: \.self) { i in
                    let item = boxes[i]
                    Rectangle()
                        .stroke(item.saved ? Color.green : Color.orange,
                                style: StrokeStyle(lineWidth: 1.5, dash: item.saved ? [] : [4, 3]))
                        .frame(width: item.box.width * w, height: item.box.height * h)
                        .position(x: ox + (item.box.x + item.box.width / 2) * w,
                                  y: oy + (item.box.y + item.box.height / 2) * h)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: url) {
            imageSize = await Task.detached(priority: .utility) { [url] in Self.orientedSize(url) }.value
        }
    }

    /// Dosyayı açmadan, EXIF yönünü hesaba katarak görüntü boyutu.
    nonisolated static func orientedSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }
}
