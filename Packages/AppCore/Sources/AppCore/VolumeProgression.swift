import Foundation

/// Hard sets per muscle per week, moved through a training block by how last
/// week went: performance and recovery first; your pump and soreness answers
/// (`MuscleFeedback`) only adjust that, and the UI says the evidence is weak.
///
/// - **The band.** About 10-20 hard sets a muscle a week builds the most muscle
///   for most people (Schoenfeld, Ogborn & Krieger, J Sports Sci 2017; ACSM
///   position stand, Med Sci Sports Exerc 2026: about 10 for growth), so a
///   block starts each muscle at 10. More sets keep adding a little with
///   diminishing returns, and even ~4 a week gives most of the strength gain
///   (Pelland JC, Remmert JF, Robinson Z, Hinson S, Zourdos MC. The resistance
///   training dose-response: meta-regressions exploring the effects of weekly
///   volume and frequency on muscle hypertrophy and strength gain. SportRxiv
///   2024 preprint, published Sports Med 2026; figures here are secondary). So
///   the ramp stops at 20 sets and the deload never goes below 4.
/// - **The step.** One set more in each session that trains the muscle (about
///   +2 a week at twice a week: chest 10 → 12 → 14 → 16, deload 8). The size of
///   the step, and "MEV/MRV"-style landmarks in general, are coaching
///   heuristics from practice (Israetel's Renaissance Periodization volume
///   landmarks), not measured quantities; the research gives the weekly band
///   and the dose-response, not a ramp rate. The UI says so.
/// - **Only when earned.** A muscle gets the step only if last week's sets for
///   it were all done, none harder than the effort target, its reps didn't
///   fall, and `MuscleRecovery` has it fresh. Otherwise it holds. Performance
///   and recovery are the signals because pump and soreness are poor ones:
///   muscle swelling tracks growth in some data and not in others (Schoenfeld,
///   "Is the pump a signal for hypertrophy?", Human Kinetics), and soreness
///   tracks damage, not growth (Schoenfeld & Contreras 2013, summarised by the
///   Canadian Kinesiology Alliance; Nosaka et al. 2002).
/// - **Your answers, second.** The optional per-muscle answers after a session
///   (`MuscleFeedback`: pump, soreness from last time, joint pain) only adjust
///   that rule, RP-style practice rather than evidence: still sore or joint
///   pain holds the muscle (one set fewer when it happens at two sessions in
///   the week); "recovered" with a low or OK pump allows one set (not the
///   usual step) when only the recovery model was holding it. App choices,
///   labelled so in the UI.
/// - **The block report.** Changes applied from the last block's report
///   (`NextBlockAdjustments`) add or take sets once (`Adjustment.offsets`)
///   and can cap a muscle at the last block's highest week ("same volume").
/// - **Effort.** People misjudge reps in reserve by about a rep (Halperin I et
///   al., Sports Med 2022, scoping review and meta-analysis), so a set counts
///   as "at the target" up to half an RPE point over it; the app's choice.
/// - **Caps.** Never more than 20 sets a week, and never more than the week's
///   sessions can hold in their time (`capacity`), even when that is under
///   the 4-set floor; muscles the gym has no movement for get no target. A
///   superset round of two moves for the same muscle group here (lateral
///   raise with rear-delt fly, both "shoulders") counts once, so pairing
///   never meets a target on paper.
/// - **Goal tailoring.** Muscle goals ramp to 20; strength and balanced goals
///   stop at 16, because strength rises less with extra sets than muscle size
///   does (Pelland 2024, secondary); stamina and health goals keep steady
///   weeks at 10 with no ramp, as their training block does (`TrainingBlock`).
///   The 16 is an app choice inside the band.
public enum VolumeProgression {
    /// Where every muscle starts a block (bottom of the 10-20 band).
    public static let startingSets = 10
    /// The most sets a week the ramp ever asks of one muscle.
    public static let maximumWeeklySets = 20
    /// The fewest sets a deload week keeps (Pelland 2024: ~4 a week still grows muscle).
    public static let minimumSets = 4
    /// Deload: about half the sets (Bell et al., Sports Med Open 2023, Delphi consensus).
    /// The per-exercise fallback (`TrainingBlock.deloadMultiplier`) is 0.6 only
    /// so a 3-set exercise rounds to 2; both are "about half" in the UI.
    public static let deloadFraction = 0.5
    /// RPE over the target still counted as "at the target" (Halperin 2022: ~1 rep misjudged).
    public static let effortTolerance = 0.5
    /// Sets short of last week's target still counted as "all done" (one skipped
    /// set is noise, not a sign the volume was too much; app's choice).
    public static let missedSetTolerance = 1.0
    /// A set is "hard" at RPE 7 or more (3 or fewer reps left). Easier sets
    /// still count, at this share. Direction from the evidence: muscle growth
    /// falls off as sets stop further from failure (Robinson et al., Sports
    /// Med 2024, proximity-to-failure meta-regression; Refalo et al., J
    /// Sports Sci 2024); the RPE 7 line and the 0.6 itself are the app's
    /// choice, not trial figures (same rule as `MuscleRecovery` and
    /// `MuscleCoverage`). A set with no RPE logged counts as hard.
    public static let hardSetRPE = 7.0
    public static let easySetCredit = 0.6

