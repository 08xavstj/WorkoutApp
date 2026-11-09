import Foundation

/// The end-of-block report: what a finished training block (`TrainingBlock`,
/// deload week included) did, and what the next block changes.
///
/// Evidence and honesty:
/// - Weeks kept use the same rule as the rolling score (`Consistency`, 3 of 4
///   planned sessions; docs/research/behaviour-change.md rec. 4).
/// - Volume load is weight × reps over working sets (Scott et al., Sports Med
///   2016), drop stages included, as `WorkoutSummary.totals`. It describes the
///   work; more isn't always better.
/// - Lift change compares the best estimated 1RM (`OneRepMax`, Epley with reps
///   left from RPE) of the first two weeks with the last two working weeks
///   (the deload is left out: its loads are lighter by design, Bell et al.,
///   Sports Med Open 2023). Drop stages and warm-ups are left out, as in
///   `SetFeedback`. The e1RM is about ±3 kg from 3-5RM sets, so a change
///   under `stallFraction` is read as "no clear change", not as a loss.
/// - Hard sets per muscle per week use `MuscleCoverage.setsThisWeek` (helpers
///   half, easy sets 0.6, a cluster its `SetStructure.hardSetCredit`) against
///   the block's own weekly targets (`VolumeProgression`) or 10-20 without them
///   (Schoenfeld, Ogborn & Krieger, J Sports Sci 2017; Pelland et al., Sports
///   Med 2026).
/// - The next-block rules are app choices built on that evidence, and every
///   one is labelled as such in `NextChange.isAppChoice` and in the UI:
///   more sets for a muscle under target (dose-response, Schoenfeld 2017;
///   diminishing returns past ~20, Pelland 2026); for a stalled lift, a
///   heavier rep range for a strength goal (heavy loads favour 1RM,
///   Schoenfeld et al., J Strength Cond Res 2017) or a variation swap
///   (some variation spreads regional growth, Kassiano et al., J Strength Cond
///   Res 2022; adding reps or load progress about equally, Plotkin et al.,
///   PeerJ 2022); and a planned change of the training stimulus between blocks
///   (Ratamess/Kraemer et al., ACSM position stand, Med Sci Sports Exerc 2009).
public enum BlockReport {
    // MARK: Input

    /// What an exercise trains, as the library names it ("chest", "middle back").
    public struct ExerciseMuscles: Sendable, Equatable {
        public var primary: [String]
        public var secondary: [String]

        public init(primary: [String], secondary: [String] = []) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    public struct Input: Sendable {
        /// 1-based block number, for the title.
        public var number: Int
        /// Monday the block began.
        public var start: Date
        /// The Monday after its last week (exclusive).
        public var end: Date
        /// Planned weeks, deload included.
        public var length: Int
        /// True when the block reached its planned easier week.
        public var hadDeload: Bool
        public var style: TrainingStyle
        /// Planned and done sessions for each week of the block.
        public var weeks: [WeekRecord]
        /// Finished sessions (any dates; the block's are picked out).
        public var sessions: [WorkoutSummary.LoggedSession]
        /// The previous block's dates, for the volume comparison.
        public var previous: DateInterval?
        /// Muscles per exercise ID; exercises not listed add no muscle sets.
        public var muscles: [String: ExerciseMuscles]
        /// Weekly hard-set targets per muscle for the block's working weeks
        /// (`VolumeProgression.Target.sets`), averaged here; empty means 10-20.
        public var weeklyTargets: [[Muscle: Int]]
        /// Optional: daily body weight in kg.
        public var bodyWeightKg: [DayValue]
        /// Optional: nightly HRV in ms.
        public var hrv: [DayValue]
        /// Optional: alternatives the user's gym supports, per exercise ID
        /// (`WorkoutPlanner.alternatives(for:)`); nil uses the catalog.
        public var alternatives: [String: [CatalogExercise]]?
        /// Bodyweight and per-hand lifts (`PRHistory.Traits`), for the records.
        public var traits: [String: PRHistory.Traits]

        public init(number: Int, start: Date, end: Date, length: Int, hadDeload: Bool, style: TrainingStyle,
                    weeks: [WeekRecord], sessions: [WorkoutSummary.LoggedSession], previous: DateInterval? = nil,
                    muscles: [String: ExerciseMuscles] = [:], weeklyTargets: [[Muscle: Int]] = [],
                    bodyWeightKg: [DayValue] = [], hrv: [DayValue] = [],
                    alternatives: [String: [CatalogExercise]]? = nil, traits: [String: PRHistory.Traits] = [:]) {
            self.number = number
            self.start = start
            self.end = end
            self.length = length
            self.hadDeload = hadDeload
            self.style = style
            self.weeks = weeks
            self.sessions = sessions
            self.previous = previous
            self.muscles = muscles
            self.weeklyTargets = weeklyTargets
            self.bodyWeightKg = bodyWeightKg
            self.hrv = hrv
            self.alternatives = alternatives
            self.traits = traits
        }
    }

