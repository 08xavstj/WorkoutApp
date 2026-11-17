import AppCore
import Foundation
import SwiftUI

/// What the widgets and the Watch complications are told about today: the
/// plan (`PlanGlance.Plan`) and the scores the snapshot didn't carry before.
/// One place builds it, so the iPhone widgets and the watch face always get
/// the same sessions, bed-by window and week count (a glance that disagrees
/// with the app is a top complaint about competing apps,
/// docs/research/competitors-2026-11.md).
///
/// Written after every metrics refresh and whenever the plan, the week's
/// queue or rest mode changes (`GlanceReactions`).
enum GlanceFeed {
    /// Days of planned sessions sent, from the start of today.
    static let horizonDays = 8

    /// Today's plan as the app has it now.
    static func plan(plans: WeeklyPlanStore, metrics: DailyMetricsModel, checkIns: CheckInStore, muscles: MuscleModel,
                     sessions: [WorkoutSession], restUntil: Date?, now: Date = .now) -> PlanGlance.Plan {
        // The plan file can't be read while the phone is locked; this only runs
        // after Apple Health was read, so the phone is unlocked and it loads now.
        plans.reloadIfUnavailable()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekStart = WeeklyPlan.weekStart(containing: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) ?? today.addingTimeInterval(TimeInterval(horizonDays) * 86_400)
        let trainingDays = WeeklyPlanStore.trainingDays(sessions: sessions, extra: metrics.recentLiftingDays)

        // From the start of today, so today's session stays in (done or not).
        var planned = plans.upcomingSlots(now: today, trainingDays: trainingDays)
        // A fixed week whose queue wasn't worked out today (a background wake,
        // before Today has been on screen): this week from the queue all the
        // same, so a session that moved shows on the day that takes it.
        if let current = plans.current, !current.isFlexible,
           !(plans.adaptive.map { calendar.isDate($0.week.day, inSameDayAs: now) } ?? false),
           let week = plans.adaptiveWeek(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns, muscles: muscles, now: now) {
            planned.removeAll { $0.start < weekEnd }
            let queued = week.slots.compactMap { slot -> (day: PlannedDay, start: Date)? in
                let time = slot.session.time
                guard let start = calendar.date(bySettingHour: time / 60, minute: time % 60, second: 0, of: slot.date),
                      start > today else { return nil }
                return (day: slot.session, start: start)
            }
            planned = queued + planned
        }
        let slots = planned
            .filter { $0.start < horizon }
            .sorted { $0.start < $1.start }
            .map { slot in
                PlanGlance.Slot(start: slot.start, title: slot.day.focus.title, shortTitle: slot.day.focus.shortTitle,
                                symbol: symbol(for: slot.day.focus), minutes: slot.day.minutes)
            }

        let progress = plans.progress(sessions: sessions, extra: metrics.recentLiftingDays, now: now)
        // Done today: a logged session, or a lift another app recorded (the same days the plan ticks).
        let trainedToday = progress?.trainedToday ?? trainingDays.contains(today)
        var doneAt = sessions.lazy.filter { !$0.isActive }.compactMap(\.endedAt).max()
        if trainedToday, !(doneAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false) {
            doneAt = today
        }

        let hasPlan = !(plans.current?.plannedDays.isEmpty ?? true)
        let nextWeek: PlanGlance.NextWeek
        if let following = plans.plan(for: weekEnd), !following.plannedDays.isEmpty {
            nextWeek = following.isFlexible ? .open : .planned
        } else {
            nextWeek = .unplanned
        }

        // Tonight's window only: one that has already ended says nothing about tonight.
        let window = metrics.bedtimeWindow.flatMap { $0.end > now ? $0 : nil }
        let restMode = (restUntil ?? .distantPast) > now
        return PlanGlance.Plan(
            updated: now, hasPlan: hasPlan, slots: slots, weekEnd: weekEnd, nextWeek: nextWeek,
            doneAt: doneAt,
            restToday: restMode || metrics.restMode || metrics.dayGuidance?.isRestDay == true,
            bedByStart: window?.start, bedByEnd: window?.end,
            weekDone: hasPlan ? progress.map { min($0.done, $0.target) } : nil,
            weekPlanned: hasPlan ? progress?.target : nil,
            restUntil: restMode ? restUntil : nil
        )
    }

    /// `snapshot` with the plan and the scores the Plan and Scores widgets
    /// read. The same rules as the fields already in it: recovery's band only
    /// with today's recovery, sleep only once last night is recorded.
    static func completed(_ snapshot: WidgetSnapshot, metrics: DailyMetricsModel, plan: PlanGlance.Plan) -> WidgetSnapshot {
        var snapshot = snapshot
        var plan = plan
        plan.updated = snapshot.updated
        snapshot.plan = plan
        snapshot.sleep = metrics.sleepIsFromYesterday ? nil : metrics.sleep?.score
        snapshot.band = snapshot.recovery == nil ? nil : metrics.recovery?.status.rawValue
        snapshot.calibrating = metrics.recovery.map { !$0.isCalibrated }
        let target = metrics.targetStrain
        snapshot.targetLower = target?.lowerBound
        snapshot.targetUpper = target?.upperBound
        return snapshot
    }

    /// SF Symbol for a planned session's focus (the same as the watch face's).
    static func symbol(for focus: WorkoutFocus) -> String {
        switch focus {
        case .legs, .lower: "figure.strengthtraining.functional"
        case .fullBody: "figure.strengthtraining.traditional"
        case .push, .pull, .upper: "dumbbell.fill"
        }
    }
}

nonisolated extension WatchFaceData {
    /// Takes the sessions, done time, bed-by window and week count from the
    /// plan the iPhone widgets get, so the wrist and the phone can't differ.
    mutating func apply(_ plan: PlanGlance.Plan) {
        slots = plan.slots.map { slot in
            Slot(start: slot.start, title: slot.title, shortTitle: slot.shortTitle, symbol: slot.symbol, minutes: slot.minutes)
        }
        lastWorkoutEnd = plan.doneAt
        restToday = plan.restToday
        bedByStart = plan.bedByStart
        bedByEnd = plan.bedByEnd
        weekDone = plan.weekDone
        weekPlanned = plan.weekPlanned
        weekEnd = plan.weekEnd
        hasPlan = plan.hasPlan
        nextWeek = plan.nextWeek.rawValue
        restUntil = plan.restUntil
    }
}

/// Rewrites the widgets' and the watch face's data when something they show
/// changes between metrics refreshes: the weekly plan is saved, the week's
/// queue is worked out (`WeeklyPlanStore.refreshAdaptive`), rest mode is
/// switched, or the app leaves the screen. Also presents last night's sleep
/// for the Plan widget's bed-by link (workoutapp://sleep).
struct GlanceReactions: ViewModifier {
    let router: AppRouter
    let plans: WeeklyPlanStore
    let restModeUntil: Date?
    let update: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .onChange(of: plans.plans) { update() }
            .onChange(of: plans.adaptive) { update() }
            .onChange(of: restModeUntil) { update() }
            .onChange(of: scenePhase) { _, phase in
                // The last word before the app is suspended (WidgetKit: reload on entering the background).
                if phase == .background { update() }
            }
            .sheet(isPresented: $router.showSleep) {
                LastNightSleepSheet()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.background)
            }
    }
}
