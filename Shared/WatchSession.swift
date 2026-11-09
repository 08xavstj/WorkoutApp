import Foundation

/// A workout's elapsed time: "4:07" under an hour, "1:04:07" after. The
/// same on the workout screen, the Today bar and the Apple Watch.
nonisolated func workoutElapsedText(_ seconds: TimeInterval) -> String {
    let whole = seconds.isFinite ? Int(max(0, seconds).rounded(.down)) : 0
    let pattern: Duration.TimeFormatStyle.Pattern = whole >= 3600 ? .hourMinuteSecond : .minuteSecond
    return Duration.seconds(whole).formatted(.time(pattern: pattern))
}

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
        /// Last session's same working set, for the ghost line under the
        /// target (`LiveSetCoach.watchSets`). All the fields below are
        /// optional so snapshots from older phones still decode.
        var lastWeightKg: Double? = nil
        var lastReps: Int? = nil
        var lastRPE: Double? = nil
        /// The plan's reps and reps in reserve for this set (`SessionTargets`).
        var targetReps: Int? = nil
        var targetRIR: Double? = nil
        /// A note from the phone for this set, e.g. the set-by-set load change
        /// ("Next set 62.5 kg (you had 3 in reserve)", `Autoregulation`).
        var note: String? = nil
        /// The set type's raw value (`SetKind` on the phone: "drop", "restPause",
        /// "myoRep", "failure"); nil for a straight set or an older phone.
        var kind: String? = nil
        /// For a drop stage or mini-set: the rest before it, in seconds (0 for a
        /// drop: the timer is skipped). Nil for a normal set, which rests as usual.
        var restBeforeSeconds: Int? = nil
        /// "Set 2 of 3", "Drop 1 of 2", "Warm-up 1 of 3", from the phone; nil on older phones.
        var title: String? = nil
        /// The set's stable id on the phone (`SetLog.order`), so a queued command
        /// still finds it after sets were added or removed. Nil on older phones.
        var order: Int? = nil

        /// A drop stage or mini-set that carries on from the set before it.
        var isStage: Bool { restBeforeSeconds != nil }

        /// "Last 60 kg × 8 · RPE 8", or nil without a matching set last time.
        func ghostLine(unit: String) -> String? {
            guard let lastReps, lastReps > 0, let lastWeightKg else { return nil }
            let value = unit == "lb" ? lastWeightKg * 2.20462 : lastWeightKg
            let weight = value.formatted(.number.precision(.fractionLength(0...1)))
            var line = lastWeightKg > 0 ? "Last \(weight) \(unit) × \(lastReps)" : "Last \(lastReps) reps"
            if let lastRPE { line += " · RPE \(lastRPE.formatted())" }
            return line
        }

        /// "Target 8 · 2 reps in the tank", "Target 8 · 2-3 reps in the tank" or "to failure",
        /// or nil without a plan (worded as the phone's `ReserveText` in AppCore,
        /// which the Watch doesn't compile).
        var targetLine: String? {
            guard targetReps != nil || targetRIR != nil else { return nil }
            var parts: [String] = []
            if let targetReps { parts.append("Target \(targetReps)") }
            if let targetRIR { parts.append(Self.reserveText(targetRIR)) }
            return parts.joined(separator: " · ")
        }

        /// "2 reps in the tank", "1 rep in the tank", "2-3 reps in the tank",
        /// "to failure"; rounded to the nearest half rep first (as `ReserveText.text`).
        static func reserveText(_ reserve: Double) -> String {
            let halves = (max(0, reserve) * 2).rounded() / 2
            let low = Int(halves.rounded(.down))
            let high = Int(halves.rounded(.up))
            if high == 0 { return "to failure" }
            if low == high { return low == 1 ? "1 rep in the tank" : "\(low) reps in the tank" }
            return "\(low)-\(high) reps in the tank"
        }

        /// The effort to pre-select after the set: 10 minus the target reps in
        /// reserve (`TrainingBlock.WeekState.targetRPE`), else the planned RPE; 6-10.
        var suggestedRPE: Int? {
            let value = targetRIR.map { 10 - $0 } ?? rpe
            guard let value else { return nil }
            return min(10, max(6, Int(value.rounded())))
        }
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
        /// Run the experimental rep counter: the setting is on and this is a barbell squat or deadlift (`RepDetection.supports`). Missing on older phones.
        var repCounting: Bool? = nil
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
    /// Records from the exercise just finished on the wrist (`SetFeedback`),
    /// sent for about a minute so the Watch can show them once. Missing on older phones.
    var records: WatchRecordNote?
    /// The movement warm-up before the first lift (`WarmUpRoutine` on the
    /// phone), when the session has one. Missing on older phones.
    var warmUp: [WatchWarmUpStep]?
    /// Index into `warmUp` of the current step; at or past its count once
    /// the warm-up is done or skipped.
    var warmUpStepIndex: Int?
    /// When the current step's countdown ends on the phone (timed steps only).
    var warmUpStepEndsAt: Date?
    /// False while the phone shows the warm-up overview ("Start warm-up");
    /// nil (older phones) counts as started.
    var warmUpStarted: Bool?
    /// The routine's planned length, for the overview.
    var warmUpMinutes: Int?
    /// Whether the Watch buzzes when rest ends (Settings › Rest timer alerts).
    /// nil (older phones) buzzes, as before.
    var restBuzz: Bool?

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

    /// Working sets; a drop set or rest-pause set counts once, not once per stage.
    var completedSets: Int {
        exercises.flatMap(\.sets).filter { $0.isCompleted && !$0.isWarmup && !$0.isStage }.count
    }

    var totalSets: Int {
        exercises.flatMap(\.sets).filter { !$0.isWarmup && !$0.isStage }.count
    }

    /// Index of the exercise with the next set to do (`currentExercise`, or
    /// the first one with a set left).
    var nextExerciseIndex: Int? {
        if let currentExercise, currentExercise < exercises.count { return currentExercise }
        return exercises.firstIndex { $0.sets.contains { !$0.isCompleted } }
    }

    /// The set that's up: the first exercise with a set left, or its superset
    /// partner once the first half is a round ahead (A1 done, A2 next), as
    /// the phone rests (none between the halves, `Supersets`). A drop stage or
    /// mini-set of the first half comes before the partner.
    func upNext() -> (exercise: Int, set: Int)? {
        guard let first = exercises.firstIndex(where: { $0.sets.contains { !$0.isCompleted } }) else { return nil }
        var index = first
        if let partner = partnerIndex(of: first), partner > first,
           exercises[partner].sets.contains(where: { !$0.isCompleted }),
           exercises[first].sets.first(where: { !$0.isCompleted })?.isStage != true,
           roundsDone(first) > roundsDone(partner) {
            index = partner
        }
        guard let set = exercises[index].sets.firstIndex(where: { !$0.isCompleted }) else { return nil }
        return (index, set)
    }

    /// Working sets ticked (a drop set or rest-pause set counts once).
    func roundsDone(_ index: Int) -> Int {
        exercises[index].sets.filter { $0.isCompleted && !$0.isWarmup && !$0.isStage }.count
    }

    /// Where a set is now, found by its stable ids (exercise `id`, set `order`),
    /// else by the positions it had (older phones send no set ids).
    func locate(exerciseID: Int, setOrder: Int?, exerciseIndex: Int, setIndex: Int) -> (exercise: Int, set: Int)? {
        let index: Int
        if exerciseIndex < exercises.count, exercises[exerciseIndex].id == exerciseID {
            index = exerciseIndex
        } else if let found = exercises.firstIndex(where: { $0.id == exerciseID }) {
            index = found
        } else {
            return nil
        }
        let sets = exercises[index].sets
        guard let setOrder else { return setIndex < sets.count ? (index, setIndex) : nil }
        if setIndex < sets.count, sets[setIndex].order == setOrder { return (index, setIndex) }
        return sets.firstIndex { $0.order == setOrder }.map { (index, $0) }
    }

    /// A key for one set that survives sets being added or removed on the
    /// phone ("exercise id-set id"; by position on older phones).
    func setKey(exercise index: Int, set setIndex: Int) -> String {
        guard index < exercises.count, setIndex < exercises[index].sets.count else { return "\(index)-\(setIndex)" }
        let exercise = exercises[index]
        return "\(exercise.id)-\(exercise.sets[setIndex].order ?? setIndex)"
    }

    /// The warm-up step to show, or nil when there's none left (or none at all).
    var currentWarmUpStep: WatchWarmUpStep? {
        guard let warmUp, let index = warmUpStepIndex, index >= 0, index < warmUp.count else { return nil }
        return warmUp[index]
    }

    var isWarmingUp: Bool { currentWarmUpStep != nil }

    /// True while the overview shows (before the first step is started).
    var isWarmUpOverview: Bool { isWarmingUp && warmUpStarted == false }

    /// The other half of a superset, by position in `exercises`.
    func partnerIndex(of index: Int) -> Int? {
        guard index < exercises.count, let label = exercises[index].supersetLabel, let group = label.first else { return nil }
        return exercises.indices.first { $0 != index && exercises[$0].supersetLabel?.first == group }
    }
}

