import Foundation
import Testing
@testable import AppCore

/// Set types (drop sets, rest-pause, myo-reps, failure) and the short-session
/// "same work, less time" option (`SetKind`, `SetStructure`, `TimeSaver`).
struct SetKindsTests {
    let gym = GymProfile.commercialKilograms

    // MARK: Set kinds

    @Test func storedValueDefaultsToStraight() {
        #expect(SetKind(storedValue: nil) == .straight)
        #expect(SetKind(storedValue: "drop") == .drop)
        #expect(SetKind(storedValue: "nonsense") == .straight)
        #expect(SetKind.allCases.allSatisfy { SetKind(storedValue: $0.rawValue) == $0 })
    }

    @Test func stagesSkipOrShortenTheRestAndNeverAutoregulate() {
        #expect(SetKind.drop.restBeforeSeconds == 0)
        #expect(SetKind.restPause.restBeforeSeconds == 20)
        #expect(SetKind.myoRep.restBeforeSeconds == 15)
        #expect(SetKind.straight.restBeforeSeconds == nil)
        #expect(SetKind.failure.restBeforeSeconds == nil)
        #expect(SetKind.stageKinds.allSatisfy { $0.isStage })
        #expect(!SetKind.failure.isStage && !SetKind.straight.isStage)
        // A set to failure is RPE 10 on purpose; a stage is fatigued by design.
        #expect(SetKind.allCases.filter(\.allowsAutoregulation) == [.straight])
    }

    @Test func myoRepsAreLabelledUntested() {
        #expect(SetKind.myoRep.evidence.contains("haven't been tested"))
        #expect(SetKind.drop.evidence.contains("Sødal"))
        #expect(SetKind.restPause.evidence.contains("Tsartsapakis"))
    }

    // MARK: Structure

    @Test func stagesBelongToTheSetBeforeThem() {
        let items: [SetStructure.Item] = [
            .init(isWarmup: true, kind: .straight),
            .init(isWarmup: true, kind: .straight),
            .init(isWarmup: false, kind: .straight),
            .init(isWarmup: false, kind: .straight),
            .init(isWarmup: false, kind: .drop),
            .init(isWarmup: false, kind: .drop),
            .init(isWarmup: false, kind: .failure)
        ]
        let positions = SetStructure.positions(items)
        #expect(positions.map(\.warmUp) == [1, 2, nil, nil, nil, nil, nil])
        #expect(positions.map(\.number) == [nil, nil, 1, 2, 2, 2, 3])
        #expect(positions.map(\.stage) == [nil, nil, nil, nil, 1, 2, nil])
        #expect(positions.map(\.stages) == [0, 0, 0, 2, 2, 2, 0])
        #expect(SetStructure.title(at: 0, in: items) == "Warm-up 1 of 2")
        #expect(SetStructure.title(at: 3, in: items) == "Set 2 of 3")
        #expect(SetStructure.title(at: 5, in: items) == "Drop 2 of 2")
        #expect(SetStructure.title(at: 6, in: items) == "Set 3 of 3")
    }

    @Test func aStageWithNothingBeforeItIsASetOfItsOwn() {
        let items: [SetStructure.Item] = [
            .init(isWarmup: true, kind: .straight),
            .init(isWarmup: false, kind: .myoRep),
            .init(isWarmup: false, kind: .myoRep)
        ]
        let positions = SetStructure.positions(items)
        #expect(positions[1].isStage == false)
        #expect(positions[1].number == 1)
        #expect(positions[2].stage == 1)
        #expect(SetStructure.title(at: 2, in: items) == "Mini-set 1 of 1")
    }

    @Test func aClusterCountsAsTheStraightSetsItStandsIn() {
        // Changed from 1.5: a converted session must meet its planned sets.
        #expect(SetStructure.hardSetCredit(stages: 0) == 1)
        #expect(SetStructure.hardSetCredit(stages: 1) == 2)
        #expect(SetStructure.hardSetCredit(stages: 2) == 3)
        #expect(SetStructure.hardSetCredit(stages: 3) == 3)
        // Three straight curls → one drop set with two drops: still three hard sets.
        var exercise = curl()
        let planned = Double(exercise.sets)
        TimeSaver.convert(&exercise, to: .drop, gym: gym)
        #expect(SetStructure.hardSetCredit(stages: exercise.stages?.count ?? 0) == planned)
    }