    // MARK: Output

    public struct LiftChange: Sendable, Equatable, Identifiable {
        public var exerciseID: String
        public var name: String
        /// Bodyweight lift (no load logged): the numbers are reps, not kg.
        public var isBodyweight: Bool
        /// Best e1RM (kg) or most reps in the first two weeks.
        public var start: Double
        /// The same over the last two working weeks.
        public var end: Double
        /// (end − start) ÷ start.
        public var change: Double
        /// Best e1RM (or reps) per session in the block, oldest first, for a sparkline.
        public var points: [DayValue]
        /// Under `stallFraction`.
        public var isStalled: Bool
        public var id: String { exerciseID }
    }

    public struct BlockRecord: Sendable, Equatable, Identifiable {
        public var exerciseID: String
        public var name: String
        public var date: Date
        /// In kilograms.
        public var record: PRHistory.Record
        public var id: String { "\(exerciseID)|\(date.timeIntervalSinceReferenceDate)|\(record)" }
    }

    public struct MuscleLine: Sendable, Equatable, Identifiable {
        public enum Status: Sendable, Equatable { case under, inRange, over }
        public var muscle: Muscle
        /// Average hard sets a working week (deload left out).
        public var averageSets: Double
        public var target: ClosedRange<Int>
        public var status: Status
        public var id: Muscle { muscle }
    }

    public struct Trend: Sendable, Equatable {
        /// Average of the block's first 7 days with data, and of its last 7.
        public var start: Double
        public var end: Double
        public var change: Double { end - start }
        public var fraction: Double { start > 0 ? (end - start) / start : 0 }
    }

    public struct NextChange: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable {
            case addSets(Muscle, sets: Int)
            case swapExercise(fromID: String, toID: String, toName: String)
            case repRange(exerciseID: String, reps: ClosedRange<Int>)
            case volumeUp(sets: Int)
            case holdVolume
        }
        public var kind: Kind
        /// One plain line for the UI.
        public var text: String
        /// Why, with the study.
        public var why: String
        /// Every rule here is the app's reading of the evidence, not a trial protocol.
        public var isAppChoice: Bool = true
        public var id: String { text }
    }

    public struct Report: Sendable, Equatable {
        public var number: Int
        public var start: Date
        public var end: Date
        public var weeksRun: Int
        public var hadDeload: Bool
        public var sessionsDone: Int
        public var sessionsPlanned: Int
        public var weeksKept: Int
        public var weeksPlanned: Int
        public var volumeKg: Double
        /// Change in volume a week against the previous block, as a fraction; nil without one.
        public var volumeChange: Double?
        public var lifts: [LiftChange]
        public var records: [BlockRecord]
        public var muscles: [MuscleLine]
        public var bodyWeight: Trend?
        public var hrv: Trend?
        public var next: [NextChange]

        /// Weeks kept ÷ planned weeks, 0 with no plan.
        public var adherence: Double { weeksPlanned > 0 ? Double(weeksKept) / Double(weeksPlanned) : 0 }
        public var under: [MuscleLine] { muscles.filter { $0.status == .under } }
        public var over: [MuscleLine] { muscles.filter { $0.status == .over } }
    }

    // MARK: Constants

