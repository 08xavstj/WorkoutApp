import Foundation
import Testing
@testable import AppCore

/// Copy the gym screens show from AppCore: the builder's rationale without
/// what the card already shows, the RPE guide's rows, the goal title and the
/// body-fat cut-offs behind the goal suggestion (QA round 1).
struct WorkoutScreenCopyTests {
    let planner = WorkoutPlanner(gym: .commercialPounds)

    @Test func builderRationaleDropsTitleMusclesAndBlock() {
        let week = TrainingBlock.weekState(1, style: .balanced, length: 5)
        let plan = planner.plan(focus: .upper, minutes: 60, recovery: 50, history: [:], block: week)
        // The full text (used by the coach) still names the focus and the week.
        #expect(plan.rationale.hasPrefix("Upper Body:"))
        #expect(plan.rationale.contains(week.label))
        // The builder's text doesn't repeat them.
        let detail = plan.rationaleDetail
        #expect(!detail.contains("Upper Body"))
        #expect(!detail.contains("Block week"))
        #expect(!detail.contains(WorkoutFocus.upper.muscles.lowercased()))
        #expect(detail.contains("60 min"))
        // Effort as rep goals, not a reps-in-reserve number.
        #expect(detail.contains("rep goals are a little easier"))
        #expect(detail.contains("50% recovery"))
    }

    @Test func rationaleDetailFallsBackToTheWholeText() {
        var plan = planner.plan(focus: .legs, minutes: 45, recovery: 80, history: [:])
        plan.rationaleLead = "Something else."
        #expect(plan.rationaleDetail == plan.rationale)
        plan.rationaleLead = nil
        #expect(plan.rationaleDetail == plan.rationale)
    }

    @Test func savedPlansWithoutALeadStillDecode() throws {
        let plan = planner.plan(focus: .pull, minutes: 30, recovery: 70, history: [:])
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        json.removeValue(forKey: "rationaleLead")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(PlannedWorkout.self, from: data)
        #expect(decoded.rationaleLead == nil)
        #expect(decoded.rationaleDetail == decoded.rationale)
    }

    @Test func rpeRowsHaveDistinctTitles() {
        let titles = RPEScale.levels.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test func goalTitleNamesEveryFocus() {
        let recomp = Goals(weight: .lose, focuses: [.muscle, .strength])
        #expect(recomp.title == "Lose fat, build muscle & get stronger")
        #expect(Goals(weight: .lose, focuses: [.muscle]).title == "Lose fat, build muscle")
        #expect(Goals(weight: .maintain, focuses: [.muscle, .strength]).title == "Maintain weight, build muscle & get stronger")
    }

    @Test func bodyFatSuggestionUsesTheNamedCutOffs() {
        #expect(GoalPlanner.suggest(bodyFatPercent: 23, bmi: nil, sex: .male).weight == .lose)
        #expect(GoalPlanner.suggest(bodyFatPercent: 22, bmi: nil, sex: .male).weight == .maintain)
        #expect(GoalPlanner.suggest(bodyFatPercent: 11, bmi: nil, sex: .male).weight == .gain)
        #expect(GoalPlanner.suggest(bodyFatPercent: 33, bmi: nil, sex: .female).weight == .lose)
        #expect(GoalPlanner.suggest(bodyFatPercent: 19, bmi: nil, sex: .female).weight == .gain)
        #expect(GoalPlanner.highBodyFatPercent.male == 22)
        #expect(GoalPlanner.lowBodyFatPercent.female == 20)
    }
}
