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
    /// The weekly review and this week's plan (Monday notification, Home card, Log tab).
    var showWeeklyReview = false
    var showWeeklyPlan = false
    /// Body measurements (workoutapp://measurements) and blood pressure (workoutapp://bp) sheets.
    var showMeasurements = false
    var showBloodPressure = false
    /// Settings, presented once at the root so any tab's profile button
    /// (`TabToolbar`) can open it.
    var showSettings = false
    /// Bumped to bring the running workout back on screen (Live Activity tap).
    var openWorkout = 0
    /// Bumped when doses change outside the app (Live Activity, notification).
    var dosesVersion = 0
    /// A link from a tapped notification, opened once the app is fully on
    /// screen. Presenting a sheet while iOS is still bringing the app to the
    /// front (or launching it) fails or crashes, so it waits for `.active`.
    var pendingLink: URL?

    /// Opens a waiting notification link, a moment after the app becomes active.
    func openPendingLink() {
        guard let url = pendingLink else { return }
        pendingLink = nil
        Logger.diagnostics.notice("opening pending link \(url.absoluteString, privacy: .public)")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.open(url)
        }
    }

    func open(_ url: URL) {
        Logger.diagnostics.notice("router.open \(url.absoluteString, privacy: .public)")
        guard url.scheme == "workoutapp" else { return }
        switch url.host() {
        case "hrv": showHRVEntry = true
        case "meds": showMedications = true
        case "photos": showProgressPhotos = true
        case "workout": openWorkout += 1
        case "checkin": openCheckIn(url.lastPathComponent == "evening" ? .evening : .morning)
        case "review": showWeeklyReview = true
        case "plan": showWeeklyPlan = true
        case "measurements": showMeasurements = true
        case "bp": showBloodPressure = true
        default: break
        }
    }

    /// A sheet can't open while another one is showing, so close any other
    /// screen first and open the check-in once it has gone.
    private func openCheckIn(_ kind: CheckInKind) {
        let otherOpen = showHRVEntry || showMedications || showProgressPhotos || showWeeklyReview || showWeeklyPlan
            || showMeasurements || showBloodPressure || showSettings || (checkIn != nil && checkIn != kind)
        guard otherOpen else {
            checkIn = kind
            return
        }
        showHRVEntry = false
        showMedications = false
        showProgressPhotos = false
        showWeeklyReview = false
        showWeeklyPlan = false
        showMeasurements = false
        showBloodPressure = false
        showSettings = false
        checkIn = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            self.checkIn = kind
        }
    }

    // iOS calls these on the main thread and expects the completion handler
    // back on the main thread. The `async` versions of these methods finish
    // on a background thread, and UIKit then aborts the app ("must be called
    // on the main thread"), which is what crashed taps on check-in
    // notifications. So these use completion handlers and call them from the
    // main actor.
    @objc(userNotificationCenter:willPresentNotification:withCompletionHandler:)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    @objc(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        let link = response.notification.request.content.userInfo["link"] as? String
        Logger.diagnostics.notice("didReceive \(identifier, privacy: .public) action \(action, privacy: .public)")
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            await self.handleResponse(identifier: identifier, action: action, title: title, body: body, link: link)
            done()
        }
    }

    private func handleResponse(identifier: String, action: String, title: String, body: String, link: String?) async {
        if let doseID = Reminders.doseID(fromIdentifier: identifier) {
            switch action {
            case DoseNotifications.takenAction:
                MedicationStore.markTaken(doseID)
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Reminders.snoozeIdentifier(for: doseID)])
                await MedsLiveActivity.refresh()
                dosesVersion += 1
                return
            case DoseNotifications.snoozeAction:
                await Reminders.snooze(doseID: doseID, title: title, body: body)
                return
            default:
                break
            }
        }
        if let dayKey = Reminders.workoutDayKey(fromIdentifier: identifier) {
            // A tapped workout reminder counts as answered (see `Reminders.WorkoutReminderLog`).
            Reminders.WorkoutReminderLog.noteTapped(dayKey: dayKey)
        }
        if let link, let url = URL(string: link) {
            pendingLink = url
        }
    }
}