    /// The RPE from which a set counts as hard in a week with this effort
    /// target: `hardSetRPE`, or one point under the target when that's
    /// lower. Reps in reserve are misjudged by about a rep (Halperin et al.,
    /// Sports Med 2022), so a set one point easier than a 3-in-reserve week's
    /// target is on plan, not easy; counting it at 0.6 held weekly volume
    /// for weeks (audit 2026-11 §2, sim bug 3). App choice.
    public static func hardLine(targetRPE: Double) -> Double {
        guard targetRPE.isFinite else { return hardSetRPE }
        return min(hardSetRPE, targetRPE - 1)
    }

    /// The top of the ramp for a goal's training style.
    public static func ceiling(style: TrainingStyle) -> Int {
        switch style {
        case .muscle, .strengthAndMuscle: maximumWeeklySets
        case .strength, .balanced: 16
        case .endurance: startingSets
        }
    }

    // MARK: Last week's sets

    /// One logged working set, with what the progression rule needs.
    public struct LoggedSet: Sendable, Equatable {
        public var exerciseID: String
        public var name: String
        /// When the session started (sets of one session share it).
        public var sessionStart: Date
        /// The set's position within its exercise (0, 1, 2 …).
        public var order: Int
        public var primary: [Muscle]
        public var secondary: [Muscle]
        public var weightKg: Double
        public var reps: Int
        public var rpe: Double?
        public var isCompleted: Bool
        public var isCompound: Bool
        /// Superset group within the session, if the set was paired.
        public var supersetGroup: Int?
        /// Hard sets it counts as: 1, or for a set followed by drop stages or
        /// mini-sets (not logged sets of their own here) the straight sets
        /// they stand in for, up to 3 (`SetStructure.hardSetCredit`).
        public var setCredit: Double

        public init(exerciseID: String, name: String, sessionStart: Date, order: Int, primary: [Muscle],
                    secondary: [Muscle] = [], weightKg: Double, reps: Int, rpe: Double?, isCompleted: Bool = true,
                    isCompound: Bool, supersetGroup: Int? = nil, setCredit: Double = 1) {
            self.exerciseID = exerciseID
            self.name = name
            self.sessionStart = sessionStart
            self.order = order
            self.primary = primary
            self.secondary = secondary
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isCompleted = isCompleted
            self.isCompound = isCompound
            self.supersetGroup = supersetGroup
            self.setCredit = setCredit
        }
    }

    /// How one muscle's week went.
    public struct Performance: Sendable, Equatable {
        /// Hard sets done (helpers half, as everywhere in the app).
        public var sets: Double
        /// Every logged working set for it was finished. Sets passed in from
        /// finished sessions are always completed (the finish sheet deletes
        /// unticked sets), so a skipped set shows up as fewer `sets` against
        /// the target instead; this stays for callers that pass unfinished sets.
        public var allCompleted: Bool
        /// Exercises with a set harder than the effort target.
        public var overEffort: [String]
        /// Exercises whose top-set reps fell at the same or a heavier weight.
        public var repsDropped: [String]

        public init(sets: Double, allCompleted: Bool = true, overEffort: [String] = [], repsDropped: [String] = []) {
            self.sets = sets
            self.allCompleted = allCompleted
            self.overEffort = overEffort
            self.repsDropped = repsDropped
        }
    }

    /// The hardest a set may be and still count as at the target: the block's
    /// RPE on compound lifts, plus the planner's isolation offset for the style
    /// (`WorkoutPlanner.prescribe` lets small lifts go closer to failure), plus
    /// `effortTolerance`.
    public static func effortCeiling(targetRPE: Double, compound: Bool, style: TrainingStyle) -> Double {
        let offset: Double = switch style {
        case .balanced: 1
        case .strength: 0.5
        case .muscle, .strengthAndMuscle: 1.5
        case .endurance: 0.5
        }
        return min(10, targetRPE + (compound ? 0 : offset) + effortTolerance)
    }

