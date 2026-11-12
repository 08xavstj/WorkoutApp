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
