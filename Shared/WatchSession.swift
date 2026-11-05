import Foundation

/// The live gym session as the Apple Watch sees it. The phone (`WatchSync`)
/// sends one whenever the session changes; the Watch shows it and sends
/// `WatchCommand`s back. Weights stay in kilograms; `unit` says how to show
/// them. Compiled into both the iPhone app and the Watch app.
nonisolated struct WatchSession: Codable, Sendable, Equatable {
    nonisolated struct SetSnapshot: Codable, Sendable, Equatable {
        var reps: Int
        var weightKg: Double
        var isCompleted: Bool
        var isWarmup: Bool
        /// The set's effort (planned, or logged once completed), 1-10.
        var rpe: Double?
    }

    nonisolated struct ExerciseSnapshot: Codable, Sendable, Equatable, Identifiable {
        /// Position in the workout (`ExerciseLog.order`).
        var id: Int
        var name: String
        /// "A1" / "A2" when the exercise is half of a superset.
        var supersetLabel: String?
        var sets: [SetSnapshot]
        /// Weights the gym can actually load for this exercise, in kg, ascending
        /// (a window around the planned weight). Empty or missing: step by
        /// `WatchSession.weightStepKg`.
        var achievableLoadsKg: [Double]?
    }

    /// Stable id for the session: its start time in whole seconds, the same
    /// key `SupersetRegistry` uses.
    var id: String
    var startedAt: Date
    var name: String
    var exercises: [ExerciseSnapshot]
    /// Index into `exercises` of the exercise with the next set to do.
    var currentExercise: Int?
    /// Index into that exercise's `sets`.
    var currentSet: Int?
    /// Rest after a set of the current exercise, in seconds.
    var restSeconds: Int
    /// When the phone's rest timer ends, if it's running.
    var restEndsAt: Date?
    /// "kg" or "lb": how the gym labels its plates.
    var unit: String
    /// True once the session was finished or discarded on the phone.
    var isFinished: Bool
    /// When the phone built this snapshot; older ones are ignored.
    var sentAt: Date
    /// Weight jump in kg when an exercise has no load list (2.5 kg, or 5 lb).
    var weightStepKg: Double?
    /// The movement warm-up before the first lift (`WarmUpRoutine` on the
    /// phone), when the session has one. Missing on older phones.
    var warmUp: [WatchWarmUpStep]?
    /// Index into `warmUp` of the current step; at or past its count once
    /// the warm-up is done or skipped.
    var warmUpStepIndex: Int?
    /// When the current step's countdown ends on the phone.
    var warmUpStepEndsAt: Date?

    static func id(for startedAt: Date) -> String {
        String(Int(startedAt.timeIntervalSince1970))
    }

    /// The phone session's start time, from its id (whole seconds).
    static func startDate(for id: String) -> Date? {
        Double(id).map { Date(timeIntervalSince1970: $0) }
    }

    /// Converts kilograms to the gym's unit.
    func display(_ kilograms: Double) -> Double {
        unit == "lb" ? kilograms * 2.20462 : kilograms
    }

    /// e.g. "60 kg" or "135 lb".
    func format(_ kilograms: Double) -> String {
        "\(display(kilograms).formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    var step: Double { weightStepKg ?? (unit == "lb" ? 5 / 2.20462 : 2.5) }

    var completedSets: Int {
        exercises.flatMap(\.sets).filter { $0.isCompleted && !$0.isWarmup }.count
    }

    var totalSets: Int {
        exercises.flatMap(\.sets).filter { !$0.isWarmup }.count
    }

    /// Index of the exercise with the next set to do (`currentExercise`, or
    /// the first one with a set left).
    var nextExerciseIndex: Int? {
        if let currentExercise, currentExercise < exercises.count { return currentExercise }
        return exercises.firstIndex { $0.sets.contains { !$0.isCompleted } }
    }

    /// The warm-up step to show, or nil when there's none left (or none at all).
    var currentWarmUpStep: WatchWarmUpStep? {
        guard let warmUp, let index = warmUpStepIndex, index >= 0, index < warmUp.count else { return nil }
        return warmUp[index]
    }

    var isWarmingUp: Bool { currentWarmUpStep != nil }

    /// The other half of a superset, by position in `exercises`.
    func partnerIndex(of index: Int) -> Int? {
        guard index < exercises.count, let label = exercises[index].supersetLabel, let group = label.first else { return nil }
        return exercises.indices.first { $0 != index && exercises[$0].supersetLabel?.first == group }
    }
}

/// One movement of the warm-up, as the Watch shows it.
nonisolated struct WatchWarmUpStep: Codable, Sendable, Equatable {
    var name: String
    var seconds: Int
    var cue: String
    /// e.g. "10 each side".
    var reps: String?
}

/// What the Watch asks the phone to do with the session.
nonisolated enum WatchCommand: Codable, Sendable, Equatable {
    /// Ticks off a set with what was actually done. `rpe` is nil when the effort step was skipped.
    case completeSet(exerciseIndex: Int, setIndex: Int, reps: Int, weightKg: Double, rpe: Double?)
    case skipRest
    /// Drops the current exercise's remaining sets so the next one is up.
    case nextExercise
    case pause
    case resume
    /// Opens the finish sheet on the phone, pre-filled with the session effort (1-10) if given.
    case finish(sessionRPE: Int?)
    /// The Watch began its HKWorkoutSession for the session: the Watch's workout is the record.
    case recordingStarted
    /// The Watch stopped without saving a workout (discarded or failed).
    case recordingStopped
    /// Next warm-up movement (the last one finishes the warm-up).
    case warmUpNext
    /// Finish or skip the warm-up and start lifting.
    case warmUpFinish
}

nonisolated struct WatchCommandMessage: Codable, Sendable, Equatable {
    /// The session the command is for (nil: whatever is active).
    var sessionID: String?
    var command: WatchCommand
    var sentAt: Date
}

/// What the phone asks the Watch to do with its recording.
nonisolated struct WatchRequest: Codable, Sendable, Equatable {
    nonisolated enum Kind: String, Codable, Sendable {
        case startRecording, stopRecording, discardRecording
    }

    var kind: Kind
    var sessionID: String
    var sentAt: Date
}

/// The workout the Watch saved to Apple Health, sent to the phone when it ends.
nonisolated struct WatchWorkoutSummary: Codable, Sendable, Equatable {
    var sessionID: String?
    /// The HKWorkout's UUID; nil when HealthKit didn't save one.
    var workoutUUID: UUID?
    var start: Date
    var end: Date
    var averageHeartRate: Double?
    var maximumHeartRate: Double?
    var activeKilocalories: Double?
    /// Whole-session effort (1-10) rated on the wrist, if it was.
    var sessionRPE: Int?

    var minutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
}

/// Keys in the WatchConnectivity dictionaries. Every value is JSON `Data` of
/// the matching type, so the delegate can decode it before hopping actors.
nonisolated enum WatchMessage {
    static let snapshot = "snapshot"
    static let command = "command"
    static let request = "request"
    static let summary = "summary"
    /// `WatchFaceData` for the complications (phone → Watch).
    static let faceData = "faceData"

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from payload: [String: Any], key: String) -> T? {
        guard let data = payload[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Effort choices shown on the wrist. The reps-left labels follow
/// `RPEScale.levels` in AppCore (6 → 4 left … 10 → none left); the
/// whole-session labels follow `RPEScale.sessionLabel`.
nonisolated struct WatchRPEChoice: Sendable, Identifiable, Equatable {
    let value: Int
    let label: String
    var id: Int { value }

    /// Per-set effort: 6-10 as reps in reserve.
    static let set: [WatchRPEChoice] = [
        WatchRPEChoice(value: 6, label: "4 left"),
        WatchRPEChoice(value: 7, label: "3 left"),
        WatchRPEChoice(value: 8, label: "2 left"),
        WatchRPEChoice(value: 9, label: "1 left"),
        WatchRPEChoice(value: 10, label: "Max"),
    ]

    /// Whole-session effort, 1-10.
    static let session: [WatchRPEChoice] = (1...10).map { WatchRPEChoice(value: $0, label: WatchRPEChoice.sessionLabel($0)) }

    /// Foster's CR-10 anchors, as `RPEScale.sessionLabel`, shortened to fit
    /// five buttons a row on the wrist ("very, very easy" → "Very easy",
    /// "somewhat hard" → "Fairly hard"; same meaning).
    static func sessionLabel(_ rpe: Int) -> String {
        switch rpe {
        case ...1: "Very easy"
        case 2: "Easy"
        case 3: "Moderate"
        case 4: "Fairly hard"
        case 5...6: "Hard"
        case 7...9: "Very hard"
        default: "Maximal"
        }
    }
}
