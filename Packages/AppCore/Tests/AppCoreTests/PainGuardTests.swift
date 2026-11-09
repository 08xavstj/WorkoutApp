import Foundation
import Testing
@testable import AppCore

struct PainGuardTests {
    let gym = GymProfile.commercialKilograms
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func pain(_ area: PainArea, _ level: Int, worse: Bool? = nil, daysAgo: Int = 0) -> PainReport {
        PainReport(area: area, level: level, worseAfterTraining: worse, loggedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    func planner(_ gym: GymProfile, _ filter: ExerciseFilter) -> WorkoutPlanner {
        var planner = WorkoutPlanner(gym: gym)
        planner.exerciseFilter = filter
        return planner
    }

    // MARK: Area → slot mapping

    @Test func areasMapToTheLiftsThatLoadThem() {
        #expect(PainGuard.areas(for: .squat).contains(.knee))
        #expect(PainGuard.areas(for: .legExtension).contains(.knee))
        #expect(PainGuard.areas(for: .hinge).contains(.lowerBack))
        #expect(PainGuard.areas(for: .horizontalPress).contains(.shoulder))
        #expect(PainGuard.areas(for: .verticalPress).contains(.neck))
        #expect(PainGuard.areas(for: .triceps).contains(.elbow))
        #expect(PainGuard.areas(for: .calves).contains(.ankle))
        #expect(!PainGuard.areas(for: .legCurl).contains(.shoulder))
        // A bar on the back loads the lower back; a supported row doesn't.
        #expect(PainGuard.areas(forExerciseID: "Bent_Over_Barbell_Row", slot: .horizontalRow).contains(.lowerBack))
        #expect(!PainGuard.areas(forExerciseID: "Seated_Cable_Rows", slot: .horizontalRow).contains(.lowerBack))
        #expect(PainGuard.areas(forExerciseID: "Barbell_Squat", slot: .squat).contains(.lowerBack))
        #expect(!PainGuard.areas(forExerciseID: "Leg_Press", slot: .squat).contains(.lowerBack))
        #expect(PainGuard.areas(forExerciseID: "Pushups", slot: .horizontalPress).contains(.wrist))
    }

    /// Every regression is a real catalog-style exercise in its own slot's
    /// pattern, and swaps can find its slot.
    @Test func regressionsResolveToASlot() {
        for regression in PainGuard.regressionTable {
            #expect(PainGuard.areas(for: regression.slot).contains(regression.area)
                    || (ExerciseCatalog.options[regression.slot] ?? []).contains { PainGuard.areas(forExerciseID: $0.id, slot: regression.slot).contains(regression.area) },
                    "\(regression.area) \(regression.slot)")
            for exercise in regression.exercises {
                #expect(ExerciseCatalog.slot(for: exercise.id) != nil, "\(exercise.id)")
                #expect(ExerciseCatalog.exercise(id: exercise.id) != nil, "\(exercise.id)")
            }
        }
        #expect(ExerciseCatalog.slot(for: "Box_Squat") == .squat)
        // Hip thrusts are a regular movement now (glutes first), so the catalog's slot wins.
        #expect(ExerciseCatalog.slot(for: "Barbell_Hip_Thrust") == .hipThrust)
        #expect(PainGuard.regressionSlot(for: "Barbell_Hip_Thrust") == .hinge)
    }

    // MARK: Thresholds

    @Test func thresholdsFollowTheFiveOutOfTenRule() {
        #expect(PainGuard.response(to: pain(.knee, 0)) == .unchanged)
        #expect(PainGuard.response(to: pain(.knee, 2)) == .unchanged)
        #expect(PainGuard.response(to: pain(.knee, 3)) == .regress)
        #expect(PainGuard.response(to: pain(.knee, 5)) == .regress)
        #expect(PainGuard.response(to: pain(.knee, 6)) == .avoid)
        #expect(PainGuard.response(to: pain(.knee, 10)) == .avoid)
        // Worse after training is the stop signal, even within 5/10.
        #expect(PainGuard.response(to: pain(.knee, 4, worse: true)) == .avoid)
        #expect(PainGuard.response(to: pain(.knee, 2, worse: true)) == .unchanged)
        #expect(PainReport(area: .knee, level: 14, loggedAt: now).level == 10)
    }

    @Test func avoidLeavesOutEveryLiftThatLoadsTheArea() {
        let filter = ExerciseFilter(pains: [pain(.knee, 7)])
        let plan = WorkoutPlanner(gym: gym).plan(focus: .legs, minutes: 60, recovery: 80, history: [:], exerciseFilter: filter)
        #expect(!plan.exercises.isEmpty)
        for exercise in plan.exercises {
            let slot = ExerciseCatalog.slot(for: exercise.exerciseID)
            #expect(slot != nil)
            if let slot {
                #expect(!PainGuard.areas(forExerciseID: exercise.exerciseID, slot: slot).contains(.knee), "\(exercise.exerciseID)")
            }
        }
        #expect(planner(gym, filter).alternatives(for: .squat).isEmpty)
        #expect(plan.rationale.contains("knee (7/10)"))
    }

    @Test func avoidKeepsOptionsThatSpareTheArea() {
        let filter = ExerciseFilter(pains: [pain(.lowerBack, 8)])
        let rows = planner(gym, filter).alternatives(for: .horizontalRow).map(\.id)
        #expect(!rows.contains("Bent_Over_Barbell_Row"))
        #expect(rows.contains("Seated_Cable_Rows"))
        #expect(planner(gym, filter).choose(.squat)?.id == "Leg_Press")
        #expect(planner(gym, filter).choose(.hinge) == nil)
    }

    // MARK: Regressions respect the gym

    @Test func regressionComesFirstWhenTheGymSupportsIt() {
        let knee = ExerciseFilter(pains: [pain(.knee, 4)])
        #expect(planner(gym, knee).choose(.squat)?.id == "Box_Squat")
        let shoulder = ExerciseFilter(pains: [pain(.shoulder, 5)])
        #expect(planner(gym, shoulder).choose(.horizontalPress)?.id == "Dumbbell_Bench_Press_with_Neutral_Grip")
        let back = ExerciseFilter(pains: [pain(.lowerBack, 3)])
        #expect(planner(gym, back).choose(.hinge)?.id == "Barbell_Hip_Thrust")
        #expect(planner(gym, back).choose(.horizontalRow)?.id == "Seated_Cable_Rows")
        // The usual options stay as swaps after the regression.
        #expect(planner(gym, knee).alternatives(for: .squat).contains { $0.id == "Barbell_Squat" })
    }

    @Test func regressionNeedsTheGymsEquipment() {
        let home = GymProfile.homeDumbbells // dumbbells, bench, pull-up bar, bands
        let knee = ExerciseFilter(pains: [pain(.knee, 4)])
        let squats = planner(home, knee).alternatives(for: .squat).map(\.id)
        #expect(!squats.contains("Box_Squat"))
        #expect(!squats.contains("Leg_Press"))
        #expect(planner(home, knee).choose(.squat)?.id == WorkoutPlanner(gym: home).choose(.squat)?.id)
        let back = ExerciseFilter(pains: [pain(.lowerBack, 4)])
        #expect(planner(home, back).choose(.hinge)?.id == "Single_Leg_Glute_Bridge")
        var barbellOnly = gym
        barbellOnly.equipment = [.barbell, .bench, .squatRack]
        let shoulder = ExerciseFilter(pains: [pain(.shoulder, 4)])
        #expect(planner(barbellOnly, shoulder).choose(.horizontalPress)?.id == "Floor_Press")
        for exercise in planner(barbellOnly, shoulder).alternatives(for: .horizontalPress) {
            #expect(PainGuard.gymSupports(exercise, gym: barbellOnly), "\(exercise.id)")
        }
    }

    // MARK: Load cap

    @Test func regressCapsTheLoadAboutTwentyPercent() {
        let filter = ExerciseFilter(pains: [pain(.knee, 4)])
        var squat = PlannedExercise(exerciseID: "Box_Squat", name: "Box Squat", sets: 3, reps: 6...8, rpe: 8, load: 100, loadKind: .barbell, note: nil)
        squat.progressionNote = "+2.5 kg on last time"
        filter.capLoad(&squat, slot: .squat, gym: gym)
        #expect(squat.load == 80)
        #expect(squat.progressionNote == nil)
        #expect(squat.note?.contains("20%") == true)
        // Rounds down to a load the gym can make.
        var odd = PlannedExercise(exerciseID: "Leg_Press", name: "Leg Press", sets: 3, reps: 8...10, rpe: 8, load: 103, loadKind: .machine, note: nil)
        filter.capLoad(&odd, slot: .squat, gym: gym)
        #expect(odd.load == 80) // 82.4 → 80 on a 5 kg stack
        // A lift that doesn't load the area is untouched.
        var press = PlannedExercise(exerciseID: "Dumbbell_Bench_Press", name: "DB Press", sets: 3, reps: 8...10, rpe: 8, load: 30, loadKind: .dumbbell, note: nil)
        filter.capLoad(&press, slot: .horizontalPress, gym: gym)
        #expect(press.load == 30 && press.note == nil)
    }

    @Test func planCapsTheRegressedLift() {
        let history = ["Dumbbell_Bench_Press_with_Neutral_Grip": ExerciseHistory(bestEstimatedOneRepMax: 38, lastWeight: 30, lastReps: 8, lastRPE: 8, lastDate: now)]
        let filter = ExerciseFilter(pains: [pain(.shoulder, 4)])
        let plain = WorkoutPlanner(gym: gym).plan(focus: .push, minutes: 45, recovery: 80, history: history)
        let guarded = WorkoutPlanner(gym: gym).plan(focus: .push, minutes: 45, recovery: 80, history: history, exerciseFilter: filter)
        let neutral = "Dumbbell_Bench_Press_with_Neutral_Grip"
        #expect(plain.exercises.contains { $0.exerciseID == "Barbell_Bench_Press_-_Medium_Grip" })
        #expect(!plain.exercises.contains { $0.exerciseID == neutral })
        let first = guarded.exercises.first { $0.exerciseID == neutral }
        #expect(first != nil)
        if let load = first?.load {
            #expect(load <= 30 * 0.9)
        }
        #expect(first?.note?.contains("your shoulder") == true)
        #expect(guarded.rationale.contains("shoulder (4/10)"))
    }

    // MARK: Never again

    @Test func neverAgainIsNeverPlannedOrOffered() {
        let filter = ExerciseFilter(neverAgain: ["Barbell_Squat", "Romanian_Deadlift"])
        let guarded = planner(gym, filter)
        #expect(!guarded.alternatives(for: .squat).contains { $0.id == "Barbell_Squat" })
        #expect(guarded.choose(.squat)?.id == "Leg_Press")
        for focus in WorkoutFocus.allCases {
            let plan = WorkoutPlanner(gym: gym).plan(focus: focus, minutes: 75, recovery: 80, history: [:], exerciseFilter: filter)
            #expect(!plan.exercises.contains { filter.neverAgain.contains($0.exerciseID) }, "\(focus)")
        }
        // Never-again beats a regression too.
        let both = ExerciseFilter(neverAgain: ["Box_Squat"], pains: [pain(.knee, 4)])
        #expect(planner(gym, both).choose(.squat)?.id == "Leg_Press")
        #expect(ExerciseFilter().isEmpty)
        #expect(!filter.isEmpty)
        #expect(ExerciseFilter(pains: [pain(.knee, 2)]).isEmpty)
    }

    // MARK: Expiry

    @Test func reportsExpireAfterSevenDaysUnlessLoggedAgain() {
        let sixDays = PainGuard.active([pain(.knee, 6, daysAgo: 6)], today: now, calendar: calendar)
        #expect(sixDays.map(\.area) == [.knee])
        #expect(PainGuard.active([pain(.knee, 6, daysAgo: 7)], today: now, calendar: calendar).isEmpty)
        // Re-logging renews it; the newest report per area wins.
        let renewed = PainGuard.active([pain(.knee, 6, daysAgo: 9), pain(.knee, 4, daysAgo: 2)], today: now, calendar: calendar)
        #expect(renewed.first?.level == 4)
        // A 0 clears it.
        #expect(PainGuard.active([pain(.knee, 6, daysAgo: 2), pain(.knee, 0, daysAgo: 1)], today: now, calendar: calendar).isEmpty)
        // Worst first.
        let two = PainGuard.active([pain(.wrist, 3), pain(.hip, 7)], today: now, calendar: calendar)
        #expect(two.map(\.area) == [.hip, .wrist])
        let filter = ExerciseFilter(neverAgain: [], reports: [pain(.knee, 7, daysAgo: 8)], today: now, calendar: calendar)
        #expect(filter.pains.isEmpty && filter.avoidAreas.isEmpty)
    }

    @Test func clinicianLineAfterTwoWeeks() {
        let lasting = [pain(.knee, 4, daysAgo: 15), pain(.knee, 5, daysAgo: 10), pain(.knee, 4, daysAgo: 5), pain(.knee, 3, daysAgo: 0)]
        #expect(PainGuard.daysHurting(.knee, reports: lasting, today: now, calendar: calendar) == 16)
        #expect(PainGuard.seeClinician(.knee, reports: lasting, today: now, calendar: calendar))
        // A clear in between restarts the count.
        let cleared = [pain(.knee, 4, daysAgo: 15), pain(.knee, 0, daysAgo: 10), pain(.knee, 4, daysAgo: 5), pain(.knee, 3, daysAgo: 0)]
        #expect(!PainGuard.seeClinician(.knee, reports: cleared, today: now, calendar: calendar))
        // A gap longer than the expiry restarts it too.
        let gap = [pain(.knee, 4, daysAgo: 16), pain(.knee, 3, daysAgo: 0)]
        #expect(PainGuard.daysHurting(.knee, reports: gap, today: now, calendar: calendar) == 1)
        #expect(PainGuard.daysHurting(.knee, reports: [pain(.knee, 0)], today: now, calendar: calendar) == nil)
    }

    // MARK: Check-in

    @Test func checkInWithoutPainsStillDecodes() throws {
        let old = MorningCheckIn(day: now)
        let data = try JSONEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("pains"))
        let decoded = try JSONDecoder().decode(MorningCheckIn.self, from: data)
        #expect(decoded.pains == nil)
        var withPain = old
        withPain.pains = [pain(.lowerBack, 5, worse: true)]
        let roundTrip = try JSONDecoder().decode(MorningCheckIn.self, from: JSONEncoder().encode(withPain))
        #expect(roundTrip == withPain)
    }
}