    /// Last week's performance per muscle from logged sets. Pass sets from at
    /// least a week before `weekStart` too, so a fall in reps can be seen
    /// against the session before.
    /// - Parameters:
    ///   - weekStart: Monday of the week to judge.
    ///   - targetRPE: that week's effort target (`TrainingBlock.WeekState.targetRPE`).
    public static func summarize(_ sets: [LoggedSet], weekStart: Date, targetRPE: Double, style: TrainingStyle,
                                 calendar: Calendar = .current) -> [Muscle: Performance] {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
        let inWeek = sets.filter { $0.sessionStart >= weekStart && $0.sessionStart < weekEnd }
        var result: [Muscle: Performance] = [:]
        func touch(_ muscle: Muscle) {
            if result[muscle] == nil { result[muscle] = Performance(sets: 0) }
        }
        // Superset rounds: a muscle counts once per (session, group, round).
        var creditedRounds: Set<String> = []
        for set in inWeek {
            for muscle in set.primary { touch(muscle) }
            guard set.isCompleted else {
                for muscle in set.primary { result[muscle]?.allCompleted = false }
                continue
            }
            let effort = (set.rpe ?? hardSetRPE) >= hardLine(targetRPE: targetRPE) - 0.001 ? 1.0 : easySetCredit
            var weights: [Muscle: Double] = [:]
            for muscle in set.secondary { weights[muscle] = max(weights[muscle] ?? 0, 0.5) }
            for muscle in set.primary { weights[muscle] = 1 }
            for (muscle, weight) in weights {
                if let group = set.supersetGroup {
                    let key = "\(set.sessionStart.timeIntervalSince1970)|\(group)|\(set.order)|\(muscle.rawValue)"
                    if creditedRounds.contains(key) { continue }
                    creditedRounds.insert(key)
                }
                touch(muscle)
                result[muscle]?.sets += weight * effort * set.setCredit
            }
            if let rpe = set.rpe, rpe > effortCeiling(targetRPE: targetRPE, compound: set.isCompound, style: style) {
                for muscle in set.primary where result[muscle]?.overEffort.contains(set.name) == false {
                    result[muscle]?.overEffort.append(set.name)
                }
            }
        }
        for entry in repsDropped(sets, weekStart: weekStart, weekEnd: weekEnd) {
            for muscle in entry.primary {
                touch(muscle)
                if result[muscle]?.repsDropped.contains(entry.name) == false {
                    result[muscle]?.repsDropped.append(entry.name)
                }
            }
        }
        for muscle in Array(result.keys) {
            let sets = result[muscle]?.sets ?? 0
            result[muscle]?.sets = (sets * 10).rounded() / 10
        }
        return result
    }

    /// Exercises whose latest session in the week did fewer reps on its top
    /// (heaviest completed) set than the session before, at the same or a
    /// heavier weight. A lighter top set isn't compared: fewer reps there
    /// isn't the rule's signal.
    static func repsDropped(_ sets: [LoggedSet], weekStart: Date, weekEnd: Date) -> [(name: String, primary: [Muscle])] {
        let working = sets.filter { $0.isCompleted && $0.reps > 0 }
        let byExercise = Dictionary(grouping: working, by: \.exerciseID)
        var dropped: [(name: String, primary: [Muscle])] = []
        for exerciseID in byExercise.keys.sorted() {
            guard let all = byExercise[exerciseID] else { continue }
            let sessions = Dictionary(grouping: all, by: \.sessionStart)
            let starts = sessions.keys.sorted()
            guard let latest = starts.last(where: { $0 >= weekStart && $0 < weekEnd }),
                  let before = starts.last(where: { $0 < latest }),
                  let now = topSet(sessions[latest] ?? []), let then = topSet(sessions[before] ?? []) else { continue }
            if now.weightKg >= then.weightKg - 0.01, now.reps < then.reps {
                dropped.append((now.name, now.primary))
            }
        }
        return dropped
    }

    /// The heaviest completed set, most reps on a tie.
    static func topSet(_ sets: [LoggedSet]) -> LoggedSet? {
        sets.max { a, b in
            if abs(a.weightKg - b.weightKg) > 0.01 { return a.weightKg < b.weightKg }
            return a.reps < b.reps
        }
    }

    // MARK: This week's target

    /// Why a muscle's target is what it is.
    public enum Change: Codable, Sendable, Equatable {
        /// Week 1 of a block (or no earlier target).
        case start
        /// One more set per session: last week was done, at the target, recovered.
        case added
        /// The block's planned easier week.
        case deload
        /// Stamina and health goals: steady weeks.
        case steady
        case heldHRV
        case heldNotTrained
        /// Sets done last week, of the target.
        case heldMissedSets(done: Double, target: Int)
        case heldRepsDropped(exercise: String)
        case heldTooHard(exercise: String)
        case heldNotRecovered
        /// The step was earned but the 20-set or goal ceiling stopped it.
        case cappedCeiling
        /// The step was earned (or the old target was higher) but the week's
        /// session time can't hold more.
        case cappedTime
        /// Your answer after a session (`MuscleFeedback`): still sore at the
        /// newest one, left over from the session on `from` (if known).
        case heldSore(from: Date?)
        /// You reported joint pain for it last week.
        case heldJointPain
        /// Still sore at two or more sessions last week: one set fewer.
        case reducedSore
        /// Joint pain at two or more sessions last week: one set fewer.
        case reducedJointPain
        /// You said it had recovered with a low or OK pump while the recovery
        /// model still had it tired: one set more, not the usual step.
        case addedFeedback
        /// Sets added (or, after an undo, taken off) by the last block's report.
        case fromReport(offset: Int)
        /// "Same volume next block" from the report: held at the last block's highest week.
        case heldReport

