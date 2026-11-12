import Foundation
import Testing
@testable import AppCore

// Scenario sweep of the lifting planner (`WorkoutPlanner` and friends): many
// generated plans across gyms, focuses, lengths, styles, lifters, recovery,
// block weeks, pain, never-again lists, the abs finisher and history, then a
// multi-week simulation (plan → a simulated lifter does the session → log →
// plan again), and the weekly schedulers (`AdaptiveWeek`, flexible weeks).
//
// Every invariant collects its violations, with the exact scenario, and
// reports them together (`Issue.record`), so one run shows every failure.
// Invariants that fail today because of a known planner bug are wrapped in
// `withKnownIssue("known bug: …")`, so the suite stays green and flags the
// day the bug is fixed (a known issue that stops failing is reported).
//
// Set PLANNER_SIM_DUMP=/path/file.txt to write every violation to a file.

// MARK: - Violations

struct SimViolation: Sendable {
    var invariant: SimInvariant
    var scenario: String
    var detail: String
}

enum SimInvariant: String, CaseIterable, Sendable, CustomStringConvertible {
    case estimateConsistent
    case timeOverLength
    case timeUnderWithoutNote
    case emptyPlan
    case compoundAtLeastThreeSets
    case setsInRange
    case exerciseInCatalog
    case equipmentAvailable
    case loadAchievable
    case warmUpAchievable
    case loadWithinPainCap
    case dumbbellPerHandPlausible
    case firstTimeLoadPlausible
    case firstTimeLoadNotRoundedUpHeavy
    case loadWithinCapability
    case noDuplicateExercise
    case absPresentWithFinisher
    case absNotTwice
    case finisherFitsItsMinutes
    case painfulAreaNotLoaded
    case painRegressionNoted
    case neverAgainRespected
    case repRangeMatchesStyle
    case targetRepsInRange
    case effortReasonable
    case restReasonable
    case sessionVolumePerMuscle
    // Week-level
    case pushPullBalancedPerWeek
    case weeklySetsWithinBand
    // Multi-week progression
    case progressionNoRunaway
    case progressionNoBigJump
    case progressionNoCollapseAfterDeload
    case progressionRises
    case progressionNoOscillation
    case doubleProgressionReps
    case doubleProgressionStepOnlyAtTop
    // Schedulers
    case adaptiveOneSessionPerDay
    case adaptiveMissedMovesForward
    case adaptiveNoSessionAfterLifting
    case flexibleNoSecondSessionSuggested
    case flexibleTrainsWhenWeekNeedsIt
    // Robustness
    case robustNoNaN

    var description: String { rawValue }

    /// Invariants that fail today because of a planner bug (see the report
    /// in the test names / PR). Nil = must pass.
    var knownBug: String? {
        SimKnownBugs.reasons[self]
    }
}

/// Invariants that fail today, each with its root cause (see also
/// `PlannerBugReproTests` for a minimal case of each). Remove an entry once
/// the bug is fixed: `withKnownIssue` reports a known issue that stops failing.
enum SimKnownBugs {
    // The 2026-11 planner pass fixed the rest (pain-cap ratchet, set-mode stall, slow catch-up,
    // empty bar, ping-pong, full-body balance, bodyweight pull, compound sets, short-session
    // warm-ups, regression starting weights, stale estimate, big-jump rep target, per-session volume,
    // weekly targets the gym's equipment or time can't meet, easy sets at the gym's heaviest weight,
    // and the step up → miss → back down cycle near the limit on coarse steps).
    static let reasons: [SimInvariant: String] = [:]
}

struct SimReport {
    var violations: [SimInvariant: [SimViolation]] = [:]
    var plans = 0

    mutating func add(_ invariant: SimInvariant, _ scenario: String, _ detail: String) {
        violations[invariant, default: []].append(SimViolation(invariant: invariant, scenario: scenario, detail: detail))
    }

    mutating func merge(_ other: SimReport) {
        plans += other.plans
        for (key, list) in other.violations { violations[key, default: []] += list }
    }

    /// Records every violation of `invariant` as one issue: the count, then
    /// examples with distinct details first (so one bug doesn't hide another).
    func record(_ invariant: SimInvariant, examples: Int = 12) {
        let list = violations[invariant] ?? []
        guard !list.isEmpty else { return }
        var seen: Set<String> = []
        var picked: [SimViolation] = []
        for violation in list {
            let key = String(violation.detail.prefix(60))
            if seen.insert(key).inserted { picked.append(violation) }
            if picked.count >= examples { break }
        }
        let scenarios = Set(list.map(\.scenario)).count
        let lines = picked.map { "  • \($0.detail)\n      in: \($0.scenario)" }.joined(separator: "\n")
        Issue.record("\(invariant): \(list.count) violation(s) in \(scenarios) scenario(s) of \(plans) runs. Examples:\n\(lines)")
    }

    /// Records `invariant`, as a known issue when it's a known bug.
    func check(_ invariant: SimInvariant) {
        if let bug = invariant.knownBug {
            withKnownIssue("known bug: \(bug)") { record(invariant) }
        } else {
            record(invariant)
        }
    }

