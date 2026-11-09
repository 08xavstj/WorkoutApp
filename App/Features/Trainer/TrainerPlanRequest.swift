import Foundation
import AppCore

/// One way to ask the planner for a session, shared by the workout builder
/// and the coach, so "ask the coach for a workout" gives the same plan as
/// the builder: the week's set targets, the movements for muscles behind on
/// the week, the pain and never-again filter, your age and any numbers you
/// gave ("Know your numbers?"), and the abs finisher (audit 2026-11 §8: the
/// coach's plans had none of these).
struct TrainerPlanRequest {
    var focus: WorkoutFocus
    var minutes: Int
    /// "because of the soreness you reported", for the plan's rationale.
    var focusReason: String? = nil
    /// Movements for muscles behind on the week (`MuscleCoverage`).
    var prioritySlots: [MovementSlot] = []
    /// This week in the training block.
    var block: TrainingBlock.WeekState?
    /// Your finisher setting; short sessions skip it (`effectiveFinisher`).
    var finisherLength: AbsFinisher.Length
    /// True for the plan's short version (it skips the finisher too).
    var isShortVersion = false
    var exerciseFilter: ExerciseFilter
    /// The movement warm-up's minutes (`WarmUpRoutine`), counted in the time.
    var warmUpMinutes: Int

    /// The finisher after the short-session rule (`AbsFinisher.length`).
    var effectiveFinisher: AbsFinisher.Length {
        AbsFinisher.length(finisherLength, sessionMinutes: minutes, isShortVersion: isShortVersion)
    }

    /// The session, without the finisher (`finisher(for:)` adds it).
    func plan(gym: GymStore, plans: WeeklyPlanStore, muscles: MuscleModel, metrics: DailyMetricsModel,
              settings: UserSettings, sessions: [WorkoutSession], history: [String: ExerciseHistory]) -> PlannedWorkout {
        let goals = plans.sessionSetGoals(focus: focus, minutes: minutes, muscles: muscles, sessions: sessions,
                                          extra: metrics.recentTrainingDays)
        return gym.planner.plan(focus: focus, minutes: minutes, recovery: metrics.recoveryForTraining, history: history,
                                block: block, focusReason: focusReason, prioritySlots: prioritySlots,
                                bodyMassKg: metrics.bodyMassKg, sex: metrics.sex,
                                trainingStatus: metrics.trainingStatus ?? .novice,
                                warmUpMinutes: warmUpMinutes,
                                exerciseFilter: exerciseFilter.isEmpty ? nil : exerciseFilter,
                                muscleSetGoals: goals,
                                // With the abs finisher on, it covers the core (no abs twice).
                                includeCore: effectiveFinisher == .off,
                                age: settings.ageIsSet ? settings.age : nil,
                                anchorOneRepMaxKg: LiftAnchorsStore.shared.anchors)
    }

    /// Exercises from this many days back count as recent, so the finisher
    /// rotates its moves across about a week of sessions (app choice).
    static let finisherRotationDays = 10

    /// The abs finisher for `plan`: moves the gym and the pain filter allow,
    /// none already in the plan, rotating away from recent ones. Nil when off
    /// (or skipped for a short session) or the plan is empty.
    func finisher(for plan: PlannedWorkout, gym: GymStore, sessions: [WorkoutSession],
                  history: [String: ExerciseHistory]) -> AbsFinisher.Plan? {
        guard !plan.exercises.isEmpty, effectiveFinisher != .off else { return nil }
        var planner = gym.planner
        planner.exerciseFilter = exerciseFilter
        return AbsFinisher.make(
            length: effectiveFinisher,
            planner: planner,
            history: history,
            recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions, days: Self.finisherRotationDays),
            excluding: Set(plan.exercises.map(\.exerciseID)),
            sessionRPE: plan.targetRPE,
            firstGroup: AbsFinisher.nextGroup(after: plan.exercises)
        )
    }
}
