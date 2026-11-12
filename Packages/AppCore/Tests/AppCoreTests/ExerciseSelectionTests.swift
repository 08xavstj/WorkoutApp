import Foundation
import Testing
@testable import AppCore

/// Exercise selection follows the hypertrophy evidence (docs/research/exercise-selection-2026-11.md).
struct ExerciseSelectionTests {
    let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)

    func slots(_ focus: WorkoutFocus, _ minutes: Int, core: Bool = false, variant: Int = 0) -> [MovementSlot] {
        planner.plan(focus: focus, minutes: minutes, recovery: 70, history: [:], includeCore: core, variant: variant)
            .exercises.compactMap { ExerciseCatalog.slot(for: $0.exerciseID) }
    }

    func count(_ slots: [MovementSlot], _ wanted: Set<MovementSlot>) -> Int {
        slots.filter { wanted.contains($0) }.count
    }

    // Presses alone barely grow the triceps' long head (Brandão 2020).
    @Test func pushDaysAlwaysHaveDirectTricepsWork() {
        for minutes in [30, 45, 60, 75, 90] {
            #expect(count(slots(.push, minutes), [.triceps]) >= 1, "\(minutes) min")
        }
        // From an hour: two triceps exercises, an overhead extension and a pushdown.
        let hour = planner.plan(focus: .push, minutes: 60, recovery: 70, history: [:])
        let triceps = hour.exercises.filter { ExerciseCatalog.slot(for: $0.exerciseID) == .triceps }.map(\.exerciseID)
        #expect(triceps == ["Cable_Rope_Overhead_Triceps_Extension", "Triceps_Pushdown_-_Rope_Attachment"])
    }

    // Curls grew the elbow flexors about twice as much as rows (Mannarino 2021).
    @Test func pullDaysAlwaysHaveDirectBicepsWork() {
        for minutes in [30, 45, 60, 75, 90] {
            #expect(count(slots(.pull, minutes), [.biceps, .hammerCurl]) >= 1, "\(minutes) min")
        }
        for minutes in [45, 60, 75] {
            #expect(count(slots(.pull, minutes), [.biceps, .hammerCurl]) == 2, "\(minutes) min")
        }
    }

    @Test func upperDaysHaveACurlAndATricepsExtensionFromAnHour() {
        for variant in 0..<2 {
            let hour = slots(.upper, 60, variant: variant)
            #expect(hour.contains(.biceps), "version \(variant)")
            #expect(hour.contains(.triceps), "version \(variant)")
        }
        // At 45 minutes A keeps the curl and B the triceps extension, so a week has both.
        #expect(slots(.upper, 45, variant: 0).contains(.biceps))
        #expect(slots(.upper, 45, variant: 1).contains(.triceps))
    }

    @Test func fullBodyDaysGetArmWorkWhenTheFinisherCoversTheCore() {
        #expect(slots(.fullBody, 60, core: false, variant: 0).contains(.biceps))
        #expect(slots(.fullBody, 60, core: false, variant: 1).contains(.triceps))
    }

    // Squats don't grow the rectus femoris or the hamstrings (Kubo 2019).
    @Test func legAndLowerDaysHaveALegCurlAndALegExtension() {
        for focus in [WorkoutFocus.legs, .lower] {
            let hour = slots(focus, 60)
            #expect(hour.contains(.legCurl), "\(focus)")
            #expect(hour.contains(.legExtension), "\(focus)")
        }
    }

    // Big lifts first: a curl before a row costs the row reps (Nunes 2021; Simão 2012).
    @Test func compoundLiftsComeBeforeSmallOnes() {
        for focus in WorkoutFocus.allCases {
            for minutes in [45, 60, 75, 90] {
                for variant in 0..<focus.variantCount {
                    let plan = planner.plan(focus: focus, minutes: minutes, recovery: 70, history: [:], variant: variant)
                    guard !plan.hasSupersets else { continue }
                    let compound = plan.exercises.map { ExerciseCatalog.slot(for: $0.exerciseID)?.isCompound == true }
                    let firstSmall = compound.firstIndex(of: false) ?? compound.count
                    #expect(!compound[firstSmall...].contains(true), "\(focus) \(minutes) v\(variant): \(plan.exercises.map(\.name))")
                }
            }
        }
    }

    @Test func liftOrderKeepsTheChosenOrderWithinEachGroupAndPutsCoreLast() {
        func exercise(_ id: String) -> PlannedExercise {
            PlannedExercise(exerciseID: id, name: id, sets: 3, reps: 8...12, rpe: 8, load: nil, loadKind: nil)
        }
        let chosen = ["Wide-Grip_Lat_Pulldown", "Barbell_Curl", "Plank", "Bent_Over_Barbell_Row", "Face_Pull"].map(exercise)
        #expect(WorkoutPlanner.liftOrder(chosen).map(\.exerciseID)
                == ["Wide-Grip_Lat_Pulldown", "Bent_Over_Barbell_Row", "Barbell_Curl", "Face_Pull", "Plank"])
    }

    // Rows plan as upper-back work, the way the exercise library logs them.
    @Test func rowsCountForTheUpperBack() {
        #expect(MuscleCoverage.muscles(for: .horizontalRow).primary == .middleBack)
        #expect(MuscleCoverage.muscles(for: .horizontalRow).secondary.contains(.lats))
        #expect(MuscleCoverage.muscles(for: .verticalPull).primary == .lats)
        // So a long pull day fills its time instead of stopping at one muscle's cap.
        let long = planner.plan(focus: .pull, minutes: 75, recovery: 70, history: [:], includeCore: false)
        #expect((long.estimatedMinutes ?? 0) >= 68)
    }

    @Test func noMuscleGoesOverTheSessionCap() {
        for focus in WorkoutFocus.allCases {
            for minutes in [45, 60, 75, 90, 120] {
                let plan = planner.plan(focus: focus, minutes: minutes, recovery: 70, history: [:], includeCore: false)
                let direct = VolumeProgression.directSets(plan.exercises)
                #expect(direct.values.allSatisfy { $0 <= VolumeProgression.sessionCap(minutes: minutes) },
                        "\(focus) \(minutes): \(direct)")
            }
        }
    }
}

