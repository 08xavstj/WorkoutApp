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
        /// When the dose joins the card (`DoseCard`): 06:00 for medications,
        /// noon for creatine and other supplements. Optional so a card started
        /// by an older build still decodes.
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

        /// The next time untaken doses join the card (noon, while supplements wait).
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
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [DoseNotifications.identifier(for: doseID)])
        center.removeDeliveredNotifications(withIdentifiers: [DoseNotifications.identifier(for: doseID)])
        await MedsLiveActivity.refresh()
        return .result()
    }
}

nonisolated enum DoseNotifications {
    static let category = "DOSE"
    static let takenAction = "DOSE_TAKEN"
    static let snoozeAction = "DOSE_SNOOZE"

    static func identifier(for doseID: String) -> String { "dose|\(doseID)" }

    static func doseID(fromIdentifier identifier: String) -> String? {
        identifier.hasPrefix("dose|") ? String(identifier.dropFirst(5)) : nil
    }
}

nonisolated enum MedsLiveActivity {
    /// Today's doses with taken state.
    static func state(for day: Date = .now) -> MedsActivityAttributes.ContentState {
        let taken = MedicationStore.takenLog()
        let items = MedicationStore.doses(on: day).map { dose in
            MedsActivityAttributes.Item(id: dose.id, name: dose.name, dose: dose.dose, time: dose.time, taken: taken[dose.id] != nil,
                                        showFrom: DoseCard.showFrom(name: dose.name, day: dose.day),
                                        supplement: DoseCard.isSupplement(dose.name))
        }
        return .init(doses: items)
    }

    /// Updates running activities; ends them once everything showing is taken
    /// or the day is over. The stale date is the next time doses join the card
    /// (noon), which is when iOS redraws it.
    static func refresh() async {
        let now = Date.now
        for activity in Activity<MedsActivityAttributes>.activities {
            let isToday = Calendar.current.isDateInToday(activity.attributes.day)
            let state = state(for: activity.attributes.day)
            let content = ActivityContent(state: state, staleDate: state.nextReveal(after: now))
            if !isToday || state.remaining(at: now).isEmpty {
                await activity.end(content, dismissalPolicy: isToday ? .after(.now.addingTimeInterval(10 * 60)) : .immediate)
            } else {
                await activity.update(content)
            }
        }
    }
}