    func dump(to path: String, title: String) {
        var text = "# \(title): \(plans) runs\n"
        for invariant in SimInvariant.allCases {
            let list = violations[invariant] ?? []
            text += "\n## \(invariant) (\(list.count))\n"
            for violation in list { text += "- \(violation.detail) | \(violation.scenario)\n" }
        }
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Fixtures

enum SimFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Monday 5 January 2026, 00:00 UTC.
    static let monday: Date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!

    struct Gym: Sendable {
        var name: String
        var profile: GymProfile
    }

    static let homeDumbbellsKg = GymProfile(
        name: "Home DB set", unit: .kg, equipment: [.dumbbell, .bench],
        barbellWeight: 20, ezBarWeight: 10, smithBarWeight: 10, plates: [],
        dumbbells: [4, 6, 8, 10, 12.5, 15, 17.5, 20, 22.5, 25], kettlebells: [],
        cableStack: WeightStack(start: 5, step: 5, max: 100), machineStack: WeightStack(start: 5, step: 5, max: 150)
    )

    static let barbellRack = GymProfile(
        name: "Garage rack", unit: .kg, equipment: [.barbell, .bench, .squatRack, .pullUpBar],
        barbellWeight: 20, ezBarWeight: 10, smithBarWeight: 10,
        plates: [PlateCount(weight: 20, pairs: 2), PlateCount(weight: 10, pairs: 2), PlateCount(weight: 5, pairs: 2),
                 PlateCount(weight: 2.5, pairs: 2), PlateCount(weight: 1.25, pairs: 1)],
        dumbbells: [], kettlebells: [],
        cableStack: WeightStack(start: 5, step: 5, max: 100), machineStack: WeightStack(start: 5, step: 5, max: 150)
    )

    static let hotel = GymProfile(
        name: "Hotel machines", unit: .lb, equipment: [.cable, .machine],
        barbellWeight: 45, ezBarWeight: 25, smithBarWeight: 20, plates: [], dumbbells: [], kettlebells: [],
        cableStack: WeightStack(start: 10, step: 10, max: 150), machineStack: WeightStack(start: 10, step: 15, max: 220)
    )

    static let bodyweightOnly = GymProfile(
        name: "Bodyweight", unit: .kg, equipment: [],
        barbellWeight: 20, ezBarWeight: 10, smithBarWeight: 10, plates: [], dumbbells: [], kettlebells: [],
        cableStack: WeightStack(start: 5, step: 5, max: 100), machineStack: WeightStack(start: 5, step: 5, max: 150)
    )

    static let gyms: [Gym] = [
        Gym(name: "commercial-kg", profile: .commercialKilograms),
        Gym(name: "commercial-lb", profile: .commercialPounds),
        Gym(name: "home-DB-kg", profile: homeDumbbellsKg),
        Gym(name: "home-DB-lb-preset", profile: .homeDumbbells),
        Gym(name: "barbell-rack", profile: barbellRack),
        Gym(name: "hotel-machines-lb", profile: hotel),
        Gym(name: "bodyweight", profile: bodyweightOnly)
    ]

    static let lengths = [15, 20, 30, 45, 60, 75, 90, 120]
    static let styles: [TrainingStyle] = [.muscle, .strength, .endurance, .balanced, .strengthAndMuscle]
    /// Goals → style, including a mixed goal (strength + muscle → strength + muscle).
    static let goalStyles: [(String, TrainingStyle)] = [
        ("muscle", GoalPlanner.trainingStyle(Goals(focuses: [.muscle]))),
        ("strength", GoalPlanner.trainingStyle(Goals(focuses: [.strength]))),
        ("endurance", GoalPlanner.trainingStyle(Goals(focuses: [.endurance]))),
        ("general", GoalPlanner.trainingStyle(Goals(focuses: [.health]))),
        ("mixed", GoalPlanner.trainingStyle(Goals(focuses: [.strength, .muscle, .endurance])))
    ]
    static let statuses: [TrainingStatus] = [.novice, .intermediate, .advanced]
    static let masses: [Double?] = [50, 80, 120, nil]
    static let recoveries: [Int?] = [20, 50, 80]
    static let painAreas: [PainArea] = [.knee, .shoulder, .lowerBack]
    static let painLevels = [2, 4, 7]
    static let neverAgainLists: [Set<String>] = [
        [],
        ["Barbell_Squat", "Pullups"],
        ["Barbell_Bench_Press_-_Medium_Grip", "Dumbbell_Bench_Press", "Leg_Press", "Wide-Grip_Lat_Pulldown", "Romanian_Deadlift"],
        Set((ExerciseCatalog.options[.horizontalPress] ?? []).map(\.id))
    ]

    static func blockWeeks(_ style: TrainingStyle) -> [TrainingBlock.WeekState?] {
        [nil] + TrainingBlock.schedule(style: style).map { Optional($0) }
    }

    // MARK: Simulated lifter

    /// A realistic 1RM in kg for the slot's reference lift for this lifter:
    /// the strength-standard column for their status (`LoadEstimator`), a
    /// little above it, times the variant's factor.
    static func trueOneRepMaxKg(exerciseID: String, slot: MovementSlot, sex: BiologicalSex, massKg: Double,
                                status: TrainingStatus) -> Double {
        let fraction = LoadEstimator.bodyweightFraction(slot: slot, sex: sex, status: status) ?? {
            let male: Double = switch slot {
            case .chestFly: 0.3
            case .lateralRaise: 0.08
            case .triceps: 0.25
            case .rearDelt: 0.15
            case .hammerCurl: 0.12
            case .calves: 0.8
            default: 0.3
            }
            let byStatus: Double = switch status {
            case .untrained, .novice: 1
            case .intermediate: 1.3
            case .advanced: 1.6
            }
            return (sex == .female ? male * 0.65 : male) * byStatus
        }()
        let factor = LoadEstimator.exerciseFactor(exerciseID) ?? 1
        return massKg * fraction * 1.1 * factor
    }

    /// History as `LiftHistory.make` builds it: the two first options of
    /// every slot the gym supports, a few weeks of sets at about 10 reps, RPE 8.
    static func history(gym: GymProfile, style: TrainingStyle, sex: BiologicalSex, massKg: Double?,
                        status: TrainingStatus, daysAgo: Double = 3) -> [String: ExerciseHistory] {
        let planner = WorkoutPlanner(gym: gym, style: style)
        let mass = massKg ?? 75
        var result: [String: ExerciseHistory] = [:]
        for slot in MovementSlot.allCases {
            for (rank, exercise) in planner.alternatives(for: slot).prefix(2).enumerated() {
                let date = monday.addingTimeInterval(-86_400 * (daysAgo + Double(rank) * 4))
                guard let kind = exercise.load else {
                    result[exercise.id] = ExerciseHistory(bestEstimatedOneRepMax: 0, lastWeight: 0, lastReps: 10, lastRPE: 8,
                                                          lastDate: date, recentWeights: [0, 0, 0], lastSets: 3)
                    continue
                }
                let oneRM = gym.unit.fromKilograms(trueOneRepMaxKg(exerciseID: exercise.id, slot: slot, sex: sex,
                                                                   massKg: mass, status: status))
                let weight = gym.load(atMost: oneRM / (1 + 12.0 / 30), on: kind) ?? 0
                let reps = 9 + rank
                let e1RM = OneRepMax.estimate(weight: weight, reps: reps, rpe: 8)
                result[exercise.id] = ExerciseHistory(bestEstimatedOneRepMax: e1RM, lastWeight: weight, lastReps: reps,
                                                      lastRPE: 8, lastDate: date, recentWeights: [weight, weight, weight],
                                                      lastSets: 3)
            }
        }
        return result
    }

    /// Small deterministic PRNG for the random sweep.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

// MARK: - One plan

struct PlanScenario: Sendable, CustomStringConvertible {
    var gym: SimFixtures.Gym
    var focus: WorkoutFocus
    var minutes: Int
    var style: TrainingStyle
    var status: TrainingStatus = .novice
    var sex: BiologicalSex = .male
    var massKg: Double? = 80
    var recovery: Int? = 80
    var block: TrainingBlock.WeekState? = nil
    var pains: [PainReport] = []
    var neverAgain: Set<String> = []
    var finisher: AbsFinisher.Length = .off
    var withHistory = false
    var warmUpMinutes = 0

    var description: String {
        let blockText = block.map { "w\($0.week)/\($0.length)\($0.isDeload ? "-deload" : "")" } ?? "none"
        let massText = massKg.map { "\(Int($0))kg" } ?? "nil"
        let painText = pains.map { "\($0.area.rawValue)@\($0.level)" }.joined(separator: ",")
        return "gym=\(gym.name) focus=\(focus.rawValue) min=\(minutes) style=\(style.rawValue) \(status.rawValue) \(sex.rawValue) \(massText) "
            + "recovery=\(recovery.map(String.init) ?? "nil") block=\(blockText) pain=[\(painText)] "
            + "never=\(neverAgain.count) abs=\(finisher.label) history=\(withHistory) warmUp=\(warmUpMinutes)"
    }

    var filter: ExerciseFilter {
        ExerciseFilter(neverAgain: neverAgain, pains: pains)
    }

    struct Output {
        var workout: PlannedWorkout
        var finisher: AbsFinisher.Plan?
        var history: [String: ExerciseHistory]
    }

    /// Plans the way the workout builder does (`WorkoutBuilderView.rebuild`, `refreshFinisher`).
    func run() -> Output {
        let planner = WorkoutPlanner(gym: gym.profile, style: style)
        let history = withHistory
            ? SimFixtures.history(gym: gym.profile, style: style, sex: sex, massKg: massKg, status: status)
            : [:]
        let filter = self.filter
        let workout = planner.plan(focus: focus, minutes: minutes, recovery: recovery, history: history, block: block,
                                   bodyMassKg: massKg, sex: sex, trainingStatus: status, warmUpMinutes: warmUpMinutes,
                                   exerciseFilter: filter.isEmpty ? nil : filter, includeCore: finisher == .off)
        var finisherPlanner = planner
        finisherPlanner.exerciseFilter = filter
        let abs = (finisher == .off || workout.exercises.isEmpty) ? nil : AbsFinisher.make(
            length: finisher, planner: finisherPlanner, history: history,
            excluding: Set(workout.exercises.map(\.exerciseID)), sessionRPE: workout.targetRPE,
            firstGroup: AbsFinisher.nextGroup(after: workout.exercises))
        return Output(workout: workout, finisher: abs, history: history)
    }
}

enum PlanChecks {
    /// The style's rep range for a slot (`WorkoutPlanner.prescribe`); `heavy`
    /// is the session's first big lift in the strength + muscle style.
    static func expectedReps(style: TrainingStyle, slot: MovementSlot, exerciseID: String, heavy: Bool = false) -> ClosedRange<Int> {
        if CoreMoves.move(id: exerciseID)?.isHold == true { return CoreMoves.holdSeconds }
        let compound = slot.isCompound
        switch style {
        case .balanced: return compound ? 6...8 : (slot == .core ? 10...15 : 10...12)
        case .strength: return compound ? 3...6 : (slot == .core ? 8...12 : 8...10)
        case .muscle: return compound ? 6...10 : (slot == .core ? 10...15 : 8...12)
        case .strengthAndMuscle:
            if compound && heavy { return 4...6 }
            return compound ? 6...10 : (slot == .core ? 10...15 : 8...12)
        case .endurance: return compound ? 10...15 : 12...20
        }
    }

    /// Per-hand ceiling for a first-time weight, as a share of body mass:
    /// roughly an advanced lifter's working weight (ExRx advanced 1RM
    /// standards × ~0.75 for a set of 6+), per lift family.
    static func firstTimeCeilingFraction(slot: MovementSlot, sex: BiologicalSex) -> Double {
        let male: Double = switch slot {
        case .squat: 1.6   // leg press sleds run higher: checked with factor below
        case .hinge: 1.6
        case .horizontalPress, .inclinePress: 1.1
        case .verticalPress: 0.75
        case .horizontalRow, .verticalPull: 1.0
        case .singleLeg: 1.0
        case .legCurl, .legExtension: 0.9
        case .calves: 1.6
        case .biceps, .triceps: 0.5
        case .hipThrust: 1.8
        default: 0.4
        }
        return sex == .female ? male * 0.7 : male
    }

    static func achievable(_ load: Double, kind: EquipmentKind, gym: GymProfile) -> Bool {
        gym.achievableLoads(for: kind).contains { abs($0 - load) < 0.001 }
    }

    static func check(_ scenario: PlanScenario, _ output: PlanScenario.Output, into report: inout SimReport) {
        let s = scenario.description
        let gym = scenario.gym.profile
        let workout = output.workout
        let main = workout.exercises
        let finisherExercises = output.finisher?.exercises ?? []
        let all = main + finisherExercises
        let deload = scenario.block?.isDeload == true
        let filter = scenario.filter
        let avoid = filter.avoidAreas
        let regress = Set(filter.regressAreas)

        // Time.
        let estimate = workout.estimatedMinutes ?? -1
        let recomputed = WorkoutPlanner.estimatedMinutes(main, style: scenario.style, warmUpMinutes: scenario.warmUpMinutes)
        if estimate != recomputed {
            report.add(.estimateConsistent, s, "estimatedMinutes \(estimate) but the exercises add up to \(recomputed)")
        }
        if scenario.minutes > 0 {
            let minutes = Double(scenario.minutes)
            // A movement warm-up can leave a short session no room: allowed at the
            // planner's minimum (two exercises) when the plan says so (`lengthNote`).
            let overExplained = workout.lengthNote != nil && scenario.warmUpMinutes > 0 && main.count <= 2
            if Double(estimate) > minutes * 1.1 + 0.5, !overExplained {
                report.add(.timeOverLength, s, "estimate \(estimate) min > \(scenario.minutes) + 10% "
                    + "(\(main.count) ex, \(workout.totalSets) sets: \(main.map { "\($0.name)×\($0.sets)" }.joined(separator: ", ")))")
            }
            if Double(estimate) < minutes * 0.9 - 0.5, workout.lengthNote == nil {
                report.add(.timeUnderWithoutNote, s, "estimate \(estimate) of \(scenario.minutes) min (\(Int(Double(estimate) / minutes * 100))%) "
                    + "with no lengthNote; \(main.count) ex, \(workout.totalSets) sets: \(main.map { "\($0.name)×\($0.sets)" }.joined(separator: ", "))")
            }
            // Empty is honest when pain or never-again rule out the whole focus and the plan says why.
            let emptyExplained = workout.lengthNote.map { !$0.contains("every set this plan can add") } ?? false
            if main.isEmpty, scenario.minutes >= 15, !emptyExplained {
                report.add(.emptyPlan, s, "no exercises at all (lengthNote: \(workout.lengthNote ?? "nil"))")
            }
        }

        var ids: [String] = []
        for (position, exercise) in all.enumerated() {
            ids.append(exercise.exerciseID)
            let finisher = exercise.isFinisher == true
            guard let catalog = ExerciseCatalog.exercise(id: exercise.exerciseID),
                  let slot = ExerciseCatalog.slot(for: exercise.exerciseID) else {
                report.add(.exerciseInCatalog, s, "\(exercise.exerciseID) isn't in the catalog")
                continue
            }
            let tag = "\(exercise.name) [\(slot.rawValue)]"

            // Sets.
            // Big lifts keep 3 sets; 2 (the ACSM's 2-3) is fine where 3 can't fit: sessions of 20 min
            // or less, or a movement warm-up taking a third of the time.
            let tight = scenario.minutes <= 20 || scenario.warmUpMinutes * 3 >= scenario.minutes
            let fewest = tight ? WorkoutPlanner.minimumSetsWhenShort : WorkoutPlanner.minimumCompoundSets
            if slot.isCompound, !finisher, !deload, exercise.sets < fewest {
                report.add(.compoundAtLeastThreeSets, s, "\(tag) has \(exercise.sets) sets (superset \(exercise.supersetGroup.map(String.init) ?? "-"))")
            }
            if exercise.sets < 1 || exercise.sets > TrainingBlock.setRange.upperBound {
                report.add(.setsInRange, s, "\(tag) has \(exercise.sets) sets")
            }

            // Equipment.
            let missing = catalog.requires.filter { !gym.has($0) }
            if !missing.isEmpty {
                report.add(.equipmentAvailable, s, "\(tag) needs \(missing.map(\.rawValue).sorted())")
            }
            if exercise.loadKind != catalog.load {
                report.add(.equipmentAvailable, s, "\(tag) loadKind \(String(describing: exercise.loadKind)) vs catalog \(String(describing: catalog.load))")
            }

            // Loads.
            if let load = exercise.load {
                if !load.isFinite || load <= 0 {
                    report.add(.robustNoNaN, s, "\(tag) load \(load)")
                }
                if let kind = exercise.loadKind {
                    if !achievable(load, kind: kind, gym: gym) {
                        report.add(.loadAchievable, s, "\(tag) load \(load) \(gym.unit.rawValue) can't be made on \(kind.rawValue)")
                    }
                    for ramp in exercise.warmUpSets ?? [] where !achievable(ramp.load, kind: kind, gym: gym) || ramp.load >= load - 0.001 {
                        report.add(.warmUpAchievable, s, "\(tag) ramp \(ramp.load) for working \(load)")
                    }
                    for stage in exercise.stages ?? [] {
                        if let stageLoad = stage.load, !achievable(stageLoad, kind: kind, gym: gym) {
                            report.add(.loadAchievable, s, "\(tag) stage load \(stageLoad)")
                        }
                    }
                    if let cap = exercise.maxLoadKg, gym.unit.toKilograms(load) > cap + 0.01 {
                        report.add(.loadWithinPainCap, s, "\(tag) load \(load) above its pain cap \(cap) kg")
                    }
                    let kg = gym.unit.toKilograms(load)
                    if kind == .dumbbell || kind == .kettlebell {
                        let mass = scenario.massKg ?? 80
                        if kg > mass * 0.65 || kg > 70 {
                            report.add(.dumbbellPerHandPlausible, s, "\(tag) \(load) \(gym.unit.rawValue) per hand (\(Int(kg)) kg) for a \(Int(mass)) kg lifter")
                        }
                    }
                    let past = output.history[exercise.exerciseID]
                    if past == nil, let mass = scenario.massKg {
                        // First time: under an advanced lifter's working weight for this body mass.
                        let factor = LoadEstimator.exerciseFactor(exercise.exerciseID) ?? 1
                        let ceiling = mass * firstTimeCeilingFraction(slot: slot, sex: scenario.sex) * max(1, factor)
                        if kg > ceiling + 0.01, kg > gym.unit.toKilograms(gym.achievableLoads(for: kind).first ?? 0) + 0.01 {
                            report.add(.firstTimeLoadPlausible, s, "\(tag) first-time \(load) \(gym.unit.rawValue) (\(Int(kg)) kg) > ceiling \(Int(ceiling)) kg")
                        }
                        // A body-weight estimate rounded *up* to the lightest weight far above it.
                        if exercise.note?.contains("your body weight") == true,
                           exercise.note?.contains("lightest weight here may be heavy") != true,
                           let fraction = LoadEstimator.bodyweightFraction(slot: slot, sex: scenario.sex, status: scenario.status) {
                            let reps = LoadEstimator.estimateReps(exercise.reps)
                            let raw = gym.unit.fromKilograms(mass) * fraction
                                * factor / (1 + (Double(reps) + max(0, 10 - exercise.rpe)) / 30) * LoadEstimator.conservativeFraction
                            if load > raw * 1.5, load - raw > 2 {
                                report.add(.firstTimeLoadNotRoundedUpHeavy, s, "\(tag) first-time \(load) \(gym.unit.rawValue) vs body-weight estimate \(String(format: "%.1f", raw)) (lightest load on \(kind.rawValue))")
                            }
                        }
                    }
                    if let past, past.bestEstimatedOneRepMax > 0 {
                        let doable = past.bestEstimatedOneRepMax / (1 + Double(exercise.reps.lowerBound) / 30)
                        if load > doable * 1.05 + (gym.smallestJump(from: doable, on: kind) ?? 0) {
                            report.add(.loadWithinCapability, s, "\(tag) \(load) > what e1RM \(String(format: "%.1f", past.bestEstimatedOneRepMax)) allows for \(exercise.reps.lowerBound) reps (\(String(format: "%.1f", doable)))")
                        }
                    }
                } else {
                    report.add(.loadAchievable, s, "\(tag) has a load \(load) but no load kind")
                }
            }

            // Pain and never again.
            let areas = PainGuard.areas(forExerciseID: exercise.exerciseID, slot: slot)
            let hit = areas.intersection(avoid)
            if !hit.isEmpty {
                report.add(.painfulAreaNotLoaded, s, "\(tag) loads \(hit.map(\.rawValue).sorted()) at ≥6/10")
            }
            let eased = areas.intersection(regress)
            if !eased.isEmpty, !eased.contains(where: { exercise.note?.contains($0.possessive) == true }) {
                report.add(.painRegressionNoted, s, "\(tag) loads \(eased.map(\.rawValue).sorted()) (3-5/10) without the easy-going note")
            }
            if scenario.neverAgain.contains(exercise.exerciseID) {
                report.add(.neverAgainRespected, s, "\(tag) is on the never-again list")
            }

            // Reps, effort, rest.
            let heavy = position == 0 && !finisher && scenario.style == .strengthAndMuscle
            let expected = expectedReps(style: scenario.style, slot: slot, exerciseID: exercise.exerciseID, heavy: heavy)
            // At the gym's heaviest weight, or under a big next jump, reps build past the range
            // (`WorkoutPlanner.extendedReps`) rather than leave the sets far from failure. A pain
            // cap (`ExerciseFilter.capLoad`) then lowers the load and keeps those reps.
            let weightCapped = exercise.maxLoadKg != nil || exercise.load.flatMap { load in
                exercise.loadKind.map { kind in
                    gym.nextLoad(above: load, on: kind).map { ($0 - load) / load > WorkoutPlanner.routineJumpFraction + 0.0001 } ?? true
                }
            } ?? false
            let roof = weightCapped ? WorkoutPlanner.maximumExtendedReps : expected.upperBound + WorkoutPlanner.bigJumpExtraReps
            if exercise.reps.lowerBound != expected.lowerBound || exercise.reps.upperBound < expected.upperBound
                || exercise.reps.upperBound > roof {
                report.add(.repRangeMatchesStyle, s, "\(tag) reps \(exercise.reps) for \(scenario.style.rawValue) (expected \(expected))")
            }
            if let target = exercise.targetReps, !exercise.reps.contains(target) {
                report.add(.targetRepsInRange, s, "\(tag) target \(target) outside \(exercise.reps)")
            }
            if !(5...10).contains(exercise.rpe) || !exercise.rpe.isFinite {
                report.add(.effortReasonable, s, "\(tag) RPE \(exercise.rpe)")
            }
            if let rest = exercise.restSeconds, !(15...300).contains(rest) {
                report.add(.restReasonable, s, "\(tag) rest \(rest) s")
            }
        }
        // One session's direct sets for a muscle: about 10 at most (`VolumeProgression.sessionCap`).
        for (muscle, sets) in VolumeProgression.directSets(main) where sets > VolumeProgression.sessionCap(minutes: max(0, scenario.minutes)) + 2 {
            report.add(.sessionVolumePerMuscle, s, "\(muscle.name): \(sets) direct sets in one session (cap \(VolumeProgression.sessionCap(minutes: scenario.minutes)))")
        }
        let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
        if !duplicates.isEmpty {
            report.add(.noDuplicateExercise, s, "duplicates \(duplicates.sorted())")
        }

        // Abs finisher.
        if scenario.finisher != .off, !main.isEmpty {
            if finisherExercises.isEmpty {
                report.add(.absPresentWithFinisher, s, "finisher \(scenario.finisher.label) on, but no abs moves")
            }
            if main.contains(where: { ExerciseCatalog.slot(for: $0.exerciseID) == .core }) {
                report.add(.absNotTwice, s, "finisher on and the session still has a core movement")
            }
            if let plan = output.finisher, plan.estimatedMinutes > scenario.finisher.minutes + 1 {
                report.add(.finisherFitsItsMinutes, s, "\(plan.title) estimated \(plan.estimatedMinutes) min")
            }
        }
    }
}

// MARK: - The sweep

enum PlannerSweep {
    static let result: SimReport = {
        var report = SimReport()
        func run(_ scenario: PlanScenario) {
            let output = scenario.run()
            report.plans += 1
            PlanChecks.check(scenario, output, into: &report)
        }

        // 1. The grid: every gym × focus × length × style, the other inputs rotating.
        var index = 0
        for gym in SimFixtures.gyms {
            for focus in WorkoutFocus.allCases {
                for minutes in SimFixtures.lengths {
                    for style in SimFixtures.styles {
                        index += 1
                        var scenario = PlanScenario(gym: gym, focus: focus, minutes: minutes, style: style)
                        scenario.status = SimFixtures.statuses[index % 3]
                        scenario.sex = index % 2 == 0 ? .male : .female
                        scenario.massKg = SimFixtures.masses[index % SimFixtures.masses.count]
                        scenario.recovery = SimFixtures.recoveries[(index / 2) % 3]
                        scenario.finisher = AbsFinisher.Length.allCases[(index / 3) % 3]
                        for history in [false, true] {
                            scenario.withHistory = history
                            run(scenario)
                        }
                    }
                }
            }
        }

        // 2. Block weeks (deload included) × style × focus × a few lengths.
        for gym in [SimFixtures.gyms[0], SimFixtures.gyms[2], SimFixtures.gyms[5]] {
            for style in SimFixtures.styles {
                for block in SimFixtures.blockWeeks(style) {
                    for focus in WorkoutFocus.allCases {
                        for minutes in [30, 60, 90] {
                            for recovery in SimFixtures.recoveries {
                                var scenario = PlanScenario(gym: gym, focus: focus, minutes: minutes, style: style)
                                scenario.block = block
                                scenario.recovery = recovery
                                scenario.withHistory = true
                                run(scenario)
                            }
                        }
                    }
                }
            }
        }

        // 3. Pain: area × level × gym × focus, finisher off and 10 min.
        for gym in SimFixtures.gyms {
            for area in SimFixtures.painAreas {
                for level in SimFixtures.painLevels {
                    for focus in WorkoutFocus.allCases {
                        for minutes in [30, 60] {
                            for finisher in [AbsFinisher.Length.off, .ten] {
                                var scenario = PlanScenario(gym: gym, focus: focus, minutes: minutes, style: .balanced)
                                scenario.pains = [PainReport(area: area, level: level, loggedAt: SimFixtures.monday)]
                                scenario.finisher = finisher
                                scenario.withHistory = level == 4
                                run(scenario)
                            }
                        }
                    }
                }
            }
        }

        // 4. Lifters for first-time loads: status × sex × mass × gym × focus.
        for gym in SimFixtures.gyms {
            for status in SimFixtures.statuses {
                for sex in BiologicalSex.allCases {
                    for mass in SimFixtures.masses {
                        for focus in WorkoutFocus.allCases {
                            var scenario = PlanScenario(gym: gym, focus: focus, minutes: 60, style: .balanced)
                            scenario.status = status
                            scenario.sex = sex
                            scenario.massKg = mass
                            run(scenario)
                        }
                    }
                }
            }
        }

        // 5. Random mix of everything (never-again lists, two pains, warm-ups, goals).
        var rng = SimFixtures.SplitMix(state: 0x7E57_1E)
        for _ in 0..<2500 {
            let gym = SimFixtures.gyms.randomElement(using: &rng)!
            let style = SimFixtures.goalStyles.randomElement(using: &rng)!.1
            var scenario = PlanScenario(gym: gym, focus: WorkoutFocus.allCases.randomElement(using: &rng)!,
                                        minutes: SimFixtures.lengths.randomElement(using: &rng)!, style: style)
            scenario.status = SimFixtures.statuses.randomElement(using: &rng)!
            scenario.sex = BiologicalSex.allCases.randomElement(using: &rng)!
            scenario.massKg = SimFixtures.masses.randomElement(using: &rng)!
            scenario.recovery = ([nil] + SimFixtures.recoveries).randomElement(using: &rng)!
            scenario.block = SimFixtures.blockWeeks(style).randomElement(using: &rng)!
            let painCount = Int.random(in: 0...2, using: &rng)
            scenario.pains = SimFixtures.painAreas.shuffled(using: &rng).prefix(painCount).map {
                PainReport(area: $0, level: SimFixtures.painLevels.randomElement(using: &rng)!, loggedAt: SimFixtures.monday)
            }
            scenario.neverAgain = SimFixtures.neverAgainLists.randomElement(using: &rng)!
            scenario.finisher = AbsFinisher.Length.allCases.randomElement(using: &rng)!
            scenario.withHistory = Bool.random(using: &rng)
            scenario.warmUpMinutes = [0, 0, 5, 10].randomElement(using: &rng)!
            run(scenario)
        }
        return report
    }()
}

// MARK: - Multi-week simulation

struct LiftSimulation {
    enum Behaviour: String, Sendable {
        /// Does the target reps when able, reports RPE honestly.
        case honest
        /// Every third exposure of a lift misses two reps (bad day).
        case missesSometimes
        /// Always reports RPE 9.5+.
        case reportsHigh
        /// Always reports RPE 6 or less.
        case reportsLow
    }

    var name: String
    var gym: SimFixtures.Gym
    var style: TrainingStyle
    var sex: BiologicalSex
    var massKg: Double
    var status: TrainingStatus
    var days: [WorkoutFocus]
    var minutes: Int
    var weeks = 12
    var behaviour: Behaviour = .honest
    /// Recovery for (week, session).
    var recovery: @Sendable (Int, Int) -> Int? = { _, _ in 80 }
    var pains: [PainReport] = []

    var description: String {
        "sim=\(name) gym=\(gym.name) style=\(style.rawValue) \(sex.rawValue) \(Int(massKg))kg \(status.rawValue) "
            + "days=\(days.map(\.shortTitle)) min=\(minutes) weeks=\(weeks) behaviour=\(behaviour.rawValue)"
    }

    struct Point {
        var week: Int
        var session: Int
        var load: Double
        var reps: ClosedRange<Int>
        var targetReps: Int
        var sets: Int
        var deload: Bool
        var rpeTarget: Double
        var recovery: Int?
        var lastReps: Int?
        var lastRPE: Double?
        var lastWeight: Double?
        var lastWasLighter: Bool
        var capability: Double
        var compound: Bool
        var progressionNote: String?
    }

    struct Output {
        var series: [String: [Point]] = [:]
        var report = SimReport()
    }

    /// Plan → do → log, `weeks` times, with the block, the weekly set targets
    /// (`VolumeProgression`) and per-session goals, as the app runs them.
    func run() -> Output {
        var output = Output()
        let s = description
        let unit = gym.profile.unit
        let planner = WorkoutPlanner(gym: gym.profile, style: style)
        let schedule = TrainingBlock.schedule(style: style)
        let weekdays = WeeklyPlan.suggestedWeekdays(count: days.count)
        let plannedDays = zip(weekdays, days).map { PlannedDay(weekday: $0, time: 18 * 60, focus: $1, minutes: minutes) }
        var history: [String: ExerciseHistory] = [:]
        var capability: [String: Double] = [:]     // true 1RM in the gym's unit
        var exposures: [String: Int] = [:]
        var logged: [VolumeProgression.LoggedSet] = []
        var previousTargets: VolumeProgression.WeekTargets?
        // Sets the planner can't make harder yet (session start | exercise; see the weekly check).
        var calibrating: Set<String> = []
        let filter = ExerciseFilter(pains: pains)

        for week in 0..<weeks {
            let weekStart = SimFixtures.calendar.date(byAdding: .day, value: 7 * week, to: SimFixtures.monday)!
            let block = schedule[week % schedule.count]
            let lastWeekStart = SimFixtures.calendar.date(byAdding: .day, value: -7, to: weekStart)!
            let lastWeek = VolumeProgression.summarize(logged, weekStart: lastWeekStart, targetRPE: previousTargets?.targetRPE ?? 7,
                                                       style: style, calendar: SimFixtures.calendar)
            let targets = VolumeProgression.week(weekStart: weekStart, block: block, style: style, days: plannedDays,
                                                 previous: previousTargets, lastWeek: lastWeek, states: [:], gym: gym.profile)
            previousTargets = targets
            var weekDirect: [Muscle: Int] = [:]
            var pushSets = 0
            var pullSets = 0

            for (session, day) in plannedDays.enumerated() {
                let start = SimFixtures.calendar.date(byAdding: .day, value: WeeklyPlan.order(day.weekday), to: weekStart)!
                    .addingTimeInterval(18 * 3600)
                let done = VolumeProgression.summarize(logged, weekStart: weekStart, targetRPE: targets.targetRPE, style: style,
                                                       calendar: SimFixtures.calendar).mapValues(\.sets)
                let goals = VolumeProgression.sessionGoals(targets: targets, doneThisWeek: done, focus: day.focus,
                                                           minutes: day.minutes, laterSessions: Array(plannedDays.dropFirst(session + 1)),
                                                           gym: gym.profile)
                let recovery = self.recovery(week, session)
                let workout = planner.plan(focus: day.focus, minutes: day.minutes, recovery: recovery, history: history,
                                           block: block, bodyMassKg: massKg, sex: sex, trainingStatus: status,
                                           exerciseFilter: filter.isEmpty ? nil : filter, muscleSetGoals: goals)
                let scenario = "\(s) week=\(week + 1) (\(block.isDeload ? "deload" : "block w\(block.week)")) session=\(session + 1) \(day.focus.shortTitle)"
                output.report.plans += 1
                for (muscle, sets) in VolumeProgression.directSets(workout.exercises) { weekDirect[muscle, default: 0] += sets }

                for (order, exercise) in workout.exercises.enumerated() {
                    guard let slot = ExerciseCatalog.slot(for: exercise.exerciseID) else { continue }
                    switch slot.muscleGroup {
                    case .push: pushSets += exercise.sets
                    case .pull: pullSets += exercise.sets
                    default: break
                    }
                    let id = exercise.exerciseID
                    let muscles = MuscleCoverage.muscles(for: slot)
                    let past = history[id]
                    exposures[id, default: 0] += 1
                    let target = exercise.repsToday

                    var plannedLoad = exercise.load
                    if plannedLoad == nil, let kind = exercise.loadKind {
                        // "First time: pick a weight": the lifter picks one for the top of the range.
                        let oneRM = unit.fromKilograms(SimFixtures.trueOneRepMaxKg(exerciseID: id, slot: slot, sex: sex,
                                                                                    massKg: massKg, status: status))
                        plannedLoad = gym.profile.load(atMost: oneRM / (1 + Double(exercise.reps.upperBound + 2) / 30), on: kind)
                    }
                    guard let load = plannedLoad, exercise.loadKind != nil else {
                        // Bodyweight: the target reps at the target effort.
                        for set in 0..<exercise.sets {
                            logged.append(VolumeProgression.LoggedSet(
                                exerciseID: id, name: exercise.name, sessionStart: start, order: order * 10 + set,
                                primary: [muscles.primary], secondary: muscles.secondary, weightKg: 0, reps: target,
                                rpe: exercise.rpe, isCompound: slot.isCompound, supersetGroup: exercise.supersetGroup))
                        }
                        history[id] = ExerciseHistory(bestEstimatedOneRepMax: 0, lastWeight: 0, lastReps: target, lastRPE: exercise.rpe,
                                                      lastDate: start, recentWeights: ExerciseHistory.appending(0, to: past?.recentWeights ?? []),
                                                      lastSets: exercise.sets)
                        continue
                    }
                    let oneRM = capability[id] ?? unit.fromKilograms(SimFixtures.trueOneRepMaxKg(
                        exerciseID: id, slot: slot, sex: sex, massKg: massKg, status: status))
                    capability[id] = oneRM
                    output.series[id, default: []].append(Point(
                        week: week, session: session, load: load, reps: exercise.reps, targetReps: target, sets: exercise.sets,
                        deload: block.isDeload, rpeTarget: exercise.rpe, recovery: recovery, lastReps: past?.lastReps,
                        lastRPE: past?.lastRPE, lastWeight: past?.lastWeight, lastWasLighter: past?.lastWasLighter ?? false,
                        capability: oneRM, compound: slot.isCompound, progressionNote: exercise.progressionNote))

                    // Runaway: heavier than the lifter can do for the bottom of the range, fresh,
                    // planned again from logged history (a first-time estimate that misses is
                    // `firstTimeLoadPlausible`'s job; the lifter then adjusts after set 1, below).
                    // A big jump (light dumbbells, coarse stacks: over 10% from the next weight down) may
                    // land under the range (at least half its bottom); you then build reps there
                    // (`WorkoutPlanner.progression`'s `stepWithinReach`).
                    let below = gym.profile.achievableLoads(for: exercise.loadKind ?? .machine).last { $0 < load - 0.001 }
                    let bigStep = below.map { (load - $0) / $0 > WorkoutPlanner.routineJumpFraction + 0.0001 } ?? false
                    let slack = bigStep ? Double(exercise.reps.lowerBound) / 2 : 0.5
                    let plannedCanDo = 30 * (oneRM / load - 1)
                    // The gym's lightest load can't go lighter (the plan notes it).
                    let lightest = gym.profile.achievableLoads(for: exercise.loadKind ?? .machine).first.map { abs($0 - load) < 0.001 } ?? false
                    if plannedCanDo < Double(exercise.reps.lowerBound) - slack, behaviour != .reportsLow, past != nil, !lightest {
                        output.report.add(.progressionNoRunaway, scenario, "\(exercise.name) \(load) \(unit.rawValue): the lifter (1RM \(String(format: "%.1f", oneRM))) can do \(String(format: "%.1f", plannedCanDo)) reps, range \(exercise.reps)")
                    }
                    // "Start here and adjust after set 1": far too heavy, the lifter drops to
                    // a weight they can do the bottom of the range with, and logs that.
                    var done = load
                    if plannedCanDo < Double(exercise.reps.lowerBound) - 0.5, let kind = exercise.loadKind,
                       let lighter = gym.profile.load(atMost: oneRM / (1 + Double(exercise.reps.lowerBound + 2) / 30), on: kind) {
                        done = min(load, lighter)
                    }
                    let canDo = 30 * (oneRM / done - 1)
                    // The weight is still being found (a first session; last time clearly easier than
                    // planned, which the plan answers with a catch-up or more reps; or the first session
                    // at a heavier weight, whose reps are predicted and rounded down), or it's the gym's
                    // heaviest with the reps at the ceiling: the plan can't make these sets harder yet.
                    let easyLastTime = (past?.lastRPE).map { $0 <= exercise.rpe - WorkoutPlanner.catchUpGap + 0.001 } ?? false
                    let heavier = past.map { done > $0.lastWeight + 0.001 } ?? false
                    let atCeiling = gym.profile.nextLoad(above: done, on: exercise.loadKind ?? .machine) == nil
                        && target >= WorkoutPlanner.maximumExtendedReps
                    if past == nil || easyLastTime || heavier || atCeiling {
                        calibrating.insert("\(start.timeIntervalSince1970)|\(id)")
                    }

                    // Do the sets.
                    var sets: [(reps: Int, rpe: Double)] = []
                    for set in 0..<exercise.sets {
                        let failure = canDo - 0.5 * Double(set)
                        var reps = min(target, max(0, Int(failure.rounded(.down))))
                        var rpe = min(10, max(5, ((10 - (failure - Double(reps))) * 2).rounded() / 2))
                        switch behaviour {
                        case .honest: break
                        case .missesSometimes:
                            if exposures[id, default: 0] % 3 == 0 { reps = max(0, reps - 2); rpe = 10 }
                        case .reportsHigh: rpe = max(rpe, 9.5)
                        case .reportsLow: rpe = min(rpe, 6)
                        }
                        sets.append((reps, rpe))
                        logged.append(VolumeProgression.LoggedSet(
                            exerciseID: id, name: exercise.name, sessionStart: start, order: order * 10 + set,
                            primary: [muscles.primary], secondary: muscles.secondary, weightKg: unit.toKilograms(done),
                            reps: reps, rpe: rpe, isCompleted: reps > 0, isCompound: slot.isCompound,
                            supersetGroup: exercise.supersetGroup))
                    }
                    let working = sets.filter { $0.reps > 0 }
                    if let top = working.max(by: { OneRepMax.estimate(weight: done, reps: $0.reps, rpe: $0.rpe)
                        < OneRepMax.estimate(weight: done, reps: $1.reps, rpe: $1.rpe) }) {
                        let e1RM = OneRepMax.estimate(weight: done, reps: top.reps, rpe: top.rpe)
                        history[id] = ExerciseHistory(
                            bestEstimatedOneRepMax: max(past?.bestEstimatedOneRepMax ?? 0, e1RM), lastWeight: done,
                            lastReps: top.reps, lastRPE: top.rpe, lastDate: start,
                            recentWeights: ExerciseHistory.appending(done, to: past?.recentWeights ?? []), lastSets: working.count)
                    }
                    // Training effect: hard sets build strength; a deload holds it.
                    if !block.isDeload, exercise.sets >= 2 {
                        let gain: Double = switch status {
                        case .untrained, .novice: 0.012
                        case .intermediate: 0.006
                        case .advanced: 0.003
                        }
                        capability[id] = oneRM * (1 + gain)
                    }
                }
            }

            // Weekly checks.
            let weekScenario = "\(s) week=\(week + 1) (\(block.isDeload ? "deload" : "block w\(block.week)"))"
            if pushSets + pullSets > 0 {
                let ratio = Double(pushSets) / Double(max(1, pullSets))
                if ratio > 1.5 || ratio < 1 / 1.5 {
                    output.report.add(.pushPullBalancedPerWeek, weekScenario, "push \(pushSets) vs pull \(pullSets) sets this week (ratio \(String(format: "%.2f", ratio)))")
                }
            }
            // A set far from failure counts 0.6 (`VolumeProgression.easySetCredit`: muscle growth falls
            // off with reps in reserve, Robinson et al. 2024). While a lift's weight is still being
            // found, or the gym has nothing heavier and the reps are at the ceiling, the plan can't
            // make its sets harder, so they count in full here: the band then checks the planned
            // volume and the effort of every lift the planner already knows.
            let bandSets = logged.map { set -> VolumeProgression.LoggedSet in
                var set = set
                if calibrating.contains("\(set.sessionStart.timeIntervalSince1970)|\(set.exerciseID)") { set.rpe = nil }
                return set
            }
            let credited = VolumeProgression.summarize(bandSets, weekStart: weekStart, targetRPE: targets.targetRPE, style: style,
                                                       calendar: SimFixtures.calendar)
            let reported = VolumeProgression.summarize(logged, weekStart: weekStart, targetRPE: targets.targetRPE, style: style,
                                                       calendar: SimFixtures.calendar)
            for target in targets.targets {
                let actual = weekDirect[target.muscle] ?? 0
                let done = credited[target.muscle]?.sets ?? 0
                let ceiling = VolumeProgression.ceiling(style: style)
                // Credit depends on the RPE reported, so only the honest lifter is held to the band.
                // A deload's sets are easier on purpose (RIR 3), so some count 0.6: when the planned
                // sets meet the band, the credit shortfall is the deload working as designed.
                let deloadAsPlanned = block.isDeload && actual >= target.band.lowerBound
                if behaviour == .honest, done < Double(target.band.lowerBound) - 0.001, !deloadAsPlanned {
                    let asLogged = reported[target.muscle]?.sets ?? 0
                    output.report.add(.weeklySetsWithinBand, weekScenario, "\(target.muscle.name): \(done.formatted()) sets credited (\(asLogged.formatted()) as logged, \(actual) direct planned), target \(target.sets) (band \(target.bandText), \(target.change))")
                } else if actual > max(target.sets, ceiling) + 4 {
                    output.report.add(.weeklySetsWithinBand, weekScenario, "\(target.muscle.name): \(actual) direct sets planned, target \(target.sets), ceiling \(ceiling)")
                }
            }
        }
        checkSeries(&output)
        return output
    }

    func checkSeries(_ output: inout Output) {
        let s = description
        let gymProfile = gym.profile
        for (id, points) in output.series.sorted(by: { $0.key < $1.key }) {
            let name = ExerciseCatalog.exercise(id: id)?.name ?? id
            guard let kind = ExerciseCatalog.exercise(id: id)?.load else { continue }
            let tag = "\(name)"
            for (previous, point) in zip(points, points.dropFirst()) {
                let at = "\(s) \(tag) week \(point.week + 1) session \(point.session + 1)"
                let step = gymProfile.smallestJump(from: previous.load, on: kind) ?? 0
                // Catching up after a session clearly easier than planned (`WorkoutPlanner.catchUp`):
                // a bigger jump is the point, up to its cap (30% early on).
                let caughtUp = (point.lastRPE ?? 10) <= point.rpeTarget - WorkoutPlanner.catchUpGap + 0.001
                    && (point.lastReps ?? 0) >= point.reps.lowerBound && !point.lastWasLighter
                let jumpCap = caughtUp ? 1 + WorkoutPlanner.catchUpFraction.early : 1.15
                if point.load > previous.load * jumpCap + 0.001, point.load - previous.load > step + 0.001 {
                    output.report.add(.progressionNoBigJump, at, "\(tag) \(previous.load) → \(point.load) (+\(Int((point.load / previous.load - 1) * 100))%, one step is \(step)); last \(point.lastReps ?? 0) reps @RPE \(point.lastRPE ?? 0)")
                }
                // Double progression, at the same weight with effort held: one more rep, never fewer.
                let effortHeld = (point.lastRPE ?? point.rpeTarget) <= point.rpeTarget + 0.001
                if behaviour == .honest, abs(point.load - previous.load) < 0.001, effortHeld, !point.lastWasLighter,
                   let lastReps = point.lastReps, lastReps >= point.reps.lowerBound, lastReps < point.reps.upperBound,
                   point.targetReps < lastReps {
                    output.report.add(.doubleProgressionReps, at, "\(tag) same \(point.load) after \(lastReps) reps @RPE \(point.lastRPE ?? 0), target \(point.targetReps) (range \(point.reps), RPE target \(point.rpeTarget))")
                }
                // The weight steps up only after the top of the range (or coming back from an easier day).
                if point.load > previous.load + 0.001, let lastReps = point.lastReps, !point.lastWasLighter, !caughtUp,
                   let lastWeight = point.lastWeight, point.load > lastWeight + 0.001,
                   lastReps < point.reps.upperBound {
                    output.report.add(.doubleProgressionStepOnlyAtTop, at, "\(tag) \(previous.load) → \(point.load) after only \(lastReps) reps (range \(point.reps)); note: \(point.progressionNote ?? "-")")
                }
                // After a step up, the target is what the new weight allows (audit 2026-11 §4):
                // inside the range and not more than a rep over what the lighter weight got.
                if behaviour == .honest, point.load > previous.load + 0.001, !point.lastWasLighter, !caughtUp, let lastReps = point.lastReps,
                   let lastWeight = point.lastWeight, point.load > lastWeight + 0.001,
                   !point.reps.contains(point.targetReps) || point.targetReps > max(lastReps, point.reps.lowerBound) + 1 {
                    output.report.add(.doubleProgressionReps, at, "\(tag) stepped up to \(point.load) and targets \(point.targetReps) reps after \(lastReps) (range \(point.reps))")
                }
            }
            // After a deload: back to at least ~95% of the best pre-deload weight the
            // lifter actually managed (the bottom of the range at it, as the next session's
            // history shows); a weight they missed reps at needn't come back.
            func achieved(_ position: Int) -> Bool {
                let point = points[position]
                guard position + 1 < points.count, let lastWeight = points[position + 1].lastWeight,
                      abs(lastWeight - point.load) < 0.001 else { return false }
                return (points[position + 1].lastReps ?? 0) >= point.reps.lowerBound
            }
            for (index, point) in points.enumerated() where index > 0 && !point.deload && points[index - 1].deload {
                let candidates = points.indices.prefix(index).filter { !points[$0].deload }.suffix(3).filter(achieved)
                guard let top = candidates.max(by: { points[$0].load < points[$1].load }) else { continue }
                // The week after a deload starts the block again at more reps in reserve: each
                // rep is worth about 3.3% of the load (Epley), so that much lighter is on plan.
                let easier = max(0, points[top].rpeTarget - point.rpeTarget)
                let before = points[top].load * max(0.5, 1 - 0.033 * easier)
                // One load step under that is within rounding on coarse equipment (a 2.5 kg curl step is 10%).
                let step = gymProfile.smallestJump(from: point.load, on: kind) ?? 0
                if point.load < before * 0.95 - step - 0.001 {
                    output.report.add(.progressionNoCollapseAfterDeload, "\(s) \(tag) week \(point.week + 1)",
                                      "\(tag) \(point.load) after the deload vs \(before) before it")
                }
            }
            // Over the weeks an honest, progressing lifter's weights rise; no back-and-forth.
            guard behaviour == .honest else { continue }
            let hard = points.filter { !$0.deload }
            guard hard.count >= 6, let first = hard.first, let last = hard.last else { continue }
            let maxLoad = gymProfile.achievableLoads(for: kind).last ?? 0
            // Coarse equipment (the next weight up 20%+ heavier: 6 → 8 kg dumbbells, a 10 lb cable
            // step at 10 lb) can hold a light lift for months; reps build instead.
            let coarse = gymProfile.nextLoad(above: first.load, on: kind).map { ($0 - first.load) / first.load > 0.2 } ?? false
            // A lift held at a pain cap all along isn't expected to rise, only not to sink.
            let sore = !pains.isEmpty && !PainGuard.areas(forExerciseID: id, slot: ExerciseCatalog.slot(for: id) ?? .core)
                .isDisjoint(with: pains.map(\.area))
            if sore, last.load < first.load - 0.001 {
                output.report.add(.progressionRises, "\(s) \(tag)", "\(tag) sank under its pain cap: \(first.load) → \(last.load)")
            }
            if last.load <= first.load + 0.001, first.load < maxLoad - 0.001, weeks >= 8, !coarse, !sore {
                output.report.add(.progressionRises, "\(s) \(tag)", "\(tag) \(first.load) → \(last.load) over \(hard.count) sessions (1RM \(String(format: "%.1f", first.capability)) → \(String(format: "%.1f", last.capability)))")
            }
            let constantRecovery = Set(points.map { $0.recovery ?? -1 }).count == 1
            if constantRecovery {
                var reversals = 0
                var lastDirection = 0
                // A change in the block's effort target (RIR 3 → 2 → 1, then back to 3) is a planned
                // load change, not a reversal. Nor is one fine step answering an RPE a point off the
                // target: no more than two RPE points' worth of load by Epley (1/(30 + reps + reps in
                // reserve) each: 2.5 kg on a 100 kg row), the line `WorkoutPlanner.repEased` draws.
                // That is RPE autoregulation at work (Helms et al., Strength Cond J 2016; it works
                // as well as fixed loading: Hickmott et al., Sports Med Open 2022). A coarse step
                // (2 kg on 34 kg dumbbells) overshoots the correction, and cycling on it is the bug.
                for (a, b) in zip(hard, hard.dropFirst()) where (a.week == b.week || b.week == a.week + 1)
                    && abs(a.rpeTarget - b.rpeTarget) < 0.01 {
                    let step = gymProfile.smallestJump(from: min(a.load, b.load), on: kind) ?? 0
                    let pointShare = 1 / (30 + Double(a.targetReps) + max(0, 10 - a.rpeTarget))
                    let fine = abs(b.load - a.load) <= step + 0.001 && abs(b.load - a.load) / max(a.load, b.load) <= 2 * pointShare + 1e-9
                    if fine { continue }
                    let direction = b.load > a.load + 0.001 ? 1 : (b.load < a.load - 0.001 ? -1 : 0)
                    if direction != 0 {
                        if lastDirection != 0, direction != lastDirection { reversals += 1 }
                        lastDirection = direction
                    }
                }
                // A rate, not a count: three reversals in a lift trained once a week for 12 weeks,
                // so one in four sessions. Upper days A and B both have a curl and a triceps
                // extension now, so those lifts have twice the sessions in the same weeks.
                if reversals >= max(3, Int((Double(hard.count) / 4).rounded(.up))) {
                    output.report.add(.progressionNoOscillation, "\(s) \(tag)", "\(tag) loads reversed \(reversals)× outside deloads: \(hard.map { "\($0.load)" }.joined(separator: " → "))")
                }
            }
        }
    }

    static let configs: [LiftSimulation] = {
        let gyms = SimFixtures.gyms
        var list: [LiftSimulation] = [
            LiftSimulation(name: "UL4-muscle", gym: gyms[0], style: .muscle, sex: .male, massKg: 80, status: .intermediate,
                           days: [.upper, .lower, .upper, .lower], minutes: 60),
            LiftSimulation(name: "PPL3-strength-lb", gym: gyms[1], style: .strength, sex: .female, massKg: 62, status: .novice,
                           days: [.push, .pull, .legs], minutes: 45),
            LiftSimulation(name: "FB3-homeDB", gym: gyms[2], style: .balanced, sex: .male, massKg: 90, status: .intermediate,
                           days: [.fullBody, .fullBody, .fullBody], minutes: 45),
            LiftSimulation(name: "UL4-rack-strength", gym: gyms[4], style: .strength, sex: .male, massKg: 75, status: .novice,
                           days: [.upper, .lower, .upper, .lower], minutes: 60),
            LiftSimulation(name: "UL2-hotel-endurance", gym: gyms[5], style: .endurance, sex: .female, massKg: 70, status: .intermediate,
                           days: [.upper, .lower], minutes: 30),
            LiftSimulation(name: "PPL6-advanced", gym: gyms[0], style: .muscle, sex: .male, massKg: 95, status: .advanced,
                           days: [.push, .pull, .legs, .push, .pull, .legs], minutes: 75),
            LiftSimulation(name: "FB2-bodyweight", gym: gyms[6], style: .balanced, sex: .female, massKg: 58, status: .novice,
                           days: [.fullBody, .fullBody], minutes: 30),
            LiftSimulation(name: "UL4-balanced-90", gym: gyms[1], style: .balanced, sex: .male, massKg: 100, status: .advanced,
                           days: [.upper, .lower, .upper, .lower], minutes: 90)
        ]
        for behaviour in [Behaviour.missesSometimes, .reportsHigh, .reportsLow] {
            var sim = list[0]
            sim.behaviour = behaviour
            list.append(sim)
            var lb = list[1]
            lb.behaviour = behaviour
            list.append(lb)
        }
        var varying = list[0]
        varying.name = "UL4-muscle-recovery-varies"
        varying.recovery = { week, session in [80, 50, 20, 80, 50][(week * 4 + session) % 5] }
        list.append(varying)
        var sore = list[3]
        sore.name = "UL4-rack-knee4"
        sore.pains = [PainReport(area: .knee, level: 4, loggedAt: SimFixtures.monday)]
        list.append(sore)
        return list
    }()

    static let result: SimReport = {
        var report = SimReport()
        for config in configs { report.merge(config.run().report) }
        return report
    }()
}

// MARK: - Weekly schedulers

enum WeekSimulation {
    static let result: SimReport = {
        var report = SimReport()
        let calendar = SimFixtures.calendar
        var rng = SimFixtures.SplitMix(state: 0xAD_A9)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: SimFixtures.monday)! }

        // Fixed days as a queue (`AdaptiveWeek` + `TrainingDayPlanner.adaptiveGuidance`).
        for count in 1...6 {
            for missRate in [0.0, 0.3, 0.6] {
                for trial in 0..<25 {
                    let weekdays = WeeklyPlan.suggestedWeekdays(count: count)
                    let focuses = WeeklyPlan.focusRotation(start: .push, count: count)
                    let days = zip(weekdays, focuses).map { PlannedDay(weekday: $0, time: 18 * 60, focus: $1, minutes: 45) }
                    let plan = WeeklyPlan(weekStart: SimFixtures.monday, plannedDays: days)
                    var done: [AdaptiveWeek.DoneSession] = []
                    var past: [TrainingDayPlanner.PastDay] = []
                    let s = "adaptive count=\(count) miss=\(missRate) trial=\(trial)"
                    for offset in 0..<7 {
                        let today = day(offset)
                        let at = "\(s) day=\(WeeklyPlan.weekdayName(calendar.component(.weekday, from: today), calendar: calendar))"
                        guard let week = AdaptiveWeek.make(plan: plan, done: done, now: today.addingTimeInterval(12 * 3600),
                                                           calendar: calendar) else {
                            report.add(.adaptiveOneSessionPerDay, at, "AdaptiveWeek.make returned nil")
                            continue
                        }
                        report.plans += 1
                        let dates = week.slots.map(\.date)
                        if Set(dates).count != dates.count {
                            report.add(.adaptiveOneSessionPerDay, at, "two slots on one day: \(dates)")
                        }
                        if week.slots.contains(where: { $0.date < today }) {
                            report.add(.adaptiveMissedMovesForward, at, "a slot in the past")
                        }
                        if week.queue.count != week.done.count + week.slots.count + week.stillToDo.count {
                            report.add(.adaptiveMissedMovesForward, at, "sessions lost: queue \(week.queue.count), done \(week.done.count), slots \(week.slots.count), still to do \(week.stillToDo.count)")
                        }
                        let daysLeft = 7 - offset
                        if !week.stillToDo.isEmpty, week.remaining <= daysLeft {
                            report.add(.adaptiveMissedMovesForward, at, "\(week.stillToDo.map(\.focus.shortTitle)) left undone with \(daysLeft) days for \(week.remaining) sessions; slots \(week.slots.map { WeeklyPlan.weekdayName($0.session.weekday, calendar: calendar) })")
                        }
                        let guidance = TrainingDayPlanner.adaptiveGuidance(week: week, past: past, lowRecovery: false,
                                                                           usualTrainingStrain: 60, calendar: calendar)
                        // The user trains when there's a slot today, unless they miss it.
                        var trained = false
                        if let slot = week.today, Double.random(in: 0..<1, using: &rng) >= missRate {
                            done.append(AdaptiveWeek.DoneSession(date: today.addingTimeInterval(18 * 3600), focus: slot.focus))
                            trained = true
                        }
                        if guidance.focus != nil, week.today == nil {
                            report.add(.adaptiveOneSessionPerDay, at, "guidance suggests \(guidance.focus!.shortTitle) on a day with no slot: \(guidance.reason)")
                        }
                        // Later the same day, after lifting: no second session.
                        if trained, let after = AdaptiveWeek.make(plan: plan, done: done, now: today.addingTimeInterval(20 * 3600),
                                                                  calendar: calendar) {
                            if after.today != nil {
                                report.add(.adaptiveNoSessionAfterLifting, at, "a second slot today after lifting")
                            }
                            let g = TrainingDayPlanner.adaptiveGuidance(week: after, past: past, lowRecovery: false,
                                                                        usualTrainingStrain: 60, calendar: calendar)
                            if g.focus != nil {
                                report.add(.adaptiveNoSessionAfterLifting, at, "guidance after lifting still names \(g.focus!.shortTitle)")
                            }
                        }
                        past.append(TrainingDayPlanner.PastDay(date: today, plannedFocus: plan.day(for: calendar.component(.weekday, from: today))?.focus,
                                                               strain: trained ? 60 : 8, trained: trained))
                    }
                    let perDay = Dictionary(grouping: done, by: { calendar.startOfDay(for: $0.date) })
                    if perDay.values.contains(where: { $0.count > 1 }) {
                        report.add(.adaptiveOneSessionPerDay, s, "two sessions logged on one day")
                    }
                }
            }
        }

        // Flexible weeks (`TrainingDayPlanner.flexibleGuidance`).
        for target in 1...6 {
            for missRate in [0.0, 0.3] {
                for low in [false, true] {
                    for trial in 0..<10 {
                        let templates = WeeklyPlan.focusRotation(start: .upper, count: target).enumerated()
                            .map { PlannedDay(weekday: WeeklyPlan.weekdayOrder[$0.offset], time: 18 * 60, focus: $0.element, minutes: 45) }
                        let plan = WeeklyPlan(weekStart: SimFixtures.monday, plannedDays: templates, mode: .flexible, sessionsPerWeek: target)
                        var trainingDays: [Date] = []
                        var past: [TrainingDayPlanner.PastDay] = []
                        let s = "flexible target=\(target) miss=\(missRate) lowRecovery=\(low) trial=\(trial)"
                        for offset in 0..<7 {
                            let today = day(offset)
                            let at = "\(s) day=\(offset + 1)"
                            let progress = plan.progress(trainingDays: trainingDays, now: today.addingTimeInterval(12 * 3600), calendar: calendar)
                            let next = plan.nextFlexibleSession(done: progress.done)?.focus
                            let guidance = TrainingDayPlanner.flexibleGuidance(week: progress, nextFocus: next, past: past,
                                                                               lowRecovery: low, usualTrainingStrain: 60, calendar: calendar)
                            report.plans += 1
                            if progress.slack <= 0, !progress.isMet, guidance.isRestDay {
                                report.add(.flexibleTrainsWhenWeekNeedsIt, at, "\(progress.remaining) to go, \(progress.daysLeft) days left, but \(guidance.title)")
                            }
                            var trained = false
                            if !guidance.isRestDay, Double.random(in: 0..<1, using: &rng) >= missRate {
                                trainingDays.append(today.addingTimeInterval(18 * 3600))
                                trained = true
                            }
                            if trained {
                                let after = plan.progress(trainingDays: trainingDays, now: today.addingTimeInterval(20 * 3600), calendar: calendar)
                                let nextAfter = plan.nextFlexibleSession(done: after.done)?.focus
                                let g = TrainingDayPlanner.flexibleGuidance(week: after, nextFocus: nextAfter, past: past,
                                                                            lowRecovery: low, usualTrainingStrain: 60, calendar: calendar)
                                if !g.reason.hasPrefix("Session done today") || g.isRestDay == false && g.kind != .training {
                                    report.add(.flexibleNoSecondSessionSuggested, at, "after today's session: \(g.title), \(g.reason)")
                                }
                            }
                            past.append(TrainingDayPlanner.PastDay(date: today, plannedFocus: nil, strain: trained ? 60 : 8,
                                                                   planKnown: false, trained: trained))
                        }
                    }
                }
            }
        }
        return report
    }()
}

