import Foundation

/// Personal records over all time and per year: each lift's best estimated
/// 1RM, heaviest weight, most reps at a weight and best session volume, with
/// the date, plus every record as it was set (for the month-by-month timeline).
///
/// Rules match the records after an exercise (`SetFeedback.records`): only
/// ticked working sets, no warm-ups, no drop stages or mini-sets (they are
/// lighter or fatigued by design); no record on a lift's first session, since
/// there is nothing to beat yet. Records are reported as plain facts:
/// feedback on performance helps over a training cycle (Weakley et al.,
/// Sports Med 2023), celebrating them is not training (behaviour-change.md).
/// The e1RM is Epley with reps left from RPE (`OneRepMax`), an estimate.
///
/// Bodyweight lifts (no load logged, weight 0) get rep records; with a belt
/// or vest the logged weight is the added weight, and the heaviest added
/// weight is a record. Their e1RM and volume aren't shown, since the logged
/// weight leaves out the body. Dumbbell weights are per hand (`Traits.isPerHand`).
/// "Heaviest weight" and the top-lifts order are app choices, not research.
public enum PRHistory {
    public struct Traits: Sendable, Equatable {
        /// Body weight is the load (pull-ups, dips, push-ups).
        public var isBodyweight: Bool
        /// Dumbbells and kettlebells: the weight is per hand.
        public var isPerHand: Bool

        public init(isBodyweight: Bool = false, isPerHand: Bool = false) {
            self.isBodyweight = isBodyweight
            self.isPerHand = isPerHand
        }
    }

    /// Weights in kilograms.
    public enum Record: Sendable, Equatable, Hashable {
        case estimatedOneRepMax(Double)
        /// Heaviest weight lifted for at least one rep (added weight on a bodyweight lift).
        case heaviest(weight: Double, reps: Int)
        /// Most reps at this weight or heavier; weight 0 is body weight.
        case reps(weight: Double, reps: Int)
        /// Most weight × reps in one session.
        case volume(Double)
    }

    public struct Event: Sendable, Equatable, Identifiable {
        public var exerciseID: String
        public var name: String
        public var date: Date
        public var record: Record
        public var id: String { "\(exerciseID)|\(date.timeIntervalSinceReferenceDate)|\(record)" }
    }

    /// A best within a period, with the set behind it.
    public struct Best: Sendable, Equatable {
        /// e1RM or volume (kg); for weight and reps bests, the weight.
        public var value: Double
        public var weightKg: Double
        public var reps: Int
        public var date: Date
    }

    public struct ExerciseBests: Sendable, Equatable, Identifiable {
        public var exerciseID: String
        public var name: String
        public var traits: Traits
        /// Nil for a bodyweight lift.
        public var estimatedOneRepMax: Best?
        /// Nil when nothing was loaded.
        public var heaviest: Best?
        /// Rep maxes: the most reps at each weight that no heavier weight
        /// matched, heaviest first ("8 at 60 kg, 12 at 50 kg").
        public var repMaxes: [Best]
        /// Nil for a bodyweight lift.
        public var volume: Best?
        public var sessions: Int
        public var lastDate: Date
        /// Records set in the period (sessions with at least one).
        public var recordSessions: Int
        public var id: String { exerciseID }
    }

    // MARK: Sets

    static func sets(_ exercise: WorkoutSummary.LoggedExercise) -> [LiftProgress.LoggedSet] {
        BlockReport.effortSets(exercise).map { LiftProgress.LoggedSet(weight: max(0, $0.weightKg), reps: $0.reps, rpe: $0.rpe) }
    }