        public var isHeld: Bool {
            switch self {
            case .heldHRV, .heldNotTrained, .heldMissedSets, .heldRepsDropped, .heldTooHard, .heldNotRecovered,
                 .heldSore, .heldJointPain, .reducedSore, .reducedJointPain, .heldReport: true
            default: false
            }
        }

        /// The change comes from your answers after a session (`MuscleFeedback`).
        public var isFromFeedback: Bool {
            switch self {
            case .heldSore, .heldJointPain, .reducedSore, .reducedJointPain, .addedFeedback: true
            default: false
            }
        }

        /// The change comes from the last block's report (`NextBlockAdjustments`).
        public var isFromReport: Bool {
            switch self {
            case .fromReport, .heldReport: true
            default: false
            }
        }
    }

    public struct Target: Codable, Sendable, Equatable, Identifiable {
        public var muscle: Muscle
        /// Hard sets to aim for this week.
        public var sets: Int
        /// Last week's target, if there was one.
        public var previous: Int?
        public var change: Change
        public var id: Muscle { muscle }

        public init(muscle: Muscle, sets: Int, previous: Int?, change: Change) {
            self.muscle = muscle
            self.sets = sets
            self.previous = previous
            self.change = change
        }

        /// The week's band: the target, with one set fewer in each of two
        /// sessions as the bottom ("12-14"), never under `minimumSets`, or
        /// under the target when the sessions can't hold that many (`target`).
        public var band: ClosedRange<Int> {
            let floor = min(VolumeProgression.minimumSets, max(1, sets))
            return max(floor, sets - 2)...max(floor, sets)
        }

        /// "12-14 sets".
        public var bandText: String { "\(band.lowerBound)-\(band.upperBound) sets" }

        /// One line on the change: "Lats held at 14 sets: reps dropped on Barbell Row last week."
        public var note: String {
            let name = muscle.name
            switch change {
            case .start: return "\(name) starts the block at \(sets) sets."
            case .added: return "\(name) up to \(sets) sets: last week's sets were all done at the effort target and it's recovered."
            case .deload: return "\(name) \(sets) sets: the planned easier week, about half."
            case .steady: return "\(name) \(sets) sets: steady weeks for your goal."
            case .heldHRV: return "\(name) held at \(sets) sets: HRV was below your normal range as the week began."
            case .heldNotTrained: return "\(name) held at \(sets) sets: it wasn't trained last week."
            case .heldMissedSets(let done, let target):
                let doneText = done.formatted(.number.precision(.fractionLength(0...1)))
                return "\(name) held at \(sets) sets: \(doneText) of \(target) done last week."
            case .heldRepsDropped(let exercise): return "\(name) held at \(sets) sets: reps dropped on \(exercise) last week."
            case .heldTooHard(let exercise): return "\(name) held at \(sets) sets: \(exercise) went past the effort target last week."
            case .heldNotRecovered: return "\(name) held at \(sets) sets: not fully recovered yet."
            case .cappedCeiling: return "\(name) at \(sets) sets, the most the plan asks for your goal."
            case .cappedTime: return "\(name) at \(sets) sets: the most your planned sessions can hold."
            case .heldSore(let from):
                guard let from else { return "\(name) held at \(sets) sets: you said it was still sore last week." }
                let day = from.formatted(.dateTime.weekday(.wide))
                return "\(name) held at \(sets) sets: still sore from \(day)."
            case .heldJointPain: return "\(name) held at \(sets) sets: you reported joint pain last week."
            case .reducedSore: return "\(name) down to \(sets) sets: still sore at two sessions last week."
            case .reducedJointPain: return "\(name) down to \(sets) sets: joint pain at two sessions last week."
            case .addedFeedback: return "\(name) up to \(sets) sets: you said it had recovered, so one set more."
            case .fromReport(let offset):
                let sign = offset > 0 ? "+" : "−"
                return "\(name) \(sets) sets: \(sign)\(abs(offset)) from the block report."
            case .heldReport: return "\(name) held at \(sets) sets: same volume as last block, from the block report."
            }
        }
    }

