import ActivityKit
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
    /// Bumped when doses change outside the app (Live Activity, notification).
    var dosesVersion = 0

    func open(_ url: URL) {
        guard url.scheme == "workoutapp" else { return }
        switch url.host() {
        case "hrv": showHRVEntry = true
        case "meds": showMedications = true
        case "photos": showProgressPhotos = true
        case "checkin": checkIn = url.lastPathComponent == "evening" ? .evening : .morning
        default: break
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        let link = response.notification.request.content.userInfo["link"] as? String
        if let doseID = DoseNotifications.doseID(fromIdentifier: identifier) {
            switch action {
            case DoseNotifications.takenAction:
                MedicationStore.markTaken(doseID)
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
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let fire = day.addingTimeInterval(TimeInterval(minutes * 60))
            guard fire > .now else { continue }
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
                let fire = day.addingTimeInterval(TimeInterval(minutes * 60))
                guard fire > .now else { continue }
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

    // MARK: Medications

    /// Reminders for every untaken dose over the next 3 days.
    static func scheduleDoses() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("dose|") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let doses = (0..<3).flatMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { MedicationStore.doses(on: $0) } ?? []
        }
        guard !doses.isEmpty, await requestPermission() else { return }
        let taken = MedicationStore.takenLog()
        for dose in doses where dose.time > .now && taken[dose.id] == nil {
            let content = UNMutableNotificationContent()
            content.title = "Time for \(dose.name)"
            content.body = dose.dose.isEmpty ? "Tap Taken once you've had it." : "\(dose.dose) · Tap Taken once you've had it."
            content.sound = .default
            content.categoryIdentifier = DoseNotifications.category
            content.userInfo = ["link": "workoutapp://meds"]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dose.time)
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
        let request = UNNotificationRequest(identifier: DoseNotifications.identifier(for: doseID), content: content,
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
