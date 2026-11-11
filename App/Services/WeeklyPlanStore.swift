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
        /// Per-muscle weekly set targets, this week and last (`VolumeProgression`).
        /// Optional so files saved before it existed still decode.
        var volume: [VolumeProgression.WeekTargets]? = nil
        /// "Why a different workout?" answers, one per day (`AdaptiveWeek.Swap`).
        /// Optional so files saved before it existed still decode.
        var swaps: [AdaptiveWeek.Swap]? = nil
    }

    /// Weeks of plans kept (this week included).
    static let keptWeeks = 12

    private var saved = Saved()

    /// The trainer's style from the user's goals; new blocks take it. Set by
    /// the views that know the goals before they save or refresh.
    var trainingStyle: TrainingStyle = .balanced
    /// The active gym's equipment, so muscles it has no movement for get no
    /// weekly set target (`VolumeProgression.week(gym:)`). Set beside `trainingStyle`.
    @ObservationIgnored var gym: GymProfile?

    @ObservationIgnored private let file = SafeJSONFile.appSupport("weeklyplans.json")
    /// False while the file exists but couldn't be read (a background launch
    /// while the phone was locked): nothing is saved over it until it loads.
    @ObservationIgnored private var canSave = false

    init() {
        reload()
    }

    /// Reads the file again if the last read failed (call when the phone unlocks).
    /// Every method that writes calls it first.
    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        let loaded = file.loadLogged(Saved.self)
        canSave = loaded.state.canSave
        if canSave { saved = loaded.value ?? Saved() }
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
    /// planned, the week is (`progress`, `nextSession`). In a fixed week whose
    /// queue was worked out today (`refreshAdaptive`), today's session from
    /// the queue as it stood before today's training (`AdaptiveWeek`), so a
    /// missed session shows on the day that takes it; other days, the calendar.
    func todayPlan(now: Date = .now) -> PlannedDay? {
        guard let plan = plan(containing: now), !plan.isFlexible else { return nil }
        if let state = freshAdaptive(now: now) { return state.suggestedToday?.session }
        return plan.day(for: Calendar.current.component(.weekday, from: now))
    }

    /// The next planned day after today, within this week. In a flexible
    /// week, the first session template (the days aren't fixed). In a fixed
    /// week, the queue's next session after today when it is known.
    func nextPlannedDay(after now: Date = .now) -> PlannedDay? {
        if current?.isFlexible == true { return plannedDays.first }
        if let state = freshAdaptive(now: now) {
            return state.week.slots.first { $0.date > state.week.day }?.session
        }
        let today = WeeklyPlan.order(Calendar.current.component(.weekday, from: now))
        return plannedDays.first { WeeklyPlan.order($0.weekday) > today }
    }

    /// Start times still to come for this week's planned days and, once next
    /// week's plan is saved, next week's. A plan isn't carried into a week
    /// that has none, the same as `todayPlan` and `reminderSlots` (each week is
    /// planned or confirmed on its own), so the watch face never shows a
    /// Monday session that Monday won't have. For workout reminders
    /// tied to planned slots (`Reminders.PlannedSlot(start:name:ifThen:)`) and
    /// the watch face. In a flexible week the remaining sessions are projected
    /// onto the next days at their usual time (today included unless trained),
    /// so pass `trainingDays` (`trainingDays(sessions:extra:)`) for the count.
    func upcomingSlots(now: Date = .now, trainingDays: [Date] = []) -> [(day: PlannedDay, start: Date)] {
        guard let current = plan(containing: now) else { return [] }
        if current.isFlexible { return flexibleSlots(plan: current, trainingDays: trainingDays, now: now) }
        var slots: [(day: PlannedDay, start: Date)] = []
        // This week from the queue when it's known today (`AdaptiveWeek`), else the calendar.
        let queued = freshAdaptive(now: now)
        if let queued {
            for slot in queued.week.slots {
                let time = slot.session.time
                if let start = Calendar.current.date(bySettingHour: time / 60, minute: time % 60, second: 0, of: slot.date),
                   start > now { slots.append((slot.session, start)) }
            }
        }
        for week in (queued == nil ? 0 : 1)..<2 {
            guard let weekStart = Calendar.current.date(byAdding: .day, value: 7 * week, to: current.weekStart),
                  let plan = week == 0 ? Optional(current) : self.plan(for: weekStart), !plan.isFlexible else { continue }
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
        plan(containing: now)?.progress(trainingDays: Self.trainingDays(sessions: sessions, extra: liftingExtra(extra, now: now)), now: now)
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
            let queued = freshAdaptive(now: now)
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: WeeklyPlan.weekStart(containing: now)) ?? today
            return (0..<8).compactMap { offset -> Reminders.PlannedSlot? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
                // This week's days follow the queue when it's known (a missed session moves); later, the plan.
                let planned: PlannedDay?
                if let queued, day < weekEnd {
                    planned = queued.week.slot(on: day)?.session
                } else {
                    planned = todayPlan(now: day)
                }
                guard let planned,
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
        reloadIfUnavailable()
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
        reloadIfUnavailable()
        guard saved.block == nil else { return }
        saved.block = TrainingBlock(start: WeeklyPlan.weekStart(containing: now), style: trainingStyle)
        if persist { write() }
    }

    /// Starts over from week 1 this week (e.g. after changing goals).
    func restartBlock(now: Date = .now) {
        reloadIfUnavailable()
        let thisWeek = WeeklyPlan.weekStart(containing: now)
        saved.block = TrainingBlock(start: thisWeek, style: trainingStyle)
        // A new block starts every muscle again at week 1's sets.
        saved.volume?.removeAll { Calendar.current.isDate($0.weekStart, inSameDayAs: thisWeek) }
        write()
    }

    /// Moves the block on to the week containing `now` if a new calendar week
    /// has begun (`TrainingBlock.advanced`). `hrvBelowNormal` is the 7-day HRV
    /// flag (`DailyMetricsModel.trainEasyToday`): when a week starts with it
    /// on, the ramp holds instead of adding sets. Starts a block if a plan
    /// exists but no block does (plans saved before blocks existed).
    @discardableResult
    func refreshBlock(now: Date = .now, hrvBelowNormal: Bool = false) -> TrainingBlock.WeekState? {
        reloadIfUnavailable()
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
        file.saveLogged(saved, canSave: canSave)
    }

    // MARK: Matching sessions

    /// Start-of-day dates with a finished gym session, plus any other training
    /// days (`DailyMetricsModel.recentLiftingDays`: strength workouts another
    /// app or the watch recorded, at strain at least 35%,
    /// `TrainingDayPlanner.isWatchTrainingDay`). A logged session always
    /// counts as done, however light; soccer, a run or a walk never do.
    static func trainingDays(sessions: [WorkoutSession], extra: Set<Date> = []) -> [Date] {
        let calendar = Calendar.current
        var days = Set(sessions.filter { !$0.isActive }.map { calendar.startOfDay(for: $0.startedAt) })
        days.formUnion(extra.map { calendar.startOfDay(for: $0) })
        return days.sorted()
    }

    /// Days this week with a session so far.
    func sessionsDone(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> Int {
        let plan = self.plan(containing: now) ?? WeeklyPlan(weekStart: WeeklyPlan.weekStart(containing: now))
        return WeekRecord.make(plan: plan, trainingDays: Self.trainingDays(sessions: sessions, extra: liftingExtra(extra, now: now))).done
    }

    /// Weekdays this week that had a session. The same training days as
    /// `sessionsDone` (`liftingExtra`), so the dots and the count agree.
    func doneWeekdays(sessions: [WorkoutSession], extra: Set<Date> = [], now: Date = .now) -> Set<Int> {
        let plan = self.plan(containing: now) ?? WeeklyPlan(weekStart: WeeklyPlan.weekStart(containing: now))
        return plan.doneWeekdays(trainingDays: Self.trainingDays(sessions: sessions, extra: liftingExtra(extra, now: now)))
    }

    /// Planned and done counts for every saved week.
    func records(sessions: [WorkoutSession], extra: Set<Date> = []) -> [WeekRecord] {
        let days = Self.trainingDays(sessions: sessions, extra: liftingExtra(extra, now: .now))
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

    // MARK: Per-muscle volume (`VolumeProgression`)

    private func savedVolume(for weekStart: Date) -> VolumeProgression.WeekTargets? {
        saved.volume?.first { Calendar.current.isDate($0.weekStart, inSameDayAs: weekStart) }
    }

    /// This week's per-muscle set targets: the saved ones once the week has
    /// them, else worked out from last week's targets and sets
    /// (`VolumeProgression.week`), with the sessions from this week's plan (or
    /// last week's as the template). Works the same for fixed and flexible
    /// weeks: the coverage rule picks each session's focus, this sets the
    /// volume. Nil without a block or plan, or before `MuscleModel` has loaded.
    func volumeTargets(muscles: MuscleModel, now: Date = .now) -> VolumeProgression.WeekTargets? {
        let calendar = Calendar.current
        let thisWeek = WeeklyPlan.weekStart(containing: now)
        if let stored = savedVolume(for: thisWeek) { return stored }
        guard muscles.hasRefreshed, let current = saved.block else { return nil }
        let running = current.covers(weekStart: thisWeek) ? current : current.advanced(to: now, style: trainingStyle)
        let block = running.week
        let days = (plan(for: thisWeek) ?? lastPlan(before: thisWeek))?.plannedDays ?? []
        guard !days.isEmpty else { return nil }
        let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        let previous = savedVolume(for: lastMonday)
        // Last week's effort target: as saved with its targets, else the block's week if it was last week's.
        var lastRPE = block.targetRPE
        if let previous {
            lastRPE = previous.targetRPE
        } else if current.covers(weekStart: lastMonday) {
            lastRPE = current.week.targetRPE
        }
        let style = current.style
        let lastWeek = VolumeProgression.summarize(muscles.loggedSets, weekStart: lastMonday, targetRPE: lastRPE, style: style)
        // Your answers after last week's sessions (`MuscleFeedbackStore`) and the
        // last block's report, if you applied it to this block (`NextBlockStore`).
        let feedback = MuscleFeedbackStore.shared.signals(sets: muscles.loggedSets, weekStart: lastMonday)
        let adjustment = NextBlockStore.shared.volume(blockStart: running.start, weekStart: thisWeek)
        return VolumeProgression.week(weekStart: thisWeek, block: block, style: style, days: days,
                                      previous: previous, lastWeek: lastWeek, states: muscles.states,
                                      recentWeeklySets: VolumeProgression.recentWeeklySets(muscles.loggedSets, before: thisWeek, style: style),
                                      feedback: feedback, adjustment: adjustment, gym: gym)
    }

    /// Drops this week's saved targets, so the next `refreshVolume` works them
    /// out again: after the block report's changes are applied or undone
    /// (`NextBlockStore`), which change this week's targets.
    func redoVolume(now: Date = .now) {
        reloadIfUnavailable()
        let thisWeek = WeeklyPlan.weekStart(containing: now)
        guard savedVolume(for: thisWeek) != nil else { return }
        saved.volume?.removeAll { Calendar.current.isDate($0.weekStart, inSameDayAs: thisWeek) }
        write()
    }

    /// Saves this week's targets the first time they can be worked out from
    /// real data (they then hold for the week), keeping this week and last;
    /// also notes which recent days were only easy cardio (`liftingExtra`).
    /// Call from a task once `MuscleModel.refresh` has run.
    func refreshVolume(muscles: MuscleModel, now: Date = .now) {
        reloadIfUnavailable()
        let calendar = Calendar.current
        if let kind = current?.cardio?.kind {
            let names = kind.workoutNames
            cardioOnlyDays = Set(muscles.recentCardio
                .filter { names.contains($0.name) && $0.minutes >= CardioPlanner.minimumDoneMinutes }
                .map { calendar.startOfDay(for: $0.start) })
        } else {
            cardioOnlyDays = []
        }
        let thisWeek = WeeklyPlan.weekStart(containing: now)
        guard savedVolume(for: thisWeek) == nil, let targets = volumeTargets(muscles: muscles, now: now) else { return }
        let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        var weeks = (saved.volume ?? []).filter { $0.weekStart >= lastMonday && $0.weekStart < thisWeek }
        weeks.append(targets)
        saved.volume = weeks
        write()
        // The block report's sets now live in this week's targets: later weeks
        // build on them. A deload week leaves them out, so they wait for the next.
        if let block = saved.block {
            let running = block.covers(weekStart: thisWeek) ? block : block.advanced(to: now, style: trainingStyle)
            if !running.week.isDeload {
                NextBlockStore.shared.markOffsetsApplied(blockStart: running.start, weekStart: thisWeek)
            }
        }
    }

    /// Direct sets for each muscle today's session trains (`VolumeProgression.sessionGoals`),
    /// for `WorkoutPlanner.plan(muscleSetGoals:)`: what the week still owes it,
    /// shared over the sessions left that train it. Empty without targets.
    func sessionSetGoals(focus: WorkoutFocus, minutes: Int, muscles: MuscleModel, sessions: [WorkoutSession],
                         extra: Set<Date> = [], now: Date = .now) -> [Muscle: Int] {
        guard let targets = volumeTargets(muscles: muscles, now: now), let plan = plan(containing: now) else { return [:] }
        var later: [PlannedDay] = []
        if plan.isFlexible {
            // The sessions after this one, from the templates (the days aren't fixed).
            if let progress = progress(sessions: sessions, extra: extra, now: now) {
                let templates = plan.sortedDays
                let after = max(0, progress.remaining - (progress.trainedToday ? 0 : 1))
                if !templates.isEmpty {
                    later = (0..<after).map { templates[min(progress.done + 1 + $0, templates.count - 1)] }
                }
            }
        } else if let state = freshAdaptive(now: now) {
            // The queue's sessions after today (`AdaptiveWeek`), so a moved session still counts.
            later = state.week.slots.filter { $0.date > state.week.day }.map(\.session)
        } else {
            let today = WeeklyPlan.order(Calendar.current.component(.weekday, from: now))
            later = plan.sortedDays.filter { WeeklyPlan.order($0.weekday) > today }
        }
        return VolumeProgression.sessionGoals(targets: targets, doneThisWeek: muscles.weekSets, focus: focus,
                                              minutes: minutes, laterSessions: later, gym: gym)
    }

    // MARK: Easy cardio (`CardioPlanner`)

    /// Recent days with a workout of this week's easy-cardio type (set by `refreshVolume`).
    private(set) var cardioOnlyDays: Set<Date> = []

    /// Watch training days that count toward the lifting quota: in a
    /// flexible week with easy cardio, days that were only that cardio don't
    /// (a gym session that day still counts, from `sessions`).
    private func liftingExtra(_ extra: Set<Date>, now: Date) -> Set<Date> {
        guard let plan = plan(containing: now), plan.isFlexible, (plan.cardio?.sessionsPerWeek ?? 0) > 0 else { return extra }
        let calendar = Calendar.current
        return Set(extra.map { calendar.startOfDay(for: $0) }).subtracting(cardioOnlyDays)
    }

    /// This week's easy-cardio slots (`CardioPlanner.slots`).
    func cardioSlots(goals: Goals?, now: Date = .now) -> [CardioPlanner.Slot] {
        guard let plan = plan(containing: now) else { return [] }
        return CardioPlanner.slots(for: plan, goals: goals)
    }

    /// Slots done this week, from Apple Health workouts of that type.
    func cardioDone(slots: [CardioPlanner.Slot], workouts: [CardioPlanner.Workout], now: Date = .now) -> Set<Int> {
        guard let kind = slots.first?.kind else { return [] }
        let weekStart = WeeklyPlan.weekStart(containing: now)
        let days = CardioPlanner.doneDays(kind: kind, workouts: workouts, weekStart: weekStart)
        return CardioPlanner.done(slots: slots, doneDays: days, weekStart: weekStart)
    }

    /// Cardio workouts to tick slots with: the last 10 days from `MuscleModel`
    /// and today's from `DailyMetricsModel.activities` (refreshed more often).
    static func cardioWorkouts(muscles: MuscleModel, metrics: DailyMetricsModel) -> [CardioPlanner.Workout] {
        let today = metrics.activities
            .filter { !$0.isStrength }
            .map { CardioPlanner.Workout(name: $0.name, start: $0.start, minutes: $0.minutes) }
        return muscles.recentCardio + today
    }

    // MARK: The week as a queue (`AdaptiveWeek`)

    /// The queue as last worked out today (`refreshAdaptive`), with today's
    /// session as it stood before today's training.
    nonisolated struct AdaptiveState: Equatable {
        var week: AdaptiveWeek.Result
        var suggestedToday: AdaptiveWeek.Slot?
    }

    /// Set by `refreshAdaptive` from a task (Today's Scores card, Fitness ›
    /// This week); read by `todayPlan`, `upcomingSlots`, `reminderSlots` and
    /// `sessionSetGoals` only on the day it was worked out.
    private(set) var adaptive: AdaptiveState?

    private func freshAdaptive(now: Date) -> AdaptiveState? {
        guard let adaptive, Calendar.current.isDate(adaptive.week.day, inSameDayAs: now) else { return nil }
        return adaptive
    }

    /// This week's logged sessions (focus from name or exercises) and
    /// strength workouts other apps recorded on days without one.
    static func doneSessions(sessions: [WorkoutSession], extra: Set<Date>, since: Date) -> [AdaptiveWeek.DoneSession] {
        let calendar = Calendar.current
        let lifts = sessions.filter { !$0.isActive && $0.startedAt >= since }
        var done = lifts.map { session in
            AdaptiveWeek.DoneSession(
                date: session.startedAt,
                focus: AdaptiveWeek.inferFocus(name: session.name, exerciseIDs: session.orderedExercises.map(\.exerciseID))
            )
        }
        let liftDays = Set(lifts.map { calendar.startOfDay(for: $0.startedAt) })
        // `extra` is strength workouts from other apps (`DailyMetricsModel.recentLiftingDays`):
        // a lift of unknown focus, which ticks the day's planned session.
        for day in Set(extra.map { calendar.startOfDay(for: $0) }) where day >= since && !liftDays.contains(day) {
            done.append(AdaptiveWeek.DoneSession(date: day, focus: nil, isLifting: true))
        }
        return done
    }

    /// Sore groups: this morning's and yesterday's check-ins (5/10 or more),
    /// this week's "why a different workout?" answers, and today's muscle
    /// model estimate (`AdaptiveWeek.fatiguedAreas`, under 50% recovered).
    func soreSignals(checkIns: CheckInStore?, muscles: MuscleModel?, now: Date = .now,
                     todaysAnswers: Bool = true, estimated: Bool = true) -> [AdaptiveWeek.SoreSignal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var signals: [AdaptiveWeek.SoreSignal] = []
        if let checkIns {
            signals += AdaptiveWeek.signals(from: checkIns.morning(on: now))
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                signals += AdaptiveWeek.signals(from: checkIns.morning(on: yesterday))
            }
        }
        signals += AdaptiveWeek.signals(fromSwaps: swaps(inWeekOf: now).filter { todaysAnswers || $0.day < today })
        if estimated, let muscles, muscles.hasRefreshed {
            signals += AdaptiveWeek.fatiguedAreas(muscles.states, day: today)
        }
        return signals
    }

    /// The sessions the week before `weekStart` left undone, in plan order
    /// (`AdaptiveWeek.leftOver`); empty without a plan that week.
    func leftOver(before weekStart: Date, sessions: [WorkoutSession]) -> [PlannedDay] {
        let calendar = Calendar.current
        guard let lastStart = calendar.date(byAdding: .day, value: -7, to: weekStart),
              let last = plan(for: lastStart) else { return [] }
        let done = Self.doneSessions(sessions: sessions, extra: [], since: lastStart).filter { $0.date < weekStart }
        return AdaptiveWeek.leftOver(plan: last, done: done, calendar: calendar)
    }

    /// A new week's days copied from `template`, with last week's left-over
    /// session moved to the first day (`AdaptiveWeek.rotated`).
    func newWeekDays(from template: [PlannedDay], weekStart: Date, sessions: [WorkoutSession]) -> [PlannedDay] {
        AdaptiveWeek.rotated(template, startingWith: leftOver(before: weekStart, sessions: sessions).first?.focus)
    }

    /// This week as a queue: the next session not done yet, wherever the
    /// calendar had it (`AdaptiveWeek.make`), starting with what last week
    /// left undone. Nil for a flexible week or without a plan.
    func adaptiveWeek(sessions: [WorkoutSession], extra: Set<Date> = [], checkIns: CheckInStore?, muscles: MuscleModel?,
                      now: Date = .now) -> AdaptiveWeek.Result? {
        guard let plan = plan(containing: now), !plan.isFlexible else { return nil }
        let done = Self.doneSessions(sessions: sessions, extra: extra, since: plan.weekStart)
        return AdaptiveWeek.make(plan: plan, done: done, now: now,
                                 soreness: soreSignals(checkIns: checkIns, muscles: muscles, now: now),
                                 swaps: swaps(inWeekOf: now),
                                 carriedOver: leftOver(before: plan.weekStart, sessions: sessions).first?.focus)
    }

    /// Today's session as the queue had it before today's training and before
    /// today's answer, for "why a different workout?" (the model estimate is
    /// left out: it already includes today's session).
    func suggestedToday(sessions: [WorkoutSession], extra: Set<Date> = [], checkIns: CheckInStore?, now: Date = .now) -> AdaptiveWeek.Slot? {
        guard let plan = plan(containing: now), !plan.isFlexible else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        let done = Self.doneSessions(sessions: sessions, extra: extra, since: plan.weekStart).filter { $0.date < today }
        return AdaptiveWeek.make(plan: plan, done: done, now: now,
                                 soreness: soreSignals(checkIns: checkIns, muscles: nil, now: now, todaysAnswers: false, estimated: false),
                                 swaps: swaps(inWeekOf: now).filter { $0.day < today },
                                 carriedOver: leftOver(before: plan.weekStart, sessions: sessions).first?.focus)?.today
    }

    /// Works the queue out and keeps it for today (`adaptive`); returns the
    /// week for `DailyMetricsModel.adaptiveWeek`. Call from a task, never a view body.
    @discardableResult
    func refreshAdaptive(sessions: [WorkoutSession], extra: Set<Date> = [], checkIns: CheckInStore?, muscles: MuscleModel?,
                         now: Date = .now) -> AdaptiveWeek.Result? {
        guard let week = adaptiveWeek(sessions: sessions, extra: extra, checkIns: checkIns, muscles: muscles, now: now) else {
            if adaptive != nil { adaptive = nil }
            return nil
        }
        let state = AdaptiveState(week: week, suggestedToday: suggestedToday(sessions: sessions, extra: extra, checkIns: checkIns, now: now))
        if state != adaptive { adaptive = state }
        return week
    }

    /// Changes whenever the queue's inputs might have: for `.task(id:)`.
    func adaptiveKey(sessions: [WorkoutSession], extra: Set<Date>, checkIns: CheckInStore) -> String {
        let finished = sessions.filter { !$0.isActive }
        let last = finished.map(\.startedAt).max()?.timeIntervalSince1970 ?? 0
        let morning = checkIns.morning()
        let soreness = morning?.soreness ?? -1
        let areas = morning?.soreAreas.map(\.rawValue).joined(separator: ",") ?? ""
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let planText = current.map { plan in
            plan.mode.rawValue + plan.sortedDays.map { "\($0.weekday)\($0.focus.rawValue)" }.joined()
        } ?? "none"
        let answers = allSwaps.map { swap -> String in
            let reason = swap.reason?.rawValue ?? "-"
            return "\(swap.day.timeIntervalSince1970)\(reason)"
        }.joined()
        return "\(day)|\(finished.count)|\(last)|\(extra.count)|\(soreness)|\(areas)|\(answers)|\(planText)"
    }

    // MARK: Why a different workout?

    /// Every saved answer, oldest first.
    var allSwaps: [AdaptiveWeek.Swap] { (saved.swaps ?? []).sorted { $0.day < $1.day } }

    /// The answer for the day containing `date`, if one was given (or skipped).
    func swap(on date: Date = .now) -> AdaptiveWeek.Swap? {
        saved.swaps?.first { Calendar.current.isDate($0.day, inSameDayAs: date) }
    }

    /// Answers in the week containing `date`.
    func swaps(inWeekOf date: Date = .now) -> [AdaptiveWeek.Swap] {
        let start = WeeklyPlan.weekStart(containing: date)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return allSwaps.filter { $0.day >= start && $0.day < end }
    }

    /// Saves the day's answer (replacing an earlier one that day), keeping `keptWeeks` weeks.
    func recordSwap(planned: WorkoutFocus?, chosen: WorkoutFocus, reason: AdaptiveWeek.Reason?,
                    soreAreas: [AdaptiveWeek.Area] = [], now: Date = .now) {
        reloadIfUnavailable()
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        var all = saved.swaps ?? []
        all.removeAll { calendar.isDate($0.day, inSameDayAs: day) }
        all.append(AdaptiveWeek.Swap(day: day, planned: planned, chosen: chosen, reason: reason, soreAreas: soreAreas, recordedAt: now))
        let cutoff = calendar.date(byAdding: .day, value: -7 * Self.keptWeeks, to: WeeklyPlan.weekStart(containing: now)) ?? .distantPast
        saved.swaps = all.filter { $0.day >= cutoff }
        write()
    }

    /// The session the queue suggests today when `chosen` is a different one
    /// and nothing was answered today, so the builder can ask why. Nil in a
    /// flexible week, on a rest day, once today has a session, or for the same
    /// session (Legs for Lower counts as the same).
    func swapPrompt(chosen: WorkoutFocus, sessions: [WorkoutSession], extra: Set<Date> = [], checkIns: CheckInStore?,
                    muscles: MuscleModel?, now: Date = .now) -> WorkoutFocus? {
        guard swap(on: now) == nil,
              let week = adaptiveWeek(sessions: sessions, extra: extra, checkIns: checkIns, muscles: muscles, now: now),
              !week.liftedToday, let suggested = week.today?.focus,
              !AdaptiveWeek.isSameSession(suggested, chosen) else { return nil }
        return suggested
    }

    /// A session logged today that wasn't the one suggested, with no answer
    /// yet: Today and This week ask why once, after the fact (it catches
    /// sessions started from Coach, a saved workout or the watch).
    func unansweredSwap(sessions: [WorkoutSession], extra: Set<Date> = [], checkIns: CheckInStore?,
                        now: Date = .now) -> (planned: WorkoutFocus, chosen: WorkoutFocus)? {
        guard swap(on: now) == nil,
              let suggested = suggestedToday(sessions: sessions, extra: extra, checkIns: checkIns, now: now)?.focus else { return nil }
        let calendar = Calendar.current
        let chosen = sessions
            .filter { !$0.isActive && calendar.isDate($0.startedAt, inSameDayAs: now) }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { AdaptiveWeek.inferFocus(name: $0.name, exerciseIDs: $0.orderedExercises.map(\.exerciseID)) }
            .first
        guard let chosen, !AdaptiveWeek.isSameSession(suggested, chosen) else { return nil }
        return (suggested, chosen)
    }

    /// "Tue: Upper for Lower · legs sore" for each answered swap in the week
    /// starting `weekStart` (skipped ones left out), for This week and the review.
    func swapLines(weekStart: Date) -> [String] {
        swaps(inWeekOf: weekStart).filter { $0.reason != nil }.map { swap in
            let weekday = WeeklyPlan.weekdayName(Calendar.current.component(.weekday, from: swap.day))
            return "\(weekday): \(swap.label)"
        }
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
        // The queue (`AdaptiveWeek`): what's next and why sessions were swapped.
        if let state = freshAdaptive(now: now), !plan.isFlexible {
            if let next = state.week.next { line += ". Next in the queue: \(next.focus.shortTitle.lowercased()) \(WeeklyPlan.weekdayName(next.session.weekday))" }
            if let move = state.week.moveNote { line += " (\(move.dropLast()))" }
        }
        let swapped = swapLines(weekStart: plan.weekStart)
        if !swapped.isEmpty { line += ". Swaps: " + swapped.prefix(3).joined(separator: "; ") }
        line += "."
        // Training block (`TrainingBlock.coachLine`): week, RIR target, deload or held ramp.
        if let block = saved.block { line += " " + block.coachLine }
        // Easy cardio (`CardioPlanner`): not part of the lifting sessions above.
        if let cardio = plan.cardio, cardio.sessionsPerWeek > 0 {
            let kind = cardio.kind.label.lowercased()
            line += " Easy cardio: \(cardio.sessionsPerWeek) × \(cardio.minutes) min \(kind)."
        }
        return line
    }
}
