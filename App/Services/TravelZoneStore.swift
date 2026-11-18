import Foundation
import Observation
import AppCore

/// The phone's time zone over time (`TravelShift.Timeline` in AppCore), so
/// every night has the zone it was slept in, and the glue that puts travel
/// into the sleep numbers:
/// - `habitualNights`: bed and wake times for the bed-by window and the
///   caffeine cut-off, read on each night's own clock and moved onto local
///   time over a few days after a flight (`TravelShift.habitual`).
/// - `regularityScore`: the Sleep Regularity Index read zone by zone, with the
///   shift days left out (`SleepRegularity.travelAwareScore`).
/// - `shiftMinutes(on:)`: how far dose reminders still sit from their set time
///   (`Reminders.scheduleDoses`).
/// - `jetLagCard`: the melatonin and light card after a shift of 5 h or more.
///
/// The zone is noted on every metrics refresh and when iOS says the zone
/// changed. Kept as JSON in Application Support; demo mode shows a made-up
/// flight 6 h east yesterday for the card only and saves nothing.
@Observable
final class TravelZoneStore {
    static let shared = TravelZoneStore()

    nonisolated private struct Saved: Codable {
        var timeline: TravelShift.Timeline
        /// The change whose card was dismissed (`TravelShift.Change.date`).
        var dismissedCard: Date?
    }

    private(set) var timeline: TravelShift.Timeline
    private(set) var dismissedCard: Date?

    @ObservationIgnored private let file = SafeJSONFile.appSupport("travel-zones.json")
    /// False after a read that failed (phone locked): nothing is noted or saved until a read works.
    @ObservationIgnored private var canSave = false
    @ObservationIgnored private let isDemo = DemoMode.isOn
    @ObservationIgnored private var lastSaved: Date = .distantPast
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        timeline = TravelShift.Timeline(zone: Self.currentZone.identifier, at: .now)
        if isDemo {
            timeline = Self.demoTimeline()
            return
        }
        reload()
        observer = NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in
                TravelZoneStore.shared.noteZone()
                await Reminders.scheduleDoses()
            }
        }
    }

    /// The phone's zone now (the auto-updating zone, so a change while the
    /// app runs is seen without a restart).
    static var currentZone: TimeZone {
        TimeZone(identifier: TimeZone.autoupdatingCurrent.identifier) ?? .current
    }

    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        guard !isDemo else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = file.loadLogged(Saved.self, decoder: decoder)
        canSave = loaded.state.canSave
        guard canSave else { return }
        if let saved = loaded.value {
            timeline = saved.timeline
            dismissedCard = saved.dismissedCard
        } else {
            timeline = TravelShift.Timeline(zone: Self.currentZone.identifier, at: .now)
        }
    }

    private func write() {
        guard !isDemo else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        file.saveLogged(Saved(timeline: timeline, dismissedCard: dismissedCard), canSave: canSave, encoder: encoder)
    }

    // MARK: Noting the zone

    /// Notes the zone now; saves when it changed, or every half hour so
    /// `lastSeen` (which dates a change found later) stays close.
    func noteZone(now: Date = .now) {
        guard !isDemo else { return }
        reloadIfUnavailable()
        guard canSave else { return }
        let before = timeline
        let change = timeline.observe(Self.currentZone, at: now, calendar: .current)
        if change != nil || before.lastZone != timeline.lastZone || now.timeIntervalSince(lastSaved) > 30 * 60 {
            lastSaved = now
            write()
        }
    }

    /// The change still moving times today, if any.
    func activeChange(now: Date = .now) -> TravelShift.Change? {
        timeline.activeChange(on: now, calendar: .current)
    }

    // MARK: Sleep

    /// Nights for usual bed and wake times: each on its own zone's clock and
    /// moved by today's remaining shift; while a shift runs, nights since the
    /// change are left out (`TravelShift.habitual`). The nights themselves
    /// are unchanged without travel and in demo mode.
    func habitualNights(_ nights: [SleepNight], now: Date = .now) -> [SleepNight] {
        guard !isDemo, !timeline.changes.isEmpty else { return nights }
        let calendar = Calendar.current
        // Kept in step with `nights` by index: `habitual` keeps order and only drops.
        let times = nights.map { TravelShift.NightTimes(bedtime: $0.bedtime, wake: $0.wake) }
        let active = timeline.activeChange(on: now, calendar: calendar)
        let kept = nights.filter { night in active.map { night.wake < $0.date } ?? true }
        let moved = TravelShift.habitual(times, timeline: timeline, current: calendar.timeZone, now: now, calendar: calendar)
        guard moved.count == kept.count else { return nights }
        return zip(kept, moved).map { night, times in
            var copy = night
            copy.bedtime = times.bedtime
            copy.wake = times.wake
            return copy
        }
    }

    /// The Sleep Regularity Index with travel taken out; exactly
    /// `nights.regularityScore` when the timeline has no changes.
    func regularityScore(_ nights: [SleepNight], now: Date = .now) -> Int? {
        guard !isDemo, !timeline.changes.isEmpty, let first = nights.map(\.date).min() else { return nights.regularityScore }
        let calendar = Calendar.current
        let firstMorning = calendar.startOfDay(for: first)
        // The same window as `regularityScore`: noon before the first morning to noon today.
        let start = calendar.date(byAdding: .day, value: -1, to: firstMorning)
            .flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) } ?? firstMorning.addingTimeInterval(-12 * 3600)
        let mornings = SleepRegularity.calendarDays(from: start, to: now, calendar: calendar)
        return SleepRegularity.travelAwareScore(asleep: nights.flatMap(\.intervals), firstMorning: firstMorning,
                                                mornings: mornings, timeline: timeline, calendar: calendar)
    }

    // MARK: Doses

    /// Minutes a dose reminder on `day` still sits from its set time (later
    /// after flying east). 0 without a shift, and in demo mode.
    func shiftMinutes(on day: Date) -> Int {
        guard !isDemo else { return 0 }
        reloadIfUnavailable()
        return timeline.activeChange(on: day, calendar: .current)?.remainingMinutes(on: day, calendar: .current) ?? 0
    }

    // MARK: The card

    /// The melatonin and light card, while a 5 h+ shift runs and until dismissed.
    func jetLagCard(now: Date = .now) -> TravelShift.Change? {
        TravelShift.jetLagCard(timeline, dismissed: dismissedCard, now: now, calendar: .current)
    }

    func dismissCard() {
        guard let change = jetLagCard() else { return }
        dismissedCard = change.date
        write()
    }

    /// Demo mode only: minutes the card adds to the demo's (unshifted) bed-by
    /// and wake times, so its numbers match the made-up flight.
    var demoExtraMinutes: Int {
        guard isDemo, let change = activeChange() else { return 0 }
        return change.remainingMinutes(on: .now, calendar: .current)
    }

    /// A flight 6 h east, noticed yesterday morning: the card shows with 4 h to go.
    private static func demoTimeline() -> TravelShift.Timeline {
        let now = Date.now
        let current = currentZone
        let home = TimeZone(secondsFromGMT: current.secondsFromGMT(for: now) - 6 * 3600) ?? current
        let noticed = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        var timeline = TravelShift.Timeline(zone: home.identifier, at: noticed.addingTimeInterval(-12 * 3600))
        timeline.changes = [TravelShift.Change(date: noticed.addingTimeInterval(-12 * 3600), noticed: noticed,
                                               from: home.identifier, to: current.identifier, flightHours: 6, hours: 6)]
        timeline.lastZone = current.identifier
        timeline.lastSeen = now
        return timeline
    }
}
