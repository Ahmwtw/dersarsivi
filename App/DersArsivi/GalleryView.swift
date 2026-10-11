import DersArsiviCore
import PhotosUI
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var showExport = false
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    private var sources: [SourceAsset] {
        model.archive.sources.sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sources.isEmpty {
                    ContentUnavailableView {
                        Label("Arşiv boş", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Slayt ekran görüntüsü veya kitap fotoğrafı ekle; metni cihazında okunur.")
                    } actions: {
                        addButton
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(sources) { source in
                                cell(for: source)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .navigationTitle("DersArşivi")
            .navigationDestination(for: UUID.self) { id in
                SourceDetailView(sourceID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !sources.isEmpty {
                        Button(isSelecting ? "Bitti" : "Seç") {
                            isSelecting.toggle()
                            if !isSelecting { selection.removeAll() }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button {
                            showExport = true
                        } label: {
                            Label("Dışa aktar (\(selection.count))", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selection.isEmpty)
                    } else {
                        addButton
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if isSelecting {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Sil (\(selection.count))", systemImage: "trash")
                        }
                        .disabled(selection.isEmpty)
                    }
                }
                ToolbarItem(placement: .status) {
                    if model.isProcessing {
                        ProgressView().accessibilityLabel("Metin okunuyor")
                    }
                }
            }
            .confirmationDialog("\(selection.count) görsel silinsin mi?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    model.deleteSources(Array(selection))
                    selection.removeAll()
                    isSelecting = false
                }
            } message: {
                Text("Okunan metin, düzeltmeler ve kırpılan şekiller de silinir. Geri alınamaz.")
            }
            .sheet(isPresented: $showExport) {
                ExportView(sourceIDs: sources.map(\.id).filter(selection.contains))
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                pickerItems = []
                Task { await importItems(items) }
            }
        }
    }

    private var addButton: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
            Label("Ekle", systemImage: "plus")
        }
    }

    @ViewBuilder
    private func cell(for source: SourceAsset) -> some View {
        let status = model.archive.pages(of: source.id).first?.status ?? .imported
        let content = VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { ThumbnailView(url: model.originalURL(for: source)) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) { StatusBadge(status: status).padding(4) }
                .overlay(alignment: .bottomTrailing) {
                    let suggested = model.archive.suggestedFigureCount(sourceID: source.id)
                    if suggested > 0 {
                        Label("\(suggested)", systemImage: "crop")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                            .padding(4)
                            .accessibilityLabel("\(suggested) şekil önerisi")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: selection.contains(source.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(.tint, .background)
                            .padding(4)
                    }
                }
            Text(source.sourceTitle)
                .font(.caption)
                .lineLimit(1)
        }

        if isSelecting {
            Button {
                if selection.contains(source.id) { selection.remove(source.id) } else { selection.insert(source.id) }
            } label: { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.contains(source.id) ? .isSelected : [])
        } else {
            NavigationLink(value: source.id) { content }
                .buttonStyle(.plain)
        }
    }

    private func importItems(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                model.importImage(data: data, filename: "image-\(index + 1).\(ext)")
            } catch {
                model.lastError = "Görsel alınamadı: \(error.localizedDescription)"
            }
        }
    }
}
