import DersArsiviCore
import SwiftUI

struct ExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sourceIDs: [UUID]
    @State private var mode: ExportMode = .combined
    @State private var files: [URL] = []
    @State private var withFigures = true

    private var savedFigureCount: Int {
        sourceIDs.flatMap { model.archive.pages(of: $0) }
            .flatMap { model.archive.figures(of: $0.id) }
            .filter { $0.status == .accepted }.count
    }

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
                    Text("Biçim: Markdown (.md), kaynak bilgisiyle.")
                }
                if savedFigureCount > 0 {
                    Section {
                        Toggle("Şekil görsellerini ekle (\(savedFigureCount))", isOn: $withFigures)
                    } footer: {
                        Text(withFigures
                             ? "Tek ZIP dosyası: Markdown, figures/ klasöründe şekiller ve etiket konumlarıyla manifest.json."
                             : "Yalnız Markdown; şekillerin yeri ve etiketleri yazılır, görselleri eklenmez.")
                    }
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
                            files = model.exportFiles(sourceIDs: sourceIDs, mode: mode,
                                                      withFigures: withFigures && savedFigureCount > 0)
                        }
                    } else {
                        ForEach(files, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: url.pathExtension == "zip" ? "doc.zipper" : "doc.text")
                        }
                        ShareLink(items: files) {
                            Label("Paylaş", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onChange(of: mode) { _, _ in files = [] }
            .onChange(of: withFigures) { _, _ in files = [] }
            .navigationTitle("\(sourceIDs.count) kaynak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
            }
        }
    }
}
