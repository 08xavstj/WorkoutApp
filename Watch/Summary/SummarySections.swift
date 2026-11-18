import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

// Pieces of the end summaries (docs/research/watch-app-redesign-2026-11.md
// §4.7). A summary "confirms that a workout is finished and displays the
// recorded information" (HIG Workouts); its charts read at a glance and the
// detail stays on the iPhone (HIG Charts). One scrolling page, so no
// double-tap action: Done is a plain 60 pt button, and a ✓ in the toolbar.

/// The Handoff activity a summary advertises, so the iPhone can open the
/// workout ("com.lontraindustries.workoutapp.viewWorkout", with the workout's
/// UUID). Whether Handoff from the Watch surfaces on the iPhone is still to
/// be checked on the devices (§8); without it the row stays as text.
enum WatchHandoff {
    static let viewWorkout = "com.lontraindustries.workoutapp.viewWorkout"
    static let workoutKey = "workoutUUID"
}

/// The title block: "Push · saved", then a line of facts.
struct SummaryHeader: View {
    let title: String
    let saved: Bool
    let facts: [String]
    var color: Color = WatchPalette.lifting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(saved ? "Saved" : "Not saved", systemImage: saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(saved ? WatchPalette.recovery : WatchPalette.strain)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(2)
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section title in the summary.
struct SummaryTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A label and its value on one line.
struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }
}

/// Average and maximum heart rate, time in zones, and the whole session's line.
struct HeartSummarySection: View {
    let average: Double?
    let maximum: Double?
    let zoneSeconds: [Double]
    let series: HeartRateSeries

    var body: some View {
        SummaryTitle(text: "Heart rate")
        HStack {
            MetricBlock(value: average.map { "\(Int($0.rounded()))" } ?? "--", unit: "bpm", label: "Average", role: .tertiary)
            Spacer(minLength: 4)
            MetricBlock(value: maximum.map { "\(Int($0.rounded()))" } ?? "--", unit: "bpm", label: "Maximum", role: .tertiary)
        }
        if zoneSeconds.reduce(0, +) >= 60 {
            ZoneTimeBar(seconds: zoneSeconds)
        }
        let points = series.summary
        if points.count >= 2, let range = HeartRateSeries.range(of: points) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("\(Int(range.upperBound.rounded()))")
                    Spacer()
                }
                SeriesSparkline(points: points, spoken: SeriesSparkline.spokenHeartRate(points))
                    .frame(height: 50)
                HStack {
                    Text("\(Int(range.lowerBound.rounded()))")
                    Spacer()
                    Text(workoutElapsedText(points.last.map { $0.date.timeIntervalSince(points[0].date) } ?? 0))
                }
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}

/// Splits as bars (up to 10, the fastest highlighted), time per km or mile.
struct SplitsSection: View {
    let laps: [LapTracker.Lap]
    let fastest: Int?
    let miles: Bool

    private var shown: [LapTracker.Lap] { Array(laps.prefix(10)) }

    var body: some View {
        SummaryTitle(text: miles ? "Splits per mile" : "Splits per km")
        let values = shown.map { $0.pace(miles: miles) ?? 0 }
        let highlight = Set(shown.indices.filter { shown[$0].number == fastest })
        ZStack {
            SplitBars(values: values, gap: 4)
                .fill(WatchPalette.strain.opacity(0.7))
            SplitBars(values: values, gap: 4, only: highlight)
                .fill(WatchPalette.recovery)
        }
        .frame(height: 50)
        .accessibilityHidden(true)
        ForEach(shown) { lap in
            SummaryRow(label: "\(miles ? "Mile" : "Km") \(lap.number)\(lap.number == fastest ? " · fastest" : "")",
                       value: lap.pace(miles: miles).map { CardioSummary.paceText($0, miles: miles) } ?? workoutElapsedText(lap.seconds))
        }
        if laps.count > shown.count {
            Text("\(laps.count - shown.count) more on your iPhone")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// "Map, splits and coach notes on your iPhone".
struct OpenOnPhoneRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "iphone")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

/// The two ways out of a summary: a 60 pt Done at the end and a ✓ in the toolbar.
struct SummaryDone: ViewModifier {
    let identifier: String
    let action: () -> Void

    func body(content: Content) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    content
                    PrimaryWideButton(title: "Done", systemImage: "checkmark", tint: WatchPalette.recovery, action: action)
                        .padding(.top, 8)
                        .accessibilityIdentifier(identifier)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: action) {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                }
            }
        }
    }
}

extension View {
    func summaryDone(identifier: String, action: @escaping () -> Void) -> some View {
        modifier(SummaryDone(identifier: identifier, action: action))
    }
}

/// "Bench press: 4 × 8 · 82.5 kg", per exercise with a working set done.
nonisolated enum SummarySets {
    static func lines(for session: WatchSession) -> [(name: String, detail: String)] {
        session.exercises.compactMap { exercise in
            let done = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }
            guard !done.isEmpty else { return nil }
            let reps = done.map(\.reps)
            let top = done.map(\.weightKg).max() ?? 0
            let repsText: String
            if exercise.isHold == true {
                repsText = "\(done.count) × \(reps.max() ?? 0) s"
            } else if let low = reps.min(), let high = reps.max(), low != high {
                repsText = "\(done.count) sets · \(low)-\(high) reps"
            } else {
                repsText = "\(done.count) × \(reps.first ?? 0)"
            }
            let weight = top > 0 && exercise.isHold != true ? " · " + exercise.weightText(top, unit: session.unit) : ""
            return (exercise.name, repsText + weight)
        }
    }
}
