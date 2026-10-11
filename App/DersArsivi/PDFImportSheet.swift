import DersArsiviCore
import SwiftUI

/// Çok sayfalı PDF'te hangi sayfaların hemen okunacağını sorar. Seçilmeyen sayfalar da arşive girer;
/// sonra kaynak ekranından okutulabilir.
struct PDFImportSheet: View {
    let pdf: PendingPDF
    let onImport: ([Int]?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allPages = true
    @State private var text = ""
    @State private var preview: UIImage?

    private var parsed: Result<PageSelection, Error> {
        Result { try PageSelection.parse(text, pageCount: pdf.pageCount) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let preview {
                                Image(uiImage: preview).resizable().scaledToFit()
                            } else {
                                Color(.tertiarySystemFill)
                            }
                        }
                        .frame(width: 64, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pdf.filename).font(.headline).lineLimit(2)
                            Text("\(pdf.pageCount) sayfa").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Picker("Okunacak sayfalar", selection: $allPages) {
                        Text("Tümü").tag(true)
                        Text("Seçili sayfalar").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if !allPages {
                        TextField("ör. 1-5, 8, 12-14", text: $text)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                        if !text.isEmpty {
                            switch parsed {
                            case .success(let selection):
                                Label("\(selection.indices.count) sayfa okunacak", systemImage: "checkmark.circle")
                                    .foregroundStyle(.green)
                            case .failure(let error):
                                Label(Self.message(error, pageCount: pdf.pageCount), systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } footer: {
                    Text("Metin katmanı olan PDF'lerde yazı doğrudan PDF'ten alınır (hızlı, hatasız); taranmış sayfalar "
                         + "cihazda OCR ile okunur. Seçilmeyen sayfalar da arşive eklenir, sonra istediğinde okutabilirsin.")
                }
            }
            .navigationTitle("PDF ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        if allPages {
                            onImport(nil)
                        } else if case .success(let selection) = parsed {
                            onImport(selection.indices)
                        }
                        dismiss()
                    }
                    .disabled(!allPages && (try? parsed.get()) == nil)
                }
            }
            .task {
                let data = pdf.data
                preview = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("onizleme-\(UUID().uuidString).pdf")
                    guard (try? data.write(to: url)) != nil else { return nil }
                    defer { try? FileManager.default.removeItem(at: url) }
                    return PDFSupport.thumbnail(url: url, pageIndex: 0, maxSide: 300)
                }.value
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func message(_ error: Error, pageCount: Int) -> String {
        switch error as? PageSelection.ParseError {
        case .empty: return "Sayfa yaz"
        case .invalidToken(let token): return "\"\(token)\" anlaşılamadı"
        case .outOfRange(let page, _): return "\(page). sayfa yok (PDF \(pageCount) sayfa)"
        case .reversedRange(let token): return "\"\(token)\" ters aralık"
        case nil: return "Sayfa seçimi anlaşılamadı"
        }
    }
}
