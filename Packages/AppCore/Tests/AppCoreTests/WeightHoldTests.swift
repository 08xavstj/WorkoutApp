import Foundation
import Testing
@testable import AppCore

struct WeightHoldTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    var now: Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9))! }

    /// Weigh-ins `back` days ago with the value `value(back)`, every `every` days.
    func weights(days: Int, every: Int = 1, _ value: (Int) -> Double) -> [DayValue] {
        stride(from: days - 1, through: 0, by: -every).map { back in
            DayValue(date: now.addingTimeInterval(-Double(back) * 86_400), value: value(back))
        }
    }

    var cut: Goals { Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle], targetWeightKg: 80) }

    // MARK: Target reached

    /// A twelve-week cut from about 85.6 to 79, weighed daily. The smoothed
    /// trend runs about 0.7 kg behind the scale, so it reaches 80 a little
    /// after the scale does.
    @Test func theOfferAppearsWhenTheTrendReachesTheTarget() {
        let cutting = weights(days: 84) { back in 79.0 + Double(back) * 0.08 }
        let offer = WeightHold.offer(weights: cutting, goals: cut, holding: nil, hideCalories: false, now: now, calendar: utc)
        #expect(offer != nil)
        #expect((offer?.trendKg ?? 99) <= 80)
        // Two weeks earlier the trend was still above it: nothing.
        let earlier = weights(days: 84) { back in 79.0 + Double(back + 14) * 0.08 }
        #expect(WeightHold.offer(weights: earlier, goals: cut, holding: nil, hideCalories: false, now: now, calendar: utc) == nil)
    }

    @Test func noOfferWithCaloriesHiddenWhileHoldingSnoozedOrPaused() {
        let reached = weights(days: 60) { _ in 79.5 }
        #expect(WeightHold.offer(weights: reached, goals: cut, holding: nil, hideCalories: false, now: now, calendar: utc) != nil)
        #expect(WeightHold.offer(weights: reached, goals: cut, holding: nil, hideCalories: true, now: now, calendar: utc) == nil)
        let holding = WeightHold.State(targetKg: 80, since: now)
        #expect(WeightHold.offer(weights: reached, goals: cut, holding: holding, hideCalories: false, now: now, calendar: utc) == nil)
        #expect(WeightHold.offer(weights: reached, goals: cut, holding: nil, hideCalories: false,
                                 snoozedUntil: now.addingTimeInterval(86_400), now: now, calendar: utc) == nil)
        // Weigh-ins stopped three weeks ago: weight tracking counts as paused.
        let stopped = reached.filter { $0.date < now.addingTimeInterval(-21 * 86_400) }
        #expect(WeightHold.offer(weights: stopped, goals: cut, holding: nil, hideCalories: false, now: now, calendar: utc) == nil)
        // No target, or maintaining already.
        var noTarget = cut
        noTarget.targetWeightKg = nil
        #expect(WeightHold.offer(weights: reached, goals: noTarget, holding: nil, hideCalories: false, now: now, calendar: utc) == nil)
    }

    @Test func holdingMeansMaintainAtMeasuredMaintenance() {
        let held = WeightHold.holdGoals(from: cut)
        #expect(held.weight == .maintain)
        #expect(held.targetWeightKg == nil)
        #expect(held.focuses == cut.focuses)
        // Maintain: the calorie target is maintenance itself.
        #expect(GoalPlanner.calorieTarget(maintenance: 2_600, bodyMassKg: 80, goals: held, sex: .male) == 2_600)
    }

    // MARK: The regain line

    @Test func theRegainLineNeedsTwoWeeksMoreThanTwoKilosAbove() {
        let holding = WeightHold.State(targetKg: 80, since: now.addingTimeInterval(-120 * 86_400))
        let maintain = WeightHold.holdGoals(from: cut)
        // Steady at 82.5 for two months, weighed weekly: line shows.
        let drifted = weights(days: 60, every: 7) { _ in 82.5 }
        let regain = WeightHold.regain(weights: drifted, holding: holding, goals: maintain, hideCalories: false, now: now, calendar: utc)
        #expect(regain?.trendKg == 82.5)
        #expect(regain.map { abs($0.aboveKg - 2.5) < 0.001 } == true)
        // 81.9: inside the band.
        let inside = weights(days: 60, every: 7) { _ in 81.9 }
        #expect(WeightHold.regain(weights: inside, holding: holding, goals: maintain, hideCalories: false, now: now, calendar: utc) == nil)
        // A single heavy weigh-in after weeks at 80 barely moves the trend: no line.
        var spike = weights(days: 60) { _ in 80 }
        spike[spike.count - 1].value = 84
        #expect(WeightHold.regain(weights: spike, holding: holding, goals: maintain, hideCalories: false, now: now, calendar: utc) == nil)
        // Above only for the last few days: not two weeks.
        let recent = weights(days: 60) { back in back < 5 ? 86 : 80 }
        #expect(WeightHold.regain(weights: recent, holding: holding, goals: maintain, hideCalories: false, now: now, calendar: utc) == nil)
    }

    @Test func theRegainLineIsOffWithCaloriesHiddenPausedOrDuringAGain() {
        let holding = WeightHold.State(targetKg: 80, since: now.addingTimeInterval(-120 * 86_400))
        let drifted = weights(days: 60, every: 3) { _ in 83 }
        let maintain = WeightHold.holdGoals(from: cut)
        #expect(WeightHold.regain(weights: drifted, holding: holding, goals: maintain, hideCalories: false, now: now, calendar: utc) != nil)
        #expect(WeightHold.regain(weights: drifted, holding: holding, goals: maintain, hideCalories: true, now: now, calendar: utc) == nil)
        #expect(WeightHold.regain(weights: drifted, holding: nil, goals: maintain, hideCalories: false, now: now, calendar: utc) == nil)
        let bulk = Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.muscle])
        #expect(WeightHold.regain(weights: drifted, holding: holding, goals: bulk, hideCalories: false, now: now, calendar: utc) == nil)
        let stopped = drifted.filter { $0.date < now.addingTimeInterval(-15 * 86_400) }
        #expect(WeightHold.regain(weights: stopped, holding: holding, goals: maintain, hideCalories: false, now: now, calendar: utc) == nil)
    }

    @Test func theTwoWaysToAct() {
        let holding = WeightHold.State(targetKg: 80, since: now)
        let regain = WeightHold.Regain(targetKg: 80, trendKg: 82.4)
        // A short cut back at 0.5% a week, or slower if the person's limit is lower.
        let short = WeightHold.shortCutGoals(from: WeightHold.holdGoals(from: cut), holding: holding)
        #expect(short.weight == .lose)
        #expect(short.weeklyRatePercent == 0.5)
        #expect(short.targetWeightKg == 80)
        #expect(WeightHold.shortCutGoals(from: cut, holding: holding, maximumPercent: 0.25).weeklyRatePercent == 0.25)
        #expect(WeightHold.shortCutWeeks(regain) == 6) // 2.4 kg at ~0.41 kg a week
        // Or accept the new weight, to the nearest half kilo.
        #expect(WeightHold.accepted(regain, now: now).targetKg == 82.5)
    }

    // MARK: Weigh-ins

    @Test func theWeighInRowStaysWeeklyWhileHolding() {
        let holding = WeightHold.State(targetKg: 80, since: now)
        let maintain = WeightHold.holdGoals(from: cut)
        let sixDays = now.addingTimeInterval(-6 * 86_400)
        let eightDays = now.addingTimeInterval(-8 * 86_400)
        #expect(!WeighInNudge.isDue(goals: maintain, lastWeighIn: sixDays, holding: holding, now: now, calendar: utc))
        #expect(WeighInNudge.isDue(goals: maintain, lastWeighIn: eightDays, holding: holding, now: now, calendar: utc))
        // Stopped for two weeks: the row goes away rather than standing there.
        #expect(!WeighInNudge.isDue(goals: maintain, lastWeighIn: now.addingTimeInterval(-15 * 86_400), holding: holding, now: now, calendar: utc))
        // A plain maintain goal still gets none; a cut keeps its three-day rule.
        #expect(!WeighInNudge.isDue(goals: maintain, lastWeighIn: eightDays, holding: nil, now: now, calendar: utc))
        #expect(WeighInNudge.isDue(goals: cut, lastWeighIn: now.addingTimeInterval(-3 * 86_400), holding: nil, now: now, calendar: utc))
    }

    // MARK: Checking a new target

    @Test func aTargetUnderBMI18Point5AsksFirst() {
        let limit = GoalPlanner.RateLimit(percent: 1, reason: .general, weight: .lose)
        let low = WeightHold.targetWarnings(goals: cut, targetKg: 56, currentKg: 70, heightCm: 180, limit: limit)
        #expect(low.count == 1)
        if case .underweight(let bmi) = low.first { #expect(abs(bmi - 17.28) < 0.01) } else { Issue.record("expected underweight") }
        #expect(WeightHold.targetWarnings(goals: cut, targetKg: 60, currentKg: 70, heightCm: 180, limit: limit).isEmpty) // BMI 18.5
        // Gaining towards a low weight isn't a cut: no BMI question.
        let gain = Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.muscle])
        #expect(WeightHold.targetWarnings(goals: gain, targetKg: 56, currentKg: 52, heightCm: 180,
                                          limit: GoalPlanner.RateLimit(percent: 0.5, reason: .general, weight: .gain)).isEmpty)
        #expect(WeightHold.message(low[0]).contains("17.3"))
    }

    @Test func aRateFasterThanThePersonalLimitAsksFirst() {
        let lean = GoalPlanner.RateLimit(percent: 0.5, reason: .lean, weight: .lose)
        var fast = cut
        fast.weeklyRatePercent = 0.75
        let warnings = WeightHold.targetWarnings(goals: fast, targetKg: 78, currentKg: 82, heightCm: 180, limit: lean)
        #expect(warnings == [.fasterThanLimit(percentPerWeek: 0.75, limitPercent: 0.5)])
        #expect(WeightHold.targetWarnings(goals: cut, targetKg: 78, currentKg: 82, heightCm: 180, limit: lean).isEmpty)
        // A date four weeks out for 4 kg off 82 kg asks about 1.2% a week.
        let dated = WeightHold.targetWarnings(goals: cut, targetKg: 78, currentKg: 82, heightCm: 180, limit: lean,
                                              targetDate: now.addingTimeInterval(28 * 86_400), now: now)
        if case .fasterThanLimit(let rate, _) = dated.first { #expect(abs(rate - 1.22) < 0.01) } else { Issue.record("expected a rate warning") }
        #expect(WeightHold.targetWarnings(goals: Goals(), targetKg: 50, currentKg: 82, heightCm: 180, limit: lean).isEmpty)
    }
}
