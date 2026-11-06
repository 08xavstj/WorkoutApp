import Foundation
import Testing
@testable import AppCore

struct SetFeedbackTests {
    private func set(_ weight: Double, _ reps: Int, _ rpe: Double? = nil) -> LiftProgress.LoggedSet {
        LiftProgress.LoggedSet(weight: weight, reps: reps, rpe: rpe)
    }

    @Test func shortOfThePlanHoldsTheLoad() {
        let verdict = SetFeedback.verdict(logged: set(60, 6, 9), last: set(60, 8, 8), targetReps: 8, targetRPE: 8)
        #expect(verdict == .short(reps: 2))
        #expect(verdict?.message(unit: "kg") == "2 short: the planner will hold the load")
        #expect(verdict?.isCaution == true)
    }

    @Test func pastTheEffortIsNamedBeforeMoreReps() {
        // +1 rep on last time, but at RPE 10 on an RPE 8 plan.
        let verdict = SetFeedback.verdict(logged: set(60, 9, 10), last: set(60, 8, 8), targetReps: 8, targetRPE: 8)
        #expect(verdict == .pastEffort(targetRIR: 2))
        #expect(verdict?.message(unit: "kg") == "Harder than planned: aim for 2 in reserve next set")
        // One point over is within the RPE error: no warning.
        #expect(SetFeedback.verdict(logged: set(60, 9, 9), last: set(60, 8, 8), targetReps: 8, targetRPE: 8) == .moreReps(1))
    }

    @Test func comparesWithLastTime() {
        let more = SetFeedback.verdict(logged: set(60, 9, 8), last: set(60, 8, 8), targetReps: 8, targetRPE: 8)
        #expect(more?.message(unit: "kg") == "+1 rep on last time")
        #expect(SetFeedback.verdict(logged: set(60, 10), last: set(60, 8), targetReps: nil, targetRPE: nil)?.message(unit: "kg")
                == "+2 reps on last time")
        let heavier = SetFeedback.verdict(logged: set(62.5, 8, 8), last: set(60, 8, 8), targetReps: 8, targetRPE: 8)
        #expect(heavier == .heavier(by: 2.5))
        #expect(heavier?.message(unit: "kg") == "+2.5 kg on last time")
    }

    @Test func matchesThePlanOrLastTime() {
        let plan = SetFeedback.verdict(logged: set(60, 8, 8), last: set(60, 8, 8), targetReps: 8, targetRPE: 8)
        #expect(plan == .matchedPlan)
        #expect(plan?.message(unit: "kg") == "Matched the plan")
        #expect(plan?.isCaution == false)
        #expect(SetFeedback.verdict(logged: set(60, 8), last: set(60, 8), targetReps: nil, targetRPE: nil) == .matchedLastTime)
        // Nothing to compare with, or nothing logged.
        #expect(SetFeedback.verdict(logged: set(60, 8), last: nil, targetReps: nil, targetRPE: nil) == nil)
        #expect(SetFeedback.verdict(logged: set(55, 10), last: set(60, 8), targetReps: nil, targetRPE: nil) == nil)
        #expect(SetFeedback.verdict(logged: set(60, 0), last: set(60, 8), targetReps: 8, targetRPE: 8) == nil)
    }

    @Test func recordsAtTheEndOfAnExercise() {
        let earlier = [LiftProgress.LoggedSession(date: .now.addingTimeInterval(-86_400 * 3), sets: [set(60, 8, 8), set(60, 8, 8)])]
        let today = [set(62.5, 8, 8), set(60, 9, 8)]
        let records = SetFeedback.records(today: today, earlier: earlier)
        #expect(records == [
            .estimatedOneRepMax(OneRepMax.estimate(weight: 62.5, reps: 8, rpe: 8)),
            .reps(weight: 60, reps: 9),
            .volume(62.5 * 8 + 60 * 9),
        ])
        #expect(SetFeedback.Record.reps(weight: 60, reps: 9).message(unit: "kg") == "Most reps at 60 kg: 9")
        #expect(SetFeedback.Record.estimatedOneRepMax(83.3).message(unit: "kg") == "Best estimated 1RM: 83 kg")
    }

    @Test func noRecordsOnTheFirstSessionOrWithoutABest() {
        #expect(SetFeedback.records(today: [set(60, 8, 8)], earlier: []).isEmpty)
        let earlier = [LiftProgress.LoggedSession(date: .now.addingTimeInterval(-86_400), sets: [set(60, 8, 8), set(60, 8, 8)])]
        #expect(SetFeedback.records(today: [set(60, 8, 8), set(60, 8, 8)], earlier: earlier).isEmpty)
        // A first-ever weight is an e1RM record, not a rep record.
        let heavier = SetFeedback.records(today: [set(70, 3, 8)], earlier: earlier)
        let hasRepRecord = heavier.contains { record in
            if case .reps = record { return true }
            return false
        }
        #expect(!hasRepRecord)
    }
}
