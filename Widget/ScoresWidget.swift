import AppCore
import SwiftUI
import WidgetKit

/// Today's three scores, as on the Today tab: recovery, sleep and strain.
/// Home Screen small and medium (and StandBy), Lock Screen circular,
/// rectangular and inline.
///
/// A number shows only while it can be trusted (`GlanceFreshness`): recovery
/// and sleep on the day the app worked them out, strain for 3 hours after
/// that. Otherwise "--": a widget that disagrees with the app is worse than a
/// blank one (docs/research/competitors-2026-11.md).
struct ScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceKind.scores, provider: ScoresProvider()) { entry in
            ScoresWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GlanceBackground(wash: .scores)
                }
                .widgetURL(URL(string: "workoutapp://today"))
        }
        .configurationDisplayName("Scores")
        .description("Today's recovery, sleep and strain, the same numbers as the Today tab.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

nonisolated struct ScoresEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the snapshot the app saved in the App Group, with an entry for when
/// strain goes blank and for midnight, when every score does. The app reloads
/// the timeline whenever it has new numbers.
nonisolated struct ScoresProvider: TimelineProvider {
    static var sample: WidgetSnapshot {
        WidgetSnapshot(updated: .now, hrv: 58, hrvDate: .now, recovery: 72, strain: 34,
                       sleep: 81, band: "moderate", calibrating: false, targetLower: 50, targetUpper: 70)
    }

    func placeholder(in context: Context) -> ScoresEntry {
        ScoresEntry(date: .now, snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScoresEntry) -> Void) {
        let now = Date.now
        let saved = WidgetSnapshot.load()
        // The widget gallery shows real-looking scores until the app has today's.
        let hasToday = saved.map { GlanceFreshness.isToday($0.updated, at: now) && $0.recovery != nil } ?? false
        completion(ScoresEntry(date: now, snapshot: context.isPreview && !hasToday ? Self.sample : saved))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScoresEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.load()
        let dates = [now] + GlanceFreshness.changeDates(updated: snapshot?.updated, after: now)
        let entries = dates.map { ScoresEntry(date: $0, snapshot: snapshot) }
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }
}

/// The scores as they may be shown at a moment: each nil reads "--".
nonisolated struct ScoresShown: Equatable {
    var recovery: Int?
    /// "low", "moderate" or "high".
    var band: String?
    var calibrating = false
    var sleep: Int?
    var strain: Double?
    var target: ClosedRange<Double>?

    init(_ snapshot: WidgetSnapshot?, at date: Date) {
        guard let snapshot, GlanceFreshness.isToday(snapshot.updated, at: date) else { return }
        recovery = snapshot.recovery
        band = snapshot.recovery == nil ? nil : snapshot.band
        calibrating = snapshot.recovery != nil && snapshot.calibrating == true
        sleep = snapshot.sleep
        // The target is set for the day; strain itself goes blank after 3 hours.
        if let lower = snapshot.targetLower, let upper = snapshot.targetUpper, lower.isFinite, upper.isFinite, lower <= upper {
            target = lower...upper
        }
        if GlanceFreshness.strainIsCurrent(updated: snapshot.updated, at: date) {
            strain = snapshot.strain.flatMap { $0.isFinite ? $0 : nil }
        }
    }

    var recoveryText: String { recovery.map { "\($0)%" } ?? "--" }
    var sleepText: String { sleep.map { "\($0)" } ?? "--" }
    var strainText: String { strain.map { "\(Int($0.rounded()))%" } ?? "--" }
    var targetText: String? {
        target.map { "\(Int($0.lowerBound.rounded()))–\(Int($0.upperBound.rounded()))%" }
    }

    /// "Normal", "Easy day", "Recovered", or "Calibrating" while the baseline builds
    /// (the app's wording, `RecoveryWording`).
    var bandLabel: String? {
        guard recovery != nil else { return nil }
        if calibrating { return "Calibrating" }
        switch band {
        case "low": return "Easy day"
        case "moderate": return "Normal"
        case "high": return "Recovered"
        default: return nil
        }
    }

    /// "Recovery 72% · Normal", or "Recovery --".
    var recoveryLine: String {
        guard let bandLabel else { return "Recovery \(recoveryText)" }
        return "Recovery \(recoveryText) · \(bandLabel)"
    }

    /// What VoiceOver reads.
    var spoken: String {
        var parts: [String] = []
        if let recovery {
            parts.append("Recovery \(recovery) percent" + (bandLabel.map { ", \($0)" } ?? ""))
        } else {
            parts.append("Recovery not scored yet")
        }
        parts.append(sleep.map { "Sleep \($0)" } ?? "Sleep not scored yet")
        if let strain {
            var text = "Strain \(Int(strain.rounded())) percent"
            if let target {
                text += ", target \(Int(target.lowerBound.rounded())) to \(Int(target.upperBound.rounded())) percent"
            }
            parts.append(text)
        } else {
            parts.append("Strain not up to date")
        }
        return parts.joined(separator: ". ") + "."
    }
}

#if DEBUG
#Preview("Scores, medium", as: .systemMedium) {
    ScoresWidget()
} timeline: {
    ScoresEntry(date: .now, snapshot: ScoresProvider.sample)
    ScoresEntry(date: .now, snapshot: nil)
}
#endif
