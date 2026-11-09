import Foundation

/// The end-of-block report's suggestions (`BlockReport.NextChange`) that you
/// chose to apply to the next block, in a form the planner and the weekly set
/// targets use until that block ends:
/// - **Sets per muscle**: added once to the muscle's target (`VolumeProgression`),
///   inside its caps (the goal's ceiling and what the week's sessions hold); the
///   ramp then builds on it. "+1 set for every muscle" works the same way.
/// - **Same volume**: each muscle is capped at the finished block's highest
///   weekly target for the whole block.
/// - **Rep range** for a stalled lift: replaces the style's range for that
///   exercise (`WorkoutPlanner.prescribe`).
/// - **Variation swap**: the new exercise is preferred over the stalled one
///   wherever the gym supports it and the pain log and never-again list allow
///   it (`WorkoutPlanner.alternatives`, `choose`).
///
/// Every one of these is an app choice built on the report's evidence
/// (`BlockReport`); the UI labels them "Applied from Block N report".
public struct NextBlockAdjustments: Codable, Sendable, Equatable {
    public struct RepRange: Codable, Sendable, Equatable {
        public var exerciseID: String
        public var name: String
        public var lower: Int
        public var upper: Int

        public init(exerciseID: String, name: String, reps: ClosedRange<Int>) {
            self.exerciseID = exerciseID
            self.name = name
            self.lower = reps.lowerBound
            self.upper = max(reps.lowerBound, reps.upperBound)
        }

        public var reps: ClosedRange<Int> { lower...max(lower, upper) }
    }

    public struct Swap: Codable, Sendable, Equatable {
        public var fromID: String
        public var fromName: String
        public var toID: String
        public var toName: String

        public init(fromID: String, fromName: String, toID: String, toName: String) {
            self.fromID = fromID
            self.fromName = fromName
            self.toID = toID
            self.toName = toName
        }
    }

    /// The finished block's number ("Block 3 report").
    public var sourceNumber: Int
    /// The finished block's start (`BlockArchive.start`).
    public var sourceStart: Date
    /// Start of the block these apply to; they end with it.
    public var blockStart: Date
    public var appliedAt: Date
    /// Muscle (raw value) → sets a week added.
    public var setOffsets: [String: Int]
    /// Sets a week added to every muscle ("Start each muscle 1 set a week higher").
    public var everyMuscle: Int
    /// "Same volume next block".
    public var holdVolume: Bool
    /// Muscle (raw value) → the finished block's highest weekly target, for `holdVolume`.
    public var holdCeilings: [String: Int]
    public var repRanges: [RepRange]
    public var swaps: [Swap]
    /// The week whose set targets first took the offsets; nil until a week
    /// has (`markingOffsets`). Later weeks build on that week's targets.
    public var offsetsWeek: Date?
    /// Left by an undo after a week already took the offsets: takes them
    /// back off once, then goes (`undone`). Changes nothing else.
    public var isUndo: Bool

    public init(sourceNumber: Int, sourceStart: Date, blockStart: Date, appliedAt: Date, setOffsets: [String: Int] = [:],
                everyMuscle: Int = 0, holdVolume: Bool = false, holdCeilings: [String: Int] = [:],
                repRanges: [RepRange] = [], swaps: [Swap] = [], offsetsWeek: Date? = nil, isUndo: Bool = false) {
        self.sourceNumber = sourceNumber
        self.sourceStart = sourceStart
        self.blockStart = blockStart
        self.appliedAt = appliedAt
        self.setOffsets = setOffsets
        self.everyMuscle = everyMuscle
        self.holdVolume = holdVolume
        self.holdCeilings = holdCeilings
        self.repRanges = repRanges
        self.swaps = swaps
        self.offsetsWeek = offsetsWeek
        self.isUndo = isUndo
    }

    // MARK: Making

    /// The chosen suggestions (`chosen`: `NextChange.id`s) of a report.
    /// - Parameters:
    ///   - blockStart: the block they apply to (the one after the report's).
    ///   - finishedTargets: the finished block's weekly targets
    ///     (`BlockArchive.weeklyTargets`), for "same volume".
    public static func make(report: BlockReport.Report, chosen: Set<String>, sourceStart: Date, blockStart: Date,
                            finishedTargets: [[Muscle: Int]], now: Date = .now) -> NextBlockAdjustments {
        var result = NextBlockAdjustments(sourceNumber: report.number, sourceStart: sourceStart, blockStart: blockStart,
                                          appliedAt: now)
        func name(_ id: String) -> String { report.lifts.first { $0.exerciseID == id }?.name ?? id }
        for change in report.next where chosen.contains(change.id) {
            switch change.kind {
            case .addSets(let muscle, let sets):
                result.setOffsets[muscle.rawValue, default: 0] += sets
            case .volumeUp(let sets):
                result.everyMuscle += sets
            case .holdVolume:
                result.holdVolume = true
            case .repRange(let exerciseID, let reps):
                result.repRanges.removeAll { $0.exerciseID == exerciseID }
                result.repRanges.append(RepRange(exerciseID: exerciseID, name: name(exerciseID), reps: reps))
            case .swapExercise(let fromID, let toID, let toName):
                result.swaps.removeAll { $0.fromID == fromID }
                result.swaps.append(Swap(fromID: fromID, fromName: name(fromID), toID: toID, toName: toName))
            }
        }
        if result.holdVolume {
            for week in finishedTargets {
                for (muscle, sets) in week {
                    result.holdCeilings[muscle.rawValue] = max(result.holdCeilings[muscle.rawValue] ?? 0, sets)
                }
            }
        }
        return result
    }