// MARK: - Tests

@Suite("Planner simulation sweep")
struct PlannerSimulationTests {
    static let planInvariants: [SimInvariant] = [
        .estimateConsistent, .timeOverLength, .timeUnderWithoutNote, .emptyPlan, .compoundAtLeastThreeSets, .setsInRange,
        .exerciseInCatalog, .equipmentAvailable, .loadAchievable, .warmUpAchievable, .loadWithinPainCap,
        .dumbbellPerHandPlausible, .firstTimeLoadPlausible, .firstTimeLoadNotRoundedUpHeavy, .loadWithinCapability,
        .noDuplicateExercise, .absPresentWithFinisher, .absNotTwice, .finisherFitsItsMinutes, .painfulAreaNotLoaded,
        .painRegressionNoted, .neverAgainRespected, .repRangeMatchesStyle, .targetRepsInRange, .effortReasonable,
        .restReasonable, .sessionVolumePerMuscle, .robustNoNaN
    ]

    static let progressionInvariants: [SimInvariant] = [
        .pushPullBalancedPerWeek, .weeklySetsWithinBand, .progressionNoRunaway, .progressionNoBigJump,
        .progressionNoCollapseAfterDeload, .progressionRises, .progressionNoOscillation, .doubleProgressionReps,
        .doubleProgressionStepOnlyAtTop
    ]

