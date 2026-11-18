import MapKit
import RelevanceKit
import SwiftUI
import WidgetKit

/// Watch face complications: recovery + strain, today's plan, and this week's intervals.
/// The Watch app writes `WatchFaceData` to the App Group when the phone sends
/// it; these only read it. What they show and when they go blank follows the
/// same rules as the iPhone widgets (`PlanGlance`, `GlanceFreshness` in
/// Packages/AppCore/Sources/AppCore/Glances.swift, compiled into this target).
@main
struct TensileComplications: WidgetBundle {
    var body: some Widget {
        RecoveryStrainComplication()
        NextSessionComplication()
        IntervalsComplication()
        // Controls (watchOS 26): Control Center and the Smart Stack.
        StartLiftingControl()
        StartLastCardioControl()
    }
}

nonisolated struct FaceEntry: TimelineEntry {
    let date: Date
    /// nil until the phone has sent anything.
    let data: WatchFaceData?
    /// The latest workout end (phone log or Watch): today's session is done.
    let doneAt: Date?
}

/// Shared by both complications: entries now and whenever the face should
/// change on its own, so it rolls forward without the phone. Recovery and
/// strain: when strain goes blank and at midnight. The plan: midnight, a
/// session's time passing, the bed-by window taking over and the Smart Stack
/// windows. The Watch app reloads both whenever the phone sends new data
/// (`WatchComplications.store`), so the timeline asks again only after midnight.
nonisolated struct FaceProvider: TimelineProvider {
    /// Which complication this provider feeds: they share entries but not
    /// Smart Stack relevance (`relevance()`).
    nonisolated enum Kind: Sendable {
        case recoveryStrain
        case nextSession
        case intervals
    }

    var kind: Kind

    func placeholder(in context: Context) -> FaceEntry {
        FaceEntry(date: .now, data: WatchFaceData.sample(), doneAt: nil)
    }

    /// The face editor and the complication gallery show what the Watch
    /// really has: "--" until the phone has sent today's numbers. Example
    /// numbers here (recovery 72%) were taken for a real reading.
    func getSnapshot(in context: Context, completion: @escaping (FaceEntry) -> Void) {
        let data = WatchFaceStore.load()
        completion(FaceEntry(date: .now, data: data, doneAt: WatchFaceStore.lastWorkoutEnd(data)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FaceEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let data = WatchFaceStore.load()
        let doneAt = WatchFaceStore.lastWorkoutEnd(data)
        var dates = [now]
        switch kind {
        case .recoveryStrain:
            dates += GlanceFreshness.changeDates(updated: data?.updated, after: now, calendar: calendar)
        case .nextSession:
            let plan = data?.plan
            let horizon = now.addingTimeInterval(PlanGlance.timelineHorizon)
            dates += PlanGlance.changeDates(of: plan, after: now, calendar: calendar)
            dates += PlanGlance.relevantWindows(of: plan, after: now, alsoDoneAt: doneAt, calendar: calendar)
                .flatMap { [$0.interval.start, $0.interval.end] }
                .filter { $0 > now && $0 <= horizon }
        case .intervals:
            dates += IntervalGlance.changeDates(of: data?.intervalSession, after: now, calendar: calendar)
        }
        let entries = Array(Set(dates)).sorted().map { FaceEntry(date: $0, data: data, doneAt: doneAt) }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(5 * 60))))
    }

    // MARK: Smart Stack

    /// "Recovery & strain" surfaces 06:00-10:00, once the morning scores are in.
    static let morningHours = 6..<10

    /// When the Smart Stack should offer each complication (watchOS 11
    /// `TimelineProvider.relevance()`, RelevanceKit date clues; see
    /// docs/research/watch-features.md §2.6). Without this the complications
    /// never appear in the stack. Attributes go first-is-most-important.
    func relevance() async -> WidgetRelevance<Void> {
        let now = Date.now
        let calendar = Calendar.current
        var clues: [(interval: DateInterval, kind: RelevantContext.DateKind)] = []
        var trainsToday = false
        switch kind {
        case .nextSession:
            // The hour before each session still to do, and from an hour before
            // tonight's bed-by window to its end (`PlanGlance.relevantWindows`);
            // nothing while the plan reads "--".
            let data = WatchFaceStore.load()
            let windows = PlanGlance.relevantWindows(of: data?.plan, after: now,
                                                     alsoDoneAt: WatchFaceStore.lastWorkoutEnd(data), calendar: calendar)
            for window in windows {
                let dateKind: RelevantContext.DateKind = window.reason == .session ? .scheduled : .informational
                clues.append((interval: window.interval, kind: dateKind))
            }
            trainsToday = windows.contains { $0.reason == .session && calendar.isDateInToday($0.interval.start) }
        case .intervals:
            // The hard cardio session's planned day, from the morning to midnight, while
            // it's still to do and not waiting (`IntervalGlance.relevantWindows`).
            for interval in IntervalGlance.relevantWindows(of: WatchFaceStore.load()?.intervalSession, after: now, calendar: calendar) {
                clues.append((interval: interval, kind: RelevantContext.DateKind.scheduled))
            }
        case .recoveryStrain:
            var day = calendar.startOfDay(for: now)
            for _ in 0..<7 {
                if let start = calendar.date(bySettingHour: Self.morningHours.lowerBound, minute: 0, second: 0, of: day),
                   let end = calendar.date(bySettingHour: Self.morningHours.upperBound, minute: 0, second: 0, of: day),
                   end > now, end > start {
                    clues.append((interval: DateInterval(start: start, end: end), kind: RelevantContext.DateKind.informational))
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        var attributes = clues.prefix(PlanGlance.maximumRelevantIntervals).map { clue in
            WidgetRelevanceAttribute<Void>(context: .date(interval: clue.interval, kind: clue.kind))
        }
        // On a training day, also at the gym: RelevanceKit's point-of-interest
        // context (watchOS 26). It returns nil for a category it doesn't support,
        // and then only the date windows apply. Whether it needs location
        // permission is still to check on the wrist (docs/research/watch-app-redesign-2026-11.md §8).
        // (Typed as optional so it builds whether the SDK returns one or not.)
        let gym: RelevantContext? = trainsToday ? RelevantContext.location(category: .fitnessCenter) : nil
        if let gym {
            attributes.append(WidgetRelevanceAttribute<Void>(context: gym))
        }
        return WidgetRelevance(Array(attributes))
    }
}

/// e.g. "34%" (whole numbers; never crashes on NaN).
nonisolated func facePercent(_ value: Double) -> String {
    "\(faceWhole(value))%"
}

nonisolated func faceWhole(_ value: Double) -> Int {
    value.isFinite ? Int(value.rounded()) : 0
}

/// e.g. "50–70%".
nonisolated func faceRange(_ range: ClosedRange<Double>) -> String {
    "\(faceWhole(range.lowerBound))–\(faceWhole(range.upperBound))%"
}