    /// Per exercise, every finished session's sets (all logs of it joined), oldest first.
    static func history(_ sessions: [WorkoutSummary.LoggedSession])
        -> [String: (name: String, sessions: [LiftProgress.LoggedSession])] {
        var result: [String: (name: String, sessions: [LiftProgress.LoggedSession])] = [:]
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            var byID: [String: [LiftProgress.LoggedSet]] = [:]
            var order: [String] = []
            var names: [String: String] = [:]
            for exercise in session.exercises {
                if byID[exercise.exerciseID] == nil { order.append(exercise.exerciseID) }
                byID[exercise.exerciseID, default: []] += sets(exercise)
                names[exercise.exerciseID] = exercise.name
            }
            for id in order {
                guard let sets = byID[id], !sets.isEmpty else { continue }
                let logged = LiftProgress.LoggedSession(date: session.start, sets: sets)
                result[id, default: (name: names[id] ?? id, sessions: [])].sessions.append(logged)
            }
        }
        return result
    }

    // MARK: Events

    /// Every record as it was set, oldest first.
    public static func events(_ sessions: [WorkoutSummary.LoggedSession], traits: [String: Traits] = [:]) -> [Event] {
        var result: [Event] = []
        for (id, entry) in history(sessions) {
            let bodyweight = traits[id]?.isBodyweight ?? false
            for index in entry.sessions.indices where index > 0 {
                let today = entry.sessions[index]
                let earlier = Array(entry.sessions[..<index])
                for record in records(today: today.sets, earlier: earlier, bodyweight: bodyweight) {
                    result.append(Event(exerciseID: id, name: entry.name, date: today.date, record: record))
                }
            }
        }
        return result.sorted { $0.date != $1.date ? $0.date < $1.date : $0.exerciseID < $1.exerciseID }
    }

    /// `SetFeedback.records` plus the heaviest weight; no e1RM or volume for a bodyweight lift.
    static func records(today: [LiftProgress.LoggedSet], earlier: [LiftProgress.LoggedSession], bodyweight: Bool) -> [Record] {
        var result: [Record] = []
        for record in SetFeedback.records(today: today, earlier: earlier) {
            switch record {
            case let .estimatedOneRepMax(value):
                if !bodyweight { result.append(.estimatedOneRepMax(value)) }
            case let .reps(weight, reps):
                result.append(.reps(weight: weight, reps: reps))
            case let .volume(value):
                if !bodyweight { result.append(.volume(value)) }
            }
        }
        let done = today.filter { $0.reps > 0 }
        let past = earlier.flatMap(\.sets).filter { $0.reps > 0 }
        if !past.isEmpty, let top = done.max(by: { $0.weight != $1.weight ? $0.weight < $1.weight : $0.reps < $1.reps }),
           top.weight > 0, top.weight > (past.map(\.weight).max() ?? 0) + 0.01 {
            result.append(.heaviest(weight: top.weight, reps: top.reps))
        }
        return result
    }

    // MARK: Bests in a period

    /// Each lift's bests among sessions in `interval` (nil: all time), top
    /// lifts first (`rank`), then the most sessions. `events` (from
    /// `events(_:traits:)`) count the records set in the period.
    public static func bests(_ sessions: [WorkoutSummary.LoggedSession], traits: [String: Traits] = [:],
                             in interval: DateInterval?, events: [Event]) -> [ExerciseBests] {
        let inPeriod = { (date: Date) in interval.map { date >= $0.start && date < $0.end } ?? true }
        var result: [ExerciseBests] = []
        for (id, entry) in history(sessions) {
            let logged = entry.sessions.filter { inPeriod($0.date) }
            guard let last = logged.last else { continue }
            let trait = traits[id] ?? Traits()
            let recordDays = Set(events.filter { $0.exerciseID == id && inPeriod($0.date) }.map(\.date)).count
            result.append(ExerciseBests(
                exerciseID: id, name: entry.name, traits: trait,
                estimatedOneRepMax: trait.isBodyweight ? nil : bestOneRepMax(logged),
                heaviest: heaviest(logged),
                repMaxes: repMaxes(logged),
                volume: trait.isBodyweight ? nil : bestVolume(logged),
                sessions: logged.count, lastDate: last.date, recordSessions: recordDays
            ))
        }
        return result.sorted { a, b in
            let ra = rank(exerciseID: a.exerciseID, name: a.name), rb = rank(exerciseID: b.exerciseID, name: b.name)
            if ra != rb { return ra < rb }
            if a.sessions != b.sessions { return a.sessions > b.sessions }
            return a.name < b.name
        }
    }

    /// The first session to reach the highest e1RM; nil when nothing was loaded.
    static func bestOneRepMax(_ sessions: [LiftProgress.LoggedSession]) -> Best? {
        var best: Best?
        for session in sessions {
            for set in session.sets {
                let e1RM = OneRepMax.estimate(weight: set.weight, reps: set.reps, rpe: set.rpe)
                if e1RM > (best?.value ?? 0) + 0.01 {
                    best = Best(value: e1RM, weightKg: set.weight, reps: set.reps, date: session.date)
                }
            }
        }
        return best
    }

    /// Heaviest weight (more reps breaks a tie); nil when nothing was loaded.
    static func heaviest(_ sessions: [LiftProgress.LoggedSession]) -> Best? {
        var best: Best?
        for session in sessions {
            for set in session.sets where set.weight > 0 {
                let heavier = set.weight > (best?.weightKg ?? 0) + 0.01
                let moreReps = abs(set.weight - (best?.weightKg ?? 0)) <= 0.01 && set.reps > (best?.reps ?? 0)
                if heavier || moreReps {
                    best = Best(value: set.weight, weightKg: set.weight, reps: set.reps, date: session.date)
                }
            }
        }
        return best
    }

    /// Most reps at each weight, keeping only weights where no heavier
    /// weight got as many reps; heaviest first. The first time a count was
    /// reached is its date.
    static func repMaxes(_ sessions: [LiftProgress.LoggedSession]) -> [Best] {
        var byWeight: [Int: Best] = [:]
        for session in sessions {
            for set in session.sets {
                let key = Int((set.weight * 100).rounded())
                if set.reps > (byWeight[key]?.reps ?? 0) {
                    byWeight[key] = Best(value: set.weight, weightKg: set.weight, reps: set.reps, date: session.date)
                }
            }
        }
        var frontier: [Best] = []
        for best in byWeight.values.sorted(by: { $0.weightKg > $1.weightKg }) {
            if best.reps > (frontier.map(\.reps).max() ?? 0) { frontier.append(best) }
        }
        return frontier
    }

    /// The session with the most weight × reps; nil at 0.
    static func bestVolume(_ sessions: [LiftProgress.LoggedSession]) -> Best? {
        var best: Best?
        for session in sessions {
            let volume = session.sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
            if volume > (best?.value ?? 0) + 0.01 {
                let top = session.sets.max { $0.weight < $1.weight }
                best = Best(value: volume, weightKg: top?.weight ?? 0, reps: top?.reps ?? 0, date: session.date)
            }
        }
        return best
    }

    // MARK: Order

    /// The big lifts first: bench, squat, deadlift, overhead press, row,
    /// pull-up (the main barbell ID of each first, then its variations),
    /// everything else after (app choice).
    static let topLifts: [(id: String, words: [String])] = [
        ("Barbell_Bench_Press_-_Medium_Grip", ["bench press"]),
        ("Barbell_Squat", ["squat"]),
        ("Barbell_Deadlift", ["deadlift"]),
        ("Standing_Military_Press", ["overhead press", "military press", "shoulder press"]),
        ("Bent_Over_Barbell_Row", ["row", "rows"]),
        ("Pullups", ["pull-up", "pull-ups", "pullup", "pullups", "chin-up", "chin-ups"]),
    ]

    /// 0, 1 for bench (main, variation), 2, 3 for squat … 100 for others.
    public static func rank(exerciseID: String, name: String) -> Int {
        let lower = name.lowercased()
        let words = Set(lower.split { !$0.isLetter && $0 != "-" }.map(String.init))
        for (index, lift) in topLifts.enumerated() {
            if exerciseID == lift.id { return index * 2 }
            let matches = lift.words.contains { word in
                word.contains(" ") ? lower.contains(word) : words.contains(word)
            }
            if matches { return index * 2 + 1 }
        }
        return 100
    }

    // MARK: Periods

    public enum Period: Hashable, Sendable, Identifiable {
        case thisYear, last12Months, allTime
        case year(Int)

        public var id: String { title }

        public var title: String {
            switch self {
            case .thisYear: "This year"
            case .last12Months: "Last 12 months"
            case .allTime: "All time"
            case let .year(year): String(year)
            }
        }

        /// Nil for all time.
        public func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
            switch self {
            case .allTime:
                return nil
            case .thisYear:
                return yearInterval(calendar.component(.year, from: now), calendar: calendar)
            case .last12Months:
                let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
                return DateInterval(start: start, end: now.addingTimeInterval(1))
            case let .year(value):
                return yearInterval(value, calendar: calendar)
            }
        }

        private func yearInterval(_ value: Int, calendar: Calendar) -> DateInterval? {
            guard let start = calendar.date(from: DateComponents(year: value, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// This year, last 12 months, all time, then each earlier year with a
    /// session, newest first.
    public static func periods(_ sessions: [WorkoutSummary.LoggedSession], now: Date = .now,
                               calendar: Calendar = .current) -> [Period] {
        let thisYear = calendar.component(.year, from: now)
        let years = Set(sessions.map { calendar.component(.year, from: $0.start) }).filter { $0 < thisYear }
        return [.thisYear, .last12Months, .allTime] + years.sorted(by: >).map { Period.year($0) }
    }

    // MARK: Timeline

    public struct MonthCount: Sendable, Equatable, Identifiable {
        /// First day of the month.
        public var month: Date
        /// Lift sessions with at least one record that month.
        public var count: Int
        public var id: Date { month }
    }

    /// Records per month across the period, every month shown (zeros too),
    /// up to the month containing `now`. All time starts at the first record.
    /// One session's records on one lift count once, so a single big set
    /// doesn't count as four.
    public static func timeline(_ events: [Event], interval: DateInterval?, now: Date = .now,
                                calendar: Calendar = .current) -> [MonthCount] {
        let inPeriod = events.filter { event in interval.map { event.date >= $0.start && event.date < $0.end } ?? true }
        let monthOf = { (date: Date) in calendar.dateInterval(of: .month, for: date)?.start ?? date }
        guard let first = interval.map({ monthOf($0.start) }) ?? inPeriod.first.map({ monthOf($0.date) }) else { return [] }
        let lastDate = min(interval.map { $0.end.addingTimeInterval(-1) } ?? now, now)
        let last = monthOf(lastDate)
        var counts: [Date: Set<String>] = [:]
        for event in inPeriod {
            counts[monthOf(event.date), default: []].insert("\(event.exerciseID)|\(event.date.timeIntervalSinceReferenceDate)")
        }
        var result: [MonthCount] = []
        var cursor = first
        while cursor <= last, result.count < 600 {
            result.append(MonthCount(month: cursor, count: counts[cursor]?.count ?? 0))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}
