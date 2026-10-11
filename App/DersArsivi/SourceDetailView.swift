import DersArsiviCore
import SwiftUI

struct SourceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let sourceID: UUID
    @State private var editingBlock: Block?
    @State private var title = ""
    @State private var showOriginal = false
    @State private var confirmDelete = false
    @State private var pageIndex = 0
    @Environment(\.dismiss) private var dismiss

    private var source: SourceAsset? { model.archive.source(sourceID) }
    private var pages: [Page] { model.archive.pages(of: sourceID) }
    private var page: Page? { pages.first { $0.pageIndex == pageIndex } ?? pages.first }
    private var blocks: [Block] { page.map { model.archive.blocks(of: $0.id) } ?? [] }

    var body: some View {
        if let source, let page {
            List {
                Section {
                    Button { showOriginal = true } label: {
                        ThumbnailView(url: model.pageImageURL(for: page) ?? model.originalURL(for: source),
                                      maxPixel: 1400, contentMode: .fit)
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sayfayı tam ekran aç")
                    if pages.count > 1 { pageStrip }
                    TextField("Başlık", text: $title)
                        .font(.headline)
                        .onSubmit { model.rename(sourceID: sourceID, to: title) }
                }

                statusSection(page)
                exportStyleSection(source: source, page: page)

                FiguresSection(source: source, page: page)

                Section {
                    if blocks.isEmpty {
                        Text(page.status == .ready ? "Bu sayfada metin bulunamadı." : "Metin henüz okunmadı.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(blocks) { block in
                        Button { editingBlock = block } label: { BlockRow(block: block) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Çıkarılan metin")
                } footer: {
                    Text("Bir satıra dokunarak düzelt. Düzeltmen sonraki okumalarda korunur ve dışa aktarımda kullanılır. "
                         + "⭐ yanına işaret konmuş, ✍️ el yazısı satırdır.")
                }

                Section {
                    DisclosureGroup("Okuma ayarı") {
                        LabeledContent("Motor", value: source.mediaType == .pdf
                                       ? "PDF metin katmanı, yoksa Apple Vision" : "Apple Vision (cihazda)")
                        LabeledContent("Kullanılan diller",
                                       value: VisionTextExtractor.usableLanguages().joined(separator: ", "))
                    }
                }
            }
            .navigationTitle(source.sourceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Menu {
                            Button("Klasörsüz") { model.move(sources: [sourceID], toFolder: nil) }
                            ForEach(model.flatFolders()) { entry in
                                Button(entry.indentedName) { model.move(sources: [sourceID], toFolder: entry.folder.id) }
                            }
                        } label: {
                            Label("Klasöre taşı", systemImage: "folder")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    } label: {
                        Label("Diğer", systemImage: "ellipsis")
                    }
                }
            }
            .confirmationDialog("Bu kaynak silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    dismiss()
                    model.deleteSources([sourceID])
                }
            } message: {
                Text("Okunan metin, düzeltmeler ve kırpılan şekiller de silinir. Geri alınamaz.")
            }
            .onAppear { title = source.sourceTitle }
            // Okuma bitince geçici başlık sayfanın başlığıyla değişebilir.
            .onChange(of: source.sourceTitle) { _, newTitle in title = newTitle }
            .onDisappear { model.rename(sourceID: sourceID, to: title) }
            .sheet(item: $editingBlock) { block in
                CorrectionSheet(block: block) { newText in
                    model.correct(blockID: block.id, text: newText)
                }
            }
            .fullScreenCover(isPresented: $showOriginal) {
                OriginalImageView(url: model.pageImageURL(for: page) ?? model.originalURL(for: source))
            }
        } else {
            ContentUnavailableView("Kaynak bulunamadı", systemImage: "questionmark.folder")
        }
    }

    /// PDF sayfaları arasında geçiş: küçük resim şeridi, okunmamış sayfalar soluk.
    private var pageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(pages) { p in
                        let selected = p.pageIndex == pageIndex
                        let read = [.ready, .needsReview, .partial].contains(p.status)
                        Button { pageIndex = p.pageIndex } label: {
                            VStack(spacing: 4) {
                                ThumbnailView(url: model.pageImageURL(for: p) ?? model.originalURL(for: source!),
                                              maxPixel: 200)
                                    .frame(width: 52, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .opacity(read ? 1 : 0.45)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2.5)
                                    }
                                Text(p.pdfPageLabel ?? "\(p.pageIndex + 1)")
                                    .font(.caption2.weight(selected ? .bold : .regular))
                                    .foregroundStyle(selected ? Theme.accent : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(p.pageIndex)
                        .accessibilityLabel("Sayfa \(p.pageIndex + 1)\(read ? "" : ", okunmadı")")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 96)
            .onChange(of: pageIndex) { _, index in withAnimation { proxy.scrollTo(index, anchor: .center) } }
        }
    }

    @ViewBuilder
    private func statusSection(_ page: Page) -> some View {
        let unread = pages.filter { [.imported, .cancelled].contains($0.status) }
        Section {
            LabeledContent("Durum") { StatusBadge(status: page.status) }
            if page.workingImageRef != nil && source?.mediaType != .pdf {
                Label("Eğik fotoğraf okumadan önce düzleştirildi", systemImage: "perspective")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let reason = page.failureReason {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
            switch page.status {
            case .failed:
                Button("Yeniden dene") { model.retry(pageID: page.id) }
            case .ready, .needsReview, .partial:
                Button("Yeniden oku") { model.retry(pageID: page.id) }
            case .imported, .cancelled:
                Button("Bu sayfayı oku") { model.readPages([page.id]) }
            default:
                EmptyView()
            }
            if unread.count > 1 {
                Button("Okunmamış \(unread.count) sayfayı oku") { model.readPages(unread.map(\.id)) }
            }
        } footer: {
            if [.ready, .needsReview].contains(page.status) {
                Text("Yeniden oku sayfayı baştan okur. Metin düzeltmelerin, kaydettiğin ve yoksaydığın şekiller korunur; yalnız bekleyen şekil önerileri yenilenir.")
            }
        }
    }

    /// Sayfa metin mi görüntü mü aktarılsın: uygulamanın kararı ve kullanıcının seçimi.
    private func exportStyleSection(source: SourceAsset, page: Page) -> some View {
        let binding = Binding<Int>(
            get: { source.imageOnly.map { $0 ? 1 : 2 } ?? 0 },
            set: { model.setImageOnly($0 == 0 ? nil : $0 == 1, sources: [sourceID]) })
        return Section {
            Picker("Dışa aktarım", selection: binding) {
                Text("Otomatik").tag(0)
                Text("Görsel").tag(1)
                Text("Metin").tag(2)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Dışa aktarım")
        } footer: {
            Text(exportStyleNote(source: source, page: page))
        }
    }

    private func exportStyleNote(source: SourceAsset, page: Page) -> String {
        switch source.imageOnly {
        case true?:
            return "Sayfa metin yerine görüntü olarak aktarılır; yapay zekâ görüntüyü kendisi okur. Karmaşık slaytlar ve el yazılı sayfalar için."
        case false?:
            return "Sayfa her zaman okunan metinle aktarılır."
        case nil:
            if page.looksComplex == true {
                let share = Int(((page.handwritingShare ?? 0) * 100).rounded())
                return "Sayfa karışık görünüyor (metnin %\(share)'i el yazısı); görüntü olarak aktarılacak."
            }
            return "Uygulama karar verir: el yazısı ağırlıklı veya okunması güç sayfalar görüntü olarak, diğerleri metin olarak aktarılır."
        }
    }
}

private struct BlockRow: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if block.marked == true {
                    Image(systemName: "star.fill").foregroundStyle(Theme.star)
                        .accessibilityLabel("İşaretli")
                }
                if block.kind == .handwriting {
                    Image(systemName: "pencil.and.scribble").foregroundStyle(Theme.note)
                        .accessibilityLabel("El yazısı")
                }
                if let runs = block.runs, !block.isUserCorrected {
                    Text(Self.attributed(runs))
                } else {
                    Text(block.acceptedText)
                }
            }
            HStack(spacing: 8) {
                if block.isUserCorrected {
                    Label("Düzeltildi", systemImage: "pencil").foregroundStyle(.blue)
                }
                if block.reviewStatus == .conflict {
                    Label("Yeni okuma farklı", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if !block.isUserCorrected, let c = block.engineConfidence, c < 0.5 {
                    Label("Belirsiz okuma", systemImage: "questionmark.circle").foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Algılanan vurgu ve renkleri ekranda da gösterir; doğru algılanıp algılanmadığı gözle kontrol edilsin.
    static func attributed(_ runs: [TextRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if let h = run.highlight { piece.backgroundColor = h.swiftUIColor.opacity(0.35) }
            if let c = run.color { piece.foregroundColor = c.swiftUIColor }
            result += piece
        }
        return result
    }
}

extension NamedColor {
    var swiftUIColor: Color {
        switch self {
        case .kirmizi: .red
        case .turuncu: .orange
        case .sari: .yellow
        case .yesil: .green
        case .mavi: .blue
        case .mor: .purple
        case .pembe: .pink
        }
    }
}

private struct CorrectionSheet: View {
    let block: Block
    let onSave: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(block: Block, onSave: @escaping (String) -> Void) {
        self.block = block
        self.onSave = onSave
        _text = State(initialValue: block.acceptedText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metin") {
                    TextEditor(text: $text).frame(minHeight: 120)
                }
                if block.rawText != block.acceptedText {
                    Section("Makinenin okuduğu") {
                        Text(block.rawText).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Düzelt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct OriginalImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                if let image = ThumbnailLoader.thumbnail(for: url, maxPixel: 3000) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: UIScreen.main.bounds.width * scale)
                        .gesture(MagnifyGesture().onChanged { scale = max(1, min(5, $0.magnification)) })
                } else {
                    ContentUnavailableView("Orijinal bulunamıyor", systemImage: "exclamationmark.triangle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
            }
        }
    }
}