    /// One week's targets, saved so next week can build on them.
    public struct WeekTargets: Codable, Sendable, Equatable {
        public var weekStart: Date
        /// The week's effort target, for judging its sets next week.
        public var targetRIR: Int
        public var targets: [Target]

        public init(weekStart: Date, targetRIR: Int, targets: [Target]) {
            self.weekStart = weekStart
            self.targetRIR = targetRIR
            self.targets = targets
        }

        public var targetRPE: Double { Double(10 - targetRIR) }

        public func target(for muscle: Muscle) -> Target? { targets.first { $0.muscle == muscle } }

        /// Muscle → sets, for the planner.
        public var sets: [Muscle: Int] {
            Dictionary(targets.map { ($0.muscle, $0.sets) }, uniquingKeysWith: { first, _ in first })
        }

        /// Targets that changed from last week or held, for the notes list
        /// (week 1 and steady weeks have nothing to explain per muscle).
        public var notable: [Target] {
            targets.filter { $0.change != .start && $0.change != .steady }
        }
    }

    /// This week's target for one muscle.
    /// - Parameters:
    ///   - previous: last week's target; nil when there was none.
    ///   - week: this week in the training block.
    ///   - lastWeek: how last week went for the muscle; nil when it wasn't trained.
    ///   - state: the muscle's recovery now.
    ///   - sessions: sessions this week that train it directly (the step is one set each).
    ///   - timeCap: the most sets those sessions can hold (`capacity`).
    ///   - feedback: last week's answers for it after sessions (`MuscleFeedback.signals`).
    ///   - offset: sets the block report adds (or an undo takes off) this week, once (`Adjustment`).
    ///   - reportCeiling: "same volume" from the block report: the most sets it may reach.
    public static func target(
        for muscle: Muscle,
        previous: Int?,
        week: TrainingBlock.WeekState,
        style: TrainingStyle,
        lastWeek: Performance?,
        state: MuscleRecovery.State?,
        sessions: Int,
        timeCap: Int,
        recent: Double? = nil,
        feedback: MuscleFeedback.Signal? = nil,
        offset: Int = 0,
        reportCeiling: Int? = nil
    ) -> Target {
        let top = ceiling(style: style)
        // What the sessions can hold, even under `minimumSets`: a 30-minute upper day holds about
        // three chest sets, and a target of four there could never be met, so it held the muscle
        // as "missed sets" every week. The note says the time caps it (`cappedTime`).
        let cap = max(1, min(top, timeCap))
        let floor = min(minimumSets, cap)
        let earned = earnedTarget(for: muscle, previous: previous, week: week, style: style, lastWeek: lastWeek,
                                  state: state, sessions: sessions, cap: cap, top: top, recent: recent, feedback: feedback)
        // The block report's changes: never on a deload or a steady (stamina) week.
        guard !week.isDeload, style != .endurance else { return earned }
        var result = earned
        if offset != 0 {
            let sets = max(floor, min(cap, earned.sets + offset))
            if sets != earned.sets {
                result = Target(muscle: muscle, sets: sets, previous: previous, change: .fromReport(offset: sets - earned.sets))
            }
        }
        if let reportCeiling, result.sets > max(floor, reportCeiling) {
            result = Target(muscle: muscle, sets: max(floor, reportCeiling), previous: previous, change: .heldReport)
        }
        return result
    }

    /// The rule itself (performance, recovery, your answers), before the block report's changes.
    static func earnedTarget(
        for muscle: Muscle, previous: Int?, week: TrainingBlock.WeekState, style: TrainingStyle,
        lastWeek: Performance?, state: MuscleRecovery.State?, sessions: Int, cap: Int, top: Int,
        recent: Double?, feedback: MuscleFeedback.Signal?
    ) -> Target {
        func make(_ sets: Int, _ change: Change) -> Target {
            if sets > cap { return Target(muscle: muscle, sets: cap, previous: previous, change: cap < top ? .cappedTime : .cappedCeiling) }
            return Target(muscle: muscle, sets: sets, previous: previous, change: change)
        }
        if week.isDeload {
            let base = previous ?? startingSets
            let sets = max(minimumSets, Int((Double(base) * deloadFraction).rounded()))
            return make(sets, .deload)
        }
        if style == .endurance { return make(startingSets, .steady) }
        guard week.week > 1, let base = previous else { return make(startingSets(recent: recent, style: style), .start) }
        if week.isHeld { return make(base, .heldHRV) }
        guard let lastWeek, lastWeek.sets >= 0.5 else { return make(base, .heldNotTrained) }
        // Your answers, a pattern first: one set fewer (app choice, RP-style practice).
        if let feedback, feedback.painRepeatedly { return make(max(minimumSets, base - 1), .reducedJointPain) }
        if let feedback, feedback.soreRepeatedly { return make(max(minimumSets, base - 1), .reducedSore) }
        if !lastWeek.allCompleted || lastWeek.sets < Double(base) - missedSetTolerance {
            return make(base, .heldMissedSets(done: lastWeek.sets, target: base))
        }
        if let exercise = lastWeek.repsDropped.first { return make(base, .heldRepsDropped(exercise: exercise)) }
        if let exercise = lastWeek.overEffort.first { return make(base, .heldTooHard(exercise: exercise)) }
        if let feedback, feedback.jointPainReports > 0 { return make(base, .heldJointPain) }
        if let feedback, feedback.isStillSore { return make(base, .heldSore(from: feedback.soreFrom)) }
        if let state, state.status != .fresh {
            // Performance held and you said it had recovered: one set, not the full step.
            if let feedback, feedback.allowsStepWhenTired { return make(base + 1, .addedFeedback) }
            return make(base, .heldNotRecovered)
        }
        return make(base + max(1, min(2, sessions)), .added)
    }

