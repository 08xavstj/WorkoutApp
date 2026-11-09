import ActivityKit
import AppIntents
import Foundation
import os
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

extension WorkoutActivityAttributes.ContentState {
    /// From when the rest started to when it ends. Always a valid range, unlike
    /// `now...end`, which traps if the rest ends between two reads of the clock.
    nonisolated var restRange: ClosedRange<Date>? {
        guard let restEndsAt else { return nil }
        return restEndsAt.addingTimeInterval(-max(1, restLength))...restEndsAt
    }
}

/// The rest timer, kept in the App Group so the app and the Live Activity's
/// buttons (+15s, Skip) change the same timer.
nonisolated enum RestTimerStore {
    private static let endsKey = "restEndsAt"
    /// Posted when the Live Activity's +15s / Skip change the timer, so the
    /// app can pass the new end to the Watch (`WatchSync`).
    static let changedNotification = Notification.Name("RestTimerStoreChanged")
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

    /// How long the workout screen shows "Rest done" after a rest runs out (app choice).
    static let doneDisplaySeconds: TimeInterval = 4

    /// When the rest ran out by itself, for up to `doneDisplaySeconds` after;
    /// nil while resting, after Skip (`stop`) and once the moment has passed.
    static var justFinishedAt: Date? {
        guard let value = SharedStore.defaults.object(forKey: endsKey) as? Date else { return nil }
        let since = Date.now.timeIntervalSince(value)
        return since >= 0 && since < doneDisplaySeconds ? value : nil
    }
}

/// How the end of a rest is signalled (Settings › Training › Rest timer alerts).
/// Stored in the App Group so the Live Activity's +15s / Skip use it too.
nonisolated enum RestAlertMode: String, CaseIterable, Sendable {
    /// The Watch buzzes when its app is recording the workout; otherwise the
    /// phone notifies, but only while the app isn't on screen.
    case watchFirst
    /// Only the phone's notification (iOS still shows it on the Watch when the phone is locked).
    case phoneOnly
    /// No notification and no buzz; the timer still counts down on screen.
    case off

    static let key = "restAlertMode"

    static var current: RestAlertMode {
        SharedStore.defaults.string(forKey: key).flatMap(RestAlertMode.init(rawValue:)) ?? .watchFirst
    }

    var title: String {
        switch self {
        case .watchFirst: "Watch, else phone"
        case .phoneOnly: "Phone only"
        case .off: "Off"
        }
    }
}

/// Whether the phone schedules its "Rest's over" notification and whether
/// the Watch buzzes.
///
/// iOS shows an iPhone notification on the Watch only while the iPhone is
/// locked or asleep, and there's no per-notification switch to stop that
/// (`interruptionLevel` changes Focus and Summary handling, not mirroring).
/// So while the Watch app records the workout (its HKWorkoutSession keeps it
/// running with the wrist down, so it buzzes on time), the phone schedules
/// nothing; otherwise you'd feel two buzzes.
nonisolated enum RestAlertPolicy {
    /// In memory only: a phone app that was quit forgets it, and then notifies
    /// as usual, which is the safe side.
    private static let watchRecordingState = OSAllocatedUnfairLock(initialState: false)

    /// Set by `WatchSync`: the Watch app is recording this workout and in reach.
    static var watchIsRecording: Bool {
        get { watchRecordingState.withLock { $0 } }
        set { watchRecordingState.withLock { $0 = newValue } }
    }

    static var phoneNotifies: Bool {
        switch RestAlertMode.current {
        case .watchFirst: !watchIsRecording
        case .phoneOnly: true
        case .off: false
        }
    }

    /// Sent to the Watch in each snapshot (`WatchSession.restBuzz`).
    static var watchBuzzes: Bool { RestAlertMode.current == .watchFirst }

    /// The in-app cue (haptic) on the workout screen.
    static var appCues: Bool { RestAlertMode.current != .off }
}

nonisolated enum WorkoutLiveActivity {
    static let restNotificationID = "rest-over"

    /// Pushes the current rest timer (and optionally exercise text) to the Live Activity
    /// and schedules the "rest's over" alert.
    static func refresh(exercise: String? = nil, detail: String? = nil) async {
        let ends = RestTimerStore.endsAt
        // +15s / Skip pass no detail: keep the Live Activity's for the alert text.
        let alertDetail = detail ?? Activity<WorkoutActivityAttributes>.activities.first?.content.state.detail
        for activity in Activity<WorkoutActivityAttributes>.activities {
            var state = activity.content.state
            state.restEndsAt = ends
            state.restLength = RestTimerStore.length
            if let exercise { state.exercise = exercise }
            if let detail { state.detail = detail }
            // Stale when rest ends, so iOS redraws it out of "rest" mode.
            await activity.update(ActivityContent(state: state, staleDate: ends))
        }
        await scheduleRestAlert(ends: ends, detail: alertDetail)
    }

    /// Schedules (or drops) the alert again after the rules changed: the Watch
    /// started or stopped recording, or the setting changed.
    static func rescheduleRestAlert() async {
        await scheduleRestAlert(ends: RestTimerStore.endsAt,
                                detail: Activity<WorkoutActivityAttributes>.activities.first?.content.state.detail)
    }

    /// A notification when rest ends, so it reaches you in another app or with
    /// the phone locked. Not scheduled when the Watch buzzes instead or alerts
    /// are off (`RestAlertPolicy`); not shown while the app is on screen
    /// (`AppRouter.willPresent`), where the workout screen shows "Rest done".
    static func scheduleRestAlert(ends: Date?, detail: String?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restNotificationID])
        guard let ends, ends.timeIntervalSinceNow > 1, RestAlertPolicy.phoneNotifies else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's over"
        if let detail, !detail.isEmpty {
            content.body = "Next: \(detail)"
        } else {
            content.body = "Time for your next set."
        }
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
        NotificationCenter.default.post(name: RestTimerStore.changedNotification, object: nil)
        return .result()
    }
}
