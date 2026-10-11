import SwiftUI

/// Uygulamanın görsel dili: tek vurgu rengi, yumuşak köşeler, iOS 26'da Liquid Glass, öncekilerde malzeme.
enum Theme {
    /// Sakin, okunaklı lacivert-mavi; vurgulu (sarı) ve işaret (kırmızı) renkleriyle karışmaz.
    static let accent = Color(red: 0.23, green: 0.40, blue: 0.86)
    static let star = Color(red: 0.95, green: 0.62, blue: 0.10)
    static let note = Color(red: 0.55, green: 0.33, blue: 0.85)
    static let corner: CGFloat = 16
}

extension View {
    /// Yüzen kontroller için cam zemin (iOS 26), öncekilerde ince malzeme.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Küçük etiketler (rozet, sayaç) için cam kapsül.
    func glassCapsule() -> some View {
        glassSurface(in: Capsule())
    }

    /// Kart zemini: içerik kartları camdan değil, sakin ikincil zeminden olur; cam yalnız yüzen öğelere.
    func cardBackground() -> some View {
        background(Color(.secondarySystemGroupedBackground),
                   in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    /// Önemli eylem düğmesi: iOS 26'da belirgin cam, öncekilerde dolu düğme.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// İkincil eylem düğmesi: iOS 26'da cam, öncekilerde çerçeveli.
    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Küçük bilgi rozeti: simge + sayı/metin, renk yalnız simgede.
struct InfoChip: View {
    let symbol: String
    var text: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(tint)
            if let text { Text(text).monospacedDigit() }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassCapsule()
    }
}
