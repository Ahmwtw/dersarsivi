import DersArsiviCore
import SwiftUI

struct SourceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
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

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if let source, let page {
            GeometryReader { geo in
                if sizeClass == .regular && geo.size.width >= 760 {
                    // Geniş iPad ekranı: sayfa solda (satırlara dokunup düzelt), bilgiler ve metin sağda.
                    HStack(spacing: 0) {
                        PageCanvas(url: model.pageImageURL(for: page) ?? model.originalURL(for: source),
                                   blocks: blocks, highlighted: editingBlock?.id) { editingBlock = $0 }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemBackground))
                        Divider().ignoresSafeArea()
                        detailList(source: source, page: page, showsPage: false)
                            .frame(width: min(440, geo.size.width * 0.42))
                    }
                } else {
                    detailList(source: source, page: page, showsPage: true)
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
                OriginalImageView(url: model.pageImageURL(for: page) ?? model.originalURL(for: source),
                                  pageID: page.id)
                    .environmentObject(model)
                    .environment(\.palette, palette)
            }
        } else {
            ContentUnavailableView("Kaynak bulunamadı", systemImage: "questionmark.folder")
        }
    }

    /// Kaynak bilgileri, sayfa durumu, aktarım biçimi, şekiller ve okunan metin. iPad'de sayfa ayrı panelde
    /// durduğu için burada gösterilmez.
    private func detailList(source: SourceAsset, page: Page, showsPage: Bool) -> some View {
        List {
            Section {
                if showsPage {
                    Button { showOriginal = true } label: {
                        ThumbnailView(url: model.pageImageURL(for: page) ?? model.originalURL(for: source),
                                      maxPixel: 1400, contentMode: .fit)
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Label("Sayfada düzelt", systemImage: "text.viewfinder")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .glassCapsule()
                                    .padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sayfayı tam ekran aç, satırlara dokunarak düzelt")
                }
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
                Text("Bir satıra (veya sayfadaki kutusuna) dokunarak düzelt. Düzeltmen sonraki okumalarda korunur ve "
                     + "dışa aktarımda kullanılır. ⭐ yanına işaret konmuş, ✍️ el yazısı satırdır.")
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
                                            .strokeBorder(selected ? palette.accent : .clear, lineWidth: 2.5)
                                    }
                                Text(p.pdfPageLabel ?? "\(p.pageIndex + 1)")
                                    .font(.caption2.weight(selected ? .bold : .regular))
                                    .foregroundStyle(selected ? palette.accent : .secondary)
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
    @Environment(\.palette) private var palette
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if block.marked == true {
                    Image(systemName: "star.fill").foregroundStyle(palette.star)
                        .accessibilityLabel("İşaretli")
                }
                if block.kind == .handwriting {
                    Image(systemName: "pencil.and.scribble").foregroundStyle(palette.note)
                        .accessibilityLabel("El yazısı")
                }
                if block.kind == .table, let grid = TableLayout.parse(block.acceptedText) {
                    TableGrid(rows: grid)
                } else if let runs = block.runs, !block.isUserCorrected {
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

/// Okunan tablo: ilk satır başlık, sütunlar hizalı. Geniş tablo yatayda kaydırılır.
private struct TableGrid: View {
    @Environment(\.palette) private var palette
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(rows[r].indices, id: \.self) { c in
                            Text(rows[r][c].isEmpty ? " " : rows[r][c])
                                .font(r == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                .frame(maxWidth: 220, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxHeight: .infinity, alignment: .topLeading)
                                .background(r == 0 ? palette.accent.opacity(0.12) : Color.clear)
                                .overlay { Rectangle().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5) }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tablo, \(rows.count) satır")
    }
}

struct CorrectionSheet: View {
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
                Section {
                    TextEditor(text: $text)
                        .font(block.kind == .table ? .system(.callout, design: .monospaced) : .body)
                        .frame(minHeight: block.kind == .table ? 220 : 120)
                } header: {
                    Text(block.kind == .table ? "Tablo" : "Metin")
                } footer: {
                    if block.kind == .table {
                        Text("Her satır bir tablo satırı; hücreleri | ile ayır. İkinci satır (| --- |) başlığı ayırır.")
                    }
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

/// Tam ekran sayfa: yakınlaştırılır, satır kutusuna dokununca düzeltme açılır.
private struct OriginalImageView: View {
    @EnvironmentObject private var model: AppModel
    let url: URL
    let pageID: UUID
    @State private var editing: Block?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PageCanvas(url: url, blocks: model.archive.blocks(of: pageID), highlighted: editing?.id) { editing = $0 }
                .background(Color(.secondarySystemBackground))
                .navigationTitle("Sayfa")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
                }
                .sheet(item: $editing) { block in
                    CorrectionSheet(block: block) { newText in
                        model.correct(blockID: block.id, text: newText)
                    }
                }
        }
    }
}