/// Records from one exercise, as short lines ("Best estimated 1RM: 102 kg").
nonisolated struct WatchRecordNote: Codable, Sendable, Equatable {
    /// "<session id>-<exercise order>": the Watch shows each one once.
    var id: String
    var exercise: String
    var lines: [String]
}

/// One step of the warm-up, as the Watch shows it (`WarmUpRoutine.Step` on
/// the phone). Only the raise has `seconds`; drills are rep-based and
/// advance on tap. `dose` and `why` are optional so a snapshot from another
/// app version still decodes.
nonisolated struct WatchWarmUpStep: Codable, Sendable, Equatable {
    var name: String
    /// "10 each side", "15" or "90 s".
    var dose: String?
    var cue: String
    /// One line on what the step is for.
    var why: String?
    /// Countdown length for the timed step; nil for a rep step.
    var seconds: Int?

    var isTimed: Bool { seconds != nil }
}

/// What the Watch asks the phone to do with the session.
nonisolated enum WatchCommand: Codable, Sendable, Equatable {
    /// Ticks off a set with what was actually done. `rpe` is nil when the effort step was skipped.
    /// `exerciseOrder` / `setOrder` are the stable ids (`ExerciseLog.order`,
    /// `SetLog.order`) the phone looks the set up by; the indices are kept for
    /// older phones. `repsEdited` / `weightEdited`: whether the wrist changed
    /// the value from the snapshot it had, so an unchanged one doesn't overwrite
    /// an edit made on the phone meanwhile. All four are nil from older Watches
    /// (synthesized Codable decodes a missing optional as nil).
    case completeSet(exerciseIndex: Int, setIndex: Int, reps: Int, weightKg: Double, rpe: Double?,
                     exerciseOrder: Int? = nil, setOrder: Int? = nil, repsEdited: Bool? = nil, weightEdited: Bool? = nil)
    case skipRest
    /// +/- seconds on the rest timer from the wrist. Older phones can't decode
    /// it and drop the message; the Watch's own timer still moves.
    case adjustRest(seconds: Int)
    /// Sent by older Watches for "Skip exercise". The phone no longer deletes
    /// anything for it: the Watch moves on by itself, and Finish drops unticked sets.
    case nextExercise
    case pause
    case resume
    /// Opens the finish sheet on the phone, pre-filled with the session effort (1-10) if given.
    case finish(sessionRPE: Int?)
    /// The Watch began its HKWorkoutSession for the session: the Watch's workout is the record.
    case recordingStarted
    /// The Watch stopped without saving a workout (discarded or failed).
    case recordingStopped
    /// Next warm-up step (the last one finishes the warm-up; from the overview
    /// it starts). `fromStep`: the step the Watch was on, so a timed step that
    /// ends on both devices advances once; nil advances unconditionally.
    case warmUpNext(fromStep: Int?)
    /// Back one warm-up step (from the first, back to the overview).
    case warmUpBack
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
    /// three buttons a row on the wrist ("very, very easy" → "Very easy",
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
