import RelevanceKit
import SwiftUI
import WidgetKit

/// Watch face complications: recovery + strain, and today's plan.
/// The Watch app writes `WatchFaceData` to the App Group when the phone sends
/// it; these only read it. What they show and when they go blank follows the
/// same rules as the iPhone widgets (`PlanGlance`, `GlanceFreshness` in
/// Packages/AppCore/Sources/AppCore/Glances.swift, compiled into this target).
@main
struct TensileComplications: WidgetBundle {
    var body: some Widget {
        RecoveryStrainComplication()
        NextSessionComplication()
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
    }

    var kind: Kind

    func placeholder(in context: Context) -> FaceEntry {
        FaceEntry(date: .now, data: WatchFaceData.sample(), doneAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FaceEntry) -> Void) {
        // The face editor shows sample data until the phone has sent real data.
        let data = WatchFaceStore.load()
        if context.isPreview && data == nil {
            completion(placeholder(in: context))
        } else {
            completion(FaceEntry(date: .now, data: data, doneAt: WatchFaceStore.lastWorkoutEnd(data)))
        }
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
        let attributes = clues.prefix(PlanGlance.maximumRelevantIntervals).map { clue in
            WidgetRelevanceAttribute<Void>(context: .date(interval: clue.interval, kind: clue.kind))
        }
        return WidgetRelevance(Array(attributes))
    }
}

/// The app's score colours (dark variants from `App/Design/Theme.swift` and
/// `RecoveryWording`), copied here because `Theme` needs UIKit.
nonisolated enum FacePalette {
    static let strain = color(0xFF8E3C)
    static let lifting = color(0xFF6B97)
    /// The bed-by window (`Theme.sleep`, dark).
    static let sleep = color(0x9692FF)
    /// "Easy day" band (`Theme.oxygen`).
    static let easy = color(0x5C9DFF)
    /// "Normal" band (`Theme.recoveryModerate`).
    static let normal = color(0xFFC53D)
    /// "Recovered" band (`Theme.recoveryHigh`).
    static let recovered = color(0x3EDB84)
    static let track = Color.white.opacity(0.18)

    static func band(_ band: String?) -> Color {
        switch band {
        case "low": easy
        case "moderate": normal
        case "high": recovered
        default: .secondary
        }
    }

    static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// e.g. "34%" (whole numbers; never crashes on NaN).
nonisolated func facePercent(_ value: Double) -> String {
    "\(faceWhole(value))%"
}

nonisolated func faceWhole(_ value: Double) -> Int {
    value.isFinite ? Int(value.rounded()) : 0
}

/// A 0-100 score as a 0-1 fraction for rings and bars.
nonisolated func faceFraction(_ value: Double) -> Double {
    value.isFinite ? min(max(value / 100, 0), 1) : 0
}

/// e.g. "50–70%".
nonisolated func faceRange(_ range: ClosedRange<Double>) -> String {
    "\(faceWhole(range.lowerBound))–\(faceWhole(range.upperBound))%"
}
