import ActivityKit
import os
import Foundation
import UserNotifications
import WidgetKit

/// Opens screens from links (widget, Live Activity, notifications) and
/// handles notification buttons ("Taken", "Snooze").
@Observable
final class AppRouter: NSObject, UNUserNotificationCenterDelegate {
    var showHRVEntry = false
    var showMedications = false
    var checkIn: CheckInKind?
    var showProgressPhotos = false
    /// Bumped to bring the running workout back on screen (Live Activity tap).
    var openWorkout = 0
    /// Bumped when doses change outside the app (Live Activity, notification).
    var dosesVersion = 0

    func open(_ url: URL) {
        Logger.diagnostics.notice("router.open \(url.absoluteString, privacy: .public)")
        guard url.scheme == "workoutapp" else { return }
        switch url.host() {
        case "hrv": showHRVEntry = true
        case "meds": showMedications = true
        case "photos": showProgressPhotos = true
        case "workout": openWorkout += 1
        case "checkin": checkIn = url.lastPathComponent == "evening" ? .evening : .morning
        default: break
        }
    }

    // These are called by iOS from a background queue. With approachable
    // concurrency a plain `nonisolated async` method would try to run on the
    // caller's executor, which crashes when a notification is tapped, so they
    // are explicitly @concurrent and hop to the main actor for UI state.
    @concurrent
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    @concurrent
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        Logger.diagnostics.notice("didReceive \(identifier, privacy: .public) action \(action, privacy: .public)")
        let link = response.notification.request.content.userInfo["link"] as? String
        if let doseID = Reminders.doseID(fromIdentifier: identifier) {
            switch action {
            case DoseNotifications.takenAction:
                MedicationStore.markTaken(doseID)
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Reminders.snoozeIdentifier(for: doseID)])
                await MedsLiveActivity.refresh()
                await MainActor.run { self.dosesVersion += 1 }
                return
            case DoseNotifications.snoozeAction:
                let title = response.notification.request.content.title
                let body = response.notification.request.content.body
                await Reminders.snooze(doseID: doseID, title: title, body: body)
                return
            default:
                break
            }
        }
        if let link, let url = URL(string: link) {
            await MainActor.run { self.open(url) }
        }
    }
}

extension Logger {
    /// Notification and link handling, for diagnosing launch and tap problems.
    nonisolated static let diagnostics = Logger(subsystem: "com.lontraindustries.workoutapp", category: "diagnostics")
}

