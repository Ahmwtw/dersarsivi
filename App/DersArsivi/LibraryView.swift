import DersArsiviCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Kütüphane: klasörler, kaynak ızgarası, seçim ve içeri alma.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    let scope: LibraryScope
    let selectScope: (LibraryScope) -> Void
    /// Yeni klasör iste: parametre üst klasör (nil: en üst).
    let newFolder: (UUID?) -> Void

    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var search = ""
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingPDFs: [PendingPDF] = []
    @State private var showExport = false
    @State private var confirmDelete = false
    @AppStorage(AppModel.autoSaveFiguresKey) private var autoSaveFigures = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14)]

    private var folderID: UUID? {
        if case .folder(let id) = scope { return id }
        return nil
    }

    var body: some View {
        let summaries = model.summaries()
        let sources = filtered(model.sources(in: scope, summaries: summaries), summaries: summaries)
        let folders = visibleFolders

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if case .folder(let id) = scope { breadcrumb(id) }
                if !folders.isEmpty && search.isEmpty && !isSelecting {
                    folderStrip(folders)
                }
                if sources.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(sources) { source in
                            card(source, summary: summaries[source.id] ?? SourceSummary())
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, isSelecting ? 110 : 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isSelecting ? (selection.isEmpty ? "Seç" : "\(selection.count) seçili") : model.title(of: scope))
        .searchable(text: $search, prompt: "Başlıkta ve metinde ara")
        .toolbar { toolbar(sources: sources) }
        .overlay(alignment: .bottom) {
            if isSelecting { selectionBar.padding(.bottom, 8) }
        }
        .animation(.snappy, value: isSelecting)
        .onChange(of: scope) { _, _ in
            isSelecting = false
            selection.removeAll()
        }
        .photosPicker(isPresented: $showPhotos, selection: $pickerItems, maxSelectionCount: 50, matching: .images)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await importPhotos(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) {
            result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): model.lastError = "Dosya açılamadı: \(error.localizedDescription)"
            }
        }
        .sheet(item: Binding(get: { pendingPDFs.first }, set: { if $0 == nil, !pendingPDFs.isEmpty { pendingPDFs.removeFirst() } })) {
            pdf in
            PDFImportSheet(pdf: pdf) { pages in
                model.importPDF(data: pdf.data, filename: pdf.filename, pages: pages, folderID: folderID)
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView(sourceIDs: sources.map(\.id).filter(selection.contains))
        }
        .confirmationDialog("\(selection.count) kaynak silinsin mi?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                model.deleteSources(Array(selection))
                selection.removeAll()
                isSelecting = false
            }
        } message: {
            Text("Okunan metin, düzeltmeler ve kırpılan şekiller de silinir. Geri alınamaz.")
        }
    }

    // MARK: Bölümler

    private var visibleFolders: [Folder] {
        switch scope {
        case .all: return model.archive.subfolders(of: nil)
        case .folder(let id): return model.archive.subfolders(of: id)
        default: return []
        }
    }

    private func filtered(_ sources: [SourceAsset], summaries: [UUID: SourceSummary]) -> [SourceAsset] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sources }
        return sources.filter {
            $0.sourceTitle.localizedStandardContains(query)
                || (summaries[$0.id]?.text.localizedStandardContains(query) ?? false)
        }
    }

    private func breadcrumb(_ id: UUID) -> some View {
        let path = model.archive.folderPath(id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("Tümü") { selectScope(.all) }
                ForEach(path.dropLast()) { folder in
                    Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                    Button(folder.name) { selectScope(.folder(folder.id)) }
                }
            }
            .font(.subheadline)
        }
    }

    private func folderStrip(_ folders: [Folder]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Klasörler").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(folders) { folder in
                        FolderTile(folder: folder, count: model.archive.sources(inFolderTree: folder.id).count) {
                            selectScope(.folder(folder.id))
                        } onDrop: { ids in
                            model.move(sources: ids, toFolder: folder.id)
                        }
                    }
                    Button { newFolder(folderID) } label: {
                        Label("Yeni klasör", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .frame(width: 56, height: 72)
                    }
                    .secondaryButton()
                    .accessibilityLabel("Yeni klasör")
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView {
                Label(scope == .all ? "Arşiv boş" : "Burada henüz bir şey yok",
                      systemImage: scope == .marked ? "star" : "photo.on.rectangle.angled")
            } description: {
                Text(scope == .marked
                     ? "Yanına yıldız konmuş satırlar ve el notları olan kaynaklar burada toplanır."
                     : "Slayt ekran görüntüsü, kitap fotoğrafı veya PDF ekle; metni cihazında okunur.")
            } actions: {
                if scope != .marked && scope != .pending {
                    HStack {
                        Button { showPhotos = true } label: { Label("Fotoğraflar", systemImage: "photo") }
                            .prominentButton()
                        Button { showFiles = true } label: { Label("Dosyalar", systemImage: "doc") }
                            .secondaryButton()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    @ViewBuilder
    private func card(_ source: SourceAsset, summary: SourceSummary) -> some View {
        let selected = selection.contains(source.id)
        let content = SourceCard(source: source, summary: summary, selecting: isSelecting, selected: selected)
        if isSelecting {
            Button {
                if selected { selection.remove(source.id) } else { selection.insert(source.id) }
            } label: { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            NavigationLink(value: source.id) { content }
                .buttonStyle(.plain)
                .draggable(source.id.uuidString)
                .contextMenu { contextMenu(for: [source.id]) }
        }
    }

    // MARK: Araç çubuğu ve seçim

    @ToolbarContentBuilder
    private func toolbar(sources: [SourceAsset]) -> some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let all = Set(sources.map(\.id))
                Button(selection.isSuperset(of: all) && !all.isEmpty ? "Seçimi kaldır" : "Tümünü seç") {
                    selection = selection.isSuperset(of: all) ? [] : all
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bitti") {
                    isSelecting = false
                    selection.removeAll()
                }
                .fontWeight(.semibold)
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.isProcessing {
                    ProgressView().accessibilityLabel("Metin okunuyor")
                }
                if !sources.isEmpty {
                    Button("Seç") { isSelecting = true }
                }
                settingsMenu
                Menu {
                    Button { showPhotos = true } label: { Label("Fotoğraflardan", systemImage: "photo.on.rectangle") }
                    Button { showFiles = true } label: { Label("Dosyalardan (PDF, görsel)", systemImage: "doc") }
                    Divider()
                    Button { newFolder(folderID) } label: {
                        Label(folderID == nil ? "Yeni klasör" : "Alt klasör", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Ekle", systemImage: "plus")
                }
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Şekil önerilerini otomatik kaydet", isOn: $autoSaveFigures)
            if model.archive.figures.contains(where: { $0.status == .suggested }) {
                Button {
                    Task { await model.saveAllSuggestions() }
                } label: {
                    Label("Bekleyen tüm önerileri kaydet", systemImage: "checkmark.circle")
                }
            }
        } label: {
            Label("Ayarlar", systemImage: "gearshape")
        }
    }

    /// Seçim modunda altta yüzen cam eylem çubuğu: geniş, etiketli, parmakla rahat basılır.
    private var selectionBar: some View {
        let ids = Array(selection)
        return HStack(spacing: 4) {
            Button { showExport = true } label: { barLabel("Dışa aktar", "square.and.arrow.up") }
            Menu { moveMenu(ids) } label: { barLabel("Taşı", "folder") }
            Menu { exportStyleMenu(ids) } label: { barLabel("Aktarım", "photo.badge.checkmark") }
            Button(role: .destructive) { confirmDelete = true } label: { barLabel("Sil", "trash") }
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .padding(8)
        .frame(maxWidth: 620)
        .glassSurface(in: RoundedRectangle(cornerRadius: 28, style: .continuous), interactive: true)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .padding(.horizontal, 16)
        .disabled(ids.isEmpty)
        .opacity(ids.isEmpty ? 0.6 : 1)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func barLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func contextMenu(for ids: [UUID]) -> some View {
        Menu { moveMenu(ids) } label: { Label("Klasöre taşı", systemImage: "folder") }
        Menu { exportStyleMenu(ids) } label: { Label("Aktarım biçimi", systemImage: "photo.badge.checkmark") }
        Button(role: .destructive) {
            selection = Set(ids)
            confirmDelete = true
        } label: {
            Label("Sil", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func moveMenu(_ ids: [UUID]) -> some View {
        Button { done { model.move(sources: ids, toFolder: nil) } } label: {
            Label("Klasörsüz", systemImage: "tray")
        }
        Divider()
        ForEach(model.flatFolders()) { entry in
            Button(entry.indentedName) { done { model.move(sources: ids, toFolder: entry.folder.id) } }
        }
    }

    /// Sorunlu (karışık, el yazılı) sayfaları elle "sadece görsel" yapmak için.
    @ViewBuilder
    private func exportStyleMenu(_ ids: [UUID]) -> some View {
        Button { done { model.setImageOnly(true, sources: ids) } } label: {
            Label("Sadece görsel olarak aktar", systemImage: "photo")
        }
        Button { done { model.setImageOnly(false, sources: ids) } } label: {
            Label("Metin olarak aktar", systemImage: "text.alignleft")
        }
        Button { done { model.setImageOnly(nil, sources: ids) } } label: {
            Label("Uygulama karar versin", systemImage: "wand.and.stars")
        }
    }

    private func done(_ action: () -> Void) {
        action()
        selection.removeAll()
        isSelecting = false
    }

    // MARK: İçeri alma

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                model.importImage(data: data, filename: "image-\(index + 1).\(ext)", folderID: folderID)
            } catch {
                model.lastError = "Görsel alınamadı: \(error.localizedDescription)"
            }
        }
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                model.lastError = "\(url.lastPathComponent) okunamadı."
                continue
            }
            let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
            if isPDF {
                let pageCount = PDFSupport.info(data: data)?.sizes.count ?? 0
                if pageCount > 1 {
                    pendingPDFs.append(PendingPDF(data: data, filename: url.lastPathComponent, pageCount: pageCount))
                } else {
                    model.importPDF(data: data, filename: url.lastPathComponent, folderID: folderID)
                }
            } else {
                model.importImage(data: data, filename: url.lastPathComponent, folderID: folderID)
            }
        }
    }
}

/// Galeri kartı: sayfa görüntüsü, başlık ve kısa bilgi.
struct SourceCard: View {
    @EnvironmentObject private var model: AppModel
    let source: SourceAsset
    let summary: SourceSummary
    var selecting = false
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { thumbnail }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let status = summary.attention {
                        StatusBadge(status: status).padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.9),
                                             selected ? Theme.accent : Color.black.opacity(0.25))
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) { chips.padding(6) }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Color.primary.opacity(0.06),
                                      lineWidth: selected ? 3 : 1)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(source.sourceTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .cardBackground()
        .scaleEffect(selected ? 0.97 : 1)
        .animation(.snappy(duration: 0.2), value: selected)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        let page = model.archive.pages(of: source.id).first
        let url = page.flatMap(model.pageImageURL(for:)) ?? model.originalURL(for: source)
        return ThumbnailView(url: url, maxPixel: 600)
    }

    private var meta: String {
        var parts: [String] = []
        if source.mediaType == .pdf {
            parts.append("PDF · \(summary.pageCount) sayfa")
            if summary.readCount < summary.pageCount { parts.append("\(summary.readCount) okundu") }
        } else {
            parts.append(source.importedAt.formatted(.dateTime.day().month(.abbreviated)))
        }
        if summary.savedFigures > 0 { parts.append("\(summary.savedFigures) şekil") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var chips: some View {
        HStack(spacing: 4) {
            if summary.markedLines > 0 {
                InfoChip(symbol: "star.fill", text: "\(summary.markedLines)", tint: Theme.star)
                    .accessibilityLabel("\(summary.markedLines) işaretli satır")
            }
            if summary.notes > 0 {
                InfoChip(symbol: "pencil.and.scribble", text: "\(summary.notes)", tint: Theme.note)
                    .accessibilityLabel("\(summary.notes) el notu satırı")
            }
            if summary.imageOnlyPages > 0 {
                InfoChip(symbol: "photo", tint: .secondary)
                    .accessibilityLabel("Görsel olarak aktarılır")
            }
            if summary.suggestedFigures > 0 {
                InfoChip(symbol: "crop", text: "\(summary.suggestedFigures)")
                    .accessibilityLabel("\(summary.suggestedFigures) şekil önerisi")
            }
        }
    }
}

/// Klasör kutucuğu; üstüne kaynak sürüklenip bırakılabilir.
private struct FolderTile: View {
    let folder: Folder
    let count: Int
    let open: () -> Void
    let onDrop: ([UUID]) -> Void
    @State private var targeted = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent.gradient)
                Spacer(minLength: 0)
                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(count) kaynak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 128, height: 72, alignment: .leading)
            .padding(12)
            .cardBackground()
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: targeted ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(UUID.init(uuidString:))
            guard !ids.isEmpty else { return false }
            onDrop(ids)
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// İçeri alınmayı bekleyen çok sayfalı PDF.
struct PendingPDF: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
    let pageCount: Int
}
