import Foundation

/// Small rules the live gym session applies on the phone: how a set ticked on
/// the Apple Watch (possibly queued while out of reach) lands, when a forgotten
/// workout is asked about, which order an added exercise gets, and how typed
/// numbers are read. Pure, so they can be tested; the app wires them up
/// (`WatchSync`, `ActiveWorkoutView`, `FinishWorkoutSheet`).
public enum LiveWorkoutRules {
    // MARK: Watch ticks

    /// The value a set gets from a Watch tick. `edited` says whether the wrist
    /// changed it from the snapshot it had (nil from older Watches, which sent
    /// no flags: then any value above zero wins, as before). An untouched value
    /// normally loses to the phone's, which may hold a newer edit, except when
    /// the only thing that moved the phone's value since the Watch's snapshot
    /// was the set-by-set change (`Autoregulation`) made by an earlier queued
    /// tick: the wrist never showed that change, so what was lifted is the
    /// Watch's value. `watchBase` is the value the Watch's snapshot had;
    /// `autoregulatedFrom` is this set's value before that change, if it made one.
    public static func tickedValue(phone: Double, watch: Double, watchBase: Double?, edited: Bool?,
                                   autoregulatedFrom: Double?) -> Double {
        tickedValue(phone: phone, watch: watch, watchBase: watchBase, edited: edited,
                    autoregulatedFromAny: autoregulatedFrom.map { [$0] } ?? [])
    }

    /// `tickedValue` when more than one set-by-set change moved the set since
    /// the Watch's snapshot (two queued ratings, each moving the rep goal):
    /// `autoregulatedFromAny` holds the value the set had before each of
    /// them. The Watch showed one of those, so matching any of them means the
    /// phone's value moved only by changes the wrist never saw.
    public static func tickedValue(phone: Double, watch: Double, watchBase: Double?, edited: Bool?,
                                   autoregulatedFromAny earlier: [Double]) -> Double {
        guard let edited else { return watch > 0 ? watch : phone }
        if edited { return max(0, watch) }
        if let watchBase, abs(phone - watchBase) >= 0.01,
           earlier.contains(where: { abs($0 - watchBase) < 0.01 }) {
            return max(0, watch)
        }
        return phone
    }

    /// When a Watch tick happened: when the Watch sent it (a queued command can
    /// arrive minutes later), never before the session started or in the future.
    public static func completedAt(sentAt: Date, sessionStart: Date, now: Date) -> Date {
        min(now, max(sessionStart, sentAt))
    }

    /// The rest still left after a set ticked at `sentAt`, for a rest of
    /// `seconds`; nil when it has (nearly) run out already, so a tick that
    /// arrives late doesn't start a full rest the lifter already took.
    public static func remainingRest(seconds: Double, sentAt: Date, now: Date) -> Double? {
        let left = seconds - max(0, now.timeIntervalSince(sentAt))
        return left > 1 ? left : nil
    }

    // MARK: Ending

    /// How long without a ticked set before a running workout is likely
    /// forgotten and the app asks "Still training?". App choice: no study sets
    /// this; gym sessions rarely run past 2 hours, so 4 hours without a single
    /// tick almost always means the Finish was missed.
    public static let forgottenAfter: TimeInterval = 4 * 3600

    /// True when the workout's last activity (its last tick, else its start)
    /// was `forgottenAfter` or longer ago.
    public static func isForgotten(start: Date, lastTick: Date?, now: Date) -> Bool {
        now.timeIntervalSince(max(start, lastTick ?? start)) >= forgottenAfter
    }

    /// The workout's end: when the Watch finished it (the phone may only hear
    /// later), or the last tick if sets were logged after that, else now.
    /// Never before the start or after now.
    public static func endDate(start: Date, watchFinishedAt: Date?, lastTick: Date?, now: Date) -> Date {
        guard let watchFinishedAt else { return now }
        let end = max(watchFinishedAt, lastTick ?? watchFinishedAt)
        return min(now, max(start, end))
    }

    // MARK: Pauses

