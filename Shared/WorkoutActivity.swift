import ActivityKit
import AppIntents
import Foundation
import UserNotifications

/// Live Activity for a gym session: elapsed time, the next set, and the rest
/// timer counting down on the Lock Screen and in the Dynamic Island.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// When the current rest ends, or nil when not resting.
        var restEndsAt: Date?
        var restLength: Double
        /// e.g. "Bench Press"
        var exercise: String
        /// e.g. "Set 3 of 4 · 135 lb × 8"
        var detail: String
    }

    var workoutName: String
    var startedAt: Date
}

/// The rest timer, kept in the App Group so the app and the Live Activity's
/// buttons (+15s, Skip) change the same timer.
nonisolated enum RestTimerStore {
    private static let endsKey = "restEndsAt"
    private static let lengthKey = "restLength"

    static var endsAt: Date? {
        guard let value = SharedStore.defaults.object(forKey: endsKey) as? Date, value > .now else { return nil }
        return value
    }

    static var length: Double {
        let value = SharedStore.defaults.double(forKey: lengthKey)
        return value > 0 ? value : 90
    }

    static func start(seconds: Double) {
        SharedStore.defaults.set(Date.now.addingTimeInterval(seconds), forKey: endsKey)
        SharedStore.defaults.set(seconds, forKey: lengthKey)
    }

    /// +/- seconds; ends the rest if it drops to zero.
    static func adjust(by seconds: Double) {
        guard let ends = endsAt else { return }
        let newEnd = ends.addingTimeInterval(seconds)
        if newEnd <= .now {
            stop()
        } else {
            SharedStore.defaults.set(newEnd, forKey: endsKey)
            SharedStore.defaults.set(max(15, length + seconds), forKey: lengthKey)
        }
    }

    static func stop() {
        SharedStore.defaults.removeObject(forKey: endsKey)
    }
}

nonisolated enum WorkoutLiveActivity {
    static let restNotificationID = "rest-over"

    /// Pushes the current rest timer (and optionally exercise text) to the Live Activity
    /// and schedules the "rest's over" alert.
    static func refresh(exercise: String? = nil, detail: String? = nil) async {
        let ends = RestTimerStore.endsAt
        for activity in Activity<WorkoutActivityAttributes>.activities {
            var state = activity.content.state
            state.restEndsAt = ends
            state.restLength = RestTimerStore.length
            if let exercise { state.exercise = exercise }
            if let detail { state.detail = detail }
            // Stale when rest ends, so iOS redraws it out of "rest" mode.
            await activity.update(ActivityContent(state: state, staleDate: ends))
        }
        await scheduleRestAlert(ends: ends, detail: detail)
    }

    /// A notification when rest ends, so it reaches you in another app.
    static func scheduleRestAlert(ends: Date?, detail: String?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        guard let ends, ends.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's over"
        content.body = detail.map { "Next: \($0)" } ?? "Time for your next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: restNotificationID, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: ends.timeIntervalSinceNow, repeats: false))
        try? await center.add(request)
    }

    static func endAll() async {
        RestTimerStore.stop()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// "+15s" / "Skip" on the rest timer Live Activity. Runs in the app's process.
struct AdjustRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust rest timer"
    static let description = IntentDescription("Adds time to, or skips, the rest timer.")

    /// Seconds to add; 0 skips the rest.
    @Parameter(title: "Seconds")
    var seconds: Int

    init() {}

    init(seconds: Int) {
        self.seconds = seconds
    }

    func perform() async throws -> some IntentResult {
        if seconds == 0 {
            RestTimerStore.stop()
        } else {
            RestTimerStore.adjust(by: Double(seconds))
        }
        await WorkoutLiveActivity.refresh()
        return .result()
    }
}
