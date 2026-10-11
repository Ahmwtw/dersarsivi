import DersArsiviCore
import SwiftUI

struct SourceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let sourceID: UUID
    @State private var editingBlock: Block?
    @State private var title = ""
    @State private var showOriginal = false

    private var source: SourceAsset? { model.archive.source(sourceID) }
    private var page: Page? { model.archive.pages(of: sourceID).first }
    private var blocks: [Block] { page.map { model.archive.blocks(of: $0.id) } ?? [] }

    var body: some View {
        if let source, let page {
            List {
                Section {
                    Button { showOriginal = true } label: {
                        ThumbnailView(url: model.pageImageURL(for: page) ?? model.originalURL(for: source),
                                      maxPixel: 1200, contentMode: .fit)
                            .frame(maxHeight: 320)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Orijinal görseli tam ekran aç")
                    TextField("Başlık", text: $title)
                        .onSubmit { model.rename(sourceID: sourceID, to: title) }
                    LabeledContent("Durum") { StatusBadge(status: page.status) }
                    if page.workingImageRef != nil {
                        Label("Eğik fotoğraf okumadan önce düzleştirildi", systemImage: "perspective")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let reason = page.failureReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                    if page.status == .failed {
                        Button("Yeniden dene") { model.retry(pageID: page.id) }
                    } else if [.ready, .needsReview].contains(page.status) {
                        // Okuma ayarları değiştiyse yeniden okur; düzeltmelerin korunur.
                        Button("Yeniden oku") { model.retry(pageID: page.id) }
                    }
                }

                FiguresSection(source: source, page: page)

                Section {
                    if blocks.isEmpty {
                        Text(page.status == .ready ? "Bu görselde metin bulunamadı." : "Metin henüz okunmadı.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(blocks) { block in
                        Button { editingBlock = block } label: { BlockRow(block: block) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Çıkarılan metin")
                } footer: {
                    Text("Bir satıra dokunarak düzelt. Düzeltmen sonraki okumalarda korunur ve dışa aktarımda kullanılır.")
                }

                Section("Okuma ayarı") {
                    LabeledContent("Motor", value: "Apple Vision (cihazda)")
                    LabeledContent("Kullanılan diller", value: VisionTextExtractor.usableLanguages().joined(separator: ", "))
                    DisclosureGroup("Cihazın desteklediği diller") {
                        Text(VisionTextExtractor.supportedLanguages().joined(separator: ", "))
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(source.sourceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { title = source.sourceTitle }
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
}

private struct BlockRow: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let runs = block.runs, !block.isUserCorrected {
                Text(Self.attributed(runs))
            } else {
                Text(block.acceptedText)
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
                if let image = UIImage(contentsOfFile: url.path) {
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