    static let weekInvariants: [SimInvariant] = [
        .adaptiveOneSessionPerDay, .adaptiveMissedMovesForward, .adaptiveNoSessionAfterLifting,
        .flexibleNoSecondSessionSuggested, .flexibleTrainsWhenWeekNeedsIt
    ]

    init() {
        guard let path = ProcessInfo.processInfo.environment["PLANNER_SIM_DUMP"] else { return }
        Self.dumpOnce(path)
    }

    private static let dumped: Bool = {
        guard let path = ProcessInfo.processInfo.environment["PLANNER_SIM_DUMP"] else { return false }
        try? FileManager.default.removeItem(atPath: path)
        PlannerSweep.result.dump(to: path, title: "Plan sweep")
        LiftSimulation.result.dump(to: path, title: "Multi-week simulation")
        WeekSimulation.result.dump(to: path, title: "Weekly schedulers")
        return true
    }()

    private static func dumpOnce(_ path: String) { _ = dumped }

    @Test func theSweepCoversThousandsOfPlans() {
        #expect(PlannerSweep.result.plans > 5000)
        #expect(LiftSimulation.result.plans > 400)
        #expect(WeekSimulation.result.plans > 1000)
    }

    @Test("Plan invariant", arguments: planInvariants)
    func planInvariant(_ invariant: SimInvariant) {
        PlannerSweep.result.check(invariant)
    }

