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

    /// Plain effort words, easiest first; the band below zone 1 isn't a zone
    /// and has no name of its own, so the words never clash.
    static let names = ["Very light", "Light", "Moderate", "Hard", "Max"]

    /// Heart-rate range for zone 1-5 (50-60%, ... 90-100% of heart-rate reserve).
    private func bpmRange(_ index: Int) -> String? {
        guard let profile = metrics.heartRateProfile else { return nil }
        let reserve = profile.maxHeartRate - profile.restingHeartRate
        let low = profile.restingHeartRate + (0.5 + 0.1 * Double(index)) * reserve
        let high = profile.restingHeartRate + (0.6 + 0.1 * Double(index)) * reserve
        return "\(whole(low))–\(whole(high))"
    }

    /// Why a day with workouts can show no zones: Apple Health's heart-rate read
    /// failed, heart rate stayed below zone 1 (common when lifting), or there
    /// were no readings and strain came from exercise minutes and session effort,
    /// which add strain but no zone time (`StrainCalculator`).
    private var noZonesReason: String? {
        if let error = metrics.heartRateReadError {
            return "Heart rate couldn't be read from Apple Health (\(error)). Pull down on Today to try again."
        }
        if metrics.todaysHeartRateReadings > 0 {
            let light = whole(metrics.todaysLightMinutes)
            // The lifting explanation only when a strength session was logged today.
            if metrics.activities.contains(where: \.isStrength) {
                return metrics.todaysLightMinutes >= 1
                    ? "Your heart rate today stayed below zone 1 (30–50% of reserve). Lifting often does: the effort is in the muscles, not the heart."
                    : "Your heart rate today stayed under 30% of your reserve. Lifting often does: the effort is in the muscles, not the heart."
            }
            return metrics.todaysLightMinutes >= 1
                ? "Only light movement so far (\(light) min at 30–50% of reserve)."
                : "Your heart rate today stayed under 30% of your reserve, close to resting."
        }
        guard let strain = metrics.strain, strain.strain > 0 else { return nil }
        if strain.movementMinutes > 0 || strain.liftingLoad > 0 {
            return "No heart-rate readings today yet, so strain so far comes from exercise minutes and workout effort. Zones need heart rate from a watch or an AirPods recording."
        }
        return nil
    }

    /// "96–120 bpm" for the band below zone 1 (30-50% of reserve).
    private var lightRange: String? {
        guard let profile = metrics.heartRateProfile else { return nil }
        let low = profile.heartRate(atReserve: HeartRateProfile.lightBand.lowerBound)
        let high = profile.heartRate(atReserve: HeartRateProfile.lightBand.upperBound)
        return "\(whole(low))–\(whole(high)) bpm"
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
            if total == 0, let reason = noZonesReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if metrics.todaysLightMinutes >= 1 {
                LightBandRow(minutes: metrics.todaysLightMinutes, range: lightRange)
            }
            if total == 0 {
                // No zone time: one line of ranges instead of five empty bars.
                if let line = rangesLine {
                    Text(line)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(0..<5, id: \.self) { index in
                        zoneColumn(index, minutes: index < minutes.count ? minutes[index] : 0, peak: peak)
                    }
                }
            }
            if total > 0, metrics.heartRateProfile != nil {
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

    /// "Z1 120–135 · Z2 135–150 · … bpm", for a day with no zone time.
    private var rangesLine: String? {
        let parts = (0..<5).compactMap { index in bpmRange(index).map { "Z\(index + 1) \($0)" } }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + " bpm"
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
            Text(Self.names[index])
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

/// Minutes in the light band below zone 1 (30-50% of reserve, `HeartRateProfile.lightBand`).
/// They add strain but aren't a zone.
private struct LightBandRow: View {
    let minutes: Double
    let range: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Below zone 1")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(range.map { "30–50% of reserve · \($0)" } ?? "30–50% of reserve")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text("\(whole(minutes.rounded())) min")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
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
            // Light band 30-50% HRR: strain's 30% floor (ACSM's Guidelines, 10th ed. 2018) up to zone 1.
            Text("Each zone is a share of your heart-rate reserve, the gap between your resting and maximum heart rate (Karvonen et al. 1957): zone 1 (very light) is 50–60%, up to zone 5 (max) at 90–100%. Time at 30–50%, below zone 1, still adds strain.")
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
