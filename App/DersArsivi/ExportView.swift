import DersArsiviCore
import SwiftUI

struct ExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sourceIDs: [UUID]
    @State private var mode: ExportMode = .combined
    @State private var files: [URL] = []

    private var unprocessedCount: Int {
        sourceIDs.flatMap { model.archive.pages(of: $0) }
            .filter { ![.ready, .needsReview, .partial].contains($0.status) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Dosya", selection: $mode) {
                        Text("Tek birleşik dosya").tag(ExportMode.combined)
                        Text("Kaynak başına ayrı").tag(ExportMode.perSource)
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("Biçim: Markdown (.md). Görseller dosyaya eklenmez; yalnız metin ve kaynak bilgisi.")
                }
                if unprocessedCount > 0 {
                    Section {
                        Label("\(unprocessedCount) görsel henüz okunmadı. Dosyada eksik olarak belirtilecek.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    if files.isEmpty {
                        Button("Dosyayı hazırla") {
                            files = model.exportMarkdown(sourceIDs: sourceIDs, mode: mode)
                        }
                    } else {
                        ForEach(files, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: "doc.text")
                        }
                        ShareLink(items: files) {
                            Label("Paylaş", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onChange(of: mode) { _, _ in files = [] }
            .navigationTitle("\(sourceIDs.count) kaynak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
            }
        }
    }
}