    @Test("Multi-week progression invariant", arguments: progressionInvariants)
    func progressionInvariant(_ invariant: SimInvariant) {
        LiftSimulation.result.check(invariant)
    }

    @Test("Weekly scheduler invariant", arguments: weekInvariants)
    func weekInvariant(_ invariant: SimInvariant) {
        WeekSimulation.result.check(invariant)
    }
}

// MARK: - Odd inputs

@Suite("Planner robustness")
struct PlannerRobustnessTests {
    static let emptyGym = GymProfile(name: "", unit: .kg, equipment: [], barbellWeight: 0, ezBarWeight: 0, smithBarWeight: 0,
                                     plates: [], dumbbells: [], kettlebells: [],
                                     cableStack: WeightStack(start: 0, step: 0, max: 0), machineStack: WeightStack(start: 0, step: 0, max: 0))

    static let weirdGym = GymProfile(
        name: "Weird", unit: .lb, equipment: Set(EquipmentKind.allCases),
        barbellWeight: 33, ezBarWeight: 0, smithBarWeight: -5,
        plates: [PlateCount(weight: 0, pairs: 3), PlateCount(weight: 1.1, pairs: 7), PlateCount(weight: 17.3, pairs: 1),
                 PlateCount(weight: -10, pairs: 2), PlateCount(weight: 5, pairs: 0)],
        dumbbells: [7.3, 7.3, 0, 3, 100, 11], kettlebells: [0.5],
        cableStack: WeightStack(start: 12.5, step: 2.5, max: 10), machineStack: WeightStack(start: 1, step: 0.01, max: 400)
    )

