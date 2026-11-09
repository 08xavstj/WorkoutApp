import Foundation

/// The numbers on the end-of-workout summary: total weight lifted, sets and
/// reps, each exercise's best set and estimated 1RM, what changed since last
/// time, and how the week's sets per muscle moved. Weights are kilograms; the
/// app converts for display.
///
/// Evidence and honesty:
/// - Volume load (weight × reps, summed over working sets) is the standard
///   workload measure in resistance-training research (Scott BR, et al.
///   Training monitoring for resistance exercise: theory and applications.
///   Sports Med 2016;46:687–698). It is a description of the work done, not a
///   score: more isn't always better.
/// - Feedback on how a session compares with the last one supports
///   performance over a training cycle (Weakley J, et al. Sports Med 2023,
///   systematic review and meta-analysis), so changes are shown as plain
///   ▲/▼ facts, the way `SetFeedback` words them.
/// - Estimated 1RM is Epley with reps left from RPE (`OneRepMax`), about
///   ±3 kg from 3–5RM and less accurate past 10 reps (`LiftGoalProjection`).
/// - Weekly sets per muscle use the same counting and the same 10–20 hard
///   sets range as the rest of the app (`MuscleCoverage`; Schoenfeld, Ogborn
///   & Krieger, J Sports Sci 2017), or the training block's band when there is one.
/// - "Same kind of session", the rest estimate and the weight comparison are
///   app choices, not research; the UI words them as approximations.
public enum WorkoutSummary {
    // MARK: Input

    public struct LoggedSet: Sendable, Equatable {
        public var weightKg: Double
        public var reps: Int
        public var rpe: Double?
        public var isWarmup: Bool
        /// A drop stage or mini-set that continues the set before it (`SetKind.isStage`).
        public var isStage: Bool
        public var completedAt: Date?

        public init(weightKg: Double, reps: Int, rpe: Double? = nil, isWarmup: Bool = false,
                    isStage: Bool = false, completedAt: Date? = nil) {
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.isStage = isStage
            self.completedAt = completedAt
        }

        /// A ticked set that isn't a warm-up (drop stages included).
        public var isWorking: Bool { completedAt != nil && !isWarmup }

        public var estimatedOneRepMaxKg: Double {
            OneRepMax.estimate(weight: weightKg, reps: reps, rpe: rpe)
        }
    }

    public struct LoggedExercise: Sendable, Equatable {
        public var exerciseID: String
        public var name: String
        /// The sets in logged order.
        public var sets: [LoggedSet]

        public init(exerciseID: String, name: String, sets: [LoggedSet]) {
            self.exerciseID = exerciseID
            self.name = name
            self.sets = sets
        }

        var working: [LoggedSet] { sets.filter(\.isWorking) }
        /// Working sets without drop stages or mini-sets: one effortful set each.
        var effort: [LoggedSet] { working.filter { !$0.isStage } }
    }

    public struct LoggedSession: Sendable, Equatable {
        public var name: String
        public var start: Date
        public var end: Date
        /// In session order.
        public var exercises: [LoggedExercise]

        public init(name: String, start: Date, end: Date, exercises: [LoggedExercise]) {
            self.name = name
            self.start = start
            self.end = end
            self.exercises = exercises
        }

        public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
        var exerciseIDs: Set<String> {
            Set(exercises.filter { !$0.working.isEmpty }.map(\.exerciseID))
        }
    }

    // MARK: Totals

    public struct Totals: Sendable, Equatable {
        /// Σ weight × reps over working sets, drop stages included (as `WorkoutSession.totalVolumeKg`).
        public var volumeKg: Double
        /// Working sets, a drop or myo-rep set counted once.
        public var workingSets: Int
        public var reps: Int
        /// Exercises with at least one working set.
        public var exercises: Int
        public var duration: TimeInterval
        /// Typical time between ticked sets (`typicalRest`), nil when too few.
        public var typicalRest: TimeInterval?
    }

    public static func totals(_ session: LoggedSession) -> Totals {
        let working = session.exercises.flatMap(\.working)
        return Totals(
            volumeKg: volume(working),
            workingSets: working.filter { !$0.isStage }.count,
            reps: working.reduce(0) { $0 + max(0, $1.reps) },
            exercises: session.exercises.filter { !$0.working.isEmpty }.count,
            duration: session.duration,
            typicalRest: typicalRest(session)
        )
    }

