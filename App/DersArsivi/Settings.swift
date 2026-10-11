import SwiftUI
import UIKit

/// Kullanıcının görünüm ayarları. Cihazda saklanır; değişince tüm ekranlar hemen güncellenir.
@MainActor
final class AppSettings: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "Sistem"
            case .light: return "Açık"
            case .dark: return "Koyu"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    enum CardSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: return "Küçük"
            case .medium: return "Orta"
            case .large: return "Büyük"
            }
        }
        /// Izgara sütununun en küçük genişliği.
        var minimumWidth: CGFloat {
            switch self {
            case .small: return 116
            case .medium: return 150
            case .large: return 210
            }
        }
    }

    /// Hazır vurgu renkleri: hepsi beyaz yazıyla okunur, sarı vurgu ve kırmızı işaretle karışmaz.
    struct Preset: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    static let accentPresets: [Preset] = [
        Preset(name: "Lacivert", hex: "3B66DB"), Preset(name: "Gök", hex: "0A84FF"),
        Preset(name: "Turkuaz", hex: "138A8A"), Preset(name: "Zümrüt", hex: "2E8B57"),
        Preset(name: "Mor", hex: "7B4FD6"), Preset(name: "Gül", hex: "C73E73"),
        Preset(name: "Mercan", hex: "D9603B"), Preset(name: "Grafit", hex: "56606E"),
    ]
    static let defaultStar = "F29E1A"
    static let defaultNote = "8C54D9"

    @Published var accentHex: String { didSet { save(accentHex, "settings.accent") } }
    @Published var starHex: String { didSet { save(starHex, "settings.star") } }
    @Published var noteHex: String { didSet { save(noteHex, "settings.note") } }
    @Published var appearance: Appearance { didSet { save(appearance.rawValue, "settings.appearance") } }
    @Published var cardSize: CardSize { didSet { save(cardSize.rawValue, "settings.cardSize") } }
    /// Kütüphane zemininde vurgu renginden çok hafif bir geçiş.
    @Published var tintedBackground: Bool { didSet { UserDefaults.standard.set(tintedBackground, forKey: "settings.tinted") } }

    init() {
        let d = UserDefaults.standard
        accentHex = d.string(forKey: "settings.accent") ?? Self.accentPresets[0].hex
        starHex = d.string(forKey: "settings.star") ?? Self.defaultStar
        noteHex = d.string(forKey: "settings.note") ?? Self.defaultNote
        appearance = d.string(forKey: "settings.appearance").flatMap(Appearance.init(rawValue:)) ?? .system
        cardSize = d.string(forKey: "settings.cardSize").flatMap(CardSize.init(rawValue:)) ?? .medium
        tintedBackground = d.bool(forKey: "settings.tinted")
    }

    var palette: Palette {
        Palette(accent: Color(hex: accentHex) ?? Theme.accent,
                star: Color(hex: starHex) ?? Theme.star,
                note: Color(hex: noteHex) ?? Theme.note)
    }

    func resetColors() {
        accentHex = Self.accentPresets[0].hex
        starHex = Self.defaultStar
        noteHex = Self.defaultNote
        appearance = .system
        cardSize = .medium
        tintedBackground = false
    }

    private func save(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Ekranların kullandığı renkler; kökte ayarlardan üretilip ortama konur.
struct Palette: Equatable {
    var accent: Color
    var star: Color
    var note: Color

    static let standard = Palette(accent: Theme.accent, star: Theme.star, note: Theme.note)
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.standard
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Color {
    /// "3B66DB" biçimindeki altı haneli onaltılık renk.
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// Altı haneli onaltılık karşılık (renk seçiciden gelen değeri saklamak için).
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}

/// Ayarlar ekranı: görünüm, renkler, kütüphane ve okuma seçenekleri.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppModel.autoSaveFiguresKey) private var autoSaveFigures = false
    @State private var confirmReset = false

    private var palette: Palette { settings.palette }

    var body: some View {
        NavigationStack {
            Form {
                Section { preview }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                Section("Görünüm") {
                    Picker("Tema", selection: $settings.appearance) {
                        ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
                        ForEach(AppSettings.accentPresets) { preset in
                            swatch(preset.name, hex: preset.hex)
                        }
                    }
                    .padding(.vertical, 6)
                    ColorPicker("Özel renk", selection: Binding(
                        get: { palette.accent },
                        set: { settings.accentHex = $0.hexString }), supportsOpacity: false)
                } header: {
                    Text("Vurgu rengi")
                } footer: {
                    Text("Düğmeler, seçimler, klasörler ve kenar çubuğu bu renkle görünür.")
                }

                Section {
                    ColorPicker(selection: Binding(get: { palette.star }, set: { settings.starHex = $0.hexString }),
                                supportsOpacity: false) {
                        Label("İşaretli satır", systemImage: "star.fill").foregroundStyle(palette.star)
                    }
                    ColorPicker(selection: Binding(get: { palette.note }, set: { settings.noteHex = $0.hexString }),
                                supportsOpacity: false) {
                        Label("El notu", systemImage: "pencil.and.scribble").foregroundStyle(palette.note)
                    }
                } header: {
                    Text("İşaret renkleri")
                } footer: {
                    Text("Yalnız uygulamadaki görünüm değişir; dışa aktarılan dosyada ⭐ ve ✍️ kullanılır.")
                }

                Section("Kütüphane") {
                    Picker("Kart boyutu", selection: $settings.cardSize) {
                        ForEach(AppSettings.CardSize.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Zeminde hafif renk", isOn: $settings.tintedBackground)
                }

                Section {
                    Toggle("Şekil önerilerini otomatik kaydet", isOn: $autoSaveFigures)
                    if model.archive.figures.contains(where: { $0.status == .suggested }) {
                        Button {
                            Task { await model.saveAllSuggestions() }
                        } label: {
                            Label("Bekleyen tüm önerileri kaydet", systemImage: "checkmark.circle")
                        }
                    }
                } header: {
                    Text("Okuma ve şekiller")
                } footer: {
                    Text("Açıkken bulunan şekiller onay beklemeden kaydedilir; yanlış olanları sonra silersin. "
                         + "El notları her zaman görüntü olarak kaydedilir.")
                }

                Section {
                    Button("Görünüm ayarlarını sıfırla", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .confirmationDialog("Renkler ve görünüm varsayılana dönsün mü?", isPresented: $confirmReset,
                                titleVisibility: .visible) {
                Button("Sıfırla", role: .destructive) { settings.resetColors() }
            }
        }
        .tint(palette.accent)
    }

    /// Seçimlerin kartta nasıl görüneceğini gösteren küçük örnek.
    private var preview: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [palette.accent.opacity(0.25), palette.accent.opacity(0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 70)
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 4) {
                            InfoChip(symbol: "star.fill", text: "3", tint: palette.star)
                            InfoChip(symbol: "pencil.and.scribble", text: "1", tint: palette.note)
                        }
                        .padding(6)
                    }
                Text("Kalp döngüsü").font(.subheadline.weight(.semibold))
                Text("12 Eki · 2 şekil").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .cardBackground()
            .overlay {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(palette.accent, lineWidth: 2.5)
            }
            .frame(width: 170)
            VStack(alignment: .leading, spacing: 10) {
                Label("Fizyoloji", systemImage: "folder.fill").foregroundStyle(palette.accent)
                Button("Dışa aktar") {}
                    .prominentButton()
                    .allowsHitTesting(false)
                Text("⭐ işaretli satır").foregroundStyle(palette.star).font(.footnote.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .tint(palette.accent)
        .accessibilityHidden(true)
    }

    private func swatch(_ name: String, hex: String) -> some View {
        let selected = settings.accentHex.uppercased() == hex
        let color = Color(hex: hex) ?? Theme.accent
        return Button {
            withAnimation(.snappy) { settings.accentHex = hex }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(color.gradient)
                    .frame(width: 40, height: 40)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(.white)
                        }
                    }
                    .overlay { Circle().strokeBorder(Color.primary.opacity(selected ? 0.35 : 0.08), lineWidth: 2) }
                Text(name).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
