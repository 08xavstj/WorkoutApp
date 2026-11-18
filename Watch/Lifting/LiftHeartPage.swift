import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

/// Heart rate during a lifting session (docs/research/watch-app-redesign-2026-11.md
/// §4.4.4): the number in its zone colour, Apple's five-segment zone bar with
/// the time in the current zone, and the last 10 minutes as a line with the
/// average and maximum. Zones and zone time come from `CardioZoneTracker`,
/// the same scheme and counting rules as cardio and the phone.
///
/// A secondary page, not the Set page's headline: the Apple Watch read heart
/// rate well in squats, deadlifts and rows but less well in overhead and
/// burpee-type movements (docs/research/watch-features.md [B19]), which the
/// page says once per workout.
struct LiftHeartPage: View {
    @Environment(WatchWorkoutModel.self) private var model
    /// The caption was showing when this visit began.
    @State private var showsCaption = false

    var body: some View {
        let tracker = model.tracker
        let zone = tracker.currentZone
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .numeral(.primary)
                    .alwaysOnPrimary(model.heartRate == nil ? .secondary : WatchPalette.zoneColor(zone))
                Text("bpm")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(zone.map { "Zone \($0)" } ?? (model.heartRate == nil ? "" : "Under Z1"))
                        .font(.footnote.weight(.semibold))
                    if let zone, zone <= tracker.zoneSeconds.count {
                        Text(watchClock(tracker.zoneSeconds[zone - 1]))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenNow)
            LiveZoneBar(zone: zone)
            let recent = model.heartSeries.recent(HeartRateSeries.recentSeconds, now: .now)
            SeriesSparkline(points: recent, spoken: SeriesSparkline.spokenHeartRate(recent))
                .frame(maxHeight: .infinity)
                .hiddenWhenLuminanceReduced()
            HStack {
                stat("Avg", model.averageHeartRate)
                Spacer()
                stat("Max", model.maximumHeartRate)
            }
            if showsCaption {
                Text("Wrist heart rate reads less well in overhead lifts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .onAppear {
            showsCaption = !model.heartCaptionSeen
            model.heartCaptionSeen = true
        }
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value.map { "\(Int($0.rounded()))" } ?? "--")
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    /// "128 beats per minute, zone 3 of 5, 146 to 159, 12 minutes in zone".
    private var spokenNow: String {
        guard let heartRate = model.heartRate else { return "No heart rate yet" }
        var parts = ["\(Int(heartRate.rounded())) beats per minute"]
        let tracker = model.tracker
        if let zone = tracker.currentZone {
            parts.append("zone \(zone) of 5, \(tracker.scheme.rangeText(forZone: zone)) beats per minute")
            if zone <= tracker.zoneSeconds.count {
                parts.append("\(Int((tracker.zoneSeconds[zone - 1] / 60).rounded())) minutes in zone")
            }
        } else {
            parts.append("under zone 1")
        }
        return parts.joined(separator: ", ")
    }
}