    /// An e1RM change under 1% across a block is read as "stalled" (app
    /// choice: inside the e1RM's ±3 kg error for most lifts, `LiftGoalProjection`).
    public static let stallFraction = 0.01
    /// Sets a week added next block for a muscle under its target (app
    /// choice; more weekly sets → more growth, Schoenfeld 2017, Pelland 2026).
    public static let addedSets = 2
    /// Weeks kept at or above this share counts as high adherence
    /// (app choice; same 3-of-4 line as `Consistency.keptFraction`).
    public static let highAdherence = 0.75
    /// HRV falling more than this across the block holds volume instead of
    /// adding (app choice; 7-day averages, Plews et al., Sports Med 2013).
    public static let hrvDropFraction = 0.05
    /// Weeks averaged at each end for body weight and HRV.
    static let trendDays = 7.0
    /// Lifts on the report, at most.
    public static let maximumLifts = 6
    /// A lift needs this many sessions in the block to be on the report.
    public static let minimumLiftSessions = 3
    /// Heavier rep range for a stalled lift on a strength goal (heavy loads,
    /// about 1-6 reps, give larger 1RM gains: Schoenfeld et al. 2017).
    public static let strengthRepRange = 3...6
    /// The other way for a stalled lift on muscle/balanced goals with no
    /// variation in the gym: a higher range (similar growth from ~30-85% 1RM
    /// near failure, Schoenfeld 2017; app choice).
    public static let higherRepRange = 8...12

    // MARK: Make

    public static func make(_ input: Input, calendar: Calendar = .current) -> Report {
        let day = 86_400.0
        let inBlock = input.sessions.filter { $0.start >= input.start && $0.start < input.end }
            .sorted { $0.start < $1.start }
        let weeksRun = max(1, Int((input.end.timeIntervalSince(input.start) / (7 * day)).rounded()))
        let weekStarts = (0..<weeksRun).compactMap { calendar.date(byAdding: .day, value: 7 * $0, to: input.start) }
        // The deload is the last week, when the block reached it.
        let workingWeeks = input.hadDeload && weekStarts.count > 1 ? Array(weekStarts.dropLast()) : weekStarts

        let records = input.weeks.filter { $0.weekStart >= input.start && $0.weekStart < input.end && $0.planned > 0 }
        let weeksKept = records.filter { Consistency.weekKept(planned: $0.planned, done: $0.done) }.count
        let volume = inBlock.reduce(0) { $0 + WorkoutSummary.totals($1).volumeKg }

        var volumeChange: Double?
        if let previous = input.previous {
            let before = input.sessions.filter { $0.start >= previous.start && $0.start < previous.end }
                .reduce(0) { $0 + WorkoutSummary.totals($1).volumeKg }
            let previousWeeks = max(1, (previous.duration / (7 * day)).rounded())
            let perWeekBefore = before / previousWeeks
            if perWeekBefore > 0 { volumeChange = (volume / Double(weeksRun) - perWeekBefore) / perWeekBefore }
        }

        let lifts = liftChanges(inBlock, weekStarts: weekStarts, workingWeeks: workingWeeks, calendar: calendar)
        let muscleLines = muscles(inBlock, input: input, workingWeeks: workingWeeks, calendar: calendar)
        let hrv = trend(input.hrv, start: input.start, end: input.end)
        var report = Report(
            number: input.number, start: input.start, end: input.end, weeksRun: weeksRun, hadDeload: input.hadDeload,
            sessionsDone: records.reduce(0) { $0 + $1.done }, sessionsPlanned: records.reduce(0) { $0 + $1.planned },
            weeksKept: weeksKept, weeksPlanned: records.count, volumeKg: volume, volumeChange: volumeChange,
            lifts: lifts, records: blockRecords(input.sessions, traits: input.traits, start: input.start, end: input.end),
            muscles: muscleLines, bodyWeight: trend(input.bodyWeightKg, start: input.start, end: input.end),
            hrv: hrv, next: []
        )
        report.next = nextChanges(report, style: input.style, alternatives: input.alternatives)
        return report
    }

    // MARK: Lifts

