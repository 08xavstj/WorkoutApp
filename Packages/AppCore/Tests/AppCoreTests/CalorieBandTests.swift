import Foundation
import Testing
@testable import AppCore

struct CalorieBandTests {
    let lose = Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle])
    let gain = Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.muscle])
    let maintain = Goals(weight: .maintain, focuses: [.health])

    @Test func bandIsTenPercentEachWay() {
        let band = GoalPlanner.calorieBand(target: 2000)
        #expect(band.lowerBound == 1800)
        #expect(band.upperBound == 2200)
        #expect(band.contains(2199) && !band.contains(2201))
    }

    @Test func needsFourteenLoggedDays() {
        #expect(GoalPlanner.weeklyAdjustment(measuredMaintenance: 2600, currentTarget: 2000, goals: lose,
                                             bodyMassKg: 80, weeklyChangeKg: -0.1, loggedDays: 13) == nil)
    }

    @Test func slowerLossLowersTargetByAtMostAStep() throws {
        // Planned 0.5%/wk of 80 kg = 0.4 kg; measured 0.1 kg and a maintenance
        // that calls for a target 300 kcal lower → only −100 this week.
        let adjustment = try #require(CalorieBand.weeklyAdjustment(
            measuredMaintenance: 2400, currentTarget: 2260, goals: lose, bodyMassKg: 80,
            weeklyChangeKg: -0.1, loggedDays: 14, sex: .male))
        #expect(adjustment.deltaKcal == -100)
        #expect(adjustment.newTarget == 2160)
        #expect(adjustment.reason == .slowerThanPlanned)
        #expect(adjustment.note == "Target adjusted −100 kcal this week: weight moved slower than planned.")
    }

    @Test func smallDifferencesAreLeftAlone() {
        // Desired target 1960 vs 2000 in force: 40 kcal is inside the noise.
        #expect(GoalPlanner.weeklyAdjustment(measuredMaintenance: 2400, currentTarget: 2000, goals: lose,
                                             bodyMassKg: 80, weeklyChangeKg: -0.4, loggedDays: 20) == nil)
    }

    @Test func losingTooFastRaisesTheTargetWhateverMaintenanceSays() throws {
        // 1.2%/wk of 80 kg; maintenance would even call for a lower target.
        let adjustment = try #require(CalorieBand.weeklyAdjustment(
            measuredMaintenance: 2300, currentTarget: 2000, goals: lose, bodyMassKg: 80,
            weeklyChangeKg: -0.96, loggedDays: 14, sex: .male))
        #expect(adjustment.deltaKcal == 100)
        #expect(adjustment.reason == .losingTooFast)
    }

    @Test func gainingTooFastTrimsTheTarget() throws {
        // 0.8%/wk on a 0.25%/wk gain plan.
        let adjustment = try #require(CalorieBand.weeklyAdjustment(
            measuredMaintenance: 2800, currentTarget: 3000, goals: gain, bodyMassKg: 75,
            weeklyChangeKg: 0.6, loggedDays: 14, sex: .male))
        #expect(adjustment.deltaKcal == -100)
        #expect(adjustment.reason == .gainingTooFast)
    }

    @Test func maintenanceDriftFollowsMeasuredMaintenance() throws {
        let adjustment = try #require(CalorieBand.weeklyAdjustment(
            measuredMaintenance: 2500, currentTarget: 2420, goals: maintain, bodyMassKg: 70,
            weeklyChangeKg: -0.15, loggedDays: 14, sex: .female))
        #expect(adjustment.deltaKcal == 80)
        #expect(adjustment.reason == .driftingDown)
    }

    @Test func neverBelowTheFloor() throws {
        // Gaining too fast would trim 100 kcal, but 1,200 kcal is the floor for women.
        let adjustment = try #require(CalorieBand.weeklyAdjustment(
            measuredMaintenance: 1500, currentTarget: 1250, goals: maintain, bodyMassKg: 60,
            weeklyChangeKg: 0.5, loggedDays: 14, sex: .female))
        #expect(adjustment.deltaKcal == -50)
        #expect(adjustment.newTarget == 1200)
        // Already on the floor: nothing to trim, so no adjustment.
        #expect(CalorieBand.weeklyAdjustment(measuredMaintenance: 1500, currentTarget: 1200, goals: maintain,
                                             bodyMassKg: 60, weeklyChangeKg: 0.5, loggedDays: 14, sex: .female) == nil)
    }
}

struct WeighInNudgeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let lose = Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle])

    @Test func dueAfterThreeDaysOnAWeightGoal() {
        #expect(WeighInNudge.isDue(goals: lose, lastWeighIn: now.addingTimeInterval(-3 * 86_400), now: now))
        #expect(!WeighInNudge.isDue(goals: lose, lastWeighIn: now.addingTimeInterval(-2 * 86_400), now: now))
        #expect(WeighInNudge.isDue(goals: lose, lastWeighIn: nil, now: now))
    }

    @Test func maintainAndNoGoalGetNoNudge() {
        #expect(!WeighInNudge.isDue(goals: Goals(weight: .maintain), lastWeighIn: nil, now: now))
        #expect(!WeighInNudge.isDue(goals: nil, lastWeighIn: nil, now: now))
    }

    @Test func detailNamesTheGap() {
        #expect(WeighInNudge.detail(lastWeighIn: now.addingTimeInterval(-4 * 86_400), now: now).hasPrefix("Last weigh-in 4 days ago."))
        #expect(WeighInNudge.detail(lastWeighIn: nil, now: now).hasPrefix("No weigh-in"))
    }
}
