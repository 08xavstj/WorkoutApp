import SwiftUI
import AppCore

/// Today's single alert slot, above the Scores card: at most one card, by
/// priority: an Apple Health access problem, then illness (major signs) or
/// rest mode (`IllnessAlertCard`). A minor illness sign is a line in the
/// Scores card instead. One alert at a time keeps warnings rare enough to
/// mean something (docs/research/ux-audit.md 4.6, H7; P17, P19).
struct AlertSlot: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        if let error = metrics.errorMessage {
            HealthAccessCard(message: error)
        } else {
            IllnessAlertCard()
        }
    }
}

/// Apple Health access is missing or failed: ask again, or open Apple Health.
private struct HealthAccessCard: View {
    let message: String
    @Environment(\.healthClient) private var health

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Health", systemImage: "heart.text.square")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text("If you already answered, open Apple Health → your profile picture → Apps → Tensile, and tap Turn On All.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Allow access") {
                    Task { try? await health?.requestAuthorization() }
                }
                .buttonStyle(.borderedProminent)
                if let url = URL(string: "x-apple-health://") {
                    Link("Open Apple Health", destination: url)
                        .buttonStyle(.bordered)
                }
            }
        }
        .card()
    }
}
