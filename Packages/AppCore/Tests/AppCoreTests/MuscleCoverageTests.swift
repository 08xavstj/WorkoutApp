import Foundation
import Testing
@testable import AppCore

struct MuscleCoverageTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A push day already logged this week: chest, shoulders and triceps in the zone.
    let afterPush: [Muscle: Double] = [.chest: 12, .shoulders: 10, .triceps: 10]

    @Test func picksTheFocusWithTheBiggestGap() throws {
        let result = try #require(MuscleCoverage.suggest(setsThisWeek: afterPush, sessionsLeft: 2, preferred: .push))
        // Legs and lower both close 18 sets of gap; pull wastes its rear-delt
        // work on shoulders that are done, so legs (first in the case order) wins.
        #expect(result.focus == .legs)
        // Equal gaps keep the tracked order; nothing already in the zone lags.
        #expect(result.lagging.first == .lats)
        #expect(!result.lagging.contains(.chest))
        // Single-joint movements for the first two lagging muscles the focus trains.
        #expect(result.prioritySlots == [.legExtension, .legCurl])
        #expect(result.reason == "to catch quads and hamstrings up to this week's 10-20 hard sets")
    }

    @Test func skipsMusclesStillRecovering() throws {
        // Ten hard squat sets an hour ago: legs fatigued, so no leg focus even though lats lag just as much.
        let squats = (0..<10).map { _ in
            MuscleRecovery.WorkSet(date: now.addingTimeInterval(-3600), primary: ["quadriceps", "glutes", "hamstrings"], rpe: 9)
        }
        let states = MuscleRecovery.evaluate(sets: squats, now: now)
        let sets = afterPush.merging([.quadriceps: 10, .hamstrings: 10, .glutes: 10]) { a, _ in a }
        let result = try #require(MuscleCoverage.suggest(setsThisWeek: sets, states: states, sessionsLeft: 1, preferred: .legs))
        #expect(result.focus == .pull)
        // The last session of the week reaches one lagging muscle outside the focus (calves).
        #expect(result.prioritySlots == [.verticalPull, .biceps, .calves])
        #expect(!result.lagging.contains(.quadriceps))
    }

    @Test func nothingToSteerByFallsBackToTheRotation() {
        var full: [Muscle: Double] = [:]
        for muscle in MuscleCoverage.tracked { full[muscle] = 12 }
        #expect(MuscleCoverage.suggest(setsThisWeek: full, sessionsLeft: 3) == nil)
        #expect(MuscleCoverage.suggest(setsThisWeek: [:], sessionsLeft: 0) == nil)
        // A fresh week ties every focus, so the rotation's pick stands.
        #expect(MuscleCoverage.suggest(setsThisWeek: [:], sessionsLeft: 3, preferred: .pull)?.focus == .pull)
        let picked = WorkoutPlanner.suggestedFocus(recentExerciseIDs: ["Barbell_Bench_Press_-_Medium_Grip"],
                                                   setsThisWeek: [:], states: [:], sessionsLeft: 3)
        #expect(picked.focus == .pull)
        #expect(picked.coverage?.focus == .pull)
        // Once muscles fall behind, the coverage rule steers.
        let steered = WorkoutPlanner.suggestedFocus(recentExerciseIDs: ["Barbell_Bench_Press_-_Medium_Grip"],
                                                    setsThisWeek: afterPush, states: [:], sessionsLeft: 2)
        #expect(steered.focus == .legs)
    }

    @Test func countsThisCalendarWeekOnly() {
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let sets = [
            MuscleRecovery.WorkSet(date: monday.addingTimeInterval(-3600), primary: ["chest"], secondary: ["triceps"]),   // last week
            MuscleRecovery.WorkSet(date: monday.addingTimeInterval(3600), primary: ["chest"], secondary: ["triceps"], rpe: 8),
            MuscleRecovery.WorkSet(date: monday.addingTimeInterval(7200), primary: ["chest"], rpe: 6),                      // easy set: 0.6
        ]
        let week = MuscleCoverage.setsThisWeek(sets, weekStart: monday, now: monday.addingTimeInterval(86_400))
        #expect(abs((week[.chest] ?? 0) - 1.6) < 1e-9)
        #expect(week[.triceps] == 0.5)
        #expect(week[.lats] == nil)
    }

    @Test func prioritySlotsGoAfterTheCompoundLifts() {
        // Push puts side delts before the incline press now; pull has a second row before the core (audit 2026-11 §12, §19).
        #expect(WorkoutPlanner.orderedSlots(focus: .push, minutes: 45, priority: [.triceps])
                == [.horizontalPress, .verticalPress, .triceps, .lateralRaise, .inclinePress, .chestFly])
        #expect(WorkoutPlanner.orderedSlots(focus: .pull, minutes: 45, priority: [.hinge, .hinge])
                == [.verticalPull, .horizontalRow, .hinge, .rearDelt, .biceps, .horizontalRow, .core])
        #expect(WorkoutPlanner.orderedSlots(focus: .legs, minutes: 45, priority: []) == WorkoutFocus.legs.slots)
        // The planner then builds the session with the lagging muscle's movement in it.
        let plan = WorkoutPlanner(gym: .commercialPounds).plan(focus: .pull, minutes: 45, recovery: 80, history: [:],
                                                                focusReason: "to catch hamstrings up", prioritySlots: [.hinge])
        let slots = plan.exercises.compactMap { ExerciseCatalog.slot(for: $0.exerciseID) }
        #expect(slots.prefix(3).contains(.hinge))
        #expect(plan.rationale.hasPrefix("Pull Day to catch hamstrings up:"))
    }
}
