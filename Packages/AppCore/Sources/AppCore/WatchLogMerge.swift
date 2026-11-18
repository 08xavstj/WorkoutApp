import Foundation

// How a lifting session logged on the Apple Watch alone (a plan sent ahead,
// or a quick lift with the phone out of reach) becomes a session on the
// phone (docs/research/watch-app-redesign-2026-11.md §4.4.8, §5). The phone
// (`WatchSync.apply`) reads the Watch's summary into these plain values and
// follows the plan this returns; the Watch's own types stay out of AppCore.
//
// Rules (app's choices, no study needed: this is bookkeeping):
// - Only completed sets count; an exercise with none is dropped; the Watch's
//   order is kept.
// - A phone session that shares enough time with the Watch's recording
//   (`WorkoutLinking.sessionIndex`: at least half of the shorter of the two)
//   is the same workout: the Watch's sets join it instead of making a second
//   session. They go into the open sets of the same exercise (by catalog id,
//   else by name) in order, and any extra sets are added after; an exercise
//   the phone session doesn't have is added at the end.

public nonisolated enum WatchLogMerge {
    /// One set from the Watch. Weights in kilograms.
    public nonisolated struct LoggedSet: Sendable, Equatable {
        public var reps: Int
        public var weightKg: Double
        public var rpe: Double?
        public var isWarmup: Bool
        public var isCompleted: Bool
        /// `SetKind.rawValue` ("drop", "restPause"...), nil for a straight set.
        public var kind: String?

        public init(reps: Int, weightKg: Double, rpe: Double? = nil, isWarmup: Bool = false,
                    isCompleted: Bool = true, kind: String? = nil) {
            self.reps = reps
            self.weightKg = weightKg
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.isCompleted = isCompleted
            self.kind = kind
        }
    }

    /// One exercise from the Watch.
    public nonisolated struct LoggedExercise: Sendable, Equatable {
        /// The catalog id (`ExerciseLog.exerciseID`); nil from a Watch that had none.
        public var catalogID: String?
        public var name: String
        public var sets: [LoggedSet]

        public init(catalogID: String?, name: String, sets: [LoggedSet]) {
            self.catalogID = catalogID
            self.name = name
            self.sets = sets
        }

        /// The id to store: the catalog's, else one made from the name, so
        /// the same unknown exercise always gets the same id.
        public var storedID: String {
            if let catalogID, !catalogID.isEmpty { return catalogID }
            let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            return "watch-" + String(slug)
        }
    }

    /// An exercise already in the phone's overlapping session.
    public nonisolated struct ExistingExercise: Sendable, Equatable {
        public var catalogID: String
        public var name: String
        /// How many of its sets are still open, in order.
        public var openSets: Int

        public init(catalogID: String, name: String, openSets: Int) {
            self.catalogID = catalogID
            self.name = name
            self.openSets = openSets
        }
    }

    /// What to do with one logged exercise.
    public nonisolated enum Action: Sendable, Equatable {
        /// Fill the first `fill.count` open sets of existing exercise `index`
        /// with these values, then add `extra` sets after its last.
        case merge(index: Int, fill: [LoggedSet], extra: [LoggedSet])
        /// Add the exercise to the session.
        case add(LoggedExercise)
    }

    /// Completed sets only, exercises with none dropped, order kept.
    public static func completed(_ exercises: [LoggedExercise]) -> [LoggedExercise] {
        exercises.compactMap { exercise in
            let done = exercise.sets.filter(\.isCompleted)
            guard !done.isEmpty else { return nil }
            return LoggedExercise(catalogID: exercise.catalogID, name: exercise.name, sets: done)
        }
    }

    /// Working sets logged (warm-ups don't count), for the session's title and checks.
    public static func workingSetCount(_ exercises: [LoggedExercise]) -> Int {
        exercises.reduce(0) { $0 + $1.sets.filter { $0.isCompleted && !$0.isWarmup }.count }
    }

    /// The overlapping phone session among `sessions`, if any (`WorkoutLinking`).
    public static func overlappingSession(for recording: DateInterval, sessions: [DateInterval]) -> Int? {
        WorkoutLinking.sessionIndex(for: recording, sessions: sessions)
    }

    /// How to join the Watch's sets to an overlapping phone session. Each
    /// existing exercise is matched at most once (the first that fits).
    public static func merge(_ logged: [LoggedExercise], into existing: [ExistingExercise]) -> [Action] {
        var used = Set<Int>()
        var actions: [Action] = []
        for exercise in completed(logged) {
            let match = existing.indices.first { index in
                !used.contains(index) && (existing[index].catalogID == exercise.storedID
                    || existing[index].name.caseInsensitiveCompare(exercise.name) == .orderedSame)
            }
            guard let index = match else {
                actions.append(.add(exercise))
                continue
            }
            used.insert(index)
            let open = max(0, existing[index].openSets)
            actions.append(.merge(index: index, fill: Array(exercise.sets.prefix(open)),
                                  extra: Array(exercise.sets.dropFirst(open))))
        }
        return actions
    }
}
