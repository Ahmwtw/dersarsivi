import SwiftUI

@main
struct DersArsiviApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environment(\.palette, settings.palette)
                .tint(settings.palette.accent)
                .preferredColorScheme(settings.appearance.colorScheme)
                .alert("Bir sorun oluştu", isPresented: Binding(
                    get: { model.lastError != nil },
                    set: { if !$0 { model.lastError = nil } }
                )) {
                    Button("Tamam", role: .cancel) {}
                } message: {
                    Text(model.lastError ?? "")
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS arka planda işi garanti etmez; öne gelince kuyruk kaldığı yerden devam eder.
            if phase == .active { model.processQueue() }
        }
    }
}
