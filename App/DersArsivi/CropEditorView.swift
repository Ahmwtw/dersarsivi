import DersArsiviCore
import SwiftUI

/// Şekil kutusunu ayarlama ekranı: köşelerden boyutlandır, içinden sürükleyerek taşı.
struct CropEditorView: View {
    let url: URL
    let title: String
    let onSave: (BoundingBox) -> Void
    @State private var box: BoundingBox
    @State private var image: UIImage?
    @State private var dragStart: BoundingBox?
    @Environment(\.dismiss) private var dismiss

    init(url: URL, title: String, initial: BoundingBox, onSave: @escaping (BoundingBox) -> Void) {
        self.url = url
        self.title = title
        self.onSave = onSave
        _box = State(initialValue: initial)
    }

    private enum Handle: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private static let minSize = 0.04

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if let image {
                    let frame = fitted(image.size, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                        overlay(in: frame)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(box)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("Köşelerden boyutlandır, içinden sürükleyerek taşı.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                image = await Task.detached(priority: .userInitiated) { [url] in
                    ThumbnailLoader.thumbnail(for: url, maxPixel: 1600)
                }.value
            }
        }
    }

    private func overlay(in frame: CGRect) -> some View {
        let r = CGRect(x: frame.minX + box.x * frame.width, y: frame.minY + box.y * frame.height,
                       width: box.width * frame.width, height: box.height * frame.height)
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(frame)
                p.addRect(r)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .overlay(Rectangle().stroke(Color.yellow, lineWidth: 2))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .gesture(drag(frame: frame, handle: nil))

            ForEach(Handle.allCases, id: \.self) { handle in
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 22, height: 22)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .position(point(of: handle, in: r))
                    .gesture(drag(frame: frame, handle: handle))
            }
        }
    }

    private func point(of handle: Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func drag(frame: CGRect, handle: Handle?) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = dragStart ?? box
                if dragStart == nil { dragStart = box }
                let dx = value.translation.width / max(frame.width, 1)
                let dy = value.translation.height / max(frame.height, 1)
                box = Self.adjust(start, handle: handle, dx: dx, dy: dy)
            }
            .onEnded { _ in dragStart = nil }
    }

    private static func adjust(_ s: BoundingBox, handle: Handle?, dx: Double, dy: Double) -> BoundingBox {
        guard let handle else {
            let x = min(max(s.x + dx, 0), 1 - s.width)
            let y = min(max(s.y + dy, 0), 1 - s.height)
            return BoundingBox(x: x, y: y, width: s.width, height: s.height)
        }
        var x0 = s.x, y0 = s.y, x1 = s.maxX, y1 = s.maxY
        switch handle {
        case .topLeft: x0 += dx; y0 += dy
        case .topRight: x1 += dx; y0 += dy
        case .bottomLeft: x0 += dx; y1 += dy
        case .bottomRight: x1 += dx; y1 += dy
        }
        x0 = min(max(x0, 0), s.maxX - minSize)
        y0 = min(max(y0, 0), s.maxY - minSize)
        x1 = max(min(x1, 1), s.x + minSize)
        y1 = max(min(y1, 1), s.y + minSize)
        switch handle {
        case .topLeft: x1 = s.maxX; y1 = s.maxY
        case .topRight: x0 = s.x; y1 = s.maxY
        case .bottomLeft: x1 = s.maxX; y0 = s.y
        case .bottomRight: x0 = s.x; y0 = s.y
        }
        return BoundingBox(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func fitted(_ size: CGSize, in container: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(container.width / size.width, container.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