    /// Whatever goes in, a plan comes out with finite numbers and doesn't hang.
    private func assertSane(_ workout: PlannedWorkout, _ label: String) {
        for exercise in workout.exercises {
            if let load = exercise.load { #expect(load.isFinite, "\(label): \(exercise.name) load \(load)") }
            #expect(exercise.rpe.isFinite, "\(label): \(exercise.name) RPE")
            #expect(exercise.sets >= 0, "\(label): \(exercise.name) sets \(exercise.sets)")
            #expect(exercise.reps.lowerBound >= 0, "\(label): \(exercise.name) reps")
        }
        #expect((workout.estimatedMinutes ?? 0) >= 0, "\(label): estimate")
        #expect(Set(workout.exercises.map(\.exerciseID)).count == workout.exercises.count, "\(label): duplicates")
    }

    @Test(arguments: [0, -30, 1, 5, 10, 14, 600, 10_000])
    func oddLengths(_ minutes: Int) {
        for gym in SimFixtures.gyms.map(\.profile) + [Self.emptyGym] {
            for focus in WorkoutFocus.allCases {
                let planner = WorkoutPlanner(gym: gym, style: .muscle)
                let workout = planner.plan(focus: focus, minutes: minutes, recovery: 50, history: [:], bodyMassKg: 80)
                assertSane(workout, "\(gym.name) \(focus) \(minutes) min")
                if minutes >= 15, minutes <= 600 {
                    #expect((workout.estimatedMinutes ?? 0) <= Int(Double(max(minutes, 1)) * 1.1) + 1 || workout.exercises.count <= 2,
                            "\(gym.name) \(focus) \(minutes) min: estimate \(workout.estimatedMinutes ?? -1)")
                }
            }
        }
    }

    @Test func emptyGymPlansBodyweightOnly() {
        let planner = WorkoutPlanner(gym: Self.emptyGym, style: .balanced)
        for focus in WorkoutFocus.allCases {
            let workout = planner.plan(focus: focus, minutes: 45, recovery: nil, history: [:])
            assertSane(workout, "empty gym \(focus)")
            #expect(workout.exercises.allSatisfy { $0.loadKind == nil }, "empty gym \(focus) planned a loaded lift")
        }
    }

    @Test func weirdGymLoadsStayAchievable() {
        let planner = WorkoutPlanner(gym: Self.weirdGym, style: .strength)
        let history = SimFixtures.history(gym: Self.weirdGym, style: .strength, sex: .male, massKg: 80, status: .advanced)
        for focus in WorkoutFocus.allCases {
            for withHistory in [false, true] {
                let workout = planner.plan(focus: focus, minutes: 60, recovery: 80, history: withHistory ? history : [:],
                                           bodyMassKg: 80, trainingStatus: .advanced)
                assertSane(workout, "weird gym \(focus)")
                for exercise in workout.exercises {
                    guard let load = exercise.load, let kind = exercise.loadKind else { continue }
                    #expect(PlanChecks.achievable(load, kind: kind, gym: Self.weirdGym), "weird gym \(focus): \(exercise.name) \(load)")
                }
            }
        }
    }

    @Test func oddHistoryValues() {
        let gym = GymProfile.commercialKilograms
        let planner = WorkoutPlanner(gym: gym, style: .balanced)
        let odd: [ExerciseHistory] = [
            ExerciseHistory(bestEstimatedOneRepMax: 0, lastWeight: 0, lastReps: 0, lastRPE: nil, lastDate: .distantPast),
            ExerciseHistory(bestEstimatedOneRepMax: -50, lastWeight: -20, lastReps: -3, lastRPE: -1, lastDate: .distantFuture),
            ExerciseHistory(bestEstimatedOneRepMax: 1e9, lastWeight: 1e8, lastReps: 1000, lastRPE: 11, lastDate: .now,
                            recentWeights: [1e8, 1e8, 1e8], lastSets: 1000),
            ExerciseHistory(bestEstimatedOneRepMax: .nan, lastWeight: .nan, lastReps: 8, lastRPE: .nan, lastDate: .now,
                            recentWeights: [.nan], lastSets: nil),
            ExerciseHistory(bestEstimatedOneRepMax: .infinity, lastWeight: 100, lastReps: 8, lastRPE: 8, lastDate: .now)
        ]
        for (index, past) in odd.enumerated() {
            var history: [String: ExerciseHistory] = [:]
            for slot in MovementSlot.allCases {
                for exercise in ExerciseCatalog.options[slot] ?? [] { history[exercise.id] = past }
            }
            for focus in WorkoutFocus.allCases {
                let workout = planner.plan(focus: focus, minutes: 60, recovery: 50, history: history)
                assertSane(workout, "odd history #\(index) \(focus)")
            }
        }
    }

