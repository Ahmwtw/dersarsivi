import DersArsiviCore
import SwiftUI

/// Kaynağın şekilleri: uygulamanın önerileri tek dokunuşla kaydedilir veya yoksayılır; istenirse kutu ayarlanır.
struct FiguresSection: View {
    @EnvironmentObject private var model: AppModel
    let source: SourceAsset
    let page: Page
    @State private var editing: EditTarget?
    @State private var busy = false

    private struct EditTarget: Identifiable {
        let id = UUID()
        let figureID: UUID?
        let initial: BoundingBox
    }

    private var figures: [Figure] { model.archive.figures(of: page.id) }
    private var suggestedCount: Int { figures.filter { $0.status == .suggested }.count }
    private var pageURL: URL { model.pageImageURL(for: page) ?? model.originalURL(for: source) }

    var body: some View {
        Section {
            ForEach(figures) { figure in
                FigureRow(figure: figure, originalURL: pageURL,
                          savedURL: model.figureImageURL(figure),
                          onSave: { save(figure.id, figure.bbox) },
                          onEdit: { editing = EditTarget(figureID: figure.id, initial: figure.bbox) },
                          onDismiss: { model.dismissFigure(figure.id) },
                          onDelete: { model.removeFigure(figure.id) })
            }
            if suggestedCount >= 2 {
                Button {
                    run { await model.saveSuggestions(pageID: page.id) }
                } label: {
                    Label("Önerilerin hepsini kaydet (\(suggestedCount))", systemImage: "checkmark.circle")
                }
                .disabled(busy)
            }
            Button {
                editing = EditTarget(figureID: nil, initial: BoundingBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
            } label: {
                Label("Şekil kırp", systemImage: "crop")
            }
            .disabled(busy)
            Button {
                run { await model.addWholePage(pageID: page.id) }
            } label: {
                Label("Tüm sayfayı şekil olarak kaydet", systemImage: "rectangle.dashed")
            }
            .disabled(busy)
        } header: {
            Text("Şekiller")
        } footer: {
            Text(figures.isEmpty
                 ? "Önemli bir şema veya grafik varsa kırpıp kaydedebilirsin; dışa aktarımda görseliyle eklenir."
                 : "Kaydedilen şekiller ZIP dışa aktarımında görseliyle, içindeki yazılar etiket olarak eklenir.")
        }
        .sheet(item: $editing) { target in
            CropEditorView(url: pageURL, title: "Şekli kırp", initial: target.initial,
                           findFigure: { x, y in await model.findFigure(pageID: page.id, x: x, y: y) }) { box in
                if let id = target.figureID {
                    save(id, box)
                } else {
                    busy = true
                    Task {
                        await model.addFigure(pageID: page.id, bbox: box)
                        busy = false
                    }
                }
            }
        }
    }

    private func save(_ id: UUID, _ box: BoundingBox) {
        run { await model.saveFigure(id, bbox: box) }
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        busy = true
        Task {
            await work()
            busy = false
        }
    }
}

private struct FigureRow: View {
    let figure: Figure
    let originalURL: URL
    let savedURL: URL?
    let onSave: () -> Void
    let onEdit: () -> Void
    let onDismiss: () -> Void
    let onDelete: () -> Void
    @State private var preview: UIImage?

    private struct PreviewKey: Hashable {
        let bbox: BoundingBox
        let saved: URL?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 220)

            HStack {
                if figure.status == .suggested {
                    Label("Öneri", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Kaydedildi", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                if !figure.labels.isEmpty {
                    Text("· \(figure.labels.count) etiket").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                if figure.status == .suggested {
                    Button("Kaydet", action: onSave).buttonStyle(.borderedProminent)
                    Button("Ayarla", action: onEdit).buttonStyle(.bordered)
                    Button("Yoksay", role: .destructive, action: onDismiss).buttonStyle(.bordered)
                } else {
                    Button("Ayarla", action: onEdit).buttonStyle(.bordered)
                    Button("Sil", role: .destructive, action: onDelete).buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .task(id: PreviewKey(bbox: figure.bbox, saved: savedURL)) {
            let bbox = figure.bbox
            preview = await Task.detached(priority: .utility) { [originalURL, savedURL] in
                if let savedURL, let image = UIImage(contentsOfFile: savedURL.path) { return image }
                return FigureCropper.crop(url: originalURL, bbox: bbox, maxSide: 600)
            }.value
        }
    }
}