    /// Sets that count for records and e1RM: ticked, not a warm-up, not a drop stage or mini-set.
    static func effortSets(_ exercise: WorkoutSummary.LoggedExercise) -> [WorkoutSummary.LoggedSet] {
        exercise.sets.filter { $0.completedAt != nil && !$0.isWarmup && !$0.isStage && $0.reps > 0 }
    }

    /// Best e1RM (kg), or most reps when nothing was loaded.
    static func best(_ sets: [WorkoutSummary.LoggedSet]) -> (value: Double, bodyweight: Bool)? {
        guard !sets.isEmpty else { return nil }
        let loaded = sets.filter { $0.weightKg > 0 }
        if loaded.isEmpty { return (Double(sets.map(\.reps).max() ?? 0), true) }
        return (loaded.map(\.estimatedOneRepMaxKg).max() ?? 0, false)
    }

    static func liftChanges(_ sessions: [WorkoutSummary.LoggedSession], weekStarts: [Date], workingWeeks: [Date],
                            calendar: Calendar) -> [LiftChange] {
        guard workingWeeks.count >= 3, let first = weekStarts.first, let lastWorking = workingWeeks.last else { return [] }
        let firstEnd = calendar.date(byAdding: .day, value: 14, to: first) ?? first
        let lateStart = calendar.date(byAdding: .day, value: -7, to: lastWorking) ?? lastWorking
        let lateEnd = calendar.date(byAdding: .day, value: 7, to: lastWorking) ?? lastWorking

        // Per exercise: per-session bests, in session order.
        var perExercise: [String: (name: String, points: [(date: Date, value: Double, bodyweight: Bool)])] = [:]
        for session in sessions {
            var byID: [String: [WorkoutSummary.LoggedSet]] = [:]
            var names: [String: String] = [:]
            for exercise in session.exercises {
                byID[exercise.exerciseID, default: []] += effortSets(exercise)
                names[exercise.exerciseID] = exercise.name
            }
            for (id, sets) in byID {
                guard let top = best(sets) else { continue }
                perExercise[id, default: (name: names[id] ?? id, points: [])].points.append((date: session.start, value: top.value, bodyweight: top.bodyweight))
            }
        }

        var result: [LiftChange] = []
        for (id, entry) in perExercise where entry.points.count >= minimumLiftSessions {
            // A lift logged with load at all is compared by e1RM; reps only for bodyweight-only lifts.
            let bodyweight = entry.points.allSatisfy(\.bodyweight)
            let points = entry.points.filter { $0.bodyweight == bodyweight }
            let early = points.filter { $0.date < firstEnd }.map(\.value).max()
            let late = points.filter { $0.date >= lateStart && $0.date < lateEnd }.map(\.value).max()
            guard let early, let late, early > 0 else { continue }
            let change = (late - early) / early
            result.append(LiftChange(
                exerciseID: id, name: entry.name, isBodyweight: bodyweight, start: early, end: late, change: change,
                points: points.map { DayValue(date: $0.date, value: $0.value) },
                isStalled: change < stallFraction
            ))
        }
        return Array(result.sorted { a, b in
            let ra = PRHistory.rank(exerciseID: a.exerciseID, name: a.name)
            let rb = PRHistory.rank(exerciseID: b.exerciseID, name: b.name)
            if ra != rb { return ra < rb }
            if a.points.count != b.points.count { return a.points.count > b.points.count }
            return a.name < b.name
        }.prefix(maximumLifts))
    }

    // MARK: Records

    /// Records set in the block against everything before each session (`PRHistory.events`, kg).
    static func blockRecords(_ sessions: [WorkoutSummary.LoggedSession], traits: [String: PRHistory.Traits],
                             start: Date, end: Date) -> [BlockRecord] {
        PRHistory.events(sessions, traits: traits)
            .filter { $0.date >= start && $0.date < end }
            .map { BlockRecord(exerciseID: $0.exerciseID, name: $0.name, date: $0.date, record: $0.record) }
    }

    // MARK: Muscles