    @Test func hugeHistory() {
        let gym = GymProfile.commercialPounds
        var history = SimFixtures.history(gym: gym, style: .muscle, sex: .male, massKg: 90, status: .advanced)
        for index in 0..<20_000 {
            history["Unknown_Exercise_\(index)"] = ExerciseHistory(bestEstimatedOneRepMax: Double(index), lastWeight: 50,
                                                                   lastReps: 8, lastRPE: 8, lastDate: .now)
        }
        let planner = WorkoutPlanner(gym: gym, style: .muscle)
        let workout = planner.plan(focus: .fullBody, minutes: 120, recovery: 80, history: history, bodyMassKg: 90)
        assertSane(workout, "huge history")
        #expect(!workout.exercises.isEmpty)
    }

    @Test func oddLifterInputs() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .balanced)
        for mass in [0, -70, 1e-6, 500, .nan, .infinity] as [Double] {
            let workout = planner.plan(focus: .fullBody, minutes: 60, recovery: 50, history: [:], bodyMassKg: mass,
                                       sex: .female, trainingStatus: .advanced)
            assertSane(workout, "body mass \(mass)")
        }
        for recovery in [-50, 0, 34, 67, 100, 250] {
            let workout = planner.plan(focus: .upper, minutes: 45, recovery: recovery, history: [:], bodyMassKg: 70)
            assertSane(workout, "recovery \(recovery)")
        }
    }

    @Test func everythingNeverAgainOrPainful() {
        let all = Set(ExerciseCatalog.options.values.flatMap { $0 }.map(\.id) + PainGuard.regressionTable.flatMap(\.exercises).map(\.id))
        let pains = PainArea.allCases.map { PainReport(area: $0, level: 9, loggedAt: SimFixtures.monday) }
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        for focus in WorkoutFocus.allCases {
            for filter in [ExerciseFilter(neverAgain: all), ExerciseFilter(pains: pains)] {
                let workout = planner.plan(focus: focus, minutes: 60, recovery: 50, history: [:], exerciseFilter: filter)
                assertSane(workout, "filter \(focus)")
                var finisherPlanner = planner
                finisherPlanner.exerciseFilter = filter
                _ = AbsFinisher.make(length: .ten, planner: finisherPlanner)
            }
        }
    }

    @Test func oddBlocksAndGoals() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        let blocks = [
            TrainingBlock.WeekState(week: 0, length: 0, setMultiplier: 0, targetRIR: 0, isDeload: false),
            TrainingBlock.WeekState(week: 99, length: 1, setMultiplier: 10, targetRIR: 10, isDeload: true),
            TrainingBlock.WeekState(week: 1, length: 5, setMultiplier: -2, targetRIR: -3, isDeload: false)
        ]
        for block in blocks {
            let workout = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: [:], block: block,
                                       muscleSetGoals: [.quadriceps: 100, .hamstrings: -4, .calves: 0])
            assertSane(workout, "block \(block)")
        }
        _ = TrainingBlock.schedule(style: .muscle, length: 0)
        _ = TrainingBlock.schedule(style: .strength, length: -3)
        _ = VolumeProgression.sessionGoals(
            targets: VolumeProgression.WeekTargets(weekStart: SimFixtures.monday, targetRIR: 2, targets: []),
            doneThisWeek: [:], focus: .upper, minutes: 0, laterSessions: [])
    }

    /// `TrainingBlock.scaledSets` used to convert `Double(base) * multiplier`
    /// to Int unguarded, so a non-finite multiplier trapped the app.
    @Test func nonFiniteBlockMultiplier() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        for multiplier in [Double.nan, .infinity, -.infinity, 1e300] {
            let block = TrainingBlock.WeekState(week: 1, length: 5, setMultiplier: multiplier, targetRIR: 2, isDeload: false)
            let workout = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: [:], block: block)
            assertSane(workout, "block multiplier \(multiplier)")
        }
    }

    @Test func weeklyPlanEdgeCases() {
        let calendar = SimFixtures.calendar
        for count in -1...9 {
            let weekdays = WeeklyPlan.suggestedWeekdays(count: count)
            #expect(Set(weekdays).count == weekdays.count, "suggestedWeekdays(\(count)) repeats a day: \(weekdays)")
            _ = WeeklyPlan.focusRotation(start: .legs, count: count)
        }
        // Two planned days on the same weekday (an old saved plan): still one slot a day.
        let doubled = WeeklyPlan(weekStart: SimFixtures.monday, plannedDays: [
            PlannedDay(weekday: 2, time: 600, focus: .push, minutes: 45),
            PlannedDay(weekday: 2, time: 1100, focus: .pull, minutes: 45),
            PlannedDay(weekday: 4, time: 600, focus: .legs, minutes: 45)
        ])
        if let week = AdaptiveWeek.make(plan: doubled, done: [], now: SimFixtures.monday.addingTimeInterval(3600), calendar: calendar) {
            #expect(Set(week.slots.map(\.date)).count == week.slots.count)
        }
        let empty = WeeklyPlan(weekStart: SimFixtures.monday, plannedDays: [], mode: .flexible, sessionsPerWeek: 0)
        _ = empty.nextFlexibleSession(done: 0)
        _ = empty.progress(trainingDays: [], now: SimFixtures.monday, calendar: calendar)
        _ = RestartPlan.make(daysOff: 30, lastPlan: doubled)
        _ = RestartPlan.make(daysOff: 30, lastPlan: WeeklyPlan(weekStart: SimFixtures.monday, plannedDays:
            (1...7).map { PlannedDay(weekday: $0, time: 600, focus: .fullBody, minutes: 30) }))
    }
}

// MARK: - Minimal repros of the bugs the sweep found

/// One deterministic case per bug found by the sweep, so each is easy to
/// debug on its own. Each is a known issue until the planner is fixed.
@Suite("Planner bug repros")
struct PlannerBugReproTests {
    /// The lifter does what's planned: `targetReps` at RPE `rpe`, logged like `LiftHistory.make`.
    private func log(_ exercise: PlannedExercise, after past: ExerciseHistory?, reps: Int? = nil, rpe: Double) -> ExerciseHistory {
        let load = exercise.load ?? 0
        let done = reps ?? exercise.repsToday
        return ExerciseHistory(bestEstimatedOneRepMax: max(past?.bestEstimatedOneRepMax ?? 0, OneRepMax.estimate(weight: load, reps: done, rpe: rpe)),
                               lastWeight: load, lastReps: done, lastRPE: rpe, lastDate: SimFixtures.monday,
                               recentWeights: ExerciseHistory.appending(load, to: past?.recentWeights ?? []), lastSets: exercise.sets)
    }