extension Logger {
    /// Notification and link handling, for diagnosing launch and tap problems.
    nonisolated static let diagnostics = Logger(subsystem: "com.lontraindustries.workoutapp", category: "diagnostics")
}

/// Local notifications: one morning check-in (which covers last night's HRV),
/// one evening reflection (with tonight's bed-by window), workout reminders
/// only before a planned slot, and medication doses.
///
/// Fewer, better-timed prompts: support should arrive when the person can act
/// on it (Nahum-Shani et al., Ann Behav Med 2018), and the effect of repeated
/// prompts decays with habituation (Klasnja et al., Ann Behav Med 2019:
/// +107% early, +14% on average), so each kind is sent at most once a day,
/// skipped once done, and workout reminders pause after two ignored in a row.
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

    /// The separate HRV reminder is gone: last night's HRV is part of the
    /// morning check-in notification (one morning prompt, one evening prompt;
    /// docs/research/behaviour-change.md rec. 8). This only clears reminders
    /// left over from older versions; the arguments are kept so call sites compile.
    static func scheduleHRV(enabled: Bool, minutes: Int, loggedToday: Bool) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<7).map { "hrv|\($0)" })
    }

    // MARK: Check-ins

    /// Morning and evening reminders for the next week, skipping today's once done.
    /// - Parameters:
    ///   - morningDone: the morning check-in is saved. Today's prompt is skipped
    ///     when it is and HRV is in too (or you don't type HRV at all).
    ///   - hrvMissing: the check-in is saved but HRV isn't; today's prompt then
    ///     asks only for HRV.
    ///   - weighInNudge: add the weigh-in line to the first morning reminder
    ///     (the caller sends it at most once a week).
    ///   - bedByTonight: tonight's bed-by window ("21:50–22:20") for the evening reminder.
    /// - Returns: the day whose morning reminder carries the weigh-in line, if any.
    @discardableResult
    static func scheduleCheckIns(enabled: Bool, morningMinutes: Int, eveningMinutes: Int, morningDone: Bool, eveningDone: Bool,
                                 hrvMissing: Bool = false, weighInNudge: Bool = false, bedByTonight: String? = nil) async -> Date? {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<7).flatMap { ["checkin|m|\($0)", "checkin|e|\($0)"] }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled, await requestPermission() else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var nudgeDay: Date?
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let skipMorning = offset == 0 && morningDone && !hrvMissing
            if !skipMorning, let fire = fireDate(day: day, minutes: morningMinutes, calendar: calendar), fire > .now {
                let withNudge = weighInNudge && nudgeDay == nil
                if withNudge { nudgeDay = day }
                let content = morningContent(hrvOnly: offset == 0 && morningDone && hrvMissing, weighIn: withNudge)
                await add(content, identifier: "checkin|m|\(offset)", at: fire, center: center, calendar: calendar)
            }
            let skipEvening = offset == 0 && eveningDone
            if !skipEvening, let fire = fireDate(day: day, minutes: eveningMinutes, calendar: calendar), fire > .now {
                let content = eveningContent(bedBy: offset == 0 ? bedByTonight : nil)
                await add(content, identifier: "checkin|e|\(offset)", at: fire, center: center, calendar: calendar)
            }
        }
        return nudgeDay
    }

    /// "Morning check-in: HRV and how you feel", or only the HRV when the rest is done.
    static func morningContent(hrvOnly: Bool, weighIn: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Morning check-in"
        if hrvOnly {
            content.body = "Add last night's HRV; the rest of the check-in is done."
            content.userInfo = ["link": "workoutapp://hrv"]
        } else {
            content.body = "Last night's HRV and how you feel. 30 seconds."
            content.userInfo = ["link": "workoutapp://checkin/morning"]
        }
        if weighIn {
            // Regular self-weighing goes with better weight control (Zheng et al., Obesity 2015;
            // Madigan et al., IJBNPA 2015); the trend line needs 4+ readings over 10 days.
            content.body += " Step on the scale too: weighing most mornings keeps your trend honest."
        }
        content.sound = .default
        return content
    }

    /// Evening reflection: one win plus how the day felt (behaviour-change.md rec. 10),
    /// with tonight's bed-by window when known (`BedtimeWindow`).
    static func eveningContent(bedBy: String?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Evening check-in"
        content.body = "One win and how today felt. 45 seconds."
        if let bedBy { content.body += " In bed by \(bedBy) tonight." }
        content.userInfo = ["link": "workoutapp://checkin/evening"]
        content.sound = .default
        return content
    }

    private static func add(_ content: UNMutableNotificationContent, identifier: String, at fire: Date,
                            center: UNUserNotificationCenter, calendar: Calendar) async {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await center.add(request)
    }

    #if DEBUG
    /// For UI tests: the same notification as the daily check-in reminder, in 10 seconds.
    static func scheduleTestCheckIn(kind: String) async {
        guard await requestPermission() else { return }
        let morning = kind == "morning"
        let content = morning ? morningContent(hrvOnly: false, weighIn: false) : eveningContent(bedBy: nil)
        let request = UNNotificationRequest(identifier: "checkin|\(morning ? "m" : "e")|test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
    #endif

    // MARK: Workouts

    /// A planned training slot from the weekly plan. The lead wires these from
    /// `WeeklyPlanStore`; a workout reminder exists only for such a slot
    /// (behaviour-change.md rec. 2 and 8: reminders fire only for pre-committed days).
    struct PlannedSlot: Sendable, Equatable {
        var start: Date
        /// "Upper A", "Easy ride".
        var name: String
        /// The if-then line the user wrote ("If I'm late, I do the 15-minute version.").
        var ifThen: String?

        init(start: Date, name: String, ifThen: String? = nil) {
            self.start = start
            self.name = name
            self.ifThen = ifThen
        }
    }

    /// Minutes before the planned time (rec. 8: 30-60 minutes before a planned slot).
    static let workoutLeadMinutes = 30
    /// Ignored reminders in a row before they pause: each prompt spends attention
    /// and repeated ones habituate (Klasnja et al., Ann Behav Med 2019).
    static let ignoredBeforePause = 2

    /// "2027-01-10": sortable, one per day.
    static func dayKey(_ day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func workoutIdentifier(forDayKey key: String) -> String { "workout|\(key)" }

    static func workoutDayKey(fromIdentifier identifier: String) -> String? {
        let prefix = "workout|"
        guard identifier.hasPrefix(prefix) else { return nil }
        return String(identifier.dropFirst(prefix.count))
    }

    /// Workout reminders are paused after `ignoredBeforePause` went unanswered in a
    /// row (no tap, no session that day). Settings says so; confirming the next
    /// weekly plan resumes them.
    static var workoutRemindersPaused: Bool { WorkoutReminderLog.isPaused }

    /// Clears the pause and the ignored count. Call when the user confirms a weekly plan.
    static func resumeWorkoutReminders() { WorkoutReminderLog.resume() }

    /// One reminder per planned slot over the next week, `workoutLeadMinutes`
    /// before it, with the user's if-then line in the body.
    /// - Parameters:
    ///   - slots: planned slots (from `WeeklyPlanStore`); none means no reminders.
    ///   - trainedDays: start-of-day dates with a logged or watch workout, so an
    ///     answered reminder (trained without tapping) doesn't count as ignored.
    static func scheduleWorkoutReminders(slots: [PlannedSlot], enabled: Bool, trainedDays: Set<Date>, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("workout|") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        WorkoutReminderLog.updatePause(trainedDays: trainedDays, today: today, calendar: calendar)
        guard enabled, !WorkoutReminderLog.isPaused else { return }
        let upcoming = slots.filter { $0.start > now }.sorted { $0.start < $1.start }
        guard !upcoming.isEmpty, await requestPermission() else { return }
        var scheduled: [String] = []
        for slot in upcoming where scheduled.count < 7 {
            let fire = slot.start.addingTimeInterval(-TimeInterval(workoutLeadMinutes * 60))
            guard fire > now else { continue }
            let key = dayKey(calendar.startOfDay(for: slot.start), calendar: calendar)
            // One a day: a second slot the same day rides on the first.
            guard !scheduled.contains(key) else { continue }
            scheduled.append(key)
            let content = UNMutableNotificationContent()
            content.title = "\(slot.name) at \(slot.start.formatted(date: .omitted, time: .shortened))"
            content.body = slot.ifThen ?? "Your planned session in 30 minutes. The short version counts too."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://plan"]
            await add(content, identifier: workoutIdentifier(forDayKey: key), at: fire, center: center, calendar: calendar)
        }
        WorkoutReminderLog.noteScheduled(dayKeys: scheduled, today: today, calendar: calendar)
    }

    /// Which workout reminders went out, which were tapped, and whether they're
    /// paused. In UserDefaults so the notification delegate can write to it off
    /// the main actor.
    enum WorkoutReminderLog {
        static let scheduledKey = "workoutRemindersScheduled"
        static let tappedKey = "workoutRemindersTapped"
        static let pausedKey = "workoutRemindersPaused"

        static var isPaused: Bool { UserDefaults.standard.bool(forKey: pausedKey) }

        static func noteTapped(dayKey: String) {
            var tapped = UserDefaults.standard.stringArray(forKey: tappedKey) ?? []
            guard !tapped.contains(dayKey) else { return }
            tapped.append(dayKey)
            UserDefaults.standard.set(Array(tapped.suffix(30)), forKey: tappedKey)
        }

        /// Keeps past days (they may still count as ignored) and replaces the upcoming ones.
        static func noteScheduled(dayKeys: [String], today: Date, calendar: Calendar) {
            let todayKey = Reminders.dayKey(today, calendar: calendar)
            let past = (UserDefaults.standard.stringArray(forKey: scheduledKey) ?? []).filter { $0 < todayKey }
            let merged = Array((past + dayKeys).sorted().suffix(30))
            UserDefaults.standard.set(merged, forKey: scheduledKey)
        }

        /// Pauses when the last `ignoredBeforePause` past reminders were neither tapped nor followed by training.
        static func updatePause(trainedDays: Set<Date>, today: Date, calendar: Calendar) {
            guard !isPaused else { return }
            let todayKey = Reminders.dayKey(today, calendar: calendar)
            let scheduled = (UserDefaults.standard.stringArray(forKey: scheduledKey) ?? []).filter { $0 < todayKey }
            let tapped = Set(UserDefaults.standard.stringArray(forKey: tappedKey) ?? [])
            let trained = Set(trainedDays.map { Reminders.dayKey($0, calendar: calendar) })
            var ignored = 0
            for key in scheduled.sorted().reversed() {
                if tapped.contains(key) || trained.contains(key) { break }
                ignored += 1
            }
            if ignored >= ignoredBeforePause {
                UserDefaults.standard.set(true, forKey: pausedKey)
            }
        }

        static func resume() {
            UserDefaults.standard.set(false, forKey: pausedKey)
            UserDefaults.standard.removeObject(forKey: scheduledKey)
            UserDefaults.standard.removeObject(forKey: tappedKey)
        }
    }

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
    /// check-ins (14), workouts (up to 7), the rest timer and snoozes need room too.
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

    // MARK: - Weekly review

    static let weeklyReviewIdentifier = "review|weekly"

    /// One repeating reminder every Monday at `minutes` after midnight, opening
    /// the weekly review. A new week is a "fresh start" landmark (Dai et al.,
    /// Manag Sci 2014) and reviewing goals is what makes self-monitoring work
    /// (Michie et al., Health Psychol 2009); a fixed, user-chosen time does as
    /// well as inferred timing (Morrison et al., PLoS One 2017, cited from
    /// memory in docs/research/behaviour-change.md).
    static func scheduleWeeklyReview(enabled: Bool, minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyReviewIdentifier])
        guard enabled, await requestPermission() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Weekly review"
        content.body = "Last week in plain numbers, then three changes for this week. Two minutes."
        content.sound = .default
        content.userInfo = ["link": "workoutapp://review"]
        var components = DateComponents()
        components.weekday = 2 // Monday
        components.hour = minutes / 60
        components.minute = minutes % 60
        let request = UNNotificationRequest(identifier: weeklyReviewIdentifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        try? await center.add(request)
    }

    // MARK: - Measurements

    static let waistReminderIdentifier = "measure|waist"
    static let gripReminderIdentifier = "measure|grip"
    static let bloodPressureReminderIdentifier = "measure|bp"
    /// Measurement reminders arrive mid-morning (app choice: a tape or a cuff
    /// reading is best taken rested, before food; 9:00 leaves the morning
    /// check-in alone).
    static let measurementMinutes = 9 * 60

    /// The monthly waist reminder and the 6-monthly grip reminder
    /// (`WaistToHeightRatio.nextDue`, `GripStrength.nextDue`; Ashwell 2012,
    /// EWGSOP2 via docs/research/health-metrics.md). A nil due date clears that
    /// reminder; one already in the past fires tomorrow morning.
    static func scheduleMeasurementReminders(waistDue: Date?, gripDue: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [waistReminderIdentifier, gripReminderIdentifier])
        guard waistDue != nil || gripDue != nil, await requestPermission() else { return }
        let calendar = Calendar.current
        if let waistDue, let fire = measurementFireDate(due: waistDue, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = "Monthly waist check"
            content.body = "Tape at the navel, relaxed, after breathing out. Under half your height is the target."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://measurements"]
            await add(content, identifier: waistReminderIdentifier, at: fire, center: center, calendar: calendar)
        }
        if let gripDue, let fire = measurementFireDate(due: gripDue, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = "Grip strength, twice a year"
            content.body = "Dominant hand, best of three squeezes on a dynamometer. Two minutes."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://measurements"]
            await add(content, identifier: gripReminderIdentifier, at: fire, center: center, calendar: calendar)
        }
    }

    /// The 3-6-monthly reminder to repeat the 7-day home blood pressure check
    /// (`HomeBloodPressure.nextCheckDue`; ESH 2021, ACC/AHA). Nil clears it.
    static func scheduleBloodPressureReminder(due: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [bloodPressureReminderIdentifier])
        guard let due, await requestPermission() else { return }
        let calendar = Calendar.current
        guard let fire = measurementFireDate(due: due, calendar: calendar) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to repeat your home blood pressure check"
        content.body = "Two readings morning and evening for 7 days; the average is what counts."
        content.sound = .default
        content.userInfo = ["link": "workoutapp://bp"]
        await add(content, identifier: bloodPressureReminderIdentifier, at: fire, center: center, calendar: calendar)
    }

    /// `measurementMinutes` on the due day, or tomorrow when that has passed.
    static func measurementFireDate(due: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: max(due, now))
        if let fire = fireDate(day: day, minutes: measurementMinutes, calendar: calendar), fire > now { return fire }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        return fireDate(day: tomorrow, minutes: measurementMinutes, calendar: calendar)
    }
}

private extension WidgetSnapshot {
    nonisolated func withUpdated(_ date: Date?) -> WidgetSnapshot {
        var copy = self
        copy.updated = date ?? updated
        return copy
    }
}
