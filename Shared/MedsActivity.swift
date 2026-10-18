import ActivityKit
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
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var doses: [Item]

        var remaining: [Item] { doses.filter { !$0.taken } }
        var takenCount: Int { doses.count - remaining.count }
    }

    var day: Date
}

/// "Taken" button on the Live Activity and widget. Runs in the app's process.
nonisolated struct TakeDoseIntent: LiveActivityIntent {
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
            MedsActivityAttributes.Item(id: dose.id, name: dose.name, dose: dose.dose, time: dose.time, taken: taken[dose.id] != nil)
        }
        return .init(doses: items)
    }

    /// Updates running activities; ends them once everything is taken or the day is over.
    static func refresh() async {
        for activity in Activity<MedsActivityAttributes>.activities {
            let isToday = Calendar.current.isDateInToday(activity.attributes.day)
            let state = state(for: activity.attributes.day)
            let content = ActivityContent(state: state, staleDate: nil)
            if !isToday || state.remaining.isEmpty {
                await activity.end(content, dismissalPolicy: isToday ? .after(.now.addingTimeInterval(10 * 60)) : .immediate)
            } else {
                await activity.update(content)
            }
        }
    }
}