    /// Seconds a workout has spent paused (Pause on the Apple Watch):
    /// finished pauses plus the one still running, which ends at `now`.
    public static func pausedSeconds(finished: TimeInterval, pausedSince: Date?, now: Date) -> TimeInterval {
        max(0, finished) + (pausedSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// The workout clock: time since the start without the pauses, so it
    /// stands still while paused and matches the Health workout the Watch
    /// records (HealthKit leaves paused time out of a workout's duration).
    public static func elapsed(start: Date, now: Date, pausedFinished: TimeInterval, pausedSince: Date?) -> TimeInterval {
        max(0, now.timeIntervalSince(start) - pausedSeconds(finished: pausedFinished, pausedSince: pausedSince, now: now))
    }

    // MARK: Supersets

    /// One half of a superset pair, for `partnerIsNext`.
    public struct SupersetHalf: Sendable, Equatable {
        /// Position in the workout: the lower one is the pair's first half (A1).
        public var order: Int
        /// Working sets ticked; warm-up ramp sets, drop stages and mini-sets don't count.
        public var roundsDone: Int
        public var hasOpenSet: Bool
        /// Its next open set is a drop stage or mini-set of the set just done.
        public var nextIsStage: Bool

        public init(order: Int, roundsDone: Int, hasOpenSet: Bool, nextIsStage: Bool = false) {
            self.order = order
            self.roundsDone = roundsDone
            self.hasOpenSet = hasOpenSet
            self.nextIsStage = nextIsStage
        }
    }

    /// After a set of one half of a superset is ticked: true when the
    /// partner's set comes next. The half that is a round behind goes next,
    /// the first half on a tie (A1 → A2 → A1), so a ticked warm-up ramp set
    /// (no round done yet) stays on its own lift's first working set, as the
    /// Apple Watch does (`WatchSession.upNext`). A drop stage or mini-set of
    /// the set just done comes before the partner.
    public static func partnerIsNext(ticked: SupersetHalf, partner: SupersetHalf) -> Bool {
        guard partner.hasOpenSet else { return false }
        guard ticked.hasOpenSet else { return true }
        if ticked.nextIsStage { return false }
        return ticked.order < partner.order
            ? ticked.roundsDone > partner.roundsDone
            : ticked.roundsDone >= partner.roundsDone
    }

    // MARK: Weights changed by hand

    /// A set as `indicesTakingWeight` reads it.
    public struct WeightSlot: Sendable, Equatable {
        public var weightKg: Double
        public var isCompleted: Bool
        public var isWarmup: Bool
        /// A drop stage or mini-set (`SetKind.isStage`).
        public var isStage: Bool

        public init(weightKg: Double, isCompleted: Bool = false, isWarmup: Bool = false, isStage: Bool = false) {
            self.weightKg = weightKg
            self.isCompleted = isCompleted
            self.isWarmup = isWarmup
            self.isStage = isStage
        }
    }

    /// The sets that take a weight changed by hand on the working set at
    /// `index`: the later working sets still to do that were at its old
    /// weight (`oldKg`, the plan's weight or 0 for a first-time lift), so the
    /// weight is typed once, not on every set. Sets at another weight are the
    /// lifter's own and stay; so do ticked sets, warm-up ramp sets and drop
    /// stages or mini-sets. None when the changed set is itself a warm-up or a stage.
    public static func indicesTakingWeight(changed index: Int, oldKg: Double, in sets: [WeightSlot]) -> [Int] {
        guard sets.indices.contains(index), !sets[index].isWarmup, !sets[index].isStage else { return [] }
        return sets.indices.filter { later in
            later > index && !sets[later].isCompleted && !sets[later].isWarmup && !sets[later].isStage
                && abs(sets[later].weightKg - oldKg) < 0.01
        }
    }

    // MARK: A set in words

    /// One set in words: "60 kg × 8" with a weight (`weight`: "60 kg" or
    /// "20 kg per hand"). With none: "Bodyweight × 8" for a lift that has no
    /// load to set, else "8 reps" (a loaded lift whose weight isn't in yet),
    /// never "0 kg × 8". For set rows, the rest bar and the Lock Screen.
    public static func setText(weight: String?, reps: Int, isBodyweight: Bool) -> String {
        if let weight { return "\(weight) × \(reps)" }
        if isBodyweight { return "Bodyweight × \(reps)" }
        return reps == 1 ? "1 rep" : "\(reps) reps"
    }

    /// A catalog lift done with no added load (push-ups, pull-ups). False
    /// outside the catalog, where nothing is known about the load.
    public static func isBodyweight(exerciseID: String) -> Bool {
        guard let exercise = ExerciseCatalog.exercise(id: exerciseID) else { return false }
        return exercise.load == nil
    }

    // MARK: Orders

    /// The order for an exercise added to a session: one past every order the
    /// session has used, removed exercises included, so an added exercise
    /// never inherits a removed one's target, superset or queued Watch tick.
    public static func nextOrder(existing: [Int], highestUsed: Int?) -> Int {
        max(existing.max() ?? -1, highestUsed ?? -1) + 1
    }

    // MARK: Typing

    /// A typed weight or rep count: "62.5" or "62,5" (a comma decimal
    /// separator), surrounding spaces ignored. Nil for empty or not a number,
    /// so the value isn't changed while the field is being cleared.
    public static func parseNumber(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return max(0, value)
    }

    // MARK: Added exercises

    /// What an exercise added mid-session starts with, when the planner has no
    /// prescription for it (an exercise outside the catalog): last time's top
    /// weight × reps and set count (`ExerciseHistory`, in the gym's unit), so
    /// it doesn't start at 0 × 0. Without history, one empty set as before.
    public struct Prefill: Sendable, Equatable {
        public var sets: Int
        public var weight: Double
        public var reps: Int

        public init(sets: Int, weight: Double, reps: Int) {
            self.sets = sets
            self.weight = weight
            self.reps = reps
        }
    }

    /// `sets`: the planned set count to keep (a swap keeps the replaced
    /// exercise's); nil = last time's, else 3 (the planner's usual count) with history.
    public static func prefill(history: ExerciseHistory?, sets: Int? = nil) -> Prefill {
        guard let history, history.lastReps > 0 else { return Prefill(sets: max(1, sets ?? 1), weight: 0, reps: 0) }
        let count = sets ?? history.lastSets ?? 3
        return Prefill(sets: min(10, max(1, count)), weight: max(0, history.lastWeight), reps: history.lastReps)
    }
}

/// Bodyweight lifts in progress charts. Pull-ups, chin-ups and parallel-bar
/// dips raise the whole body, so their load is body mass plus any added
/// weight: the way pull-up 1RM is measured (Sánchez-Moreno et al., Int J
/// Sports Physiol Perform 2017). Push-ups, squats and lunges move only part of
/// it (about two-thirds for a push-up: Ebben et al., J Strength Cond Res
/// 2011), so they aren't given an estimated 1RM; their progress is in reps.
public enum BodyweightLoad {
    public static let wholeBodyExerciseIDs: Set<String> = ["Pullups", "Chin-Up", "Dips_-_Triceps_Version"]

    /// True for a pull-up, chin-up or dip, whose load counts body mass.
    public static func countsBodyMass(exerciseID: String) -> Bool {
        wholeBodyExerciseIDs.contains(exerciseID)
    }

    /// The load an estimated 1RM is worked out from: body mass + added weight
    /// for a whole-body lift when body mass is known, else the logged weight.
    public static func load(exerciseID: String, loggedKg: Double, bodyMassKg: Double?) -> Double {
        guard countsBodyMass(exerciseID: exerciseID), let bodyMassKg, bodyMassKg > 0 else { return loggedKg }
        return bodyMassKg + max(0, loggedKg)
    }
}

/// "Swap exercise" during a workout: the planner's other options for the
/// same movement (`WorkoutPlanner.alternatives`: only what the gym supports
/// and can load, without never-again lifts or ones loading a 6+/10 painful
/// area, a pain regression first), and the swapped-in lift prescribed the way
/// the planner would (history, double progression, the pain cap).
public enum LiveSwap {
    /// The other options for the exercise's movement, best first, leaving out
    /// the exercise itself and any already in the session (`used`).
    public static func options(for exerciseID: String, planner: WorkoutPlanner, excluding used: Set<String> = []) -> [CatalogExercise] {
        guard let slot = ExerciseCatalog.slot(for: exerciseID) else { return [] }
        return planner.alternatives(for: slot).filter { $0.id != exerciseID && !used.contains($0.id) }
    }

    /// Sets, reps, effort and load for an exercise added or swapped in
    /// mid-session; nil for one outside the catalog (`LiveWorkoutRules.prefill`
    /// covers those). `sets` keeps the replaced exercise's count; nil = the
    /// planner's usual count. The pain cap (`ExerciseFilter.capLoad`) applies.
    public static func prescription(for choice: CatalogExercise, planner: WorkoutPlanner, sets: Int? = nil,
                                    sessionRPE: Double, history: [String: ExerciseHistory],
                                    lifter: LoadEstimator.Lifter = .unknown) -> PlannedExercise? {
        guard let slot = ExerciseCatalog.slot(for: choice.id) else { return nil }
        var planned = planner.prescribe(choice, slot: slot, minutes: 60, sessionRPE: sessionRPE,
                                        history: history, lifter: lifter)
        if let sets { planned.sets = min(10, max(1, sets)) }
        planner.exerciseFilter?.capLoad(&planned, slot: slot, gym: planner.gym)
        return planned
    }

    /// An exercise outside the catalog (picked from the full library), started
    /// from last time (`LiveWorkoutRules.prefill`: top weight × reps, set count)
    /// at `rpe`, the session's target effort. Without history: one empty set,
    /// reps 0 (nothing to aim for, so the app saves no target for it).
    public static func prefilled(exerciseID: String, name: String, history: ExerciseHistory?, sets: Int? = nil,
                                 rpe: Double) -> PlannedExercise {
        let fill = LiveWorkoutRules.prefill(history: history, sets: sets)
        return PlannedExercise(exerciseID: exerciseID, name: name, sets: fill.sets, reps: fill.reps...fill.reps,
                               rpe: rpe, load: fill.weight > 0 ? fill.weight : nil, loadKind: nil, note: nil)
    }
}