    @Test func weeklySetsCountTheCreditButFatigueCountsOneSet() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weekStart = now.addingTimeInterval(-86_400)
        let plain = MuscleRecovery.WorkSet(date: now.addingTimeInterval(-3600), primary: ["biceps"], rpe: 9)
        var drop = plain
        drop.volumeCredit = SetStructure.hardSetCredit(stages: 2)
        #expect(MuscleCoverage.setsThisWeek([plain], weekStart: weekStart, now: now)[.biceps] == 1)
        #expect(MuscleCoverage.setsThisWeek([drop], weekStart: weekStart, now: now)[.biceps] == 3)
        let tired = MuscleRecovery.evaluate(sets: [plain], now: now)[.biceps]?.recovery
        let tiredByDrop = MuscleRecovery.evaluate(sets: [drop], now: now)[.biceps]?.recovery
        #expect(tired == tiredByDrop)
    }

    @Test func volumeProgressionCountsTheCredit() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let set = VolumeProgression.LoggedSet(exerciseID: "Dumbbell_Bicep_Curl", name: "Curl", sessionStart: start.addingTimeInterval(3600),
                                              order: 0, primary: [.biceps], weightKg: 12, reps: 10, rpe: 9,
                                              isCompound: false, setCredit: 1.5)
        let summary = VolumeProgression.summarize([set], weekStart: start, targetRPE: 8, style: .muscle)
        #expect(summary[.biceps]?.sets == 1.5)
    }

    // MARK: Drop loads

    @Test func dropLoadsRoundToTheGym() {
        // Dumbbells 2-50 kg in 2s: 12 → at most 9.6 → 8 → at most 6.4 → 6.
        #expect(TimeSaver.dropLoads(from: 12, kind: .dumbbell, gym: gym, stages: 2) == [8, 6])
        // Cable stack in 5s: 40 → 30 → 20.
        #expect(TimeSaver.dropLoads(from: 40, kind: .cable, gym: gym, stages: 2) == [30, 20])
        // The lightest dumbbell has nothing lighter.
        #expect(TimeSaver.dropLoads(from: 2, kind: .dumbbell, gym: gym, stages: 2).isEmpty)
        // Barbell isolation (curl): plates to strip, each at least 20% lighter.
        let bar = TimeSaver.dropLoads(from: 40, kind: .barbell, gym: gym, stages: 2)
        #expect(bar.count == 2)
        #expect(bar.allSatisfy { gym.achievableLoads(for: .barbell).contains($0) })
        #expect(bar[0] <= 32 && bar[1] <= bar[0] * 0.8 + 0.001)
    }

    // MARK: Time saver

    private func curl(sets: Int = 3, load: Double? = 12) -> PlannedExercise {
        PlannedExercise(exerciseID: "Dumbbell_Bicep_Curl", name: "Dumbbell Curl", sets: sets, reps: 10...12, rpe: 9,
                        load: load, loadKind: .dumbbell, note: nil)
    }

    private var row: PlannedExercise {
        PlannedExercise(exerciseID: "Bent_Over_Barbell_Row", name: "Barbell Row", sets: 3, reps: 6...8, rpe: 8,
                        load: 60, loadKind: .barbell, note: nil)
    }

    @Test func neverTheFirstExerciseNorAMultiJointLift() {
        #expect(!TimeSaver.isEligible(curl(), at: 0, kind: .drop, gym: gym))
        #expect(TimeSaver.isEligible(curl(), at: 1, kind: .drop, gym: gym))
        // Heavy multi-joint barbell lifts keep straight sets (safety).
        #expect(!TimeSaver.isEligible(row, at: 1, kind: .drop, gym: gym))
        #expect(!TimeSaver.isEligible(row, at: 1, kind: .myoRep, gym: gym))
        // One set, the lightest dumbbell, or bodyweight: nothing to drop to.
        #expect(!TimeSaver.isEligible(curl(sets: 1), at: 1, kind: .drop, gym: gym))
        #expect(!TimeSaver.isEligible(curl(load: 2), at: 1, kind: .drop, gym: gym))
        #expect(TimeSaver.isEligible(curl(load: 2), at: 1, kind: .restPause, gym: gym))
        // First time (no load yet): still a drop set, with "at least 20% lighter".
        #expect(TimeSaver.isEligible(curl(load: nil), at: 1, kind: .drop, gym: gym))
        #expect(!TimeSaver.isEligible(curl(), at: 1, kind: .straight, gym: gym))
        // A superset partner keeps straight sets: no drop chain inside "one set of each, then rest".
        var paired = curl()
        paired.supersetGroup = 1
        #expect(!TimeSaver.isEligible(paired, at: 1, kind: .drop, gym: gym))
        #expect(!TimeSaver.isEligible(paired, at: 1, kind: .restPause, gym: gym))
    }

    @Test func threeStraightSetsBecomeOneDropSetWithTwoDrops() {
        var exercise = curl()
        TimeSaver.convert(&exercise, to: .drop, gym: gym)
        #expect(exercise.sets == 1)
        #expect(exercise.lastSetKind == .drop)
        #expect(exercise.stages == [.init(load: 8, reps: 10), .init(load: 6, reps: 10)])
        #expect(TimeSaver.describe(exercise, unit: .kg) == "Drop set: 12 → 8 → 6 kg, no rest between")

        var two = curl(sets: 2)
        TimeSaver.convert(&two, to: .restPause, gym: gym)
        #expect(two.stages == [.init(load: nil, reps: 3)])

        var myo = curl(sets: 2)
        TimeSaver.convert(&myo, to: .myoRep, gym: gym)
        #expect(myo.stages?.count == 3)
        #expect(TimeSaver.describe(myo, unit: .kg)?.contains("untested") == true)

        var unknown = curl(load: nil)
        TimeSaver.convert(&unknown, to: .drop, gym: gym)
        #expect(unknown.stages == [.init(load: nil, reps: 10), .init(load: nil, reps: 10)])
        #expect(TimeSaver.describe(unknown, unit: .kg)?.contains("at least 20% lighter") == true)
    }

    @Test func stagesCountInTheTimeEstimate() {
        // Balanced isolation set: 45 s + 90 s rest = 2.25 min; three sets = 6.75 → 7.
        let straight = curl()
        #expect(WorkoutPlanner.estimatedMinutes([straight]) == 7)
        // One set (2.25 min) + two drops of 10 reps (40 s + 15 s change each) ≈ 4.1 → 4.
        var drop = straight
        TimeSaver.convert(&drop, to: .drop, gym: gym)
        #expect(WorkoutPlanner.estimatedMinutes([drop]) == 4)
        #expect(TimeSaver.stageSeconds(for: .drop, reps: 10) == 55)
        #expect(TimeSaver.stageSeconds(for: .myoRep, reps: 4) == 31)
    }

    @Test func shortPlanOffersTheSmallLiftsOnly() {
        let planner = WorkoutPlanner(gym: gym)
        let plan = planner.plan(focus: .pull, minutes: 30, recovery: 80, history: [:])
        let options = TimeSaver.options(for: plan, minutes: 30, goals: Goals(focuses: [.muscle]), gym: gym)
        let drop = options.first { $0.kind == .drop }
        #expect(drop != nil)
        #expect(options.first?.kind == .drop)
        let compoundNames = plan.exercises.filter { ExerciseCatalog.slot(for: $0.exerciseID)?.isCompound == true }.map(\.name)
        #expect(!(drop?.exerciseNames ?? []).contains { compoundNames.contains($0) })
        #expect((drop?.minutesSaved ?? 0) >= 1)

        let applied = TimeSaver.apply(.drop, to: plan, gym: gym)
        #expect((applied.estimatedMinutes ?? 99) < (plan.estimatedMinutes ?? 0))
        #expect(applied.exercises.first?.lastSetKind == nil)
        #expect(applied.rationale.contains("min less"))
        // Already applied: nothing more to offer.
        #expect(TimeSaver.options(for: applied, minutes: 30, goals: nil, gym: gym).isEmpty)
    }

    @Test func onlyShortSessionsAndGoalsTheEvidenceSuits() {
        let planner = WorkoutPlanner(gym: gym)
        let plan = planner.plan(focus: .pull, minutes: 30, recovery: 80, history: [:])
        #expect(TimeSaver.options(for: plan, minutes: 45, goals: nil, gym: gym).isEmpty)
        // Strength only: no offer, and the reason.
        let strength = Goals(focuses: [.strength])
        #expect(TimeSaver.options(for: plan, minutes: 30, goals: strength, gym: gym).isEmpty)
        #expect(TimeSaver.strengthNote(strength)?.contains("don't replace heavy straight sets") == true)
        // Strength and muscle: offered, with the note that main lifts stay.
        let mixed = Goals(focuses: [.strength, .muscle])
        #expect(!TimeSaver.options(for: plan, minutes: 30, goals: mixed, gym: gym).isEmpty)
        #expect(TimeSaver.strengthNote(mixed)?.contains("main lifts stay") == true)
        #expect(TimeSaver.suitsGoals(Goals(focuses: [.health])))
        #expect(!TimeSaver.suitsGoals(Goals(focuses: [.endurance])))
        #expect(TimeSaver.strengthNote(Goals(focuses: [.muscle])) == nil)
    }

    @Test func plannedExerciseDecodesWithoutStages() throws {
        // A plan saved before set types (no lastSetKind/stages keys).
        let old = #"{"exerciseID":"Dumbbell_Bicep_Curl","name":"Curl","sets":3,"reps":[10,12],"rpe":9}"#
        let decoded = try JSONDecoder().decode(PlannedExercise.self, from: Data(old.utf8))
        #expect(decoded.lastSetKind == nil)
        #expect(decoded.stages == nil)
        var exercise = curl()
        TimeSaver.convert(&exercise, to: .drop, gym: gym)
        let roundTrip = try JSONDecoder().decode(PlannedExercise.self, from: JSONEncoder().encode(exercise))
        #expect(roundTrip == exercise)
    }
}
