import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

// Small glanceable charts for the workout pages and summaries. A watch chart
// shows what can be read at a glance and leaves detail to the iPhone (HIG
// Charts): no interaction beyond scrolling, no animation, and one summary
// label for VoiceOver rather than one element per point. All drawn with the
// `nonisolated` shapes in WatchShapes.swift (no Canvas).

/// Five equal zone segments with the current one raised and its number
/// printed: Apple's Heart Rate Zones layout. Colour is never alone: the
/// current zone's number is on it.
struct LiveZoneBar: View {
    /// 1-5, or nil under zone 1 / no reading.
    let zone: Int?
    var height: CGFloat = 14

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...HeartRateZoneScheme.zoneCount, id: \.self) { index in
                let isCurrent = index == zone
                ZStack {
                    Capsule()
                        .fill(WatchPalette.zoneColor(index).opacity(isCurrent ? 1 : 0.35))
                    if isCurrent {
                        Text("Z\(index)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(WatchPalette.onTint)
                    }
                }
                .frame(height: isCurrent ? height + 8 : height)
                .dimmedWhenLuminanceReduced(isCurrent ? 0.8 : 0.5)
            }
        }
        .frame(height: height + 8)
        .accessibilityHidden(true)
    }
}

/// Time in each zone as one stacked bar, widths by time, with each zone's
/// minutes printed under it (zones under a minute are left unlabelled).
struct ZoneTimeBar: View {
    /// Seconds in zones 1-5.
    let seconds: [Double]
    var height: CGFloat = 12

    private var total: Double { seconds.reduce(0, +) }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Capsule().fill(WatchPalette.track)
                ForEach(Array(spans.enumerated()), id: \.offset) { index, span in
                    ZoneBar(start: span.lowerBound, end: span.upperBound, cornerRadius: height / 2)
                        .fill(WatchPalette.zoneColor(index + 1))
                }
            }
            .frame(height: height)
            HStack(spacing: 0) {
                ForEach(Array(seconds.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 0) {
                        Text("Z\(index + 1)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WatchPalette.zoneColor(index + 1))
                        Text(value >= 60 ? "\(Int((value / 60).rounded()))m" : "–")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Each zone's share of the width, 0-1.
    private var spans: [ClosedRange<Double>] {
        guard total > 0 else { return [] }
        var start = 0.0
        return seconds.map { value in
            let end = start + value / total
            defer { start = end }
            return start...end
        }
    }

    private var spoken: String {
        guard total > 0 else { return "No time in zones yet" }
        let parts = seconds.enumerated().compactMap { index, value -> String? in
            value >= 30 ? "zone \(index + 1), \(Int((value / 60).rounded())) minutes" : nil
        }
        return "Time in zones: " + parts.joined(separator: "; ")
    }
}

/// A heart-rate (or altitude) line with a faint baseline, scaled to its own range.
struct SeriesSparkline: View {
    let points: [SeriesPoint]
    var color: Color = WatchPalette.heart
    var lineWidth: CGFloat = 2.5
    /// What VoiceOver reads, e.g. "Heart rate from 92 to 171, average 138".
    let spoken: String

    var body: some View {
        let values = points.map(\.value)
        let range = HeartRateSeries.range(of: points) ?? 0...1
        // A little room above and below so a flat line doesn't sit on the edge.
        let padded = (range.lowerBound - 3)...(range.upperBound + 3)
        ZStack {
            Rectangle()
                .fill(WatchPalette.track)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
            Sparkline(values: values, range: padded)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "Heart rate from 92 to 171, average 138".
    static func spokenHeartRate(_ points: [SeriesPoint]) -> String {
        guard let range = HeartRateSeries.range(of: points), !points.isEmpty else { return "No heart rate yet" }
        let average = points.map(\.value).reduce(0, +) / Double(points.count)
        return "Heart rate from \(Int(range.lowerBound.rounded())) to \(Int(range.upperBound.rounded())), average \(Int(average.rounded()))"
    }
}
