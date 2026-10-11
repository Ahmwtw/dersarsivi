import DersArsiviCore
import SwiftUI

struct ExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sourceIDs: [UUID]
    @State private var mode: ExportMode = .combined
    @State private var files: [URL] = []
    @State private var withFigures = true
    @AppStorage("exportPageImages") private var withPages = false
    /// Son seçilen talimat; boş: talimatsız.
    @AppStorage("exportPromptID") private var promptID = ""
    @State private var debugFiles: [URL] = []
    @State private var copied = false

    private var template: PromptTemplate? { PromptLibrary.template(id: promptID) }

    private var savedFigureCount: Int {
        sourceIDs.flatMap { model.archive.pages(of: $0) }
            .flatMap { model.archive.figures(of: $0.id) }
            .filter { $0.status == .accepted }.count
    }

    private var imageOnlyCount: Int {
        sourceIDs.flatMap { model.archive.pages(of: $0) }.filter { model.archive.isImageOnly($0) }.count
    }

    private var unprocessedCount: Int {
        sourceIDs.flatMap { model.archive.pages(of: $0) }
            .filter { ![.ready, .needsReview, .partial].contains($0.status) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                promptSection
                Section {
                    Picker("Dosya", selection: $mode) {
                        Text("Tek dosya").tag(ExportMode.combined)
                        Text("Kaynak başına").tag(ExportMode.perSource)
                    }
                    .pickerStyle(.segmented)
                    if savedFigureCount > 0 {
                        Toggle(isOn: $withFigures) {
                            Label("Şekil görselleri (\(savedFigureCount))", systemImage: "photo.on.rectangle")
                        }
                    }
                    Toggle(isOn: $withPages) {
                        Label("Sayfa görüntüleri", systemImage: "doc.richtext")
                    }
                } header: {
                    Text("Paket")
                } footer: {
                    Text(packageNote)
                }
                if unprocessedCount > 0 {
                    Section {
                        Label("\(unprocessedCount) sayfa henüz okunmadı. Dosyada eksik olarak belirtilecek.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    if files.isEmpty {
                        Button {
                            files = model.exportFiles(sourceIDs: sourceIDs, mode: mode,
                                                      withFigures: withFigures && savedFigureCount > 0,
                                                      withPages: withPages, prompt: template)
                        } label: {
                            Label("Dosyayı hazırla", systemImage: "shippingbox")
                                .frame(maxWidth: .infinity)
                        }
                        .prominentButton()
                        .controlSize(.large)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(files, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: url.pathExtension == "zip" ? "doc.zipper" : "doc.text")
                        }
                        ShareLink(items: files) {
                            Label("Paylaş veya kaydet", systemImage: "square.and.arrow.up")
                        }
                    }
                } footer: {
                    if !files.isEmpty {
                        Text(template == nil
                             ? "Dosyayı ChatGPT, Claude veya Gemini sohbetine ekle."
                             : "Dosyayı sohbete ekleyip yalnız \"Dosyadaki talimatı uygula\" yazman yeterli; talimat dosyanın başında.")
                    }
                }
                Section {
                    DisclosureGroup("Geliştirici") {
                        if debugFiles.isEmpty {
                            Button("Ölçüm paketi hazırla") {
                                debugFiles = model.debugPack(sourceIDs: sourceIDs).map { [$0] } ?? []
                            }
                        } else {
                            ShareLink(items: debugFiles) {
                                Label("Ölçüm paketini paylaş", systemImage: "ladybug")
                            }
                        }
                        Text("Orijinal görseller, okunan satırlar, şekil önerileri ve kararların. Algılamayı cihazdakiyle "
                             + "aynı girdilerle ölçmeye yarar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: mode) { _, _ in files = [] }
            .onChange(of: withFigures) { _, _ in files = [] }
            .onChange(of: withPages) { _, _ in files = [] }
            .onChange(of: promptID) { _, _ in
                files = []
                if template?.recommendsImages == true { withPages = true }
            }
            .navigationTitle("Dışa aktar · \(sourceIDs.count) kaynak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
            }
        }
    }

    private var promptSection: some View {
        Section {
            NavigationLink {
                PromptPickerView(selection: $promptID)
            } label: {
                if let template {
                    HStack(spacing: 12) {
                        PromptIcon(symbol: template.symbol, category: template.category)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title).font(.body.weight(.semibold))
                            Text(template.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        PromptIcon(symbol: "doc.plaintext", category: nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Talimatsız").font(.body.weight(.semibold))
                            Text("Yalnız kaynak metni; ne isteyeceğini sohbette yazarsın")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let template {
                LabeledContent("Alacağın çıktı", value: template.outputHint)
                if template.category == .anki {
                    LabeledContent("Anki destesi", value: model.deckName(for: sourceIDs))
                }
                Button {
                    model.copyPrompt(template, sourceIDs: sourceIDs, includesImages: withPages || withFigures)
                    copied = true
                } label: {
                    Label(copied ? "Talimat kopyalandı" : "Yalnız talimatı kopyala",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .onChange(of: promptID) { _, _ in copied = false }
            }
        } header: {
            Text("Yapay zekâya ne yaptıracaksın?")
        } footer: {
            if template?.recommendsImages == true {
                Text("Bu talimat görüntüleri de kullanır; sayfa görüntüleri açıldı.")
            }
        }
    }

    private var packageNote: String {
        var parts: [String] = []
        if withPages || (withFigures && savedFigureCount > 0) || imageOnlyCount > 0 {
            parts.append("Tek ZIP: Markdown, görseller ve manifest.json.")
        } else {
            parts.append("Markdown (.md) dosyası, kaynak ve sayfa bilgisiyle.")
        }
        if imageOnlyCount > 0 {
            parts.append("\(imageOnlyCount) sayfa metin yerine görüntü olarak eklenecek.")
        }
        if withPages {
            parts.append("Her sayfanın düzleştirilmiş görüntüsü de eklenir; yapay zekâ karışık sayfaları kendisi okuyabilir.")
        }
        return parts.joined(separator: " ")
    }
}

/// Talimat listesi: kategorilere göre gruplu, her biri simge, başlık ve tek satır açıklamayla.
struct PromptPickerView: View {
    @Environment(\.palette) private var palette
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(id: "", title: "Talimatsız", summary: "Yalnız kaynak paketi", symbol: "doc.plaintext", category: nil)
            }
            ForEach(PromptTemplate.Category.allCases, id: \.self) { category in
                Section(category.title) {
                    ForEach(PromptLibrary.all.filter { $0.category == category }) { t in
                        row(id: t.id, title: t.title, summary: t.summary, symbol: t.symbol, category: t.category,
                            images: t.recommendsImages)
                    }
                }
            }
        }
        .navigationTitle("Hazır talimatlar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(id: String, title: String, summary: String, symbol: String,
                     category: PromptTemplate.Category?, images: Bool = false) -> some View {
        Button {
            selection = id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                PromptIcon(symbol: symbol, category: category)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.body.weight(.medium))
                        if images {
                            Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Görüntü kullanır")
                        }
                    }
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if selection == id {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kategori renginde yuvarlak köşeli simge.
struct PromptIcon: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let category: PromptTemplate.Category?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tint: Color {
        switch category {
        case .study: return palette.accent
        case .anki: return .teal
        case .questions: return .orange
        case .review: return .purple
        case nil: return .gray
        }
    }
}