    /// The last block's report applied to this block (`NextBlockAdjustments.volume`).
    public struct Adjustment: Sendable, Equatable {
        /// Sets added to (or taken off) a muscle's target this week, once:
        /// the next week builds on the adjusted target.
        public var offsets: [Muscle: Int]
        /// "Same volume next block": the most sets a muscle may reach.
        public var ceilings: [Muscle: Int]

        public init(offsets: [Muscle: Int] = [:], ceilings: [Muscle: Int] = [:]) {
            self.offsets = offsets
            self.ceilings = ceilings
        }

        public var isEmpty: Bool { offsets.values.allSatisfy { $0 == 0 } && ceilings.isEmpty }
    }

    /// Where a muscle starts a block: about what you've been doing (`recent`:
    /// the median of your last weeks' hard sets for it, `recentWeeklySets`),
    /// kept between `startingSets` and 4 under the style's ceiling, so the
    /// ramp still has room. Lifters used to 15-18 sets were dropped to 10 at
    /// every new block; the dose-response is diminishing but positive past 10
    /// (Pelland et al., Sports Med 2026), so starting near current volume and
    /// adding to it is the evidence-led start (audit 2026-11 §9). Nil = 10.
    public static func startingSets(recent: Double?, style: TrainingStyle) -> Int {
        guard let recent, recent.isFinite, recent > 0 else { return startingSets }
        let top = max(startingSets, ceiling(style: style) - 4)
        return max(startingSets, min(top, Int(recent.rounded())))
    }

    /// The median weekly hard sets per muscle over the `weeks` full weeks
    /// before `weekStart` (weeks with none count as 0, so a break lowers it),
    /// for `startingSets(recent:style:)`. A week-1 start after a 2-3 week gap
    /// comes out lower on its own.
    public static func recentWeeklySets(_ sets: [LoggedSet], before weekStart: Date, weeks: Int = 4, style: TrainingStyle,
                                        calendar: Calendar = .current) -> [Muscle: Double] {
        guard weeks > 0 else { return [:] }
        var perWeek: [[Muscle: Double]] = []
        for back in 1...weeks {
            guard let start = calendar.date(byAdding: .day, value: -7 * back, to: weekStart) else { continue }
            perWeek.append(summarize(sets, weekStart: start, targetRPE: 10 - Double(TrainingBlock.startRIR), style: style,
                                     calendar: calendar).mapValues(\.sets))
        }
        var result: [Muscle: Double] = [:]
        for muscle in Muscle.allCases {
            let values = perWeek.map { $0[muscle] ?? 0 }.sorted()
            guard values.contains(where: { $0 > 0 }) else { continue }
            let middle = values.count / 2
            result[muscle] = values.count % 2 == 1 ? values[middle] : (values[middle - 1] + values[middle]) / 2
        }
        return result
    }

    // MARK: The week

    /// Sets one session can hold for one muscle, by length: about two
    /// exercises of 2-5 sets (`WorkoutPlanner.baseSets`, `TrainingBlock.setRange`),
    /// fewer in short sessions. App's choice, from the planner's own limits.
    public static func sessionCap(minutes: Int) -> Int {
        switch minutes {
        case ..<21: 4
        case ..<31: 6
        case ..<46: 8
        default: 10
        }
    }

    /// Movements in a session of this length that train `muscle` as their
    /// main muscle: the fewer of the focus's versions (`WorkoutFocus.slots(variant:)`),
    /// so a muscle only one version trains (biceps on upper day A) isn't
    /// counted on every upper day. With a `gym`, only movements it can do.
    static func directSlots(_ muscle: Muscle, focus: WorkoutFocus, minutes: Int, gym: GymProfile? = nil) -> Int {
        (0..<max(1, focus.variantCount)).map { directSlots(muscle, focus: focus, minutes: minutes, variant: $0, gym: gym) }.min() ?? 0
    }