    /// Nothing that would change the plan.
    public var isEmpty: Bool {
        setOffsets.values.allSatisfy { $0 == 0 } && everyMuscle == 0 && !holdVolume && repRanges.isEmpty && swaps.isEmpty
    }

    /// For the block starting `start` (same day).
    public func applies(toBlockStarting start: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(blockStart, inSameDayAs: start)
    }

    // MARK: Volume

    /// Sets a week added to (or, after an undo, taken off) a muscle.
    public func offset(for muscle: Muscle) -> Int {
        (setOffsets[muscle.rawValue] ?? 0) + everyMuscle
    }

    /// True until a week's targets have taken the offsets, and during that week.
    public func offsetsPending(weekStart: Date, calendar: Calendar = .current) -> Bool {
        guard let offsetsWeek else { return true }
        return calendar.isDate(offsetsWeek, inSameDayAs: weekStart)
    }

    /// What `VolumeProgression.week` uses for the week starting `weekStart`:
    /// the offsets while pending, and the "same volume" caps (each muscle's
    /// finished-block peak, plus any sets this report added to it).
    public func volume(weekStart: Date, calendar: Calendar = .current) -> VolumeProgression.Adjustment? {
        var adjustment = VolumeProgression.Adjustment()
        if offsetsPending(weekStart: weekStart, calendar: calendar) {
            for muscle in Muscle.allCases where offset(for: muscle) != 0 {
                adjustment.offsets[muscle] = offset(for: muscle)
            }
        }
        if holdVolume, !isUndo {
            for (raw, peak) in holdCeilings {
                guard let muscle = Muscle(rawValue: raw) else { continue }
                adjustment.ceilings[muscle] = peak + max(0, offset(for: muscle))
            }
        }
        return adjustment.isEmpty ? nil : adjustment
    }

    /// Notes that the week starting `weekStart` took the offsets (once).
    public func markingOffsets(weekStart: Date) -> NextBlockAdjustments {
        guard offsetsWeek == nil else { return self }
        var copy = self
        copy.offsetsWeek = weekStart
        return copy
    }

    /// Undo during the week starting `thisWeek`. When an earlier week already
    /// took the offsets, the targets since have built on them, so the undo
    /// leaves a record that takes the same sets back off once; otherwise
    /// nothing is left (nil) and this week's targets are worked out again.
    public func undone(thisWeek: Date, calendar: Calendar = .current) -> NextBlockAdjustments? {
        guard !isUndo, let offsetsWeek, !calendar.isDate(offsetsWeek, inSameDayAs: thisWeek), offsetsWeek < thisWeek,
              Muscle.allCases.contains(where: { offset(for: $0) != 0 }) else { return nil }
        return NextBlockAdjustments(
            sourceNumber: sourceNumber, sourceStart: sourceStart, blockStart: blockStart, appliedAt: appliedAt,
            setOffsets: setOffsets.mapValues { -$0 }, everyMuscle: -everyMuscle, isUndo: true
        )
    }

    // MARK: Planner

    /// "Block 3 report".
    public var label: String { "Block \(sourceNumber) report" }

    /// Rep ranges and variation swaps for `WorkoutPlanner.blockPreferences`; nil when there are none.
    public var plannerPreferences: WorkoutPlanner.BlockPreferences? {
        guard !isUndo, !(repRanges.isEmpty && swaps.isEmpty) else { return nil }
        var preferences = WorkoutPlanner.BlockPreferences()
        for range in repRanges {
            preferences.repRanges[range.exerciseID] = range.reps
            preferences.notes[range.exerciseID] = "\(range.lower)-\(range.upper) reps: applied from the \(label)"
        }
        for swap in swaps {
            preferences.swaps[swap.fromID] = swap.toID
            preferences.notes[swap.toID] = "In place of \(swap.fromName): applied from the \(label)"
        }
        return preferences
    }

    // MARK: Text

    /// One short line per change, for Past blocks and the Muscles page.
    public var summaryLines: [String] {
        guard !isUndo else { return [] }
        var lines: [String] = []
        for raw in setOffsets.keys.sorted() {
            guard let sets = setOffsets[raw], sets != 0 else { continue }
            let name = Muscle(rawValue: raw)?.name ?? raw
            lines.append("\(name) \(sets > 0 ? "+" : "−")\(abs(sets)) sets a week")
        }
        if everyMuscle != 0 { lines.append("Every muscle \(everyMuscle > 0 ? "+" : "−")\(abs(everyMuscle)) set a week") }
        if holdVolume { lines.append("Same volume as Block \(sourceNumber)") }
        for range in repRanges { lines.append("\(range.name): \(range.lower)-\(range.upper) reps") }
        for swap in swaps { lines.append("\(swap.toName) in place of \(swap.fromName)") }
        return lines
    }
}