    static func volume(_ sets: [LoggedSet]) -> Double {
        sets.reduce(0) { $0 + max(0, $1.weightKg) * Double(max(0, $1.reps)) }
    }

    /// Gaps shorter than this are a drop stage or a quick re-tick, not rest
    /// (app choice).
    static let shortestRest: TimeInterval = 10
    /// Gaps longer than this are a break or a machine change, not rest
    /// between sets (app choice; typical prescribed rests are 1–5 min).
    static let longestRest: TimeInterval = 10 * 60

    /// The median gap between consecutive ticked sets, the time a set
    /// takes included (sets only record when they were ticked). Gaps that
    /// end on a drop stage or mini-set are skipped (no rest is meant there).
    /// Nil with fewer than two usable gaps.
    public static func typicalRest(_ session: LoggedSession) -> TimeInterval? {
        let ticked = session.exercises.flatMap(\.sets)
            .compactMap { set in set.completedAt.map { (date: $0, isStage: set.isStage) } }
            .sorted { $0.date < $1.date }
        var gaps: [TimeInterval] = []
        for (previous, next) in zip(ticked, ticked.dropFirst()) where !next.isStage {
            let gap = next.date.timeIntervalSince(previous.date)
            if gap >= shortestRest, gap <= longestRest { gaps.append(gap) }
        }
        guard gaps.count >= 2 else { return nil }
        let sorted = gaps.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    // MARK: Per exercise

    /// Consecutive straight sets at the same weight and reps: "3 × 8 · 60 kg".
    public struct SetGroup: Sendable, Equatable {
        public var weightKg: Double
        public var reps: Int
        public var count: Int
    }

    public struct ExerciseResult: Sendable, Equatable, Identifiable {
        /// Position in the session, so an exercise done twice stays distinct.
        public var index: Int
        public var exerciseID: String
        public var name: String
        public var workingSets: Int
        /// Drop stages and mini-sets done after the working sets they belong to.
        public var stages: Int
        public var reps: Int
        public var volumeKg: Double
        public var groups: [SetGroup]
        /// Highest estimated 1RM (for a bodyweight lift, the most reps).
        public var bestSet: LoggedSet?
        /// From the best set; 0 for a bodyweight lift.
        public var estimatedOneRepMaxKg: Double
        public var id: Int { index }
    }

    /// Exercises with at least one working set, in session order.
    public static func exerciseResults(_ session: LoggedSession) -> [ExerciseResult] {
        session.exercises.enumerated().compactMap { index, exercise in
            result(exercise, index: index)
        }
    }

    static func result(_ exercise: LoggedExercise, index: Int) -> ExerciseResult? {
        let working = exercise.working
        guard !working.isEmpty else { return nil }
        let effort = exercise.effort
        let best = bestSet(effort.isEmpty ? working : effort)
        return ExerciseResult(
            index: index,
            exerciseID: exercise.exerciseID,
            name: exercise.name,
            workingSets: effort.count,
            stages: working.count - effort.count,
            reps: working.reduce(0) { $0 + max(0, $1.reps) },
            volumeKg: volume(working),
            groups: groups(effort),
            bestSet: best,
            estimatedOneRepMaxKg: best?.estimatedOneRepMaxKg ?? 0
        )
    }

    /// Highest e1RM, then heavier, then more reps; most reps when nothing is loaded.
    static func bestSet(_ sets: [LoggedSet]) -> LoggedSet? {
        let usable = sets.filter { $0.reps > 0 }
        return usable.max { a, b in
            let ea = a.estimatedOneRepMaxKg, eb = b.estimatedOneRepMaxKg
            if abs(ea - eb) > 0.01 { return ea < eb }
            if abs(a.weightKg - b.weightKg) > 0.01 { return a.weightKg < b.weightKg }
            return a.reps < b.reps
        }
    }

    static func groups(_ sets: [LoggedSet]) -> [SetGroup] {
        var result: [SetGroup] = []
        for set in sets {
            if let last = result.last, abs(last.weightKg - set.weightKg) < 0.01, last.reps == set.reps {
                result[result.count - 1].count += 1
            } else {
                result.append(SetGroup(weightKg: set.weightKg, reps: set.reps, count: 1))
            }
        }
        return result
    }

    // MARK: Change since last time

    /// What moved on from last time, the way a double-progression plan earns it.
    public enum Progression: Sendable, Equatable {
        /// The heaviest working weight went up by this much (kg).
        case heavier(kg: Double)
        /// Same top weight, this many more reps at it (all sets added).
        case moreReps(Int)
        /// Same weight and reps, more working sets.
        case moreSets(Int)
    }

    public struct Change: Sendable, Equatable {
        public var lastDate: Date
        /// Today's volume minus last time's, kg.
        public var volumeKg: Double
        /// Today's best e1RM minus last time's, kg; nil for a bodyweight lift.
        public var estimatedOneRepMaxKg: Double?
        public var progression: Progression?
    }

    /// The same exercise in the latest earlier session that has it (every
    /// log of it in that session joined), nil if none.
    public static func previous(exerciseID: String, before start: Date, in sessions: [LoggedSession]) -> (date: Date, exercise: LoggedExercise)? {
        let earlier = sessions
            .filter { $0.start < start }
            .sorted { $0.start > $1.start }
        for session in earlier {
            let logs = session.exercises.filter { $0.exerciseID == exerciseID }
            let sets = logs.flatMap(\.sets)
            guard let first = logs.first, sets.contains(where: \.isWorking) else { continue }
            return (session.start, LoggedExercise(exerciseID: exerciseID, name: first.name, sets: sets))
        }
        return nil
    }

    /// Today against last time. Nil when last time had no working sets.
    public static func change(today: LoggedExercise, last: LoggedExercise, lastDate: Date) -> Change? {
        let todayWorking = today.working, lastWorking = last.working
        guard !lastWorking.isEmpty, !todayWorking.isEmpty else { return nil }
        let todayBest = bestSet(today.effort.isEmpty ? todayWorking : today.effort)?.estimatedOneRepMaxKg ?? 0
        let lastBest = bestSet(last.effort.isEmpty ? lastWorking : last.effort)?.estimatedOneRepMaxKg ?? 0
        return Change(
            lastDate: lastDate,
            volumeKg: volume(todayWorking) - volume(lastWorking),
            estimatedOneRepMaxKg: todayBest > 0 && lastBest > 0 ? todayBest - lastBest : nil,
            progression: progression(today: today.effort, last: last.effort)
        )
    }

    static func progression(today: [LoggedSet], last: [LoggedSet]) -> Progression? {
        guard let topToday = today.map(\.weightKg).max(), let topLast = last.map(\.weightKg).max() else { return nil }
        if topToday > topLast + 0.01 { return .heavier(kg: topToday - topLast) }
        guard abs(topToday - topLast) <= 0.01 else { return nil }
        let repsToday = today.filter { abs($0.weightKg - topToday) <= 0.01 }.reduce(0) { $0 + $1.reps }
        let repsLast = last.filter { abs($0.weightKg - topLast) <= 0.01 }.reduce(0) { $0 + $1.reps }
        if repsToday > repsLast { return .moreReps(repsToday - repsLast) }
        if repsToday == repsLast, today.count > last.count { return .moreSets(today.count - last.count) }
        return nil
    }

    // MARK: The last session like this one

    /// Share of exercises two sessions must have in common to count as the
    /// same kind of session when the names differ (app choice; the session
    /// doesn't store its focus).
    public static let sameSessionOverlap = 0.5

    /// The latest earlier session of the same kind: the same name (other
    /// than the default "Workout") with at least one exercise in common, or half its exercises in common
    /// (Jaccard index ≥ `sameSessionOverlap`). Nil if none.
    public static func comparableSession(to session: LoggedSession, in sessions: [LoggedSession]) -> LoggedSession? {
        let ids = session.exerciseIDs
        guard !ids.isEmpty else { return nil }
        let name = normalized(session.name)
        return sessions
            .filter { $0.start < session.start }
            .sorted { $0.start > $1.start }
            .first { other in
                let otherIDs = other.exerciseIDs
                let shared = ids.intersection(otherIDs).count
                guard shared > 0 else { return false }
                let overlap = Double(shared) / Double(ids.union(otherIDs).count)
                // "Workout" is the default name of an unplanned session, not a kind.
                let sameName = name != "workout" && normalized(other.name) == name
                return sameName || overlap >= sameSessionOverlap
            }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public struct SessionChange: Sendable, Equatable {
        public var lastDate: Date
        public var volumeKg: Double
        public var duration: TimeInterval
    }

    public static func sessionChange(today: LoggedSession, last: LoggedSession) -> SessionChange {
        SessionChange(
            lastDate: last.start,
            volumeKg: totals(today).volumeKg - totals(last).volumeKg,
            duration: today.duration - last.duration
        )
    }

    // MARK: Muscles

    public struct MuscleLine: Sendable, Equatable, Identifiable {
        public enum Status: Sendable, Equatable {
            /// Reached the week's range with this session.
            case reached
            case inRange
            case below
            case above
        }

        public var muscle: Muscle
        /// Hard sets this session gave the muscle (helpers count half).
        public var sessionSets: Double
        public var weekBefore: Double
        public var weekAfter: Double
        public var target: ClosedRange<Int>
        public var status: Status
        public var id: Muscle { muscle }
    }

    /// The 10–20 weekly range (`MuscleCoverage.productiveRange`) as whole sets.
    public static var defaultTarget: ClosedRange<Int> {
        Int(MuscleCoverage.productiveRange.lowerBound)...Int(MuscleCoverage.productiveRange.upperBound)
    }

    /// Muscles this session trained (at least half a set), most sets first,
    /// with the week's count before and after it against the target band
    /// (the block's when given, else 10–20).
    public static func muscleLines(sessionSets: [Muscle: Double], weekBefore: [Muscle: Double],
                                   targets: [Muscle: ClosedRange<Int>] = [:]) -> [MuscleLine] {
        sessionSets
            .filter { $0.value >= 0.5 }
            .map { muscle, sets in
                let before = weekBefore[muscle] ?? 0
                let after = before + sets
                let target = targets[muscle] ?? defaultTarget
                let low = Double(target.lowerBound), high = Double(target.upperBound)
                let status: MuscleLine.Status
                if after.rounded() > high {
                    status = .above
                } else if after.rounded() >= low {
                    status = before.rounded() < low ? .reached : .inRange
                } else {
                    status = .below
                }
                return MuscleLine(muscle: muscle, sessionSets: sets, weekBefore: before, weekAfter: after,
                                  target: target, status: status)
            }
            .sorted { $0.sessionSets != $1.sessionSets ? $0.sessionSets > $1.sessionSets : $0.muscle.name < $1.muscle.name }
    }

    // MARK: Lift goals

    /// How far an estimated 1RM is toward a target, 0...1.
    public static func goalFraction(currentKg: Double, targetKg: Double) -> Double {
        guard targetKg > 0, currentKg > 0 else { return 0 }
        return min(1, currentKg / targetKg)
    }

    // MARK: A sense of scale

    /// A rough everyday comparison for the total, e.g. "About 3 small cars".
    public struct Comparison: Sendable, Equatable {
        public var text: String
    }

    /// Typical masses, rounded (app choice for a light touch, not data): a
    /// motorbike about 200 kg, a grand piano about 400 kg, a dairy cow about
    /// 650 kg, a small car about 1,000 kg, a hippo about 1,500 kg and an
    /// elephant about 5,000 kg.
    static let objects: [(kg: Double, one: String, many: String)] = [
        (200, "a motorbike", "motorbikes"),
        (400, "a grand piano", "grand pianos"),
        (650, "a dairy cow", "dairy cows"),
        (1_000, "a small car", "small cars"),
        (1_500, "a hippo", "hippos"),
        (5_000, "an elephant", "elephants"),
    ]

    /// The largest object the total reaches; nil under 200 kg.
    public static func comparison(volumeKg: Double) -> Comparison? {
        guard let object = objects.last(where: { volumeKg >= $0.kg }) else { return nil }
        let multiple = (volumeKg / object.kg).rounded()
        if multiple < 2 { return Comparison(text: "About the weight of \(object.one)") }
        return Comparison(text: "About \(Int(multiple)) \(object.many)")
    }
}