    static func directSlots(_ muscle: Muscle, focus: WorkoutFocus, minutes: Int, variant: Int, gym: GymProfile? = nil) -> Int {
        sessionSlots(focus: focus, minutes: minutes, variant: variant, gym: gym)
            .filter { MuscleCoverage.muscles(for: $0).primary == muscle }.count
    }

    /// The movements a session of this length has room for (the long session
    /// adds the extra one). With a `gym`, as `WorkoutPlanner.plan` fills it
    /// there: a movement the gym has nothing for gives way to its stand-in
    /// (`MovementSlot.fallback`) or, with none, to the next movement in the
    /// list. A rack gym has no calf raise and a bodyweight gym no hamstring
    /// curl or hinge, so those muscles get no weekly target there: a target
    /// the equipment can't meet only held the volume ramp ("missed sets") for
    /// good. Without a gym, the focus's own list.
    static func sessionSlots(focus: WorkoutFocus, minutes: Int, variant: Int, gym: GymProfile? = nil) -> [MovementSlot] {
        let count = WorkoutPlanner.exerciseCount(minutes: minutes)
        let long = minutes >= WorkoutPlanner.longSessionMinutes
        guard let gym else {
            var slots = Array(focus.slots(variant: variant).prefix(count))
            if long { slots.append(focus.extraSlot(variant: variant)) }
            return slots
        }
        let planner = WorkoutPlanner(gym: gym)
        let listed = focus.slots(variant: variant) + (long ? [focus.extraSlot(variant: variant)] : [])
        let planned = listed.compactMap { slot -> MovementSlot? in
            if !planner.alternatives(for: slot).isEmpty { return slot }
            return slot.fallback.flatMap { planner.alternatives(for: $0).isEmpty ? nil : $0 }
        }
        return Array(planned.prefix(count))
    }

    /// About how many working sets a session of `minutes` holds in this
    /// style: the time left after the transitions and about 5 minutes of ramp
    /// sets, at a set's work plus the style's average rest, with no rest after
    /// each exercise's last set (`WorkoutPlanner.estimatedMinutes`' own
    /// model). An estimate for sharing out the week, not a plan.
    public static func sessionSetBudget(minutes: Int, style: TrainingStyle) -> Double {
        let count = Double(WorkoutPlanner.exerciseCount(minutes: minutes))
        let rest = Double(RestTimer.defaultSeconds(style: style, compound: true)
                          + RestTimer.defaultSeconds(style: style, compound: false)) / 2 / 60
        let work = Double(WorkoutPlanner.workSecondsPerSet) / 60
        let available = Double(minutes) - 5 - WorkoutPlanner.transitionMinutes * max(0, count - 1)
        return max(0, (available + count * rest) / (work + rest))
    }

    /// How far over its even share of a session's sets one muscle's cap
    /// may go (`capacity`), so the week can lean on one muscle while the
    /// others take fewer. App choice.
    public static let shareSlack = 1.25

    /// Sessions in the plan that train a muscle directly, and the sets their
    /// time can hold: each session's direct movements × 5 sets, at most
    /// `sessionCap`, and at most the muscle's share of the sets the session's
    /// time holds (`sessionSetBudget`: its share of the session's movements),
    /// so a target is never more than the planned sessions can fit (a 45-min
    /// strength push day held about 10 sets, not 8 for chest alone). In a
    /// flexible week the session templates stand in for the days: the
    /// coverage rule may move a focus, but the templates are the week's usual spread.
    /// Pass the `gym` so only movements its equipment can do count (`sessionSlots`).
    public static func capacity(_ muscle: Muscle, days: [PlannedDay], style: TrainingStyle = .balanced,
                                gym: GymProfile? = nil) -> (sessions: Int, timeCap: Int) {
        var sessions = 0
        var cap = 0
        for day in days {
            let slots = directSlots(muscle, focus: day.focus, minutes: day.minutes, gym: gym)
            guard slots > 0 else { continue }
            sessions += 1
            // Big lifts get about 4 sets and small ones 3 (`WorkoutPlanner.baseSets`): the share is by that weight.
            func weight(_ slot: MovementSlot) -> Double { slot.isCompound ? 4 : 3 }
            let session = sessionSlots(focus: day.focus, minutes: day.minutes, variant: 0, gym: gym).filter { $0 != .core }
            let total = session.reduce(0) { $0 + weight($1) }
            let mine = session.filter { MuscleCoverage.muscles(for: $0).primary == muscle }.reduce(0) { $0 + weight($1) }
            let fraction = total > 0 ? min(mine, Double(slots) * 4) / total : 0
            // Steady weeks (stamina and health goals) hold every muscle at its target at once, so
            // none can lean on another's share: no slack, or the targets overfill the session.
            let slack = style == .endurance ? 1 : shareSlack
            let share = sessionSetBudget(minutes: day.minutes, style: style) * fraction * slack
            cap += min(sessionCap(minutes: day.minutes), slots * TrainingBlock.setRange.upperBound,
                       max(TrainingBlock.setRange.lowerBound, Int(share.rounded())))
        }
        return (sessions, cap)
    }

