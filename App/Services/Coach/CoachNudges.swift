import Foundation
import BackgroundTasks
import FoundationModels
import Observation
import SwiftData
import UserNotifications
import os
import AppCore

/// Identifiers shared with the notification delegate and `Reminders.registerCategories`,
/// outside the main actor so nonisolated code can read them.
nonisolated enum CoachNotificationIDs {
    /// Every coach notification's identifier starts with this: "coach|morning|2027-01-11".
    static let prefix = "coach|"
    static let category = "coach"
    static let askAction = "coach.ask"
    static let notNowAction = "coach.notNow"
    /// BGAppRefreshTask identifier (Info.plist BGTaskSchedulerPermittedIdentifiers).
    static let refreshTask = "com.lontraindustries.workoutapp.coach-refresh"

    static func identifier(_ kind: CoachCheckIns.Kind, day: Date, calendar: Calendar = .current) -> String {
        prefix + kind.rawValue + "|" + Reminders.dayKey(day, calendar: calendar)
    }
}

/// The coach messages you first: a morning briefing, a note after a workout
/// and an evening wind-down. `CoachCheckIns` (AppCore) decides what to say
/// and whether to say anything; this schedules local notifications, keeps
/// them in the Coach tab (`CoachInbox`) and, when Apple Intelligence is on,
/// lets the on-device model reword the body into one friendlier line,
/// checked by `CoachCheckIns.acceptRephrase` (otherwise the app's own words).
/// Nothing leaves the iPhone.
///
/// Timing: the morning one 30 minutes after your usual wake time (from the
/// bed-by window, `BedtimeWindow`), the evening one an hour before tonight's
/// bed-by window, the workout one 20 minutes after you finish; quiet hours
/// move or hold them (`CoachCheckIns.outsideQuietHours`). The morning one is
/// scheduled the evening before and rewritten whenever the app refreshes
/// (Health background delivery, the 5-minute loop, a background app refresh),
/// so it carries last night's recovery when the phone had it in time.
/// At most 3 notifications are pending at once, one per kind.
@Observable
final class CoachNudges {
    static let shared = CoachNudges()

    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "coach-nudges")
    private let defaults = UserDefaults.standard

    // MARK: Settings

    var morningOn: Bool { didSet { defaults.set(morningOn, forKey: "coachNudgeMorning"); settingsChanged(.morning, on: morningOn) } }
    var postWorkoutOn: Bool { didSet { defaults.set(postWorkoutOn, forKey: "coachNudgePostWorkout"); settingsChanged(.postWorkout, on: postWorkoutOn) } }
    var eveningOn: Bool { didSet { defaults.set(eveningOn, forKey: "coachNudgeEvening"); settingsChanged(.evening, on: eveningOn) } }
    var quietHoursOn: Bool { didSet { defaults.set(quietHoursOn, forKey: "coachNudgeQuietOn"); rescheduleSoon() } }
    var quietStartMinutes: Int { didSet { defaults.set(quietStartMinutes, forKey: "coachNudgeQuietStart"); rescheduleSoon() } }
    var quietEndMinutes: Int { didSet { defaults.set(quietEndMinutes, forKey: "coachNudgeQuietEnd"); rescheduleSoon() } }
    /// Let Apple's on-device model reword the message (falls back to the app's words).
    var friendlyWording: Bool { didSet { defaults.set(friendlyWording, forKey: "coachNudgeFriendly") } }

    var anyOn: Bool { morningOn || postWorkoutOn || eveningOn }

    var quietHours: CoachCheckIns.QuietHours? {
        quietHoursOn ? CoachCheckIns.QuietHours(startMinutes: quietStartMinutes, endMinutes: quietEndMinutes) : nil
    }

    func isOn(_ kind: CoachCheckIns.Kind) -> Bool {
        switch kind {
        case .morning: morningOn
        case .postWorkout: postWorkoutOn
        case .evening: eveningOn
        }
    }

    // MARK: App models (attached once from RootView)

    @ObservationIgnored private var metrics: DailyMetricsModel?
    @ObservationIgnored private var plans: WeeklyPlanStore?
    @ObservationIgnored private var checkIns: CheckInStore?
    @ObservationIgnored private var settings: UserSettings?
    @ObservationIgnored private var gym: GymStore?
    @ObservationIgnored private var muscles: MuscleModel?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var appRefresher: AppRefresher?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var pendingReschedule: Task<Void, Never>?

    private let inbox = CoachInbox.shared

    init() {
        morningOn = defaults.bool(forKey: "coachNudgeMorning")
        postWorkoutOn = defaults.bool(forKey: "coachNudgePostWorkout")
        eveningOn = defaults.bool(forKey: "coachNudgeEvening")
        quietHoursOn = defaults.object(forKey: "coachNudgeQuietOn") as? Bool ?? true
        quietStartMinutes = defaults.object(forKey: "coachNudgeQuietStart") as? Int ?? CoachCheckIns.defaultQuietHours.startMinutes
        quietEndMinutes = defaults.object(forKey: "coachNudgeQuietEnd") as? Int ?? CoachCheckIns.defaultQuietHours.endMinutes
        friendlyWording = defaults.object(forKey: "coachNudgeFriendly") as? Bool ?? true
    }

    /// Gives the service the app's models. Call once from `RootView.task`.
    func attach(metrics: DailyMetricsModel, plans: WeeklyPlanStore, checkIns: CheckInStore, settings: UserSettings,
                gym: GymStore, muscles: MuscleModel, context: ModelContext, refresher: AppRefresher) {
        self.metrics = metrics
        self.plans = plans
        self.checkIns = checkIns
        self.settings = settings
        self.gym = gym
        self.muscles = muscles
        self.context = context
        self.appRefresher = refresher
    }

    // MARK: - Morning and evening

    /// Rebuilds the next morning and tonight's evening message from the latest
    /// numbers. Call at the end of every refresh; cheap when nothing changed
    /// (the model is only asked when the message itself changed).
    func refresh(now: Date = .now) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        if morningOn { await scheduleMorning(now: now) } else { await cancelPending(.morning) }
        if eveningOn { await scheduleEvening(now: now) } else { await cancelPending(.evening) }
        if morningOn || eveningOn { scheduleBackgroundRefresh(now: now) }
    }

    private func scheduleMorning(now: Date) async {
        guard let metrics else { return }
        let calendar = Calendar.current
        // Today's message while it is still to come (the window's wake is already tomorrow's
        // from four hours before today's), so an early-morning refresh rewrites it with this
        // morning's numbers instead of replacing it with tomorrow's (`nextMorningFire`).
        let scheduled = inbox.pending(.morning, now: now).map(\.deliverAt).first { calendar.isDate($0, inSameDayAs: now) }
        guard let adjusted = CoachCheckIns.nextMorningFire(wake: metrics.bedtimeWindow?.wake, scheduledToday: scheduled,
                                                          quiet: quietHours, now: now, calendar: calendar) else {
            return
        }
        let facts = morningFacts(for: adjusted, now: now)
        let message = CoachCheckIns.morning(facts)
        noteLowMoodRaise(message, on: adjusted, calendar: calendar)
        await deliver(message, kind: .morning, at: adjusted, now: now)
    }

    private func scheduleEvening(now: Date) async {
        guard let metrics else { return }
        let calendar = Calendar.current
        let window = metrics.bedtimeWindow
        // Tonight's window only: the evening is scheduled during the day, when the app refreshes.
        let tonight = window.flatMap { $0.start > now && $0.start.timeIntervalSince(now) < 86_400 ? $0 : nil }
        guard let planned = CoachCheckIns.eveningFire(bedByStart: tonight?.start, fallbackDay: calendar.startOfDay(for: now), calendar: calendar),
              planned > now,
              let adjusted = CoachCheckIns.outsideQuietHours(planned, kind: .evening, quiet: quietHours, calendar: calendar),
              adjusted > now else {
            return
        }
        let facts = eveningFacts(window: tonight, now: now)
        await deliver(CoachCheckIns.evening(facts), kind: .evening, at: adjusted, now: now)
    }

    // MARK: - After a workout

    /// Call when a gym session is saved as finished (`FinishWorkoutSheet`).
    /// The note goes out `postWorkoutDelayMinutes` later, and shows in the
    /// Coach tab from then.
    func workoutFinished(_ session: WorkoutSession, now: Date = .now) {
        guard postWorkoutOn, !session.isActive else { return }
        let facts = postWorkoutFacts(session, now: now)
        Task {
            let calendar = Calendar.current
            let planned = now.addingTimeInterval(TimeInterval(CoachCheckIns.postWorkoutDelayMinutes * 60))
            // Inside quiet hours: the Coach tab only, straight away.
            let fire = CoachCheckIns.outsideQuietHours(planned, kind: .postWorkout, quiet: quietHours, calendar: calendar)
            await deliver(CoachCheckIns.postWorkout(facts), kind: .postWorkout, at: fire ?? now, now: now)
        }
    }

    // MARK: - Delivery

    /// Schedules `message` (or clears what was pending when there is none):
    /// a notification when `CoachCheckIns.delivery` says so, always the inbox.
    private func deliver(_ message: CoachCheckIns.Message?, kind: CoachCheckIns.Kind, at fire: Date, now: Date) async {
        guard let message else {
            await cancelPending(kind)
            return
        }
        let delivery = CoachCheckIns.delivery(for: message, at: fire, history: inbox.history, now: now)
        if delivery == .skip {
            // Already said today, or nothing new: a stale pending one goes too.
            if inbox.pending(kind, now: now).contains(where: { $0.key != message.key }) { await cancelPending(kind) }
            return
        }
        let id = CoachNotificationIDs.identifier(kind, day: fire)
        let notify = delivery == .notify
        // Unchanged since it was scheduled: leave it (and don't ask the model again).
        if let existing = inbox.entry(id: id), existing.deliverAt > now, existing.key == message.key,
           existing.deliverAt == fire, existing.notified == notify {
            return
        }
        var body = message.body
        var reworded = false
        // A low-mood sentence keeps the app's own careful words (`CoachCheckIns.mayReword`).
        if friendlyWording, CoachCheckIns.mayReword(message), let line = await CoachNudgeWriter.reword(message.body) {
            body = line
            reworded = true
        }
        let entry = CoachInbox.Entry(id: id, kind: kind, title: message.title, body: body, link: message.link,
                                     question: message.question, deliverAt: fire, notified: notify, opened: false,
                                     key: message.key, reworded: reworded)
        await Self.removePendingNotifications(kind)
        inbox.replacePending(with: entry, now: now)
        guard notify, await Self.notificationsAllowed() else { return }
        await Self.add(entry, priority: message.priority, now: now)
    }

    /// Builds and adds the request off the main actor, from Sendable values
    /// only, the way `Reminders` does.
    nonisolated private static func add(_ entry: CoachInbox.Entry, priority: CoachCheckIns.Priority, now: Date) async {
        let request = UNNotificationRequest(identifier: entry.id, content: content(for: entry, priority: priority),
                                            trigger: trigger(for: entry.deliverAt, now: now))
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Logger(subsystem: "com.lontraindustries.workoutapp", category: "coach-nudges")
                .error("Couldn't schedule \(entry.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func content(for entry: CoachInbox.Entry, priority: CoachCheckIns.Priority) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = entry.title
        content.body = entry.body
        content.sound = priority == .low ? nil : UNNotificationSound.default
        content.categoryIdentifier = CoachNotificationIDs.category
        content.threadIdentifier = CoachNotificationIDs.category
        content.userInfo = ["link": entry.link]
        // A routine line arrives quietly in Notification Centre; one that changes the day lights the screen.
        content.interruptionLevel = priority == .low ? .passive : .active
        content.relevanceScore = priority == .high ? 1 : (priority == .normal ? 0.6 : 0.3)
        return content
    }

    nonisolated private static func trigger(for fire: Date, now: Date) -> UNNotificationTrigger {
        // Within the hour: a time interval (the workout note); later: a calendar date, right across DST.
        let seconds = fire.timeIntervalSince(now)
        if seconds < 3600 {
            return UNTimeIntervalNotificationTrigger(timeInterval: max(60, seconds), repeats: false)
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private func cancelPending(_ kind: CoachCheckIns.Kind) async {
        await Self.removePendingNotifications(kind)
        inbox.removePending(kind)
    }

    nonisolated private static func removePendingNotifications(_ kind: CoachCheckIns.Kind) async {
        let center = UNUserNotificationCenter.current()
        let prefix = CoachNotificationIDs.prefix + kind.rawValue + "|"
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    /// Never asks: the Settings toggle asks, with context, the first time (`requestPermission`).
    nonisolated private static func notificationsAllowed() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Whether iOS has been asked yet (the Settings section explains before asking).
    nonisolated static func permissionNotYetAsked() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    /// Asks iOS (once; later calls just report) and reschedules.
    @discardableResult
    func requestPermission() async -> Bool {
        let allowed = await Reminders.requestPermission()
        if allowed { rescheduleSoon() }
        return allowed
    }

    private func settingsChanged(_ kind: CoachCheckIns.Kind, on: Bool) {
        if on {
            rescheduleSoon()
        } else {
            Task { await cancelPending(kind) }
        }
    }

    /// Reschedules once the settings have settled (a time picker sends many changes).
    private func rescheduleSoon() {
        pendingReschedule?.cancel()
        pendingReschedule = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: - Taps and buttons

    /// What a coach notification's tap or button should do; nil for any other notification.
    struct Response {
        /// The screen to open; nil for "Not now".
        var link: URL?
    }

    /// Marks the message opened (a tap or either button counts: the person
    /// saw it) and says where to go. `link` is the notification's own link,
    /// used when the inbox no longer has the message.
    static func handle(identifier: String, action: String, link: String?) -> Response? {
        guard identifier.hasPrefix(CoachNotificationIDs.prefix) else { return nil }
        let inbox = CoachInbox.shared
        inbox.markOpened(id: identifier)
        let entry = inbox.entry(id: identifier)
        switch action {
        case CoachNotificationIDs.notNowAction:
            return Response(link: nil)
        case CoachNotificationIDs.askAction:
            return Response(link: URL(string: CoachCheckIns.coachLink(question: entry?.question)))
        default:
            let target = entry?.link ?? link ?? CoachCheckIns.coachLink(question: nil)
            return Response(link: URL(string: target))
        }
    }

    // MARK: - Background refresh

    /// For `.backgroundTask(.appRefresh(CoachNotificationIDs.refreshTask))`:
    /// refreshes the numbers (which ends in `refresh()`), then books the next run.
    static func backgroundRefresh() async {
        let nudges = shared
        if let refresher = nudges.appRefresher {
            await refresher.refresh()
        }
        await nudges.refresh()
        // Takes yesterday's doses card off the Lock Screen and lets noon's supplements join today's.
        await MedsLiveActivity.refresh()
    }

    /// Asks iOS for a background refresh about 45 minutes before the next
    /// morning message, so it can carry last night's recovery. iOS decides
    /// whether and when it runs; the evening-before version stands otherwise.
    private func scheduleBackgroundRefresh(now: Date) {
        guard let morning = inbox.pending(.morning, now: now).first?.deliverAt else { return }
        let request = BGAppRefreshTaskRequest(identifier: CoachNotificationIDs.refreshTask)
        request.earliestBeginDate = max(now.addingTimeInterval(15 * 60), morning.addingTimeInterval(-45 * 60))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator, Background App Refresh off, or the Info.plist entry missing: the message still goes out.
            Self.log.notice("Background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Facts

extension CoachNudges {
    /// The morning facts for the message due at `fire`: today's numbers when
    /// it is due today, otherwise only what is known ahead (tomorrow's session,
    /// sleep debt, the caffeine cut-off).
    private func morningFacts(for fire: Date, now: Date) -> CoachCheckIns.MorningFacts {
        var f = CoachCheckIns.MorningFacts()
        guard let metrics, let settings else { return f }
        let calendar = Calendar.current
        let isToday = calendar.isDate(fire, inSameDayAs: now)
        f.restMode = settings.isRestMode
        // Today's message knows the 7-day HRV trend even before last night's recovery is
        // in (yesterday's then), so nothing on it reads as a day for more than easy.
        if isToday { f.hrvBelowNormal = metrics.trainEasyToday }
        if isToday, let recovery = metrics.recovery, !metrics.recoveryIsFromYesterday {
            f.recovery = recovery.score
            f.recoveryCalibrated = recovery.isCalibrated
            f.recoveryReason = Self.reason(recovery)
            if let sleep = metrics.sleep {
                f.sleepHours = sleep.asleep / 3600
                f.sleepNeedHours = sleep.need / 3600
            }
        }
        if isToday, let guidance = metrics.dayGuidance {
            f.restDay = guidance.isRestDay
        }
        f.session = session(on: fire, now: now)
        // The morning message is the one daily prompt: it asks for the check-in until it's
        // saved (a message written ahead for tomorrow always does), and mentions a due weigh-in.
        f.checkInDone = isToday && checkIns?.morning() != nil
        f.weighInDue = WeighInNudge.isDue(goals: metrics.goals, lastWeighIn: metrics.lastWeighIn, now: fire)
        f.sleepDebtHours = metrics.sleepDebt?.hours
        // The insomnia path: short nights are the plan, so no debt or short-night tip (`SleepWindow`).
        f.sleepWindow = metrics.sleepWindowOn
        // The latest bed-by window's clock times stand in for tonight's: worked out
        // before the day starts, it is last night's or the coming night's, and the
        // wake time and need it comes from change little from one night to the next.
        if let window = metrics.bedtimeWindow {
            f.bedByText = window.windowText
        }
        let bedtime = CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes, calendar: calendar)
        let cutoff = CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: CaffeineTiming.referenceDoseMg)
        f.caffeineCutoffText = CaffeineTiming.clockText(cutoff, calendar: calendar)
        addLowMood(to: &f, fire: fire, calendar: calendar)
        return f
    }

    /// The low-mood rule's facts for the message due at `fire` (`LowMoodRule`, LowMood.swift).
    /// A message written the evening before counts the week up to its own morning, whose
    /// answer isn't in yet (so it errs towards silence), and makes no walk offer: that waits
    /// for the morning's recovery (`CoachCheckIns.lowMoodMorning`). Today's illness answer
    /// holds it back either way.
    private func addLowMood(to f: inout CoachCheckIns.MorningFacts, fire: Date, calendar: Calendar) {
        guard let checkIns else { return }
        f.lowMood = Self.lowMoodFinding(checkIns: checkIns, now: fire, calendar: calendar)
        f.illnessFlagged = checkIns.morning()?.isSick == true
        f.restForRecovery = metrics?.dayGuidance?.kind == .recovery
        guard let finding = f.lowMood, finding.fortnightApplies else { return }
        let last = defaults.object(forKey: Self.lowMoodRaisedKey) as? Date
        f.lowMoodRaiseDue = LowMoodRule.raiseDue(lastRaised: last, on: fire, calendar: calendar)
    }

    /// Keeps the day of the "worth raising" sentence: saved for the message's day only
    /// when the message says it, so the same day's rebuilds keep it and then it waits a
    /// week (`LowMoodRule.raiseEveryDays`). A rebuild of that day's message without it
    /// gives the week back.
    private func noteLowMoodRaise(_ message: CoachCheckIns.Message?, on fire: Date, calendar: Calendar) {
        let last = defaults.object(forKey: Self.lowMoodRaisedKey) as? Date
        let sameDay = last.map { calendar.isDate($0, inSameDayAs: fire) } ?? false
        if CoachCheckIns.raisesLowMood(message) {
            if !sameDay { defaults.set(fire, forKey: Self.lowMoodRaisedKey) }
        } else if sameDay {
            defaults.removeObject(forKey: Self.lowMoodRaisedKey)
        }
    }

    private static let lowMoodRaisedKey = "coachLowMoodRaisedOn"

    /// Three or more low mornings in the last week, from the check-ins' mood
    /// and, on days without one, Apple Health's State of Mind (`LowMoodRule.days`).
    /// Also read by `WorkoutVoice`, so the reminders turn plain on the same days.
    static func lowMoodFinding(checkIns: CheckInStore, now: Date, calendar: Calendar = .current) -> LowMoodRule.Finding? {
        let start = calendar.date(byAdding: .day, value: -LowMoodRule.fortnightDays, to: calendar.startOfDay(for: now)) ?? now
        let days = LowMoodRule.days(mornings: checkIns.morningMoods(since: start), health: checkIns.moods, calendar: calendar)
        return LowMoodRule.finding(days: days, on: now, calendar: calendar)
    }

    private func eveningFacts(window: BedtimeWindow.Result?, now: Date) -> CoachCheckIns.EveningFacts {
        var f = CoachCheckIns.EveningFacts()
        guard let settings, let checkIns, let metrics else { return f }
        let calendar = Calendar.current
        f.restMode = settings.isRestMode
        if let window {
            // The insomnia path: "Bed from 23:45, when sleepy", not "In bed by" (`SleepWindow`).
            f.sleepWindow = window.isSleepWindow
            f.bedByText = window.isSleepWindow ? window.start.formatted(date: .omitted, time: .shortened) : window.windowText
            f.bedByReason = window.reason
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            f.tomorrowSession = session(on: tomorrow, now: now)
        }
        let evening = checkIns.evening(on: now)
        // The form saved, not just a drink logged (`EveningCheckIn.isDone`).
        f.checkInDone = evening?.isDone ?? false
        f.drinksToday = evening?.drinks
        if let evening, let mg = evening.caffeineMg, mg > 0, let last = evening.lastCaffeineMinutes {
            let bedtime: Int
            if let window {
                let parts = calendar.dateComponents([.hour, .minute], from: window.start)
                bedtime = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            } else {
                bedtime = CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes, calendar: calendar)
            }
            f.lateCaffeine = CaffeineTiming.isTooLate(minutes: last, mg: mg, bedtimeMinutes: bedtime)
        }
        return f
    }

    /// The fixed-day week's session on `day` (`AdaptiveWeek`, with moves and
    /// short versions); nil on a day without one or in a flexible week.
    private func session(on day: Date, now: Date) -> CoachCheckIns.Session? {
        guard let plans, let context else { return nil }
        let sessions = recentSessions(context: context, now: now)
        let extra = metrics?.recentLiftingDays ?? []
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) {
            return plans.adaptiveWeek(sessions: sessions, extra: extra, checkIns: checkIns, muscles: muscles, now: now)?
                .today.map(CoachCheckIns.Session.init(slot:))
        }
        // A later day: the week as it stands now, else that day's own week (a new week starting).
        if let slot = plans.adaptiveWeek(sessions: sessions, extra: extra, checkIns: checkIns, muscles: muscles, now: now)?
            .slot(on: day, calendar: calendar) {
            return CoachCheckIns.Session(slot: slot)
        }
        return plans.adaptiveWeek(sessions: sessions, extra: extra, checkIns: checkIns, muscles: muscles, now: day)?
            .today.map(CoachCheckIns.Session.init(slot:))
    }

    private func recentSessions(context: ModelContext, now: Date) -> [WorkoutSession] {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.startedAt >= since },
                                                         sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The input that moved the score most, in words: down for a low or
    /// normal score, up for a high one; short enough for a notification.
    private static func reason(_ recovery: RecoveryCalculator.Result) -> String? {
        let high = recovery.score >= RecoveryCalculator.highBand.lowerBound
        let effect: RecoveryContributor.Effect = high ? .raises : .lowers
        guard let top = recovery.contributors.filter({ $0.weight > 0 && $0.effect == effect }).max(by: { $0.weight < $1.weight }) else {
            return nil
        }
        let name = top.name.lowercased()
        let withDetail = name + ": " + top.detail
        return withDetail.count <= 60 ? withDetail : name
    }

    private func postWorkoutFacts(_ session: WorkoutSession, now: Date) -> CoachCheckIns.PostWorkoutFacts {
        let unit = gym?.liftingUnit ?? .kilograms
        var f = CoachCheckIns.PostWorkoutFacts(name: session.name, minutes: Int((session.duration / 60).rounded()),
                                               workingSets: session.effortSets.count)
        if session.totalVolumeKg > 0 {
            let volume = unit.display(session.totalVolumeKg).formatted(.number.precision(.fractionLength(0)))
            f.volumeText = "\(volume) \(unit.rawValue)"
        }
        let all = allFinishedSessions(session)
        // New bests: the same records as the summary (`LiveSetCoach.records`).
        f.recordExercises = session.orderedExercises.filter { exercise in
            !LiveSetCoach.records(for: exercise, sessionStart: session.startedAt, sessions: all, unit: unit).isEmpty
        }.map(\.name)
        f.progressions = progressions(session, all: all, unit: unit)
        if let metrics {
            f.bodyMassKg = metrics.bodyMassKg
            f.proteinSoFarGrams = metrics.nutritionToday?.proteinGrams
            f.proteinTargetGrams = metrics.proteinTarget
            if let window = metrics.bedtimeWindow, window.isSleepWindow {
                // Not "a full night's sleep" under the insomnia path's window (`SleepWindow`).
                f.sleepWindowText = "\(window.start.formatted(date: .omitted, time: .shortened)) to \(window.wake.formatted(date: .omitted, time: .shortened))"
            } else if let window = metrics.bedtimeWindow, window.start > now {
                f.bedByText = window.windowText
            }
        }
        if let settings {
            if f.bodyMassKg == nil, settings.weightKg > 0 { f.bodyMassKg = settings.weightKg }
            f.goals = settings.goalsSet ? settings.goals : nil
        }
        if let plans {
            let extra = metrics?.recentLiftingDays ?? []
            // After a missed planned session or 7+ days off, one sentence says it's the first back (`FirstSessionBack`).
            let earlier = WeeklyPlanStore.trainingDays(sessions: all.filter { $0.startedAt < session.startedAt }, extra: extra)
            f.firstSessionBack = FirstSessionBack.applies(sessionDay: session.startedAt, earlierTrainingDays: earlier, plans: plans.plans)
            if let next = plans.adaptiveWeek(sessions: all, extra: extra, checkIns: checkIns, muscles: muscles, now: now)?.next {
                f.nextSession = CoachCheckIns.Session(slot: next)
                f.nextDayText = Self.dayText(next.date, now: now)
            } else if let next = plans.nextSession(sessions: all, extra: extra, muscles: muscles, now: now) {
                f.nextSession = CoachCheckIns.Session(name: next.day.focus.shortTitle, minutes: next.day.minutes,
                                                      shortMinutes: next.day.shortVersionMinutes)
            }
        }
        return f
    }

    /// Lifts that earned a step up since last time (`WorkoutSummary.change`), as "Squat +2.5 kg".
    private func progressions(_ session: WorkoutSession, all: [WorkoutSession], unit: WeightUnit) -> [String] {
        let today = session.summaryInput
        let earlier = all.filter { $0.startedAt < session.startedAt }.map(\.summaryInput)
        var lines: [String] = []
        for exercise in today.exercises {
            guard let last = WorkoutSummary.previous(exerciseID: exercise.exerciseID, before: today.start, in: earlier),
                  let change = WorkoutSummary.change(today: exercise, last: last.exercise, lastDate: last.date),
                  let progression = change.progression else { continue }
            switch progression {
            case .heavier(let kg):
                lines.append("\(exercise.name) +\(unit.format(kg)) \(unit.rawValue)")
            case .moreReps(let reps):
                lines.append("\(exercise.name) +\(reps) rep\(reps == 1 ? "" : "s")")
            case .moreSets(let sets):
                lines.append("\(exercise.name) +\(sets) set\(sets == 1 ? "" : "s")")
            }
        }
        return lines
    }

    private func allFinishedSessions(_ session: WorkoutSession) -> [WorkoutSession] {
        guard let context = session.modelContext ?? context else { return [session] }
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? [session]
        return all.filter { !$0.isActive }
    }

    /// "tomorrow", "on Thursday".
    private static func dayText(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return "on " + day.formatted(.dateTime.weekday(.wide))
    }
}

// MARK: - On-device rewording

/// Asks Apple's on-device model to reword a coach message as one friendly
/// line. Off the main actor; the session and its response never leave this
/// function, only the checked `String` does. Any error, refusal or a reply
/// that adds numbers or controlling words returns nil, and the app's own
/// words are used.
nonisolated enum CoachNudgeWriter {
    /// Short on purpose: the 3B model does well with small, specific prompts.
    static let instructions = """
    You rewrite short notifications for a fitness training log app. Keep the meaning, every number and every time exactly. \
    Add no new facts or numbers. Friendly and plain. Offer choices; never say "should", "must" or "missed".
    """

    @concurrent nonisolated static func reword(_ body: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        // Training-log words in, so the model doesn't decline a "health" line (`CoachPromptVocabulary`).
        guard let neutral = CoachPromptVocabulary.neutral(body) else { return nil }
        let prompt = "Notification: \(neutral)\n\nRewrite it as one or two friendly sentences, under 35 words."
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 90)
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt, options: options)
            return CoachCheckIns.acceptRephrase(response.content, of: body)
        } catch {
            return nil
        }
    }
}
