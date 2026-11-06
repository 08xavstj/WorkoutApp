import Foundation
import AppCore

/// This week's and past weeks' training plans, saved as JSON in Application
/// Support (like `CheckInStore`). Days are marked done by matching logged
/// `WorkoutSession`s, which the views pass in from their SwiftData query, so
/// the store itself holds no model context.
///
/// For other parts of the app (reminders tied to planned slots, the morning
/// briefing): `plannedDays` is this week's plan, `todayPlan()` today's slot,
/// `sessionsDone(sessions:)` how many days this week had a session, and
/// `consistency(sessions:)` the rolling 4-week score from AppCore.
@Observable
final class WeeklyPlanStore {
    private struct Saved: Codable {
        var plans: [WeeklyPlan] = []
        /// The current training block (`TrainingBlock`); nil until the first plan is confirmed.
        var block: TrainingBlock? = nil
    }

    /// Weeks of plans kept (this week included).
    static let keptWeeks = 12

    private var saved = Saved()

    /// The trainer's style from the user's goals; new blocks take it. Set by
    /// the views that know the goals before they save or refresh.
    var trainingStyle: TrainingStyle = .balanced

    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "weeklyplans.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
    }

    // MARK: Plans

    /// Every saved plan, oldest first.
    var plans: [WeeklyPlan] { saved.plans.sorted { $0.weekStart < $1.weekStart } }

    func plan(for weekStart: Date) -> WeeklyPlan? {
        saved.plans.first { Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart) }
    }

    /// The plan for the week containing `date`.
    func plan(containing date: Date = .now) -> WeeklyPlan? {
        plan(for: WeeklyPlan.weekStart(containing: date))
    }

    /// This week's plan, if the user has made one.
    var current: WeeklyPlan? { plan(containing: .now) }

    /// This week's planned days, Monday first (empty without a plan).
    var plannedDays: [PlannedDay] { current?.sortedDays ?? [] }

    /// Today's planned slot, if any. Nil in a flexible week: no day is
    /// planned, the week is (`progress`, `nextSession`).
    func todayPlan(now: Date = .now) -> PlannedDay? {
        guard let plan = plan(containing: now), !plan.isFlexible else { return nil }
        return plan.day(for: Calendar.current.component(.weekday, from: now))
    }

    /// The next planned day after today, within this week. In a flexible
    /// week, the first session template (the days aren't fixed).
    func nextPlannedDay(after now: Date = .now) -> PlannedDay? {
        if current?.isFlexible == true { return plannedDays.first }
        let today = WeeklyPlan.order(Calendar.current.component(.weekday, from: now))
        return plannedDays.first { WeeklyPlan.order($0.weekday) > today }
    }

    /// Start times still to come for this week's planned days and, unless next
    /// week has its own plan, the same days next week. For workout reminders
    /// tied to planned slots (`Reminders.PlannedSlot(start:name:ifThen:)`) and
    /// the watch face. In a flexible week the remaining sessions are projected
    /// onto the next days at their usual time (today included unless trained),
    /// so pass `trainingDays` (`trainingDays(sessions:extra:)`) for the count.
    func upcomingSlots(now: Date = .now, trainingDays: [Date] = []) -> [(day: PlannedDay, start: Date)] {
        guard let current = plan(containing: now) else { return [] }
        if current.isFlexible { return flexibleSlots(plan: current, trainingDays: trainingDays, now: now) }
        var slots: [(day: PlannedDay, start: Date)] = []
        for week in 0..<2 {
            guard let weekStart = Calendar.current.date(byAdding: .day, value: 7 * week, to: current.weekStart) else { continue }
            let plan = self.plan(for: weekStart)
                ?? WeeklyPlan(weekStart: weekStart, plannedDays: current.plannedDays, mode: current.mode, sessionsPerWeek: current.sessionsPerWeek)
            for day in plan.sortedDays {
                if let start = plan.start(of: day), start > now { slots.append((day, start)) }
            }
        }
        return slots
    }

    /// Flexible week: one slot a day for the sessions still to do, from today
    /// (tomorrow if today is done), each at its template's usual time.
    private func flexibleSlots(plan: WeeklyPlan, trainingDays: [Date], now: Date) -> [(day: PlannedDay, start: Date)] {
        let calendar = Calendar.current
        let progress = plan.progress(trainingDays: trainingDays, now: now)
        var slots: [(day: PlannedDay, start: Date)] = []
        var offset = progress.trainedToday ? 1 : 0
        var index = progress.done
        while slots.count < progress.remaining, offset < progress.daysLeft {
            guard let session = plan.nextFlexibleSession(done: index),
                  let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let start = calendar.date(bySettingHour: session.time / 60, minute: session.time % 60, second: 0, of: day) else { break }
            if start > now { slots.append((session, start)) }
            offset += 1
            index += 1
        }
        return slots
    }

    // MARK: Flexible weeks

    /// Sessions done against this week's target, days left and whether today
    /// had one (`WeeklyPlan.progress`); nil without a plan this week.
    func progress(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> WeeklyPlan.Progress? {
        plan(containing: now)?.progress(trainingDays: Self.trainingDays(sessions: sessions, extra: extra), now: now)
    }

    /// In a flexible week, the session to do next: the next template's time
    /// and length, with the focus the coverage rule picks when muscles lag
    /// (`MuscleCoverage`, via `MuscleModel.coverage`), else the template's.
    /// Nil in a fixed-day week or once the quota is met.
    func nextSession(sessions: [WorkoutSession], extra: Set<Date> = [], muscles: MuscleModel?, now: Date = .now)
        -> (day: PlannedDay, coverage: MuscleCoverage.Result?)? {
        guard let plan = plan(containing: now), plan.isFlexible,
              let progress = progress(sessions: sessions, extra: extra, now: now),
              var next = plan.nextFlexibleSession(done: progress.done) else { return nil }
        let coverage = muscles?.coverage(sessionsLeft: progress.remaining, preferred: next.focus)
        if let coverage { next.focus = coverage.focus }
        return (next, coverage)
    }

    /// Workout reminders. Fixed days: every planned slot in the next 8 days
    /// (this week's plan and next week's once saved). Flexible: one reminder
    /// at the next session's usual time, only on days when sessions remain and
    /// the days left are no more than the sessions remaining; a week with room
    /// in it gets no prompt, so the choice of day stays the user's (autonomy
    /// support: Teixeira et al. 2012; Ntoumanis et al. 2021).
    func reminderSlots(trainingDays: [Date], now: Date = .now) -> [Reminders.PlannedSlot] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let plan = plan(containing: now), plan.isFlexible else {
            return (0..<8).compactMap { offset -> Reminders.PlannedSlot? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let planned = todayPlan(now: day),
                      let start = Reminders.fireDate(day: day, minutes: planned.time, calendar: calendar) else { return nil }
                return Reminders.PlannedSlot(start: start, name: planned.focus.shortTitle, ifThen: planned.ifThen)
            }
        }
        let progress = plan.progress(trainingDays: trainingDays, now: now)
        guard progress.remaining > 0, let session = plan.nextFlexibleSession(done: progress.done) else { return [] }
        return (0..<progress.daysLeft).compactMap { offset -> Reminders.PlannedSlot? in
            // Sessions done later this week aren't known yet, so each day is judged on today's count.
            let daysLeftThen = progress.daysLeft - offset
            let remainingThen = progress.remaining
            guard daysLeftThen <= remainingThen, !(offset == 0 && progress.trainedToday),
                  let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let start = Reminders.fireDate(day: day, minutes: session.time, calendar: calendar) else { return nil }
            return Reminders.PlannedSlot(start: start, name: "\(session.focus.shortTitle) (\(remainingThen) to go)", ifThen: session.ifThen)
        }
    }

    /// The most recent plan that started before `weekStart` (the template for a new week).
    func lastPlan(before weekStart: Date) -> WeeklyPlan? {
        plans.last { $0.weekStart < weekStart }
    }

    /// Saves (or replaces) the plan for its week and drops weeks older than
    /// `keptWeeks`. The first confirmed plan with training days starts a
    /// training block (`startBlockIfNeeded`).
    func save(_ plan: WeeklyPlan) {
        saved.plans.removeAll { Calendar.current.isDate($0.weekStart, inSameDayAs: plan.weekStart) }
        saved.plans.append(plan)
        let cutoff = Calendar.current.date(byAdding: .day, value: -7 * Self.keptWeeks, to: WeeklyPlan.weekStart(containing: .now)) ?? .distantPast
        saved.plans.removeAll { $0.weekStart < cutoff }
        if !plan.plannedDays.isEmpty { startBlockIfNeeded(now: .now, persist: false) }
        write()
    }

    // MARK: Training block

    /// The current block, as last refreshed. Views read `block?.week` for the
    /// "Block week 3 of 5 · RIR 1" line after calling `refreshBlock` from a
    /// task or action (never from a view body: it may write).
    var block: TrainingBlock? { saved.block }

    /// This week's block state, if a block has started.
    var blockWeek: TrainingBlock.WeekState? { saved.block?.week }

    /// The block state for the week containing `now` without saving it, for
    /// view bodies that only read (`refreshBlock` persists the same move).
    func projectedBlockWeek(now: Date = .now, hrvBelowNormal: Bool = false) -> TrainingBlock.WeekState? {
        saved.block?.advanced(to: now, hrvBelowNormal: hrvBelowNormal, style: trainingStyle).week
    }

    /// True when the block's planned deload falls in the week starting `weekStart`.
    func isDeloadWeek(_ weekStart: Date) -> Bool {
        guard let block = saved.block, block.week.isDeload else { return false }
        return block.covers(weekStart: weekStart)
    }

    /// Starts a block in `trainingStyle` from this week if none exists.
    func startBlockIfNeeded(now: Date = .now, persist: Bool = true) {
        guard saved.block == nil else { return }
        saved.block = TrainingBlock(start: WeeklyPlan.weekStart(containing: now), style: trainingStyle)
        if persist { write() }
    }

    /// Starts over from week 1 this week (e.g. after changing goals).
    func restartBlock(now: Date = .now) {
        saved.block = TrainingBlock(start: WeeklyPlan.weekStart(containing: now), style: trainingStyle)
        write()
    }

    /// Moves the block on to the week containing `now` if a new calendar week
    /// has begun (`TrainingBlock.advanced`). `hrvBelowNormal` is the 7-day HRV
    /// flag (`DailyMetricsModel.trainEasyToday`): when a week starts with it
    /// on, the ramp holds instead of adding sets. Starts a block if a plan
    /// exists but no block does (plans saved before blocks existed).
    @discardableResult
    func refreshBlock(now: Date = .now, hrvBelowNormal: Bool = false) -> TrainingBlock.WeekState? {
        guard let current = saved.block else {
            if plans.contains(where: { !$0.plannedDays.isEmpty }) { startBlockIfNeeded(now: now) }
            return saved.block?.week
        }
        let advanced = current.advanced(to: now, hrvBelowNormal: hrvBelowNormal, style: trainingStyle)
        if advanced != current {
            saved.block = advanced
            write()
        }
        return advanced.week
    }

    private func write() {
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Matching sessions

    /// Start-of-day dates with a finished gym session, plus any other training
    /// days (`DailyMetricsModel.recentTrainingDays` covers watch workouts).
    static func trainingDays(sessions: [WorkoutSession], extra: Set<Date> = []) -> [Date] {
        let calendar = Calendar.current
        var days = Set(sessions.filter { !$0.isActive }.map { calendar.startOfDay(for: $0.startedAt) })
        days.formUnion(extra.map { calendar.startOfDay(for: $0) })
        return days.sorted()
    }

    /// Days this week with a session so far.
    func sessionsDone(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> Int {
        let plan = self.plan(containing: now) ?? WeeklyPlan(weekStart: WeeklyPlan.weekStart(containing: now))
        return WeekRecord.make(plan: plan, trainingDays: Self.trainingDays(sessions: sessions, extra: extra)).done
    }

    /// Weekdays this week that had a session.
    func doneWeekdays(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> Set<Int> {
        let plan = self.plan(containing: now) ?? WeeklyPlan(weekStart: WeeklyPlan.weekStart(containing: now))
        return plan.doneWeekdays(trainingDays: Self.trainingDays(sessions: sessions, extra: extra))
    }

    /// Planned and done counts for every saved week.
    func records(sessions: [WorkoutSession], extra: Set<Date> = []) -> [WeekRecord] {
        let days = Self.trainingDays(sessions: sessions, extra: extra)
        return plans.map { WeekRecord.make(plan: $0, trainingDays: days) }
    }

    /// The rolling 4-week consistency score (`Consistency.score`).
    func consistency(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> Consistency.Result {
        Consistency.score(records: records(sessions: sessions, extra: extra), now: now)
    }

    /// Whole days since the last training day; nil if there has never been one.
    func daysOff(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> Int? {
        RestartPlan.daysOff(lastTrained: Self.trainingDays(sessions: sessions, extra: extra).last, now: now)
    }

    // MARK: Coach

    /// One line for the AI coach: the plan, how it's going, and this week's
    /// changes. Kept short for the on-device model's budget.
    func coachSummary(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> String? {
        let result = consistency(sessions: sessions, extra: extra, now: now)
        guard let plan = self.plan(containing: now) else {
            return result.plannedWeeks > 0 ? "Weekly plan: none this week yet. Consistency \(result.label) on plan." : nil
        }
        let slots = plan.sortedDays.map { "\(WeeklyPlan.weekdayName($0.weekday)) \($0.clockText()) \($0.focus.shortTitle.lowercased()) \($0.minutes) min" }
        var line: String
        if plan.isFlexible {
            // Flexible week: a quota on any days (`WeeklyPlan.Mode.flexible`), so no weekdays are named.
            line = "Weekly plan: \(plan.sessionTarget) sessions on any days, \(plan.sortedDays.first?.minutes ?? 45) min each"
        } else {
            line = "Weekly plan: " + (slots.isEmpty ? "no training days" : slots.joined(separator: ", "))
        }
        if let ifThen = plan.sortedDays.compactMap(\.ifThen).first, !ifThen.isEmpty { line += " (\(ifThen))" }
        line += "; done \(sessionsDone(sessions: sessions, extra: extra, now: now)) of \(plan.sessionTarget) so far"
        if result.plannedWeeks > 0 { line += "; consistency \(result.label) on plan" }
        if !plan.changes.isEmpty { line += ". Changes this week: " + plan.changes.prefix(3).joined(separator: "; ") }
        line += "."
        // Training block (`TrainingBlock.coachLine`): week, RIR target, deload or held ramp.
        if let block = saved.block { line += " " + block.coachLine }
        return line
    }
}
