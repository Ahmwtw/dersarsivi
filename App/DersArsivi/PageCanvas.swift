import DersArsiviCore
import SwiftUI

/// Sayfa görüntüsü ve üstünde okunan metin kutuları. Kutuya dokununca o metin düzeltilir; iki parmakla
/// yakınlaştırılır. Kutu rengi satırın durumunu gösterir (işaretli, el yazısı, belirsiz, düzeltilmiş).
struct PageCanvas: View {
    let url: URL
    let blocks: [Block]
    var highlighted: UUID? = nil
    let onTap: (Block) -> Void

    @Environment(\.palette) private var palette
    @State private var image: UIImage?
    @State private var missing = false
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @AppStorage("canvasShowsBoxes") private var showsBoxes = true

    private var scale: CGFloat { min(5, max(1, zoom * pinch)) }

    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1) {
                page(width: max(120, geo.size.width - 32) * scale)
                    .padding(16)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(5, max(1, zoom * value.magnification)) }
            )
        }
        .overlay(alignment: .bottom) { controls.padding(.bottom, 14) }
        .task(id: url) {
            let loaded = await Task.detached(priority: .userInitiated) { [url] in
                ThumbnailLoader.thumbnail(for: url, maxPixel: 2400)
            }.value
            image = loaded
            missing = loaded == nil
        }
    }

    @ViewBuilder
    private func page(width: CGFloat) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
                .overlay {
                    if showsBoxes {
                        GeometryReader { g in
                            ForEach(blocks) { block in
                                if let box = block.bbox { boxView(block, box, in: g.size) }
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        } else if missing {
            ContentUnavailableView("Sayfa görüntüsü bulunamadı", systemImage: "exclamationmark.triangle")
        } else {
            ProgressView().frame(width: width, height: width * 0.6)
        }
    }

    private func boxView(_ block: Block, _ box: BoundingBox, in size: CGSize) -> some View {
        let color = tint(for: block)
        let active = block.id == highlighted
        let rect = CGRect(x: box.x * size.width, y: box.y * size.height,
                          width: box.width * size.width, height: box.height * size.height).insetBy(dx: -2, dy: -2)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color.opacity(active ? 0.28 : 0.07))
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(color.opacity(active ? 1 : 0.7), lineWidth: active ? 2.5 : 1.2)
            }
            .frame(width: max(rect.width, 8), height: max(rect.height, 8))
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture { onTap(block) }
            .accessibilityElement()
            .accessibilityLabel(block.kind == .table ? "Tablo" : block.acceptedText)
            .accessibilityHint("Düzeltmek için dokun")
            .accessibilityAddTraits(.isButton)
    }

    private func tint(for block: Block) -> Color {
        if block.isUserCorrected { return .green }
        if block.marked == true { return palette.star }
        if block.kind == .handwriting { return palette.note }
        if block.kind == .table { return .teal }
        if block.reviewStatus == .conflict { return .orange }
        if let c = block.engineConfidence, c < 0.5 { return .orange }
        return palette.accent
    }

    /// Altta yüzen cam kontroller: kutuları göster/gizle, yakınlaştırma, renk açıklaması.
    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                showsBoxes.toggle()
            } label: {
                Label(showsBoxes ? "Kutuları gizle" : "Kutuları göster",
                      systemImage: showsBoxes ? "eye.slash" : "eye")
            }
            Divider().frame(height: 20)
            Button { withAnimation(.snappy) { zoom = max(1, zoom / 1.5) } } label: {
                Label("Uzaklaştır", systemImage: "minus.magnifyingglass")
            }
            .disabled(zoom <= 1)
            Button { withAnimation(.snappy) { zoom = min(5, zoom * 1.5) } } label: {
                Label("Yakınlaştır", systemImage: "plus.magnifyingglass")
            }
            .disabled(zoom >= 5)
            Divider().frame(height: 20)
            Menu {
                Label("Okunan satır", systemImage: "square").foregroundStyle(palette.accent)
                Label("İşaretli (⭐)", systemImage: "square.fill").foregroundStyle(palette.star)
                Label("El notu (✍️)", systemImage: "square.fill").foregroundStyle(palette.note)
                Label("Tablo", systemImage: "tablecells").foregroundStyle(.teal)
                Label("Belirsiz okuma", systemImage: "square.fill").foregroundStyle(.orange)
                Label("Düzeltildi", systemImage: "square.fill").foregroundStyle(.green)
            } label: {
                Label("Renkler", systemImage: "info.circle")
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassSurface(in: Capsule(), interactive: true)
    }
}
