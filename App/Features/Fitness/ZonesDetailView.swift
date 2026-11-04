import SwiftUI
import AppCore

/// Fitness › Today › Heart-rate zones: today's minutes in each zone with
/// its bpm range, and what the zones are (ux-audit.md 4.3, 4.6; F8: the
/// chart labels its axis instead of explaining it in prose).
struct ZonesDetailView: View {
    var body: some View {
        FitnessDetailPage(title: "Heart-rate zones") {
            ZonesCard()
            ZonesAboutCard()
        }
    }
}

private struct ZonesCard: View {
    @Environment(DailyMetricsModel.self) private var metrics

    private let names = ["Easy", "Light", "Aerobic", "Threshold", "Max"]

    /// Heart-rate range for zone 1-5 (50-60%, ... 90-100% of heart-rate reserve).
    private func bpmRange(_ index: Int) -> String? {
        guard let profile = metrics.heartRateProfile else { return nil }
        let reserve = profile.maxHeartRate - profile.restingHeartRate
        let low = profile.restingHeartRate + (0.5 + 0.1 * Double(index)) * reserve
        let high = profile.restingHeartRate + (0.6 + 0.1 * Double(index)) * reserve
        return "\(whole(low))–\(whole(high))"
    }

    var body: some View {
        let minutes = metrics.strain?.zoneMinutes ?? [0, 0, 0, 0, 0]
        let total = minutes.reduce(0, +)
        let peak = max(minutes.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            CardLabel(text: "Today")
            Text(total > 0 ? "\(whole(total)) min in zones today" : "No time in heart-rate zones yet today")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    zoneColumn(index, minutes: index < minutes.count ? minutes[index] : 0, peak: peak)
                }
            }
            if metrics.heartRateProfile != nil {
                // Axis caption for the ranges under each bar (ux-audit.md 4.7).
                Text("bpm")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .card()
    }

    private func zoneColumn(_ index: Int, minutes: Double, peak: Double) -> some View {
        VStack(spacing: 6) {
            Text(minutes > 0 ? "\(whole(minutes.rounded()))m" : "")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10).fill(Theme.track)
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Theme.zoneColors[index], Theme.zoneColors[index].opacity(0.45)], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(6, 130 * minutes / peak))
                    .shadow(color: Theme.zoneColors[index].opacity(minutes > 0 ? 0.45 : 0), radius: 6)
            }
            .frame(height: 130)
            Text("Z\(index + 1)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text(names[index])
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let range = bpmRange(index) {
                Text(range)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("\(range) beats per minute")
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// What the zones are, from the app's own definitions (`HeartRateProfile`).
private struct ZonesAboutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "About these zones")
            // Zones on heart-rate reserve (Karvonen et al. 1957), 50-60 ... 90-100 %;
            // max heart rate from Tanaka et al., J Am Coll Cardiol 2001, unless
            // measured or learned (`HeartRateProfile`, `ObservedMaxHeartRate`).
            Text("Each zone is a share of your heart-rate reserve, the gap between your resting and maximum heart rate (Karvonen et al. 1957): zone 1 is 50–60%, up to zone 5 at 90–100%.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Unless the app knows your measured maximum, it estimates it from your age (Tanaka et al. 2001), which can be off by about 10 bpm, so treat the edges as approximate. Zones are for display; day strain weighs your heart rate continuously.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
