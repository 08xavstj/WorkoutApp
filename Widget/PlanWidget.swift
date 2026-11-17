import AppCore
import SwiftUI
import WidgetKit

/// Today's plan at a glance: the session and its time, "Rest day", or after
/// training tonight's bed-by window (docs/research/healthy-living-2026-11.md
/// §3 item 5). Lock Screen (rectangular, circular, inline), Home Screen
/// (small, medium) and StandBy (the small one). What it says at any moment,
/// and when it says "--" instead, is `PlanGlance` in AppCore, shared with the
/// Watch complication so the two can't differ.
struct PlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceKind.plan, provider: PlanProvider()) { entry in
            PlanWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GlanceBackground(wash: .plan)
                }
        }
        .configurationDisplayName("Today's plan")
        .description("Today's session and its time, a rest day, or tonight's bed-by time once you've trained.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// The widgets' `kind` strings in one place (the app reloads every timeline
/// at once, `Reminders.updateWidget`, so it doesn't name them).
nonisolated enum GlanceKind {
    static let plan = "PlanWidget"
    static let scores = "ScoresWidget"
}

nonisolated struct PlanEntry: TimelineEntry {
    let date: Date
    /// nil until the app has written a plan (or after an update from a build without one).
    let plan: PlanGlance.Plan?
    /// Smart Stack: higher in the hour before a session and around bedtime.
    var relevance: TimelineEntryRelevance? = nil
}

/// Reads the plan the app saved in the App Group (`WidgetSnapshot.plan`) and
/// lays out an entry for every moment the widget changes on its own in the
/// next two days (`PlanGlance.changeDates`): midnight, a session's time
/// passing, the bed-by window taking over. The app reloads the timeline
/// whenever the plan itself changes, so the widget only asks again after
/// midnight.
nonisolated struct PlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanEntry {
        PlanEntry(date: .now, plan: PlanGlance.Plan.sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
        let now = Date.now
        let saved = WidgetSnapshot.load()?.plan
        // The widget gallery shows a real-looking plan even before the app has one to show.
        if context.isPreview, PlanGlance.state(of: saved, at: now) == .stale {
            completion(PlanEntry(date: now, plan: PlanGlance.Plan.sample(now: now)))
        } else {
            completion(PlanEntry(date: now, plan: saved))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
        let now = Date.now
        let plan = WidgetSnapshot.load()?.plan
        let relevant = PlanGlance.relevantWindows(of: plan, after: now).map(\.interval)
        let horizon = now.addingTimeInterval(PlanGlance.timelineHorizon)
        var dates = [now] + PlanGlance.changeDates(of: plan, after: now)
        dates += relevant.flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 <= horizon }
        let entries = Array(Set(dates)).sorted().map { date in
            PlanEntry(date: date, plan: plan, relevance: Self.relevance(at: date, in: relevant))
        }
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(5 * 60))))
    }

    /// Smart Stack relevance for the entry at `date`: raised for as long as
    /// the interval it falls in lasts.
    static func relevance(at date: Date, in intervals: [DateInterval]) -> TimelineEntryRelevance {
        guard let interval = intervals.first(where: { $0.start <= date && date < $0.end }) else {
            return TimelineEntryRelevance(score: 0)
        }
        return TimelineEntryRelevance(score: 10, duration: interval.end.timeIntervalSince(date))
    }
}

#if DEBUG
#Preview("Plan, small", as: .systemSmall) {
    PlanWidget()
} timeline: {
    PlanEntry(date: .now, plan: PlanGlance.Plan.sample())
    PlanEntry(date: .now, plan: nil)
}
#endif