    static func muscles(_ sessions: [WorkoutSummary.LoggedSession], input: Input, workingWeeks: [Date],
                        calendar: Calendar) -> [MuscleLine] {
        guard !workingWeeks.isEmpty, !input.muscles.isEmpty else { return [] }
        let sets = workSets(sessions, muscles: input.muscles)
        var totals: [Muscle: Double] = [:]
        for week in workingWeeks {
            let end = (calendar.date(byAdding: .day, value: 7, to: week) ?? week).addingTimeInterval(-1)
            for (muscle, count) in MuscleCoverage.setsThisWeek(sets, weekStart: week, now: end) {
                totals[muscle, default: 0] += count
            }
        }
        let weeks = Double(workingWeeks.count)
        return MuscleCoverage.tracked.compactMap { muscle in
            let average = (totals[muscle] ?? 0) / weeks
            let target = target(for: muscle, weeklyTargets: input.weeklyTargets)
            let rounded = Int(average.rounded())
            let status: MuscleLine.Status = rounded < target.lowerBound ? .under : (rounded > target.upperBound ? .over : .inRange)
            return MuscleLine(muscle: muscle, averageSets: average, target: target, status: status)
        }
    }

    /// The block's band for a muscle: its average weekly target as the top and
    /// two sets fewer as the bottom (`VolumeProgression.Target.band`), or 10-20.
    static func target(for muscle: Muscle, weeklyTargets: [[Muscle: Int]]) -> ClosedRange<Int> {
        let values = weeklyTargets.compactMap { $0[muscle] }
        guard !values.isEmpty else { return WorkoutSummary.defaultTarget }
        let top = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        let floor = VolumeProgression.minimumSets
        return max(floor, top - 2)...max(floor, top)
    }

    /// Completed working sets with their muscles and cluster credit, as the
    /// summary and `MuscleModel` count them.
    static func workSets(_ sessions: [WorkoutSummary.LoggedSession], muscles: [String: ExerciseMuscles]) -> [MuscleRecovery.WorkSet] {
        var result: [MuscleRecovery.WorkSet] = []
        for session in sessions {
            for exercise in session.exercises {
                guard let trained = muscles[exercise.exerciseID] else { continue }
                let items = exercise.sets.map { SetStructure.Item(isWarmup: $0.isWarmup, kind: $0.isStage ? .drop : .straight) }
                let positions = SetStructure.positions(items)
                for (index, set) in exercise.sets.enumerated()
                where set.completedAt != nil && !set.isWarmup && !positions[index].isStage {
                    result.append(MuscleRecovery.WorkSet(
                        date: set.completedAt ?? session.start, primary: trained.primary, secondary: trained.secondary,
                        rpe: set.rpe, volumeCredit: SetStructure.hardSetCredit(stages: positions[index].stages)
                    ))
                }
            }
        }
        return result
    }

    // MARK: Trends

    /// First 7 days with data in the block against its last 7; nil with fewer
    /// than two readings at either end or the two ends overlapping.
    static func trend(_ values: [DayValue], start: Date, end: Date) -> Trend? {
        let inside = values.filter { $0.date >= start && $0.date < end && $0.value > 0 }.sorted { $0.date < $1.date }
        guard let first = inside.first, let last = inside.last else { return nil }
        let span = trendDays * 86_400
        let early = inside.filter { $0.date < first.date.addingTimeInterval(span) }
        let late = inside.filter { $0.date > last.date.addingTimeInterval(-span) }
        guard early.count >= 2, late.count >= 2, last.date.timeIntervalSince(first.date) >= 2 * span - 86_400 else { return nil }
        let mean = { (xs: [DayValue]) in xs.map(\.value).reduce(0, +) / Double(xs.count) }
        return Trend(start: mean(early), end: mean(late))
    }

    // MARK: Next block