    /// Every tracked muscle's target this week. Muscles the plan doesn't train
    /// directly get none (their sets come from other movements as helpers),
    /// nor do muscles the `gym` has no movement for (`sessionSlots`).
    public static func week(
        weekStart: Date,
        block: TrainingBlock.WeekState,
        style: TrainingStyle,
        days: [PlannedDay],
        previous: WeekTargets?,
        lastWeek: [Muscle: Performance],
        states: [Muscle: MuscleRecovery.State],
        recentWeeklySets: [Muscle: Double] = [:],
        feedback: [Muscle: MuscleFeedback.Signal] = [:],
        adjustment: Adjustment? = nil,
        gym: GymProfile? = nil
    ) -> WeekTargets {
        var targets: [Target] = []
        for muscle in MuscleCoverage.tracked {
            let room = capacity(muscle, days: days, style: style, gym: gym)
            guard room.sessions > 0 else { continue }
            targets.append(target(
                for: muscle, previous: previous?.target(for: muscle)?.sets, week: block, style: style,
                lastWeek: lastWeek[muscle], state: states[muscle], sessions: room.sessions, timeCap: room.timeCap,
                recent: recentWeeklySets[muscle], feedback: feedback[muscle],
                offset: adjustment?.offsets[muscle] ?? 0, reportCeiling: adjustment?.ceilings[muscle]
            ))
        }
        return WeekTargets(weekStart: weekStart, targetRIR: block.targetRIR, targets: targets)
    }

    // MARK: Today's session

    /// Direct sets for each muscle the session trains: what the week still
    /// owes it, shared over the sessions left that train it (this one
    /// included), rounded up, at most `sessionCap`. A muscle whose week is
    /// done gets 0 (the planner then keeps its exercises at the minimum).
    /// - Parameters:
    ///   - targets: this week's targets.
    ///   - doneThisWeek: hard sets so far (`MuscleCoverage.setsThisWeek`).
    ///   - focus: today's session.
    ///   - minutes: today's length.
    ///   - laterSessions: the week's sessions after today (focus and length).
    ///   - gym: the gym, so only sessions that can train a muscle share its sets.
    public static func sessionGoals(
        targets: WeekTargets,
        doneThisWeek: [Muscle: Double],
        focus: WorkoutFocus,
        minutes: Int,
        laterSessions: [PlannedDay],
        gym: GymProfile? = nil
    ) -> [Muscle: Int] {
        var goals: [Muscle: Int] = [:]
        for target in targets.targets {
            guard directSlots(target.muscle, focus: focus, minutes: minutes, gym: gym) > 0 else { continue }
            let later = laterSessions.filter { directSlots(target.muscle, focus: $0.focus, minutes: $0.minutes, gym: gym) > 0 }.count
            let owed = max(0, Double(target.sets) - (doneThisWeek[target.muscle] ?? 0))
            let share = Int((owed / Double(later + 1)).rounded(.up))
            goals[target.muscle] = min(sessionCap(minutes: minutes), share)
        }
        return goals
    }

    /// Direct sets per muscle in a planned session. Inside a superset the same
    /// muscle counts once per round (the larger of the two exercises' sets).
    public static func directSets(_ exercises: [PlannedExercise]) -> [Muscle: Int] {
        var straight: [Muscle: Int] = [:]
        var paired: [Int: [Muscle: Int]] = [:]
        for exercise in exercises {
            guard let slot = ExerciseCatalog.slot(for: exercise.exerciseID) else { continue }
            let muscle = MuscleCoverage.muscles(for: slot).primary
            if let group = exercise.supersetGroup {
                paired[group, default: [:]][muscle] = max(paired[group]?[muscle] ?? 0, exercise.sets)
            } else {
                straight[muscle, default: 0] += exercise.sets
            }
        }
        for group in paired.values {
            for (muscle, sets) in group { straight[muscle, default: 0] += sets }
        }
        return straight
    }

    /// The planned muscle of an exercise, if it's in the catalog.
    static func primaryMuscle(_ exercise: PlannedExercise) -> Muscle? {
        ExerciseCatalog.slot(for: exercise.exerciseID).map { MuscleCoverage.muscles(for: $0).primary }
    }
}
