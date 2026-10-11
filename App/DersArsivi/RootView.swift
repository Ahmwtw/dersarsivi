import DersArsiviCore
import SwiftUI

/// iPad'de kenar çubuğu + içerik; iPhone'da aynı yapı yığın olarak açılır ve doğrudan içerikten başlar.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scope: LibraryScope? = .all
    @State private var compactColumn = NavigationSplitViewColumn.detail
    @State private var path = NavigationPath()
    @State private var newFolderParent: UUID??
    @State private var folderName = ""
    @State private var renaming: Folder?
    @State private var deleting: Folder?

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                LibraryView(scope: scope ?? .all, selectScope: select,
                            newFolder: { newFolderParent = .some($0) })
                    .navigationDestination(for: UUID.self) { id in
                        SourceDetailView(sourceID: id)
                    }
            }
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) { noticeBanner }
        .animation(.snappy, value: model.notice)
        .onChange(of: scope) { _, _ in path = NavigationPath() }
        .alert("Yeni klasör", isPresented: Binding(get: { newFolderParent != nil },
                                                   set: { if !$0 { newFolderParent = nil } })) {
            TextField("Ad (ör. Fizyoloji)", text: $folderName)
            Button("Oluştur") {
                if let parent = newFolderParent, let folder = model.createFolder(name: folderName, parentID: parent) {
                    select(.folder(folder.id))
                }
                folderName = ""
            }
            Button("Vazgeç", role: .cancel) { folderName = "" }
        } message: {
            if let parent = newFolderParent ?? nil, let folder = model.archive.folder(parent) {
                Text("\(folder.name) içinde")
            }
        }
        .alert("Klasörü yeniden adlandır", isPresented: Binding(get: { renaming != nil },
                                                               set: { if !$0 { renaming = nil } })) {
            TextField("Ad", text: $folderName)
            Button("Kaydet") {
                if let renaming { model.renameFolder(renaming.id, to: folderName) }
                folderName = ""
            }
            Button("Vazgeç", role: .cancel) { folderName = "" }
        }
        .confirmationDialog("\(deleting?.name ?? "Klasör") silinsin mi?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Klasörü sil", role: .destructive) {
                if let deleting {
                    if scope == .folder(deleting.id) {
                        scope = deleting.parentID.map(LibraryScope.folder) ?? .all
                    }
                    model.deleteFolder(deleting.id)
                }
            }
        } message: {
            Text("İçindeki görseller, PDF'ler ve alt klasörler silinmez; bir üst klasöre taşınır.")
        }
    }

    /// Hata olmayan kısa bilgi: üstte cam kapsül, birkaç saniye sonra kaybolur; dokununca kapanır.
    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            Label(notice, systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassSurface(in: Capsule())
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { model.notice = nil }
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(4))
                    if model.notice == notice { model.notice = nil }
                }
        }
    }

    private func select(_ newScope: LibraryScope) {
        scope = newScope
        compactColumn = .detail
    }

    private var sidebar: some View {
        let summaries = model.summaries()
        return List(selection: $scope) {
            Section {
                row("Tüm kaynaklar", symbol: "square.grid.2x2", scope: .all, count: model.archive.sources.count)
                row("Klasörsüz", symbol: "tray", scope: .unfiled,
                    count: model.archive.sources.filter { $0.folderID == nil }.count)
                row("İşaretli ve notlu", symbol: "star", scope: .marked,
                    count: summaries.values.filter(\.hasHighlights).count)
                let pending = summaries.values.filter { $0.attention != nil }.count
                if pending > 0 {
                    row("Okunmayı bekleyen", symbol: "hourglass", scope: .pending, count: pending)
                }
            }
            Section {
                OutlineGroup(model.folderTree(), children: \.children) { node in
                    folderRow(node.folder)
                }
                Button {
                    newFolderParent = .some(nil)
                } label: {
                    Label("Yeni klasör", systemImage: "folder.badge.plus")
                }
                .foregroundStyle(Theme.accent)
            } header: {
                Text("Klasörler")
            }
        }
        .navigationTitle("DersArşivi")
        .listStyle(.sidebar)
    }

    private func row(_ title: String, symbol: String, scope: LibraryScope, count: Int) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
        } icon: {
            Image(systemName: symbol)
        }
        .tag(scope)
    }

    private func folderRow(_ folder: Folder) -> some View {
        Label {
            HStack {
                Text(folder.name)
                Spacer()
                Text("\(model.archive.sources(inFolderTree: folder.id).count)")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        } icon: {
            Image(systemName: "folder")
        }
        .tag(LibraryScope.folder(folder.id))
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(UUID.init(uuidString:))
            guard !ids.isEmpty else { return false }
            model.move(sources: ids, toFolder: folder.id)
            return true
        }
        .contextMenu {
            Button { newFolderParent = .some(folder.id) } label: {
                Label("Alt klasör oluştur", systemImage: "folder.badge.plus")
            }
            Button {
                folderName = folder.name
                renaming = folder
            } label: {
                Label("Yeniden adlandır", systemImage: "pencil")
            }
            Menu {
                Button("En üste") { model.moveFolder(folder.id, toParent: nil) }
                ForEach(model.flatFolders().filter { $0.id != folder.id }) { item in
                    Button(item.indentedName) {
                        model.moveFolder(folder.id, toParent: item.folder.id)
                    }
                }
            } label: {
                Label("Taşı", systemImage: "folder")
            }
            Button(role: .destructive) { deleting = folder } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }
}
