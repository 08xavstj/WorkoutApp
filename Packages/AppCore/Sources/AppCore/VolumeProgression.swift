import Foundation

/// Hard sets per muscle per week, moved through a training block by how last
/// week went, not by pump or soreness.
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
/// - **Effort.** People misjudge reps in reserve by about a rep (Halperin I et
///   al., Sports Med 2022, scoping review and meta-analysis), so a set counts
///   as "at the target" up to half an RPE point over it; the app's choice.
/// - **Caps.** Never more than 20 sets a week, and never more than the week's
///   sessions can hold in their time (`capacity`). A superset round of two
///   moves for the same muscle group here (lateral raise with rear-delt fly,
///   both "shoulders") counts once, so pairing never meets a target on paper.
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

    /// The top of the ramp for a goal's training style.
    public static func ceiling(style: TrainingStyle) -> Int {
        switch style {
        case .muscle: maximumWeeklySets
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
        case .muscle: 1.5
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
            let effort = (set.rpe ?? hardSetRPE) >= hardSetRPE ? 1.0 : easySetCredit
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

        public var isHeld: Bool {
            switch self {
            case .heldHRV, .heldNotTrained, .heldMissedSets, .heldRepsDropped, .heldTooHard, .heldNotRecovered: true
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
        /// sessions as the bottom ("12-14"), never under `minimumSets`.
        public var band: ClosedRange<Int> {
            let floor = VolumeProgression.minimumSets
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
    public static func target(
        for muscle: Muscle,
        previous: Int?,
        week: TrainingBlock.WeekState,
        style: TrainingStyle,
        lastWeek: Performance?,
        state: MuscleRecovery.State?,
        sessions: Int,
        timeCap: Int
    ) -> Target {
        let top = ceiling(style: style)
        let cap = max(minimumSets, min(top, timeCap))
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
        guard week.week > 1, let base = previous else { return make(startingSets, .start) }
        if week.isHeld { return make(base, .heldHRV) }
        guard let lastWeek, lastWeek.sets >= 0.5 else { return make(base, .heldNotTrained) }
        if !lastWeek.allCompleted || lastWeek.sets < Double(base) - missedSetTolerance {
            return make(base, .heldMissedSets(done: lastWeek.sets, target: base))
        }
        if let exercise = lastWeek.repsDropped.first { return make(base, .heldRepsDropped(exercise: exercise)) }
        if let exercise = lastWeek.overEffort.first { return make(base, .heldTooHard(exercise: exercise)) }
        if let state, state.status != .fresh { return make(base, .heldNotRecovered) }
        return make(base + max(1, min(2, sessions)), .added)
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

    /// Movements in a session of this length that train `muscle` as their main muscle.
    static func directSlots(_ muscle: Muscle, focus: WorkoutFocus, minutes: Int) -> Int {
        let count = WorkoutPlanner.exerciseCount(minutes: minutes)
        var slots = Array(focus.slots.prefix(count))
        if minutes >= WorkoutPlanner.longSessionMinutes { slots.append(focus.extraSlot) }
        return slots.filter { MuscleCoverage.muscles(for: $0).primary == muscle }.count
    }

    /// Sessions in the plan that train a muscle directly, and the sets their
    /// time can hold (each session: its direct movements × 5 sets, at most
    /// `sessionCap`). In a flexible week the session templates stand in for the
    /// days: the coverage rule may move a focus, but the templates are the
    /// week's usual spread.
    public static func capacity(_ muscle: Muscle, days: [PlannedDay]) -> (sessions: Int, timeCap: Int) {
        var sessions = 0
        var cap = 0
        for day in days {
            let slots = directSlots(muscle, focus: day.focus, minutes: day.minutes)
            guard slots > 0 else { continue }
            sessions += 1
            cap += min(sessionCap(minutes: day.minutes), slots * TrainingBlock.setRange.upperBound)
        }
        return (sessions, cap)
    }

    /// Every tracked muscle's target this week. Muscles the plan doesn't train
    /// directly get none (their sets come from other movements as helpers).
    public static func week(
        weekStart: Date,
        block: TrainingBlock.WeekState,
        style: TrainingStyle,
        days: [PlannedDay],
        previous: WeekTargets?,
        lastWeek: [Muscle: Performance],
        states: [Muscle: MuscleRecovery.State]
    ) -> WeekTargets {
        var targets: [Target] = []
        for muscle in MuscleCoverage.tracked {
            let room = capacity(muscle, days: days)
            guard room.sessions > 0 else { continue }
            targets.append(target(
                for: muscle, previous: previous?.target(for: muscle)?.sets, week: block, style: style,
                lastWeek: lastWeek[muscle], state: states[muscle], sessions: room.sessions, timeCap: room.timeCap
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
    public static func sessionGoals(
        targets: WeekTargets,
        doneThisWeek: [Muscle: Double],
        focus: WorkoutFocus,
        minutes: Int,
        laterSessions: [PlannedDay]
    ) -> [Muscle: Int] {
        var goals: [Muscle: Int] = [:]
        for target in targets.targets {
            guard directSlots(target.muscle, focus: focus, minutes: minutes) > 0 else { continue }
            let later = laterSessions.filter { directSlots(target.muscle, focus: $0.focus, minutes: $0.minutes) > 0 }.count
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