    public static func nextChanges(_ report: Report, style: TrainingStyle,
                                   alternatives: [String: [CatalogExercise]]? = nil) -> [NextChange] {
        var changes: [NextChange] = []
        // Steady-week goals (stamina) keep their volume: the block has no ramp.
        let ramps = style != .endurance
        if ramps {
            for line in report.under {
                let next = min(VolumeProgression.maximumWeeklySets, line.target.upperBound + addedSets)
                changes.append(NextChange(
                    kind: .addSets(line.muscle, sets: addedSets),
                    text: "\(line.muscle.name): +\(addedSets) sets a week (to about \(next))",
                    why: "Averaged \(Int(line.averageSets.rounded())) of \(line.target.lowerBound)-\(line.target.upperBound) sets. More weekly sets build more muscle (Schoenfeld 2017)."
                ))
            }
        }
        for lift in report.lifts where lift.isStalled {
            changes.append(stallChange(lift, style: style, alternatives: alternatives))
        }
        let recoveryDropped = (report.hrv?.fraction ?? 0) < -hrvDropFraction
        if report.weeksPlanned > 0 {
            if report.adherence < highAdherence {
                changes.append(NextChange(
                    kind: .holdVolume, text: "Same volume next block",
                    why: "\(report.weeksKept) of \(report.weeksPlanned) weeks kept. Sets you do beat sets you plan; adding more now would widen the gap."
                ))
            } else if recoveryDropped {
                changes.append(NextChange(
                    kind: .holdVolume, text: "Same volume next block",
                    why: "HRV ended the block lower than it started, so the app holds volume rather than adding (7-day averages, Plews 2013)."
                ))
            } else if ramps && report.under.isEmpty {
                changes.append(NextChange(
                    kind: .volumeUp(sets: 1), text: "Start each muscle 1 set a week higher",
                    why: "\(report.weeksKept) of \(report.weeksPlanned) weeks kept and every muscle on target. A small step keeps progress going; returns shrink past about 20 sets (Pelland 2026)."
                ))
            }
        }
        return changes
    }

    static func stallChange(_ lift: LiftChange, style: TrainingStyle,
                            alternatives: [String: [CatalogExercise]]?) -> NextChange {
        let percent = (lift.change * 100).formatted(.number.precision(.fractionLength(0...1)))
        let flat = "\(lift.name) moved \(percent)% this block."
        if style == .strength && !lift.isBodyweight {
            let reps = strengthRepRange
            return NextChange(
                kind: .repRange(exerciseID: lift.exerciseID, reps: reps),
                text: "\(lift.name): \(reps.lowerBound)-\(reps.upperBound) reps next block",
                why: "\(flat) Heavier sets build more 1RM strength (Schoenfeld 2017)."
            )
        }
        let options = alternatives?[lift.exerciseID]
            ?? ExerciseCatalog.slot(for: lift.exerciseID).flatMap { ExerciseCatalog.options[$0] }
            ?? []
        if let swap = options.first(where: { $0.id != lift.exerciseID }) {
            return NextChange(
                kind: .swapExercise(fromID: lift.exerciseID, toID: swap.id, toName: swap.name),
                text: "Swap \(lift.name) for \(swap.name)",
                why: "\(flat) A new variation of the same movement is a fresh stimulus (Kassiano 2022); swap one lift, not all."
            )
        }
        let reps = higherRepRange
        return NextChange(
            kind: .repRange(exerciseID: lift.exerciseID, reps: reps),
            text: "\(lift.name): \(reps.lowerBound)-\(reps.upperBound) reps next block",
            why: "\(flat) Adding reps works about as well as adding weight (Plotkin 2022)."
        )
    }

    // MARK: Share

    /// Plain text for the share sheet; weights through `format` (kg → display).
    public static func shareText(_ report: Report, format: (Double) -> String) -> String {
        var lines = ["Block \(report.number) · \(report.weeksKept) of \(report.weeksPlanned) weeks kept"]
        lines.append("\(report.sessionsDone) of \(report.sessionsPlanned) sessions · \(format(report.volumeKg)) lifted")
        for lift in report.lifts {
            let percent = (lift.change * 100).formatted(.number.precision(.fractionLength(0...1)))
            let values = lift.isBodyweight
                ? "\(Int(lift.start)) → \(Int(lift.end)) reps"
                : "\(format(lift.start)) → \(format(lift.end))"
            let sign = lift.change >= 0 ? "+" : ""
            lines.append("\(lift.name): \(values) (\(sign)\(percent)%)")
        }
        if !report.records.isEmpty { lines.append("\(report.records.count) personal records") }
        return lines.joined(separator: "\n")
    }
}
