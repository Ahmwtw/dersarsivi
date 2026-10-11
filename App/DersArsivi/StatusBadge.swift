import DersArsiviCore
import SwiftUI

/// Durumu yalnız renkle değil, simge ve metinle de gösterir.
struct StatusBadge: View {
    let status: PageStatus

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(tint)
            .accessibilityLabel("Durum: \(title)")
    }

    private var title: String {
        switch status {
        case .imported: "Alındı"
        case .queued: "Sırada"
        case .processing: "Okunuyor"
        case .needsReview: "Gözden geçir"
        case .ready: "Hazır"
        case .partial: "Kısmi"
        case .failed: "Başarısız"
        case .cancelled: "İptal"
        }
    }

    private var icon: String {
        switch status {
        case .imported, .queued: "clock"
        case .processing: "text.viewfinder"
        case .needsReview: "exclamationmark.circle"
        case .ready: "checkmark.circle"
        case .partial: "circle.lefthalf.filled"
        case .failed: "xmark.octagon"
        case .cancelled: "slash.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .ready: .green
        case .needsReview, .partial: .orange
        case .failed: .red
        default: .secondary
        }
    }
}
