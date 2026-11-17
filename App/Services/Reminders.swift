import ActivityKit
import AppCore
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
    /// The guided stretch session (workoutapp://stretch, from its reminder).
    var showStretch = false
    /// Last night's sleep with tonight's bed-by window (workoutapp://sleep, from the Plan widget).
    var showSleep = false
    /// Settings, presented once at the root so any tab's profile button
    /// (`TabToolbar`) can open it.
    var showSettings = false
    /// The selected bottom tab, so any screen can switch tabs (e.g. Today's
    /// "All measures" opens Health).
    var selectedTab: AppTab = .today
    /// Bumped to bring the running workout back on screen (Live Activity tap).
    var openWorkout = 0
    /// Bumped when doses change outside the app (Live Activity, notification).
    var dosesVersion = 0
    /// Bumped when iOS has just been allowed to send notifications (asked from a
    /// reminder switch in Settings), so every reminder that is on gets scheduled.
    var remindersVersion = 0
    /// A link from a tapped notification, opened once the app is fully on
    /// screen. Presenting a sheet while iOS is still bringing the app to the
    /// front (or launching it) fails or crashes, so it waits for `.active`.
    var pendingLink: URL?

    /// Opens a waiting notification link, a moment after the app becomes active.
    func openPendingLink() {
        guard let url = pendingLink else { return }
        pendingLink = nil
        Logger.diagnostics.notice("opening pending link \(Self.loggable(url), privacy: .public)")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.open(url)
        }
    }

    /// A link for the log without its query or fragment: a sign-in redirect
    /// carries its one-time code there, and a coach link the user's question.
    nonisolated static func loggable(_ url: URL) -> String {
        let base = "\(url.scheme ?? "")://\(url.host() ?? "")\(url.path())"
        return url.query() == nil && url.fragment() == nil ? base : base + "?<redacted>"
    }

    func open(_ url: URL) {
        Logger.diagnostics.notice("router.open \(Self.loggable(url), privacy: .public)")
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
        case "stretch": showStretch = true
        case "sleep": showSleep = true
        case "today": selectedTab = .today
        case "coach":
            // A coach check-in's question ("workoutapp://coach?q=…"), asked in the Coach tab (`CoachInbox`).
            selectedTab = .coach
            CoachInbox.shared.open(url)
        default: break
        }
    }

    /// A sheet can't open while another one is showing, so close any other
    /// screen first and open the check-in once it has gone.
    private func openCheckIn(_ kind: CheckInKind) {
        let otherOpen = showHRVEntry || showMedications || showProgressPhotos || showWeeklyReview || showWeeklyPlan
            || showMeasurements || showBloodPressure || showStretch || showSleep || showSettings || (checkIn != nil && checkIn != kind)
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
        showStretch = false
        showSleep = false
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
        // "Rest's over" while the app is open: no banner or sound; the workout
        // screen turns its timer into "Rest done" with a tap instead (iOS only
        // asks this while the app is in the foreground).
        if notification.request.identifier == WorkoutLiveActivity.restNotificationID {
            completionHandler([])
            return
        }
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
                // Its reminder and any snooze, waiting or already delivered.
                DoseNotifications.clear(doseID)
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
        if let coach = CoachNudges.handle(identifier: identifier, action: action, link: link) {
            if let url = coach.link { pendingLink = url }
            return
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
        UNUserNotificationCenter.current().setNotificationCategories([dose, Self.coachCategory])
    }

    /// Whether notifications are allowed. Never asks: every schedule below uses
    /// this, so nothing that runs at launch or in the background can put up
    /// iOS's permission prompt. The prompt comes only from `requestPermission`,
    /// called when the user turns a reminder on.
    static func notificationsAllowed() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Asks once (only from a reminder switch or a saved dose time, never from
    /// a launch-time schedule); returns whether notifications are allowed.
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
    /// left over from older versions.
    static func clearLegacyHRVReminders() {
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
                                 hrvMissing: Bool = false, logsHRV: Bool = true, weighInNudge: Bool = false,
                                 bedByTonight: String? = nil, morningOn: Bool = true, eveningOn: Bool = true) async -> Date? {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<7).flatMap { ["checkin|m|\($0)", "checkin|e|\($0)"] }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled, await notificationsAllowed() else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var nudgeDay: Date?
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // The coach's morning check-in (`CoachNudges`) replaces this one when it's on.
            let skipMorning = !morningOn || (offset == 0 && morningDone && !hrvMissing)
            if !skipMorning, let fire = fireDate(day: day, minutes: morningMinutes, calendar: calendar), fire > .now {
                let withNudge = weighInNudge && nudgeDay == nil
                if withNudge { nudgeDay = day }
                let content = morningContent(hrvOnly: offset == 0 && morningDone && hrvMissing, weighIn: withNudge, asksForHRV: logsHRV)
                await add(content, identifier: "checkin|m|\(offset)", at: fire, center: center, calendar: calendar)
            }
            let skipEvening = !eveningOn || (offset == 0 && eveningDone)
            if !skipEvening, let fire = fireDate(day: day, minutes: eveningMinutes, calendar: calendar), fire > .now {
                let content = eveningContent(bedBy: offset == 0 ? bedByTonight : nil)
                await add(content, identifier: "checkin|e|\(offset)", at: fire, center: center, calendar: calendar)
            }
        }
        return nudgeDay
    }

    /// "Morning check-in: HRV and how you feel", or only the HRV when the rest is done.
    /// - Parameter asksForHRV: false for people who don't log HRV in the app
    ///   (their watch writes it to Apple Health), so they aren't asked for it.
    static func morningContent(hrvOnly: Bool, weighIn: Bool, asksForHRV: Bool = true) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Morning check-in"
        if hrvOnly {
            content.body = "Add last night's HRV; the rest of the check-in is done."
            content.userInfo = ["link": "workoutapp://hrv"]
        } else {
            // "About a minute", as Up next says ("Morning check-in · 1 min"): the form has HRV, sleep, soreness, pain and mood.
            content.body = asksForHRV ? "Last night's HRV and how you feel. About a minute." : "How you slept and how you feel. About a minute."
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

    /// Evening reflection, in the words of the form itself and its Up next row
    /// ("Evening check-in · 1 min · Caffeine, drinks and how the day went"),
    /// with tonight's bed-by window when known (`BedtimeWindow`).
    static func eveningContent(bedBy: String?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Evening check-in"
        content.body = "Caffeine, drinks and how the day went. About a minute."
        if let bedBy { content.body += " In bed by \(bedBy) tonight." }
        content.userInfo = ["link": "workoutapp://checkin/evening"]
        content.sound = .default
        return content
    }

    // MARK: Stretching

    /// Days ahead the stretch reminder is scheduled. Few, because iOS keeps
    /// only 64 pending notifications per app and doses come first; the app
    /// reschedules on every open.
    static let stretchReminderDays = 3

    /// One reminder a day for the 5-minute stretch (`Stretching`), at the
    /// chosen time unless a planned session starts soon after it or is on at
    /// that time (then an hour after that session, or not at all that day
    /// when that would be after 22:00: `Stretching.reminderMinutes`). Today's
    /// is skipped once you've stretched.
    static func scheduleStretchReminders(enabled: Bool, minutes: Int, doneToday: Bool, slots: [PlannedSlot],
                                         areas: [String]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<7).map { "stretch|\($0)" })
        guard enabled, await notificationsAllowed() else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<stretchReminderDays {
            guard !(offset == 0 && doneToday), let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let session = slots.first { calendar.isDate($0.start, inSameDayAs: day) }
            let sessionStart = session.map { slot -> Int in
                let parts = calendar.dateComponents([.hour, .minute], from: slot.start)
                return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
            guard let at = Stretching.reminderMinutes(preferred: minutes, sessionStart: sessionStart, sessionLength: nil),
                  let fire = fireDate(day: day, minutes: at, calendar: calendar), fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(Stretching.sessionMinutes)-minute stretch"
            // Today's areas are known; later days depend on what you do before them.
            content.body = offset == 0 && !areas.isEmpty
                ? "\(areas.joined(separator: ", ")). The weekly minutes are what build flexibility."
                : "Five stretches, 30-second holds. The weekly minutes are what build flexibility."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://stretch"]
            await add(content, identifier: "stretch|\(offset)", at: fire, center: center, calendar: calendar)
        }
    }

    /// Removes today's stretch reminder (the session was just done).
    static func cancelTodaysStretchReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["stretch|0"])
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
        /// The session's focus and lengths, for the reminder's line (`WorkoutVoice`).
        var focus: WorkoutFocus?
        var minutes: Int?
        var shortMinutes: Int?

        init(start: Date, name: String, ifThen: String? = nil, focus: WorkoutFocus? = nil, minutes: Int? = nil,
             shortMinutes: Int? = nil) {
            self.start = start
            self.name = name
            self.ifThen = ifThen
            self.focus = focus
            self.minutes = minutes
            self.shortMinutes = shortMinutes
        }
    }

    /// Minutes before the planned time (rec. 8: 30-60 minutes before a planned slot).
    static let workoutLeadMinutes = 30
    /// Ignored reminders in a row before they pause: each prompt spends attention
    /// and repeated ones habituate (Klasnja et al., Ann Behav Med 2019).
    static let ignoredBeforePause = WorkoutReminderRules.ignoredBeforePause

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

    /// Workout reminders are quiet after `ignoredBeforePause` went unanswered in a
    /// row (no tap, no session that day). Settings says so; training or
    /// confirming a weekly plan brings them back, and so does opening the app
    /// once the quiet has lasted long enough (`WorkoutReminderCadence`).
    static var workoutRemindersPaused: Bool { WorkoutReminderLog.isPaused }

    /// Clears the pause and the ignored count. Call when the user confirms a weekly plan.
    static func resumeWorkoutReminders() { WorkoutReminderLog.resume() }

    /// One reminder per planned slot over the next week, `workoutLeadMinutes`
    /// before it. Its body is a line written from the day's own data, playful
    /// or plain (`WorkoutBanter`, `WorkoutVoiceWriter`), with the user's
    /// if-then line under the title. None for a day already trained on (a
    /// session started or finished early, or a watch workout): the reminder
    /// would be for something already done.
    /// - Parameters:
    ///   - slots: planned slots (from `WeeklyPlanStore`); none means no reminders.
    ///   - trainedDays: start-of-day dates with a logged, running or watch workout.
    ///     They get no reminder, and a reminder answered that way (trained
    ///     without tapping) doesn't count as ignored.
    ///   - restMode: rest mode is on. Today then never counts as an ignored reminder.
    ///   - voice: the tone and each slot's facts (`WorkoutVoice.context`); nil keeps the plain wording.
    static func scheduleWorkoutReminders(slots: [PlannedSlot], enabled: Bool, trainedDays: Set<Date>, restMode: Bool = false,
                                         voice: WorkoutVoiceContext? = nil, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("workout|") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let trainedKeys = Set(trainedDays.map { dayKey($0, calendar: calendar) })
        if restMode { WorkoutReminderLog.noteTapped(dayKey: dayKey(today, calendar: calendar)) }
        // Normal, the last call, one at a time, or quiet (`WorkoutReminderCadence`).
        let stage = WorkoutReminderLog.updatePause(trainedKeys: trainedKeys, today: today, calendar: calendar, now: now)
        var scheduled: [String: Date] = [:]
        var planned: [WorkoutVoiceWriter.Planned] = []
        // Whatever happens below, the log ends up holding what fired and what is pending now:
        // a reminder removed above (switched off, rest mode, paused, plan changed) never went out.
        defer { WorkoutReminderLog.noteScheduled(scheduled, now: now) }
        let upcoming = slots.filter { $0.start > now }.sorted { $0.start < $1.start }
        if enabled, stage != .quiet, !upcoming.isEmpty, await notificationsAllowed() {
            for slot in upcoming where scheduled.count < stage.maxPending {
                let fire = slot.start.addingTimeInterval(-TimeInterval(workoutLeadMinutes * 60))
                guard fire > now else { continue }
                let key = dayKey(calendar.startOfDay(for: slot.start), calendar: calendar)
                // One a day: a second slot the same day rides on the first. None once the day is trained.
                guard scheduled[key] == nil, !trainedKeys.contains(key) else { continue }
                scheduled[key] = fire
                var facts = voice?.facts[slot.start]
                // The reminder after an unanswered one says, once, that reminders go quiet after it.
                if stage == .lastCall { facts?.lastCall = true }
                planned.append(WorkoutVoiceWriter.Planned(key: key, fire: fire, slot: slot, facts: facts,
                                                          isToday: calendar.isDate(slot.start, inSameDayAs: now)))
            }
        }
        // Each reminder's line. A pending one keeps its line while it is still true, so
        // rescheduling uses none up; with nothing planned, lines that never went out are forgotten.
        let lines = WorkoutVoiceWriter.lines(for: planned, voice: voice, now: now)
        for item in planned {
            let content = WorkoutVoiceWriter.content(for: item, line: lines[item.key])
            await add(content, identifier: workoutIdentifier(forDayKey: item.key), at: item.fire, center: center, calendar: calendar)
        }
        // Later, off the launch path: a fresh line from the on-device model for the next reminder, when that is on.
        WorkoutVoiceWriter.freshen(planned, lines: lines, voice: voice, now: now)
    }

    /// Which workout reminders went out, which were tapped, and whether they're
    /// paused (`WorkoutReminderRules`). In UserDefaults so the notification
    /// delegate can write to it off the main actor.
    enum WorkoutReminderLog {
        /// Day key → when that day's reminder fires (seconds since 1970).
        static let fireTimesKey = "workoutReminderFireTimes"
        /// The list older builds kept (day keys only); read once, then dropped.
        static let scheduledKey = "workoutRemindersScheduled"
        static let tappedKey = "workoutRemindersTapped"
        static let pausedKey = "workoutRemindersPaused"

        static var isPaused: Bool { UserDefaults.standard.bool(forKey: pausedKey) }

        /// Marks a day's reminder as answered: tapped, or excused by rest mode.
        static func noteTapped(dayKey: String) {
            var tapped = UserDefaults.standard.stringArray(forKey: tappedKey) ?? []
            guard !tapped.contains(dayKey) else { return }
            tapped.append(dayKey)
            UserDefaults.standard.set(Array(tapped.suffix(30)), forKey: tappedKey)
        }

        /// The log: day key → fire time. The older list has no times: its past
        /// days count as fired, and its upcoming ones are dropped (they are
        /// pending reminders, which every reschedule replaces).
        static func log() -> [String: Date] {
            let defaults = UserDefaults.standard
            var log: [String: Date] = [:]
            let todayKey = Reminders.dayKey(.now)
            for key in defaults.stringArray(forKey: scheduledKey) ?? [] where key < todayKey {
                log[key] = Date(timeIntervalSince1970: 0)
            }
            for (key, seconds) in defaults.dictionary(forKey: fireTimesKey) as? [String: Double] ?? [:] {
                log[key] = Date(timeIntervalSince1970: seconds)
            }
            return log
        }

        private static func save(_ log: [String: Date]) {
            let defaults = UserDefaults.standard
            defaults.set(log.mapValues(\.timeIntervalSince1970), forKey: fireTimesKey)
            defaults.removeObject(forKey: scheduledKey)
        }

        /// Keeps the reminders that have fired (today's too) and replaces the pending ones with `scheduled`.
        static func noteScheduled(_ scheduled: [String: Date], now: Date) {
            save(WorkoutReminderRules.logAfterReschedule(log(), scheduled: scheduled, now: now))
        }

        /// Where the "going quiet" rules stand (`WorkoutReminderCadence.State`, as JSON).
        static let cadenceKey = "workoutReminderCadence"

        /// Works out the stage from what went out and what was answered
        /// (`WorkoutReminderCadence`): the last call after one unanswered
        /// reminder, quiet after two, back when you train, or one at a time
        /// when the app is opened after the quiet has lasted long enough.
        static func updatePause(trainedKeys: Set<String>, today: Date, calendar: Calendar, now: Date) -> WorkoutReminderCadence.Stage {
            let defaults = UserDefaults.standard
            let saved = defaults.data(forKey: cadenceKey).flatMap { try? JSONDecoder().decode(WorkoutReminderCadence.State.self, from: $0) }
            var state = saved ?? WorkoutReminderCadence.State()
            // Paused by an older build, which kept no date: quiet since today.
            if saved == nil, isPaused { state.quietSince = today; state.quietSpells = 1 }
            let tapped = Set(defaults.stringArray(forKey: tappedKey) ?? [])
            let decision = WorkoutReminderCadence.evaluate(state, log: log(), tapped: tapped, trained: trainedKeys, now: now,
                                                           calendar: calendar) { Reminders.dayKey($0, calendar: calendar) }
            if decision.clearLog {
                defaults.removeObject(forKey: scheduledKey)
                defaults.removeObject(forKey: fireTimesKey)
                defaults.removeObject(forKey: tappedKey)
            }
            if let data = try? JSONEncoder().encode(decision.state) { defaults.set(data, forKey: cadenceKey) }
            defaults.set(decision.stage == .quiet, forKey: pausedKey)
            return decision.stage
        }

        static func resume() {
            UserDefaults.standard.removeObject(forKey: cadenceKey)
            UserDefaults.standard.set(false, forKey: pausedKey)
            UserDefaults.standard.removeObject(forKey: scheduledKey)
            UserDefaults.standard.removeObject(forKey: fireTimesKey)
            UserDefaults.standard.removeObject(forKey: tappedKey)
        }
    }

    // MARK: Medications

    /// Snoozed reminders use their own prefix so rescheduling doesn't remove them.
    static func snoozeIdentifier(for doseID: String) -> String { DoseNotifications.snoozeIdentifier(for: doseID) }

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

    /// The most dose reminders kept pending. iOS keeps only 64 per app (the
    /// soonest 64; the rest are dropped without a word), and the other kinds
    /// need room too: check-ins 14, workouts up to 7, stretch 3
    /// (`stretchReminderDays`), measurements 3 (waist, grip, blood pressure),
    /// coach messages up to 3, the Monday review 2 and the rest timer 1 = 33.
    /// 33 + 28 = 61, which leaves 3 for snoozed doses. App's choice within that limit.
    static let maxPendingDoses = 28

    /// At most this many of the pending dose reminders go to medications taken
    /// less often than daily, so daily doses can't crowd a weekly one out.
    static let maxPendingLessOftenDoses = 12
    /// How far ahead daily and less-than-daily doses are scheduled.
    static let dailyHorizonDays = 14
    static let lessOftenHorizonDays = 84

    /// Reminders for every untaken dose: daily ones over the next 14 days,
    /// less-than-daily ones (a weekly injection, every 3 days) over the next
    /// 12 weeks with their own share of the budget, soonest first. Opening
    /// the app tops the queue back up. One-shot triggers rather than
    /// repeating ones: a dose ticked off early (here or on the Lock Screen)
    /// then never fires, which matters most for a weekly injection, and each
    /// reminder carries the id of its own day's dose.
    /// - Parameter ask: the user has just saved a dose time, so iOS may ask to
    ///   allow notifications. Otherwise (launch, foreground) it never does.
    static func scheduleDoses(ask: Bool = false) async {
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
        let schedules = Dictionary(MedicationStore.medications().map { ($0.id, $0.plan) }, uniquingKeysWith: { first, _ in first })
        var daily: [(dose: Dose, fire: Date)] = []
        var lessOften: [(dose: Dose, fire: Date)] = []
        for offset in 0..<lessOftenHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for dose in MedicationStore.doses(on: day, calendar: calendar) where taken[dose.id] == nil {
                let isLessOften = schedules[dose.medicationID]?.isLessThanDaily ?? false
                guard isLessOften || offset < dailyHorizonDays else { continue }
                guard let fire = fireDate(day: day, minutes: dose.minutes, calendar: calendar), fire > now else { continue }
                if isLessOften {
                    lessOften.append((dose, fire))
                } else {
                    daily.append((dose, fire))
                }
            }
        }
        lessOften.sort { $0.fire < $1.fire }
        daily.sort { $0.fire < $1.fire }
        let chosenLessOften = Array(lessOften.prefix(maxPendingLessOftenDoses))
        let upcoming = chosenLessOften + daily.prefix(maxPendingDoses - chosenLessOften.count)
        guard !upcoming.isEmpty else { return }
        let allowed = ask ? await requestPermission() : await notificationsAllowed()
        guard allowed else { return }
        for (dose, fire) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "Time for \(dose.name)"
            let schedule = schedules[dose.medicationID] ?? .daily
            // "Weekly on Monday" in the reminder itself, so a weekly dose is never mistaken for a daily one.
            let when = schedule.isLessThanDaily ? schedule.summary(calendar: calendar) : ""
            content.body = [dose.dose, when, "Tap Taken once you've had it."].filter { !$0.isEmpty }.joined(separator: " · ")
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

    /// Starts today's doses Live Activity if doses that show now (`DoseCard`:
    /// two hours before their time, medications never before 06:00, creatine
    /// and supplements never before noon) are left and none is showing.
    /// Nothing before 06:00, so opening the app after midnight doesn't leave a
    /// card on the Lock Screen all night. Not when the card is switched off in
    /// Settings, and not again the same day after the user swiped it away,
    /// until a dose that wasn't on it joins (`DoseCard.mayStart`). iOS only
    /// lets the app start one while it's open.
    static func startMedsActivityIfNeeded() async {
        await MedsLiveActivity.refresh() // also ends the card when it's switched off
        guard MedsLiveActivity.isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date.now
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        let state = MedsLiveActivity.state(for: now)
        let remaining = state.remaining(at: now).map(\.id)
        guard !remaining.isEmpty else { return }
        let todays = Activity<MedsActivityAttributes>.activities.filter { calendar.isDateInToday($0.attributes.day) }
        // Only a card that is really showing counts: one iOS ended or the user dismissed doesn't.
        guard !todays.contains(where: { MedsLiveActivity.isLive($0) }) else { return }
        guard DoseCard.mayStart(remaining: remaining, dayKey: Dose.dayKey(day), last: MedsLiveActivity.cardLog) else { return }
        // An "All taken" card the app ended a moment ago goes before the new one shows.
        for activity in todays where activity.activityState == .ended {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let attributes = MedsActivityAttributes(day: day)
        let content = ActivityContent(state: state, staleDate: MedsLiveActivity.staleDate(for: state, day: day, now: now))
        guard (try? Activity.request(attributes: attributes, content: content, pushType: nil)) != nil else { return }
        MedsLiveActivity.noteOffered(remaining, day: day, started: true)
    }

    /// Takes every doses card off the Lock Screen (the card was switched off in Settings).
    static func endMedsActivities() async {
        for activity in Activity<MedsActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        // Not a card the user swiped away: switching the card back on today may show it again.
        MedsLiveActivity.noteEndedByApp(day: .now)
    }

    /// An unchanged snapshot is saved again once the saved one is this old:
    /// the widgets blank strain 3 hours after its timestamp
    /// (`GlanceFreshness.strainMaxAge`), so the timestamp has to keep moving
    /// while the app keeps confirming the number. App's choice.
    static let widgetTimestampAge: TimeInterval = 30 * 60

    /// Saves what the widget shows and asks it to redraw: when anything
    /// changed, on a new day even if nothing did (the widget shows only a
    /// snapshot saved today, so an unchanged one from yesterday read as "--"),
    /// and when the saved one is half an hour old (`widgetTimestampAge`).
    static func updateWidget(_ snapshot: WidgetSnapshot) {
        let saved = WidgetSnapshot.load()
        let sameDay = saved.map { Calendar.current.isDate($0.updated, inSameDayAs: snapshot.updated) } ?? false
        let aged = saved.map { snapshot.updated.timeIntervalSince($0.updated) >= widgetTimestampAge } ?? true
        if !sameDay || aged || saved != snapshot.withUpdated(saved?.updated) {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Weekly review

    /// The repeating reminder older builds set; removed on every reschedule.
    static let weeklyReviewIdentifier = "review|weekly"
    /// Mondays kept pending: two, so a week without opening the app still gets its reminder.
    static let weeklyReviewMondays = 2
    private static let weeklyReviewOpenedKey = "weeklyReviewOpenedAt"
    private static let weeklyReviewSeenOnKey = "weeklyReviewSeenOn"

    private static var weeklyReviewIdentifiers: [String] {
        [weeklyReviewIdentifier] + (0..<weeklyReviewMondays).map { "review|weekly|\($0)" }
    }

    /// Rest mode, read from where `UserSettings` keeps it, for code off the main actor.
    private static var restModeOn: Bool {
        (UserDefaults.standard.object(forKey: "restModeUntil") as? Date ?? .distantPast) > .now
    }

    /// One reminder on each of the next Mondays at `minutes` after midnight,
    /// opening the weekly review. A new week is a "fresh start" landmark (Dai
    /// et al., Manag Sci 2014) and reviewing goals is what makes
    /// self-monitoring work (Michie et al., Health Psychol 2009); a fixed,
    /// user-chosen time does as well as inferred timing (Morrison et al., PLoS
    /// One 2017, cited from memory in docs/research/behaviour-change.md).
    /// One-shot rather than repeating, so it can be left out: none in rest
    /// mode, and none on a Monday whose review was already opened
    /// (`ReminderRules.weeklyReviewFireDates`). iOS is asked for permission
    /// only on the call that first sees the reminder switched on.
    static func scheduleWeeklyReview(enabled: Bool, minutes: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: weeklyReviewIdentifiers)
        let defaults = UserDefaults.standard
        // Off the last time this ran and on now: the user has just switched it on.
        let justTurnedOn = enabled && (defaults.object(forKey: weeklyReviewSeenOnKey) as? Bool) == false
        defaults.set(enabled, forKey: weeklyReviewSeenOnKey)
        guard enabled, !restModeOn else { return }
        let allowed = justTurnedOn ? await requestPermission() : await notificationsAllowed()
        guard allowed else { return }
        let calendar = Calendar.current
        let opened = defaults.object(forKey: weeklyReviewOpenedKey) as? Date
        let fires = ReminderRules.weeklyReviewFireDates(now: .now, minutes: minutes, lastOpened: opened,
                                                        count: weeklyReviewMondays, calendar: calendar)
        for (index, fire) in fires.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Weekly review"
            content.body = "Last week in plain numbers, then three changes for this week. Two minutes."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://review"]
            await add(content, identifier: "review|weekly|\(index)", at: fire, center: center, calendar: calendar)
        }
    }

    /// The same, with the switch and time read from where `UserSettings` keeps
    /// them (default 8:00), for callers that don't hold the settings.
    static func rescheduleWeeklyReview() async {
        let defaults = UserDefaults.standard
        await scheduleWeeklyReview(enabled: defaults.bool(forKey: "weeklyReviewOn"),
                                   minutes: defaults.object(forKey: "weeklyReviewMinutes") as? Int ?? 8 * 60)
    }

    /// The weekly review was opened: today's reminder for it, pending or
    /// already delivered, goes.
    static func noteWeeklyReviewOpened() async {
        UserDefaults.standard.set(Date.now, forKey: weeklyReviewOpenedKey)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: weeklyReviewIdentifiers)
        await rescheduleWeeklyReview()
    }

    // MARK: - Measurements

    static let waistReminderIdentifier = "measure|waist"
    static let gripReminderIdentifier = "measure|grip"
    static let bloodPressureReminderIdentifier = "measure|bp"
    /// Measurement reminders arrive mid-morning (app choice: a tape or a cuff
    /// reading is best taken rested, before food; 9:00 leaves the morning
    /// check-in alone).
    static let measurementMinutes = 9 * 60

    /// Settings › Reminders › "Measurement reminders" (waist, grip, blood
    /// pressure). On unless switched off.
    static let measurementRemindersKey = "measurementRemindersOn"
    static var measurementRemindersOn: Bool {
        UserDefaults.standard.object(forKey: measurementRemindersKey) as? Bool ?? true
    }

    private static func lastDueKey(_ identifier: String) -> String { "lastDue|" + identifier }

    /// Remembers the due date last asked for (nil clears it), so switching
    /// the reminders back on can restore them without the screens that know it.
    private static func noteDue(_ due: Date?, _ identifier: String) {
        if let due {
            UserDefaults.standard.set(due, forKey: lastDueKey(identifier))
        } else {
            UserDefaults.standard.removeObject(forKey: lastDueKey(identifier))
        }
    }

    /// "Measurement reminders" was switched: off removes the pending ones,
    /// on schedules them again from the due dates last known.
    static func measurementRemindersChanged() async {
        let defaults = UserDefaults.standard
        if !measurementRemindersOn {
            // A reminder that was only waiting never went out: forget it, so switching
            // back on reminds when due and not a whole interval later (`OverdueReminder`).
            for identifier in [waistReminderIdentifier, gripReminderIdentifier, bloodPressureReminderIdentifier] {
                if let fire = defaults.object(forKey: lastReminderKey(identifier)) as? Date, fire > .now {
                    defaults.removeObject(forKey: lastReminderKey(identifier))
                }
            }
        }
        await scheduleMeasurementReminders(waistDue: defaults.object(forKey: lastDueKey(waistReminderIdentifier)) as? Date,
                                           gripDue: defaults.object(forKey: lastDueKey(gripReminderIdentifier)) as? Date)
        await scheduleBloodPressureReminder(due: defaults.object(forKey: lastDueKey(bloodPressureReminderIdentifier)) as? Date)
    }

    /// The monthly waist reminder and the 6-monthly grip reminder
    /// (`WaistToHeightRatio.nextDue`, `GripStrength.nextDue`; Ashwell 2012,
    /// EWGSOP2 via docs/research/health-metrics.md). A nil due date clears that
    /// reminder. One reminder when due (the next morning if that has passed),
    /// then, while still not done, one a full interval later (`OverdueReminder`),
    /// not every morning the app is opened. None while "Measurement reminders"
    /// is off in Settings.
    static func scheduleMeasurementReminders(waistDue: Date?, gripDue: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [waistReminderIdentifier, gripReminderIdentifier])
        noteDue(waistDue, waistReminderIdentifier)
        noteDue(gripDue, gripReminderIdentifier)
        guard measurementRemindersOn, waistDue != nil || gripDue != nil, await notificationsAllowed() else { return }
        let calendar = Calendar.current
        if let waistDue, let fire = overdueFireDate(identifier: waistReminderIdentifier, due: waistDue,
                                                    intervalDays: WaistToHeightRatio.intervalDays, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = "Monthly waist check"
            content.body = "Tape at the navel, relaxed, after breathing out. Under half your height is the target."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://measurements"]
            await add(content, identifier: waistReminderIdentifier, at: fire, center: center, calendar: calendar)
            noteReminder(waistReminderIdentifier, firesAt: fire)
        }
        if let gripDue, let fire = overdueFireDate(identifier: gripReminderIdentifier, due: gripDue,
                                                   intervalDays: GripStrength.intervalDays, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = "Grip strength, twice a year"
            content.body = "Dominant hand, best of three squeezes on a dynamometer. Two minutes."
            content.sound = .default
            content.userInfo = ["link": "workoutapp://measurements"]
            await add(content, identifier: gripReminderIdentifier, at: fire, center: center, calendar: calendar)
            noteReminder(gripReminderIdentifier, firesAt: fire)
        }
    }

    /// The 3-6-monthly reminder to repeat the 7-day home blood pressure check
    /// (`HomeBloodPressure.nextCheckDue`; ESH 2021, ACC/AHA). Nil clears it.
    /// Once overdue it repeats after 3 months (the shorter cadence), not daily.
    static func scheduleBloodPressureReminder(due: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [bloodPressureReminderIdentifier])
        noteDue(due, bloodPressureReminderIdentifier)
        guard measurementRemindersOn, let due, await notificationsAllowed() else { return }
        let calendar = Calendar.current
        guard let fire = overdueFireDate(identifier: bloodPressureReminderIdentifier, due: due,
                                         intervalDays: bloodPressureRepeatDays, calendar: calendar) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to repeat your home blood pressure check"
        content.body = "Two readings morning and evening for 7 days; the average is what counts."
        content.sound = .default
        content.userInfo = ["link": "workoutapp://bp"]
        await add(content, identifier: bloodPressureReminderIdentifier, at: fire, center: center, calendar: calendar)
        noteReminder(bloodPressureReminderIdentifier, firesAt: fire)
    }

    /// An unanswered blood pressure reminder comes back after about 3 months
    /// (`HomeBloodPressure.repeatMonths` for an above-normal average).
    static let bloodPressureRepeatDays = 91

    /// When the reminder for a measurement due on `due` should fire, given the
    /// last one set for it (`OverdueReminder`), at `measurementMinutes`.
    static func overdueFireDate(identifier: String, due: Date, intervalDays: Int, now: Date = .now,
                                calendar: Calendar = .current) -> Date? {
        let lastFire = UserDefaults.standard.object(forKey: lastReminderKey(identifier)) as? Date
        let day = OverdueReminder.nextDay(due: due, lastNag: lastFire, intervalDays: intervalDays, now: now, calendar: calendar)
        return measurementFireDate(due: day, now: now, calendar: calendar)
    }

    private static func lastReminderKey(_ identifier: String) -> String { "lastReminder|" + identifier }

    private static func noteReminder(_ identifier: String, firesAt fire: Date) {
        UserDefaults.standard.set(fire, forKey: lastReminderKey(identifier))
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
        copy.plan?.updated = copy.updated // the plan carries the snapshot's time
        return copy
    }
}

nonisolated extension Reminders {
    /// Coach check-ins (`CoachNudges`): "Ask the coach" opens the Coach tab with
    /// the message's question; "Not now" just dismisses.
    static var coachCategory: UNNotificationCategory {
        let ask = UNNotificationAction(identifier: CoachNotificationIDs.askAction, title: "Ask the coach", options: [.foreground],
                                       icon: UNNotificationActionIcon(systemImageName: "sparkles"))
        let notNow = UNNotificationAction(identifier: CoachNotificationIDs.notNowAction, title: "Not now", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "moon.zzz"))
        return UNNotificationCategory(identifier: CoachNotificationIDs.category, actions: [ask, notNow], intentIdentifiers: [])
    }
}