/// Local notifications for the morning HRV reminder and medication doses.
nonisolated enum Reminders {
    static func registerCategories() {
        let taken = UNNotificationAction(identifier: DoseNotifications.takenAction, title: "Taken", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let snooze = UNNotificationAction(identifier: DoseNotifications.snoozeAction, title: "Snooze 10 min", options: [], icon: UNNotificationActionIcon(systemImageName: "clock"))
        let dose = UNNotificationCategory(identifier: DoseNotifications.category, actions: [taken, snooze], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([dose])
    }

    /// Asks once; returns whether notifications are allowed.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    // MARK: HRV

    /// One reminder a day for the next week at `minutes` after midnight,
    /// skipping today if HRV is already logged.
    static func scheduleHRV(enabled: Bool, minutes: Int, loggedToday: Bool) async {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<7).map { "hrv|\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled, await requestPermission() else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<7 {
            if offset == 0 && loggedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = fireDate(day: day, minutes: minutes, calendar: calendar), fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Log last night's HRV"
            content.body = "Open Garmin Connect → HRV Status and add last night's average. Takes 10 seconds."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://hrv"]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: ids[offset], content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
    }

    // MARK: Check-ins

    /// Morning and evening check-in reminders for the next week, skipping ones already done.
    static func scheduleCheckIns(enabled: Bool, morningMinutes: Int, eveningMinutes: Int, morningDone: Bool, eveningDone: Bool) async {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<7).flatMap { ["checkin|m|\($0)", "checkin|e|\($0)"] }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled, await requestPermission() else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for (kind, minutes, done) in [("m", morningMinutes, morningDone), ("e", eveningMinutes, eveningDone)] {
                if offset == 0 && done { continue }
                guard let fire = fireDate(day: day, minutes: minutes, calendar: calendar), fire > .now else { continue }
                let content = UNMutableNotificationContent()
                if kind == "m" {
                    content.title = "Morning check-in"
                    content.body = "Last night's HRV and how you feel. 30 seconds."
                    content.userInfo = ["link": "workoutapp://checkin/morning"]
                } else {
                    content.title = "Evening check-in"
                    content.body = "Caffeine, drinks and stress today. 45 seconds."
                    content.userInfo = ["link": "workoutapp://checkin/evening"]
                }
                content.sound = .default
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let request = UNNotificationRequest(identifier: "checkin|\(kind)|\(offset)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                try? await center.add(request)
            }
        }
    }

    #if DEBUG
    /// For UI tests: the same notification as the daily check-in reminder, in 10 seconds.
    static func scheduleTestCheckIn(kind: String) async {
        guard await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        let morning = kind == "morning"
        content.title = morning ? "Morning check-in" : "Evening check-in"
        content.body = morning ? "Last night's HRV and how you feel. 30 seconds." : "Caffeine, drinks and stress today. 45 seconds."
        content.userInfo = ["link": "workoutapp://checkin/\(morning ? "morning" : "evening")"]
        content.sound = .default
        let request = UNNotificationRequest(identifier: "checkin|\(morning ? "m" : "e")|test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
    #endif

    // MARK: Medications

    /// Snoozed reminders use their own prefix so rescheduling doesn't remove them.
    static func snoozeIdentifier(for doseID: String) -> String { "dose-snooze|\(doseID)" }

    /// The dose a notification is for, whether it's the scheduled one or a snooze.
    static func doseID(fromIdentifier identifier: String) -> String? {
        let snoozePrefix = "dose-snooze|"
        if identifier.hasPrefix(snoozePrefix) { return String(identifier.dropFirst(snoozePrefix.count)) }
        return DoseNotifications.doseID(fromIdentifier: identifier)
    }

    /// `minutes` after midnight on `day`, correct on daylight-saving change days.
    static func fireDate(day: Date, minutes: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    /// The most dose reminders kept pending. iOS keeps only 64 per app, and
    /// check-ins (14), HRV (7), the rest timer and snoozes need room too.
    static let maxPendingDoses = 38

    /// Reminders for every untaken dose over the next 14 days (soonest first,
    /// up to `maxPendingDoses`). Opening the app tops the queue back up.
    static func scheduleDoses() async {
        let center = UNUserNotificationCenter.current()
        let pendingIDs = await center.pendingNotificationRequests().map(\.identifier)
        let taken = MedicationStore.takenLog()
        // Scheduled reminders are rebuilt; snoozes stay unless that dose was taken.
        let stale = pendingIDs.filter { id in
            if id.hasPrefix("dose|") { return true }
            if id.hasPrefix("dose-snooze|"), let doseID = doseID(fromIdentifier: id) { return taken[doseID] != nil }
            return false
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let now = Date.now
        var upcoming: [(dose: Dose, fire: Date)] = []
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for dose in MedicationStore.doses(on: day) where taken[dose.id] == nil {
                if let fire = fireDate(day: day, minutes: dose.minutes, calendar: calendar), fire > now {
                    upcoming.append((dose, fire))
                }
            }
        }
        upcoming.sort { $0.fire < $1.fire }
        guard !upcoming.isEmpty, await requestPermission() else { return }
        for (dose, fire) in upcoming.prefix(maxPendingDoses) {
            let content = UNMutableNotificationContent()
            content.title = "Time for \(dose.name)"
            content.body = dose.dose.isEmpty ? "Tap Taken once you've had it." : "\(dose.dose) · Tap Taken once you've had it."
            content.sound = .default
            content.categoryIdentifier = DoseNotifications.category
            content.userInfo = ["link": "workoutapp://meds"]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: DoseNotifications.identifier(for: dose.id), content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
    }

    static func snooze(doseID: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = DoseNotifications.category
        content.userInfo = ["link": "workoutapp://meds"]
        let request = UNNotificationRequest(identifier: snoozeIdentifier(for: doseID), content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Starts today's medication Live Activity if there are doses left and
    /// none is showing. iOS only lets the app start one while it's open.
    static func startMedsActivityIfNeeded() async {
        await MedsLiveActivity.refresh()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = MedsLiveActivity.state()
        guard !state.remaining.isEmpty else { return }
        let running = Activity<MedsActivityAttributes>.activities.contains { Calendar.current.isDateInToday($0.attributes.day) }
        guard !running else { return }
        let attributes = MedsActivityAttributes(day: Calendar.current.startOfDay(for: .now))
        _ = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
    }

    static func endMedsActivities() async {
        for activity in Activity<MedsActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Saves what the widget shows and asks it to redraw.
    static func updateWidget(_ snapshot: WidgetSnapshot) {
        if WidgetSnapshot.load() != snapshot.withUpdated(WidgetSnapshot.load()?.updated) {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

private extension WidgetSnapshot {
    nonisolated func withUpdated(_ date: Date?) -> WidgetSnapshot {
        var copy = self
        copy.updated = date ?? updated
        return copy
    }
}