    @Test func persistentPainCapDoesNotRatchetTheLoadDown() {
        // Knee 4/10 every session; the lifter completes every planned rep at RPE 7.
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .balanced)
        let filter = ExerciseFilter(pains: [PainReport(area: .knee, level: 4, loggedAt: SimFixtures.monday)])
        var history = ExerciseHistory(bestEstimatedOneRepMax: 80 * (1 + 12.0 / 30), lastWeight: 80, lastReps: 10, lastRPE: 8,
                                      lastDate: SimFixtures.monday, recentWeights: [80, 80, 80], lastSets: 3)
        var loads: [Double] = []
        for _ in 0..<10 {
            let workout = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: ["Seated_Leg_Curl": history], exerciseFilter: filter)
            guard let curl = workout.exercises.first(where: { $0.exerciseID == "Seated_Leg_Curl" }) else { break }
            loads.append(curl.load ?? 0)
            history = log(curl, after: history, rpe: 7)
        }
        // 20% under 80 kg is 64 → 60 on a 5 kg stack; it shouldn't keep falling.
        #expect((loads.last ?? 0) >= 60, "seated leg curl with knee 4/10: \(loads)")
    }

    @Test func setProgressionWithWeeklyGoalsStillMovesTheWeightUp() {
        // Leg day has the leg extension; the weekly goals fix its sets. The lift is
        // pinned to set progression to check the old stall can't come back.
        var planner = WorkoutPlanner(gym: .commercialPounds, style: .balanced)
        planner.progressionModes = ["Leg_Extensions": .sets]
        var history = ExerciseHistory(bestEstimatedOneRepMax: 140, lastWeight: 100, lastReps: 10, lastRPE: 8,
                                      lastDate: SimFixtures.monday, recentWeights: [100, 100, 100], lastSets: 3)
        var trail: [String] = []
        for _ in 0..<8 {
            let workout = planner.plan(focus: .legs, minutes: 75, recovery: 80, history: ["Leg_Extensions": history],
                                       muscleSetGoals: [.quadriceps: 6, .hamstrings: 6, .calves: 3])
            guard let extensions = workout.exercises.first(where: { $0.exerciseID == "Leg_Extensions" }) else { break }
            trail.append("\(extensions.load ?? 0)×\(extensions.repsToday)/\(extensions.sets)")
            history = log(extensions, after: history, rpe: 8)
        }
        #expect(!trail.isEmpty, "no leg extension on leg day")
        #expect(history.lastWeight > 100, "leg extension at the top of the range for 8 sessions: \(trail)")
    }

    @Test func backToTheHeaviestDoesNotPingPong() {
        let planner = WorkoutPlanner(gym: .commercialPounds, style: .balanced)
        var history = ExerciseHistory(bestEstimatedOneRepMax: 100, lastWeight: 75, lastReps: 7, lastRPE: 10,
                                      lastDate: SimFixtures.monday, recentWeights: [70, 75, 75], lastSets: 3)
        var loads: [Double] = []
        for _ in 0..<8 {
            let workout = planner.plan(focus: .pull, minutes: 60, recovery: 80, history: ["Barbell_Curl": history])
            guard let curl = workout.exercises.first(where: { $0.exerciseID == "Barbell_Curl" }), let load = curl.load else { break }
            loads.append(load)
            // 75 lb is too heavy (7 reps at RPE 10); 70 lb goes fine.
            history = load >= 75 ? log(curl, after: history, reps: 7, rpe: 10) : log(curl, after: history, rpe: 8.5)
        }
        let reversals = zip(zip(loads, loads.dropFirst()), loads.dropFirst(2)).filter { pair, c in
            let (a, b) = pair
            return (b - a) * (c - b) < 0
        }.count
        #expect(reversals < 3, "barbell curl loads: \(loads)")
    }

    @Test func firstTimeLoadIsNotTheEmptyBarForALightLifter() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .balanced)
        let workout = planner.plan(focus: .pull, minutes: 60, recovery: 80, history: [:], bodyMassKg: 50, sex: .female,
                                   trainingStatus: .novice)
        for exercise in workout.exercises where ExerciseCatalog.slot(for: exercise.exerciseID) == .biceps {
            // Body-weight estimate: 50 × 0.15 = 7.5 kg 1RM, about 5 kg for 10-12 reps.
            #expect((exercise.load ?? 0) <= 12, "\(exercise.name) \(exercise.load ?? 0) kg first time for a 50 kg novice woman")
        }
    }

    @Test func fullBodyBalancesPushAndPull() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .balanced)
        let workout = planner.plan(focus: .fullBody, minutes: 60, recovery: 80, history: [:], bodyMassKg: 80)
        var push = 0, pull = 0
        for exercise in workout.exercises {
            switch ExerciseCatalog.slot(for: exercise.exerciseID)?.muscleGroup {
            case .push: push += exercise.sets
            case .pull: pull += exercise.sets
            default: break
            }
        }
        #expect(Double(push) <= Double(pull) * 1.5, "full body 60 min: push \(push) sets vs pull \(pull)")
    }

    @Test func bodyweightGymCanTrainPull() {
        let planner = WorkoutPlanner(gym: SimFixtures.bodyweightOnly, style: .balanced)
        let workout = planner.plan(focus: .pull, minutes: 30, recovery: 80, history: [:], includeCore: false)
        #expect(workout.exercises.contains { ExerciseCatalog.slot(for: $0.exerciseID)?.muscleGroup == .pull },
                "bodyweight pull day: \(workout.exercises.map(\.name)), note: \(workout.lengthNote ?? "-")")
    }

    @Test func compoundLiftsKeepThreeSetsBeforeIsolationDoes() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .strength)
        let workout = planner.plan(focus: .upper, minutes: 45, recovery: 50, history: [:], bodyMassKg: 120, trainingStatus: .advanced)
        let compounds = workout.exercises.filter { ExerciseCatalog.slot(for: $0.exerciseID)?.isCompound == true }
        let isolation = workout.exercises.filter { ExerciseCatalog.slot(for: $0.exerciseID)?.isCompound == false }
        let fewestCompound = compounds.map(\.sets).min() ?? 3
        let mostIsolation = isolation.map(\.sets).max() ?? 0
        #expect(fewestCompound >= WorkoutPlanner.minimumCompoundSets || mostIsolation < fewestCompound,
                "upper 45 min strength: \(workout.exercises.map { "\($0.name)×\($0.sets)" })")
    }

    @Test func warmUpDoesNotPushAShortSessionPastItsLength() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .strength)
        let workout = planner.plan(focus: .upper, minutes: 15, recovery: 80, history: [:], bodyMassKg: 80, warmUpMinutes: 10)
        let estimate = workout.estimatedMinutes ?? 0
        #expect(estimate <= 17 || workout.lengthNote != nil, "15-min plan with a 10-min warm-up runs \(estimate) min, no note")
    }

    @Test func painRegressionLiftsGetAStartingWeight() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .balanced)
        let squat = ExerciseHistory(bestEstimatedOneRepMax: 120, lastWeight: 100, lastReps: 6, lastRPE: 8, lastDate: SimFixtures.monday,
                                    recentWeights: [100], lastSets: 3)
        let filter = ExerciseFilter(pains: [PainReport(area: .knee, level: 4, loggedAt: SimFixtures.monday)])
        let workout = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: ["Barbell_Squat": squat], bodyMassKg: 85,
                                   exerciseFilter: filter)
        let box = workout.exercises.first { $0.exerciseID == "Box_Squat" }
        #expect(box == nil || box?.load != nil, "Box squat after a 100 kg back squat: \(box?.note ?? "-")")
    }

    @Test func painCapKeepsTheTimeEstimateCurrent() {
        let gym = GymProfile.commercialKilograms
        let planner = WorkoutPlanner(gym: gym, style: .balanced)
        let history = SimFixtures.history(gym: gym, style: .balanced, sex: .male, massKg: 80, status: .novice)
        let filter = ExerciseFilter(pains: [PainReport(area: .shoulder, level: 4, loggedAt: SimFixtures.monday)])
        let workout = planner.plan(focus: .push, minutes: 30, recovery: 80, history: history, bodyMassKg: 80, exerciseFilter: filter)
        #expect(workout.estimatedMinutes == WorkoutPlanner.estimatedMinutes(workout.exercises, style: .balanced))
    }

    @Test func bigJumpRepTargetStaysInsideTheShownRange() {
        let planner = WorkoutPlanner(gym: SimFixtures.barbellRack, style: .balanced)
        let press = ExerciseHistory(bestEstimatedOneRepMax: 28, lastWeight: 20, lastReps: 9, lastRPE: 8, lastDate: SimFixtures.monday,
                                    recentWeights: [20, 20, 20], lastSets: 3)
        let workout = planner.plan(focus: .push, minutes: 45, recovery: 80, history: ["Standing_Military_Press": press])
        if let ohp = workout.exercises.first(where: { $0.exerciseID == "Standing_Military_Press" }), let target = ohp.targetReps {
            #expect(ohp.reps.contains(target), "Overhead press aims for \(target) reps but shows \(ohp.reps)")
        }
    }

    @Test func veryEasySetsMoveTheWeightUpFaster() {
        // A 60 kg-1RM bencher starts at the body-weight estimate (30 kg) and reports RPE 5 every time.
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        var history = ExerciseHistory(bestEstimatedOneRepMax: 30 * (1 + 15.0 / 30), lastWeight: 30, lastReps: 10, lastRPE: 5,
                                      lastDate: SimFixtures.monday, recentWeights: [30], lastSets: 3)
        var loads: [Double] = []
        for _ in 0..<6 {
            let workout = planner.plan(focus: .push, minutes: 60, recovery: 80, history: ["Barbell_Bench_Press_-_Medium_Grip": history])
            guard let bench = workout.exercises.first(where: { $0.exerciseID == "Barbell_Bench_Press_-_Medium_Grip" }) else { break }
            loads.append(bench.load ?? 0)
            history = log(bench, after: history, rpe: 5)
        }
        // 60 kg 1RM: about 45 kg for 8 at RPE 8; after six RPE-5 sessions it should be well on the way.
        #expect((loads.last ?? 0) >= 40, "bench after six RPE-5 sessions: \(loads)")
    }

    @Test func aRegressionAvoidsTheOtherPainfulArea() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .balanced)
        let filter = ExerciseFilter(pains: [PainReport(area: .knee, level: 4, loggedAt: SimFixtures.monday),
                                            PainReport(area: .lowerBack, level: 4, loggedAt: SimFixtures.monday)])
        let workout = planner.plan(focus: .legs, minutes: 60, recovery: 80, history: [:], bodyMassKg: 80, exerciseFilter: filter)
        let squat = workout.exercises.first { ExerciseCatalog.slot(for: $0.exerciseID) == .squat }
        if let squat {
            #expect(!PainGuard.areas(forExerciseID: squat.exerciseID, slot: .squat).contains(.lowerBack),
                    "squat pick \(squat.name) loads the sore lower back; Leg Press is in both regression lists")
        }
    }

    // MARK: Weekly set band (`weeklySetsWithinBand`)

    @Test func weeklyTargetsSkipMusclesTheGymCannotTrain() {
        // A rack gym has no calf raise, a bodyweight gym no hinge or hamstring curl.
        let upperLower = zip(WeeklyPlan.suggestedWeekdays(count: 4), [WorkoutFocus.upper, .lower, .upper, .lower]).map {
            PlannedDay(weekday: $0, time: 18 * 60, focus: $1, minutes: 60)
        }
        let block = TrainingBlock.weekState(1, style: .strength, length: 5)
        func muscles(_ gym: GymProfile?, _ days: [PlannedDay]) -> Set<Muscle> {
            Set(VolumeProgression.week(weekStart: SimFixtures.monday, block: block, style: .strength, days: days, previous: nil,
                                       lastWeek: [:], states: [:], gym: gym).targets.map(\.muscle))
        }
        #expect(muscles(nil, upperLower).contains(.calves))
        #expect(!muscles(SimFixtures.barbellRack, upperLower).contains(.calves))
        #expect(muscles(SimFixtures.barbellRack, upperLower).contains(.quadriceps))
        let fullBody = [PlannedDay(weekday: 2, time: 18 * 60, focus: .fullBody, minutes: 30),
                        PlannedDay(weekday: 5, time: 18 * 60, focus: .fullBody, minutes: 30)]
        #expect(!muscles(SimFixtures.bodyweightOnly, fullBody).contains(.hamstrings))
    }

    @Test func aTargetIsNeverMoreThanTheSessionsHold() {
        // A 30-minute upper day holds about 3 chest sets: the target was 4 (the floor) and never met.
        let target = VolumeProgression.target(for: .chest, previous: nil, week: TrainingBlock.weekState(1, style: .muscle, length: 5),
                                              style: .muscle, lastWeek: nil, state: nil, sessions: 1, timeCap: 3)
        #expect(target.sets == 3)
        #expect(target.band == 3...3)
        #expect(target.change == .cappedTime)
        // Steady (stamina) weeks hold every muscle at its target at once: no share slack, so the
        // 30-minute hotel upper day's chest cap is the 3 sets it holds, not 4.
        let days = [PlannedDay(weekday: 2, time: 18 * 60, focus: .upper, minutes: 30),
                    PlannedDay(weekday: 4, time: 18 * 60, focus: .lower, minutes: 30)]
        #expect(VolumeProgression.capacity(.chest, days: days, style: .endurance, gym: SimFixtures.hotel).timeCap == 3)
    }

    @Test func theGymsHeaviestWeightBuildsRepsPastTheRange() {
        // 25 kg is the heaviest dumbbell; the lifter logs RPE 5 at the top of the range.
        let planner = WorkoutPlanner(gym: SimFixtures.homeDumbbellsKg, style: .balanced)
        var history = ExerciseHistory(bestEstimatedOneRepMax: 25 * (1 + 13.0 / 30), lastWeight: 25, lastReps: 8, lastRPE: 5,
                                      lastDate: SimFixtures.monday, recentWeights: [25, 25, 25], lastSets: 3)
        var trail: [Int] = []
        for _ in 0..<12 {
            guard let next = planner.progression(history: history, reps: 6...8, rpe: 7, kind: .dumbbell) else { break }
            #expect(next.load == 25)
            trail.append(next.targetReps)
            history = ExerciseHistory(bestEstimatedOneRepMax: history.bestEstimatedOneRepMax, lastWeight: 25, lastReps: next.targetReps,
                                      lastRPE: 5, lastDate: SimFixtures.monday, recentWeights: [25, 25, 25], lastSets: 3)
        }
        // Up past the range while the sets stay easy, never past the ceiling, never back down.
        #expect(trail.first ?? 0 > 8, "\(trail)")
        #expect(trail == trail.sorted(), "\(trail)")
        #expect(trail.last == WorkoutPlanner.maximumExtendedReps, "\(trail)")
        // Hard sets there hold the reps: 23 at the target doesn't drop back to the range's 8.
        let hard = ExerciseHistory(bestEstimatedOneRepMax: 45, lastWeight: 25, lastReps: 23, lastRPE: 7, lastDate: SimFixtures.monday,
                                   recentWeights: [25, 25, 25], lastSets: 3)
        #expect(planner.progression(history: hard, reps: 6...8, rpe: 7, kind: .dumbbell)?.targetReps == 24)
    }

    @Test func timeCutsSpreadOverTheMuscles() {
        // Two sets over the time: one off the hamstrings and one off the calves (each week's band
        // allows a set under per session), not both off the calves.
        func exercise(_ id: String, _ sets: Int) -> PlannedExercise {
            let choice = ExerciseCatalog.exercise(id: id)
            return PlannedExercise(exerciseID: id, name: choice?.name ?? id, sets: sets, reps: 8...12, rpe: 8, load: 40,
                                   loadKind: choice?.load, note: nil)
        }
        var session = [exercise("Seated_Leg_Curl", 4), exercise("Standing_Calf_Raises", 5)]
        let trimmed = [exercise("Seated_Leg_Curl", 3), exercise("Standing_Calf_Raises", 4)]
        #expect(WorkoutPlanner.estimatedMinutes(session) > WorkoutPlanner.estimatedMinutes(trimmed))
        WorkoutPlanner.fit(&session, minutes: WorkoutPlanner.estimatedMinutes(trimmed))
        #expect(session.map(\.sets) == [3, 4])
    }

    // MARK: Oscillation near the limit (`progressionNoOscillation`)

    @Test func aSmallMissOnACoarseStepTakesARepOffNotTheWeight() {
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        // 34 kg dumbbells × 10 at RPE 9.5 against 8.5: the next pair down (32 kg, 6%) is more than
        // twice the cut a point calls for, so the weight stays and a rep comes off.
        let split = ExerciseHistory(bestEstimatedOneRepMax: 45.3, lastWeight: 34, lastReps: 10, lastRPE: 9.5,
                                    lastDate: SimFixtures.monday, recentWeights: [34, 34, 34], lastSets: 3)
        #expect(planner.progression(history: split, reps: 6...10, rpe: 8.5, kind: .dumbbell)
                == WorkoutPlanner.Progression(load: 34, targetReps: 9))
        // On a 2.5 kg bar step (2.4%) the step is the cut: the weight eases as before.
        let row = ExerciseHistory(bestEstimatedOneRepMax: 140, lastWeight: 105, lastReps: 10, lastRPE: 9.5,
                                  lastDate: SimFixtures.monday, recentWeights: [105, 105, 105], lastSets: 3)
        #expect((planner.progression(history: row, reps: 6...10, rpe: 8.5, kind: .barbell)?.load ?? 105) < 105)
    }

    @Test func nearTheLimitOnCoarseStepsTheWeightDoesNotBounce() {
        // An advanced lifter (+0.3% a session) at about 34 kg × 10 on 2 kg dumbbell steps, RPE honest.
        let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)
        var oneRM = 44.5
        var history = ExerciseHistory(bestEstimatedOneRepMax: 44, lastWeight: 34, lastReps: 9, lastRPE: 8.5,
                                      lastDate: SimFixtures.monday, recentWeights: [34, 34, 34], lastSets: 3)
        var loads: [Double] = []
        for _ in 0..<20 {
            guard let next = planner.progression(history: history, reps: 6...10, rpe: 8.5, kind: .dumbbell) else { break }
            loads.append(next.load)
            let canDo = 30 * (oneRM / next.load - 1)
            let reps = min(next.targetReps, max(0, Int(canDo.rounded(.down))))
            let rpe = min(10, max(5, ((10 - (canDo - Double(reps))) * 2).rounded() / 2))
            history = ExerciseHistory(bestEstimatedOneRepMax: max(history.bestEstimatedOneRepMax,
                                                                  OneRepMax.estimate(weight: next.load, reps: reps, rpe: rpe)),
                                      lastWeight: next.load, lastReps: reps, lastRPE: rpe, lastDate: SimFixtures.monday,
                                      recentWeights: ExerciseHistory.appending(next.load, to: history.recentWeights), lastSets: 3)
            oneRM *= 1.003
        }
        var reversals = 0
        var direction = 0
        for (a, b) in zip(loads, loads.dropFirst()) where abs(b - a) > 0.001 {
            let now = b > a ? 1 : -1
            if direction != 0, now != direction { reversals += 1 }
            direction = now
        }
        #expect(reversals < 2, "34 kg split squat near the limit: \(loads)")
        #expect((loads.last ?? 0) >= 34, "\(loads)")
    }
}