/// Every muscle is trained each week on the default splits
/// (docs/research/exercise-selection-2026-11.md, "The whole week").
struct WeeklyCoverageTests {
    let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)

    struct Week {
        var direct: [Muscle: Double] = [:]
        /// Direct sets plus half for each set where the muscle helps (Pelland et al. 2026's fractional count).
        var fractional: [Muscle: Double] = [:]
        var sessions: [Muscle: Int] = [:]
    }

    func week(days: Int, minutes: Int, core: Bool) -> Week {
        var week = Week()
        var seen: [WorkoutFocus: Int] = [:]
        for focus in WeeklyPlan.focusRotation(start: .push, count: days) {
            let version = seen[focus, default: 0]
            seen[focus] = version + 1
            let plan = planner.plan(focus: focus, minutes: minutes, recovery: 70, history: [:], includeCore: core,
                                    variant: version % focus.variantCount)
            var hit: Set<Muscle> = []
            for exercise in plan.exercises {
                guard let slot = ExerciseCatalog.slot(for: exercise.exerciseID) else { continue }
                let muscles = MuscleCoverage.muscles(for: slot)
                week.direct[muscles.primary, default: 0] += Double(exercise.sets)
                week.fractional[muscles.primary, default: 0] += Double(exercise.sets)
                hit.insert(muscles.primary)
                for helper in muscles.secondary {
                    week.fractional[helper, default: 0] += 0.5 * Double(exercise.sets)
                    hit.insert(helper)
                }
            }
            for muscle in hit { week.sessions[muscle, default: 0] += 1 }
        }
        return week
    }

    static let big: [Muscle] = [.chest, .shoulders, .triceps, .biceps, .lats, .middleBack, .quadriceps, .hamstrings, .glutes]

    // Each major muscle group at least twice a week (ACSM 2026; Schoenfeld, Ogborn & Krieger 2016).
    @Test func everyBigMuscleIsTrainedTwiceAWeek() {
        for days in 2...6 {
            for minutes in [45, 60, 75] {
                for core in [true, false] {
                    let week = week(days: days, minutes: minutes, core: core)
                    for muscle in Self.big {
                        #expect((week.sessions[muscle] ?? 0) >= 2, "\(days) days, \(minutes) min: \(muscle)")
                    }
                }
            }
        }
    }

    // No compound lift trains the calves, and the abs get little: both need their own movement.
    @Test func calvesAndAbsAreTrainedEveryWeek() {
        for days in 2...6 {
            for minutes in [45, 60, 75] {
                for core in [true, false] {
                    let week = week(days: days, minutes: minutes, core: core)
                    #expect((week.direct[.calves] ?? 0) >= 3, "\(days) days, \(minutes) min: calves")
                    if days >= 3 { #expect((week.sessions[.calves] ?? 0) >= 2, "\(days) days, \(minutes) min: calves twice") }
                    // With the finisher on (`core` false) the abs come from it instead.
                    if core { #expect((week.direct[.abdominals] ?? 0) >= 3, "\(days) days, \(minutes) min: abs") }
                }
            }
        }
    }

    // Four or more hour-long days reach about the 10 weekly sets where growth is best
    // (Schoenfeld, Ogborn & Krieger 2017), counting helper sets at half; shorter weeks stay
    // over the ~4 sets that still build muscle (Pelland et al. 2026).
    @Test func weeklySetsReachTheBandWhenTheWeekHasRoom() {
        for days in 4...6 {
            for minutes in [60, 75] {
                let week = week(days: days, minutes: minutes, core: false)
                for muscle in Self.big {
                    #expect((week.fractional[muscle] ?? 0) >= 8, "\(days) days, \(minutes) min: \(muscle) \(week.fractional[muscle] ?? 0)")
                }
            }
        }
        for days in 2...6 {
            for minutes in [45, 60, 75] {
                let week = week(days: days, minutes: minutes, core: true)
                for muscle in Self.big {
                    #expect((week.fractional[muscle] ?? 0) >= 3, "\(days) days, \(minutes) min: \(muscle) \(week.fractional[muscle] ?? 0)")
                }
            }
        }
    }
}

/// Small lifts add reps before weight when the next step is big for them.
struct SmallLiftProgressionTests {
    let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)

    @Test func aBarbellCurlOnATenPercentStepIsRepFirst() {
        // 25 → 27.5 kg is 10%: three reps' worth of load on a curl.
        #expect(planner.progressionMode(for: "Barbell_Curl", kind: .barbell, compound: false, at: 25) == .reps)
        // A bench press at 100 kg moves 2.5%: load as before. So does a 60 kg row (4%).
        #expect(planner.progressionMode(for: "Barbell_Bench_Press_-_Medium_Grip", kind: .barbell, compound: true, at: 100) == .load)
        #expect(planner.progressionMode(for: "Bent_Over_Barbell_Row", kind: .barbell, compound: true, at: 60) == .load)
        // A compound lift keeps the 10% line: 30 → 32.5 kg (8%) is still a routine step.
        #expect(planner.progressionMode(for: "Standing_Military_Press", kind: .barbell, compound: true, at: 30) == .load)
    }

    @Test func theLineIsFivePercentForSingleJointLifts() {
        #expect(planner.isBigJump(from: 25, to: 27.5, compound: false))
        #expect(!planner.isBigJump(from: 25, to: 27.5, compound: true))
        #expect(!planner.isBigJump(from: 60, to: 62.5, compound: false))
        #expect(ProgressionMode.suggested(kind: .barbell, compound: false, bigJump: true) == .reps)
        #expect(ProgressionMode.suggested(kind: .barbell, compound: true, bigJump: true) == .load)
    }

    // Rep-first keeps the heaviest recent weight: one easier day doesn't lower it for good.
    @Test func repFirstReturnsToTheRecentHeaviestWeight() throws {
        let afterAnEasierDay = ExerciseHistory(bestEstimatedOneRepMax: 40, lastWeight: 25, lastReps: 10, lastRPE: 8, lastDate: .now,
                                               recentWeights: [27.5, 27.5, 25], lastSets: 3)
        let next = try #require(planner.progression(history: afterAnEasierDay, reps: 8...12, rpe: 8.5, kind: .barbell, mode: .reps))
        #expect(next.load == 27.5)
    }

    @Test func dumbbellCurlIsTheDefaultCurl() {
        #expect(planner.choose(.biceps)?.id == "Dumbbell_Bicep_Curl")
        let pull = planner.plan(focus: .pull, minutes: 60, recovery: 70, history: [:])
        #expect(pull.exercises.contains { $0.exerciseID == "Dumbbell_Bicep_Curl" })
        #expect(!pull.exercises.contains { $0.exerciseID == "Barbell_Curl" })
    }
}
