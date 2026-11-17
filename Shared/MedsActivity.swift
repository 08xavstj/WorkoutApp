import ActivityKit
import AppCore
import AppIntents
import Foundation
import UserNotifications

/// Live Activity showing today's medication doses with "Taken" buttons.
nonisolated struct MedsActivityAttributes: ActivityAttributes {
    nonisolated struct Item: Codable, Hashable, Identifiable, Sendable {
        var id: String
        var name: String
        var dose: String
        var time: Date
        var taken: Bool
        /// When the dose joins the card (`DoseCard`): two hours before its
        /// time, never before 06:00 for medications or noon for creatine and
        /// other supplements. Optional so a card started by an older build
        /// still decodes.
        var showFrom: Date? = nil
        var supplement: Bool? = nil
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var doses: [Item]

        /// Doses whose time on the card has come. The widget calls these when
        /// it draws, so supplements join at noon when iOS redraws the card
        /// (its stale date) without the app running.
        func shown(at now: Date) -> [Item] {
            doses.filter { ($0.showFrom ?? .distantPast) <= now }
        }

        func remaining(at now: Date) -> [Item] { shown(at: now).filter { !$0.taken } }
        func takenCount(at now: Date) -> Int { shown(at: now).count - remaining(at: now).count }

        /// The next time untaken doses join the card (noon for supplements, two hours before an evening dose).
        func nextReveal(after now: Date = .now) -> Date? {
            doses.filter { !$0.taken }.compactMap(\.showFrom).filter { $0 > now }.min()
        }

        /// "Medications today", "Supplements today" or both, from what's left to take.
        func title(at now: Date = .now) -> String {
            let left = remaining(at: now)
            let list = left.isEmpty ? shown(at: now) : left
            let supplements = list.filter { $0.supplement == true }.count
            if !list.isEmpty && supplements == list.count { return "Supplements today" }
            return supplements == 0 ? "Medications today" : "Meds & supplements"
        }

        var remaining: [Item] { remaining(at: .now) }
        var shown: [Item] { shown(at: .now) }
        var takenCount: Int { takenCount(at: .now) }
    }

    var day: Date
}

/// "Taken" button on the Live Activity and widget. Runs in the app's process.
struct TakeDoseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark dose taken"
    static let description = IntentDescription("Marks a medication dose as taken.")

    @Parameter(title: "Dose")
    var doseID: String

    init() {}

    init(doseID: String) {
        self.doseID = doseID
    }

    func perform() async throws -> some IntentResult {
        MedicationStore.markTaken(doseID)
        DoseNotifications.clear(doseID)
        await MedsLiveActivity.refresh()
        return .result()
    }
}

nonisolated enum DoseNotifications {
    static let category = "DOSE"
    static let takenAction = "DOSE_TAKEN"
    static let snoozeAction = "DOSE_SNOOZE"

    static func identifier(for doseID: String) -> String { "dose|\(doseID)" }

    /// Snoozed reminders use their own prefix so rescheduling doesn't remove them.
    static func snoozeIdentifier(for doseID: String) -> String { "dose-snooze|\(doseID)" }

    static func doseID(fromIdentifier identifier: String) -> String? {
        identifier.hasPrefix("dose|") ? String(identifier.dropFirst(5)) : nil
    }

    /// The dose was taken: its reminder and its snooze go, whether still
    /// waiting or already on the Lock Screen.
    static func clear(_ doseID: String) {
        let ids = [identifier(for: doseID), snoozeIdentifier(for: doseID)]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}

nonisolated enum MedsLiveActivity {
    /// Settings › Reminders › "Doses on the Lock Screen". On unless switched
    /// off; in the App Group so the card's own "Taken" button reads the same value.
    static let enabledKey = "medsLockScreenCardOn"
    static var isEnabled: Bool { SharedStore.defaults.object(forKey: enabledKey) as? Bool ?? true }

    /// How long "All taken" stays on the Lock Screen before the card goes (app's choice).
    static let allTakenLingerSeconds: TimeInterval = 10 * 60

    /// Today's doses with taken state.
    static func state(for day: Date = .now) -> MedsActivityAttributes.ContentState {
        let taken = MedicationStore.takenLog()
        let items = MedicationStore.doses(on: day).map { dose in
            MedsActivityAttributes.Item(id: dose.id, name: dose.name, dose: dose.dose, time: dose.time, taken: taken[dose.id] != nil,
                                        showFrom: DoseCard.showFrom(name: dose.name, day: dose.day, minutes: dose.minutes),
                                        supplement: DoseCard.isSupplement(dose.name))
        }
        return .init(doses: items)
    }

    /// When iOS should redraw the card without the app running: the next time
    /// a dose joins it, else the end of its day (the widget then shows one
    /// line instead of yesterday's doses).
    static func staleDate(for state: MedsActivityAttributes.ContentState, day: Date, now: Date) -> Date? {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
        return [state.nextReveal(after: now), midnight].compactMap { $0 }.filter { $0 > now }.min()
    }

    /// Showing and still updatable: not one iOS or the user has ended or dismissed.
    static func isLive(_ activity: Activity<MedsActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .stale: true
        default: false
        }
    }

    // MARK: What the app last did with today's card (`DoseCard.CardLog`)

    private static let logKey = "medsCardLog"

    static var cardLog: DoseCard.CardLog? { SharedStore.load(DoseCard.CardLog.self, key: logKey) }

    /// A card was started, or a running one updated, with these untaken doses on it.
    static func noteOffered(_ doseIDs: [String], day: Date, started: Bool) {
        let key = Dose.dayKey(day)
        var log = cardLog.flatMap { $0.day == key ? $0 : nil } ?? DoseCard.CardLog(day: key, offered: [])
        let offered = Array(Set(log.offered).union(doseIDs)).sorted()
        guard started || offered != log.offered || log.endedByApp else { return }
        log.offered = offered
        log.endedByApp = false
        SharedStore.save(log, key: logKey)
    }

    /// The app took the card down itself (all taken, or switched off), so a later start isn't held back.
    static func noteEndedByApp(day: Date) {
        let key = Dose.dayKey(day)
        guard var log = cardLog, log.day == key, !log.endedByApp else { return }
        log.endedByApp = true
        SharedStore.save(log, key: logKey)
    }

    /// Updates running activities; ends them once everything showing is taken,
    /// the day is over, there is nothing to show (the last medication was
    /// deleted) or the card was switched off. The stale date is the next time
    /// iOS should redraw the card (`staleDate`).
    static func refresh() async {
        let now = Date.now
        let calendar = Calendar.current
        let enabled = isEnabled
        for activity in Activity<MedsActivityAttributes>.activities {
            let day = activity.attributes.day
            let isToday = calendar.isDateInToday(day)
            guard isLive(activity) else {
                // Already ended: nothing to update. One left over from another day (or after switching off) goes now.
                if activity.activityState == .ended, !isToday || !enabled {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                continue
            }
            let state = state(for: day)
            let content = ActivityContent(state: state, staleDate: staleDate(for: state, day: day, now: now))
            let left = state.remaining(at: now)
            if !enabled || !isToday || state.shown(at: now).isEmpty {
                await activity.end(content, dismissalPolicy: .immediate)
                if isToday { noteEndedByApp(day: day) }
            } else if left.isEmpty {
                await activity.end(content, dismissalPolicy: .after(now.addingTimeInterval(allTakenLingerSeconds)))
                noteEndedByApp(day: day)
            } else {
                if activity.content.state != state || activity.content.staleDate != content.staleDate {
                    await activity.update(content)
                }
                noteOffered(left.map(\.id), day: day, started: false)
            }
        }
    }
}
