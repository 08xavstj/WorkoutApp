import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

// The cardio end screen as it was before the redesign, kept until the new
// summary (Watch/Summary, chunk C4) replaces it.

/// "Z2 133–146        12:30" over a bar in the zone's color.
struct WatchZoneTimeRow: View {
    let zone: Int
    let range: String
    let seconds: Double
    /// 0-1 against the longest zone.
    let share: Double
    var isCurrent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Z\(zone)")
                    .fontWeight(.bold)
                    .foregroundStyle(WatchTheme.zoneColor(zone))
                Text(range)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(watchClock(seconds))
                    .fontWeight(isCurrent ? .bold : .regular)
            }
            .font(.caption)
            .monospacedDigit()
            ProgressView(value: min(1, max(0, share)))
                .tint(WatchTheme.zoneColor(zone))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(zone), \(range) beats per minute, \(Int((seconds / 60).rounded())) minutes")
    }
}

/// A label and its value on one line.
struct WatchCardioStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.footnote)
    }
}

/// After End: time, distance, climb, heart rate and minutes in each zone.
struct WatchCardioEndView: View {
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let summary = cardio.summary {
                    Text(summary.saved ? "\(summary.activity.title) saved" : "\(summary.activity.title) ended")
                        .font(.headline)
                    rows(for: summary)
                    if summary.hasRoute {
                        Label("Map with speed and heart rate on your iPhone", systemImage: "map")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Workout ended")
                        .font(.headline)
                }
                if let problem = cardio.problem {
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.heart)
                }
                // No double tap: this page scrolls (HIG Gestures).
                PrimaryWideButton(title: "Done", systemImage: "checkmark", tint: WatchPalette.recovery) {
                    cardio.reset()
                }
                .padding(.top, 4)
                .accessibilityIdentifier("watch-cardio-done")
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func rows(for summary: CardioSummary) -> some View {
        let miles = watchUsesMiles()
        let longest = max(summary.zoneSeconds.max() ?? 0, 1)
        WatchCardioStatRow(label: "Time", value: workoutElapsedText(summary.activeSeconds))
        if summary.activity.movement != .stationary, let meters = summary.distanceMeters {
            WatchCardioStatRow(label: "Distance", value: CardioSummary.distanceText(meters: meters, miles: miles))
            if let pace = summary.paceOrSpeedText(miles: miles) {
                WatchCardioStatRow(label: summary.activity.movement.showsSpeed ? "Avg speed" : "Avg pace", value: pace)
            }
        }
        if let gain = summary.elevationGainMeters {
            WatchCardioStatRow(label: "Climb", value: CardioSummary.elevationText(meters: gain, feet: miles))
        }
        if summary.activity.movement.showsSpeed, let top = summary.maximumSpeed {
            WatchCardioStatRow(label: "Top speed", value: CardioSummary.speedText(metersPerSecond: top, miles: miles))
        }
        WatchCardioStatRow(label: "Avg HR", value: bpm(summary.averageBpm))
        WatchCardioStatRow(label: "Max HR", value: bpm(summary.maximumBpm))
        WatchCardioStatRow(label: "Calories", value: summary.activeKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "–")
        if summary.measuredSeconds > 0 {
            Text("Time in zones")
                .font(.footnote.weight(.semibold))
                .padding(.top, 4)
            ForEach(Array(summary.zoneSeconds.enumerated()), id: \.offset) { index, seconds in
                WatchZoneTimeRow(
                    zone: index + 1,
                    range: cardio.tracker.scheme.rangeText(forZone: index + 1),
                    seconds: seconds,
                    share: seconds / longest
                )
            }
            if summary.belowZoneSeconds >= 1 {
                WatchCardioStatRow(label: "Under zone 1", value: watchClock(summary.belowZoneSeconds))
            }
            if let share = summary.bandShare {
                WatchCardioStatRow(
                    label: "In \(summary.target.title) range",
                    value: "\(watchClock(summary.bandSeconds)) · \(Int((share * 100).rounded()))%"
                )
            }
        }
    }

    private func bpm(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) bpm" } ?? "–"
    }
}
