import DersArsiviCore
import PDFKit
import UIKit

/// PDF sayfalarını görüntüye çevirir ve metin katmanını satır satır okur.
enum PDFSupport {
    struct Info {
        var sizes: [(width: Double, height: Double)]
        var labels: [String?]
    }

    static func info(data: Data) -> Info? {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        var info = Info(sizes: [], labels: [])
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let size = displaySize(page)
            info.sizes.append((Double(size.width), Double(size.height)))
            info.labels.append(page.label)
        }
        return info
    }

    /// Sayfanın döndürme uygulanmış görünen boyutu (punto).
    private static func displaySize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .mediaBox)
        let quarter = ((page.rotation % 360) + 360) % 360
        return quarter == 90 || quarter == 270 ? CGSize(width: box.height, height: box.width) : box.size
    }

    /// Sayfanın en uzun kenarı `maxSide` piksel olan beyaz zeminli görüntüsü.
    static func render(url: URL, pageIndex: Int, maxSide: CGFloat = 2400) -> CGImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: pageIndex) else { return nil }
        let size = displaySize(page)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = maxSide / max(size.width, size.height)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        // Küçük resim çizimi sayfa döndürmesini ve beyaz zemini kendisi uygular.
        return page.thumbnail(of: target, for: .mediaBox).cgImage
    }

    /// PDF sayfasını gösteren URL: dosya yolu + `#page=N` (N sıfırdan başlar).
    static func pageURL(_ url: URL, pageIndex: Int) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = "page=\(pageIndex)"
        return components?.url ?? url
    }

    /// `pageURL` ile üretilmiş URL'deki sayfa numarası; PDF değilse nil.
    static func pageIndex(of url: URL) -> Int? {
        guard url.pathExtension.lowercased() == "pdf" else { return nil }
        guard let fragment = url.fragment, fragment.hasPrefix("page=") else { return 0 }
        return Int(fragment.dropFirst(5)) ?? 0
    }

    /// Küçük önizleme (galeri).
    static func thumbnail(url: URL, pageIndex: Int = 0, maxSide: CGFloat = 400) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: pageIndex) else { return nil }
        let size = displaySize(page)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = maxSide / max(size.width, size.height)
        return page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale), for: .mediaBox)
    }

    /// Metin katmanının satırları (sol üst orijinli, normalleştirilmiş). Taranmış PDF'te veya döndürülmüş sayfada
    /// boş döner; o zaman sayfa görüntüsü OCR ile okunur.
    static func textLines(url: URL, pageIndex: Int) -> [ExtractedBlock] {
        guard let document = PDFDocument(url: url), let page = document.page(at: pageIndex),
              page.rotation % 360 == 0 else { return [] }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0,
              let all = page.selection(for: box) else { return [] }
        var lines: [ExtractedBlock] = []
        for selection in all.selectionsByLine() {
            let text = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let b = selection.bounds(for: page)
            guard b.width > 0, b.height > 0 else { continue }
            let bbox = BoundingBox(x: (b.minX - box.minX) / box.width, y: 1 - (b.maxY - box.minY) / box.height,
                                   width: b.width / box.width, height: b.height / box.height)
            lines.append(ExtractedBlock(text: text, bbox: bbox, confidence: 1))
        }
        // Az yazı (yalnız sayfa numarası, başlık) taranmış sayfa demektir; görüntü okunur.
        let letters = lines.reduce(0) { $0 + $1.text.filter(\.isLetter).count }
        return letters >= 40 ? lines : []
    }
}
