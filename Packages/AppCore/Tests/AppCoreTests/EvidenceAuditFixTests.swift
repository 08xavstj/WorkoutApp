import Foundation
import Testing
@testable import AppCore

// The evidence audit's should-change items applied 17 Nov 2026
// (docs/research/evidence-audit-2026-11.md). M1-M6 and items 1-3, 5, 7 are
// tested beside their types (HeartHealthTests, CardioPlannerTests,
// FitnessAdaptationTests, SupplementKnowledgeTests, NumbersAuditTests).

// MARK: - Should change 4: the block's last week is reactive

struct ReactiveLastWeekTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))! }
    func day(_ offset: Int) -> Date { monday.addingTimeInterval(Double(offset) * 86_400) }

    @Test func aWholeBlockCarriesOnInItsLastWeekWithoutALowHRV() {
        // Strength: 5 weeks. Weeks 1-4 ramp; week 5 used to be a planned deload.
        var block = TrainingBlock(start: monday, style: .strength)
        for week in 1...4 { block = block.advanced(to: day(7 * week), calendar: calendar) }
        #expect(block.week.week == 5)
        #expect(!block.week.isDeload)
        #expect(block.week.offersEasier)
        // Carries on at week 4's sets and effort.
        let week4 = TrainingBlock.weekState(4, style: .strength, length: 5)
        #expect(block.week.setMultiplier == week4.setMultiplier)
        #expect(block.week.targetRIR == week4.targetRIR)
        #expect(block.week.note == TrainingBlock.WeekState.lastWeekNote)
        #expect(block.week.label == "Block week 5 of 5")
        #expect(block.coachLine.contains("last week of the block"))
        // The next Monday starts a new block.
        let next = block.advanced(to: day(35), calendar: calendar)
        #expect(next.week.week == 1)
        #expect(next.start == day(35))
    }

    @Test func aLowHRVAsTheLastWeekStartsMakesItTheEasierWeek() {
        var block = TrainingBlock(start: monday, style: .muscle)   // 6 weeks
        for week in 1...4 { block = block.advanced(to: day(7 * week), calendar: calendar) }
        block = block.advanced(to: day(35), hrvBelowNormal: true, calendar: calendar)
        #expect(block.week.week == 6)
        #expect(block.week.isDeload)
        #expect(block.week.offersEasier)
        #expect(block.week.setMultiplier == TrainingBlock.deloadMultiplier)
        #expect(block.week.label == "Easier week (6 of 6)")
        // You can still carry on instead.
        let carried = block.settingEasier(false)
        #expect(!carried.week.isDeload)
        #expect(carried.week.offersEasier)
        #expect(carried.week.setMultiplier == TrainingBlock.weekState(5, style: .muscle, length: 6).setMultiplier)
    }

    @Test func choosingTheEasierWeekAndBack() {
        var block = TrainingBlock(start: monday, style: .balanced)
        for week in 1...4 { block = block.advanced(to: day(7 * week), calendar: calendar) }
        let easier = block.settingEasier(true)
        #expect(easier.week.isDeload)
        #expect(easier.week.targetRIR == TrainingBlock.weekState(5, style: .balanced, length: 5).targetRIR)
        #expect(easier.week.note.hasPrefix("Easier week"))
        // Staying in the same week keeps the choice.
        #expect(easier.advanced(to: day(30), calendar: calendar) == easier)
        #expect(easier.settingEasier(false) == block)
        #expect(easier.settingEasier(true) == easier)
    }

    @Test func otherWeeksAndStylesIgnoreTheChoice() {
        let block = TrainingBlock(start: monday, style: .strength)
        #expect(block.settingEasier(true) == block)           // week 1
        #expect(!block.week.offersEasier)
        var endurance = TrainingBlock(start: monday, style: .endurance)
        for week in 1...3 { endurance = endurance.advanced(to: day(7 * week), calendar: calendar) }
        #expect(endurance.week.week == 4)
        #expect(!endurance.week.isDeload && !endurance.week.offersEasier)
        #expect(endurance.settingEasier(true) == endurance)
    }

    @Test func aBlockSavedBeforeTheChangeKeepsItsPlannedDeload() throws {
        // A saved last week without `easierOffered` decodes as the old planned deload.
        let json = #"{"week":5,"length":5,"setMultiplier":0.6,"targetRIR":3,"isDeload":true,"isHeld":false}"#
        let state = try JSONDecoder().decode(TrainingBlock.WeekState.self, from: Data(json.utf8))
        #expect(state.easierOffered == nil)
        #expect(!state.offersEasier)
        #expect(state.isDeload)
        #expect(state.label == "Deload week (5 of 5)")
        #expect(state.note == "Planned easier week: about half the sets, a little lighter.")
    }

    @Test func aBusyWeekBackOutInTheLastWeekCarriesOn() {
        var block = TrainingBlock(start: monday, style: .strength)
        for week in 1...4 { block = block.advanced(to: day(7 * week), calendar: calendar) }
        let busy = block.settingBusy(true)
        #expect(busy.week.isBusy && !busy.week.offersEasier)
        #expect(busy.settingEasier(true) == busy)
        let back = busy.settingBusy(false)
        #expect(!back.week.isDeload && back.week.offersEasier)
    }
}

// MARK: - Should change 9: bed-by window with low sleep efficiency

struct BedtimeEfficiencyTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    var evening: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 20))! }

    @Test func averageEfficiencyNeedsAWeek() throws {
        #expect(BedtimeWindow.averageEfficiency(Array(repeating: (asleepHours: 7, spanHours: 8), count: 6)) == nil)
        let week = try #require(BedtimeWindow.averageEfficiency(Array(repeating: (asleepHours: 7, spanHours: 8), count: 7)))
        #expect(abs(week - 0.875) < 1e-9)
        // Unusable nights (no span, nothing asleep) don't count toward the seven.
        let unusable: [(asleepHours: Double, spanHours: Double)] = [(asleepHours: 0, spanHours: 8), (asleepHours: 3, spanHours: 0.5)]
        let mixed: [(asleepHours: Double, spanHours: Double)] = Array(repeating: (asleepHours: 7.0, spanHours: 8.0), count: 6) + unusable
        #expect(BedtimeWindow.averageEfficiency(mixed) == nil)
        // Never above 100%.
        #expect(BedtimeWindow.averageEfficiency(Array(repeating: (asleepHours: 8, spanHours: 7.5), count: 7)) == 1)
    }

    @Test func lowEfficiencyCapsTheRepaymentAtThirtyMinutes() throws {
        // Two weeks of 6 h against an 8 h need: the plan repays the full hour a night.
        let debt = SleepDebt.compute(nightlyHours: Array(repeating: 6, count: 14), needHours: 8)
        let normal = try #require(BedtimeWindow.compute(sleepNeedHours: 8, sleepDebt: debt, usualWakeMinutes: 7 * 60, regularity: nil,
                                                        sleepEfficiency: 0.9, now: evening, calendar: calendar))
        #expect(normal.repaymentMinutes == BedtimeWindow.maxRepaymentMinutes)
        // Under 85% asleep: more time in bed than he can sleep, so at most 30 minutes extra.
        let broken = try #require(BedtimeWindow.compute(sleepNeedHours: 8, sleepDebt: debt, usualWakeMinutes: 7 * 60, regularity: nil,
                                                        sleepEfficiency: 0.8, now: evening, calendar: calendar))
        #expect(broken.repaymentMinutes == BedtimeWindow.lowEfficiencyMaxRepaymentMinutes)
        #expect(broken.start.timeIntervalSince(normal.start) == 30 * 60)
        // Exactly 85% is not low; unknown efficiency changes nothing.
        let edge = try #require(BedtimeWindow.compute(sleepNeedHours: 8, sleepDebt: debt, usualWakeMinutes: 7 * 60, regularity: nil,
                                                      sleepEfficiency: 0.85, now: evening, calendar: calendar))
        #expect(edge.repaymentMinutes == BedtimeWindow.maxRepaymentMinutes)
        let unknown = try #require(BedtimeWindow.compute(sleepNeedHours: 8, sleepDebt: debt, usualWakeMinutes: 7 * 60, regularity: nil,
                                                         now: evening, calendar: calendar))
        #expect(unknown == normal)
    }
}

// MARK: - Should change 13: HRV alone never turns a planned lift into rest

struct HRVAloneNeverRestsALiftTests {
    let today = Date(timeIntervalSince1970: 1_800_000_000)

    /// Yesterday was a planned rest day that ended up hard (a lift outside the plan).
    var hardRestDay: [TrainingDayPlanner.PastDay] {
        [TrainingDayPlanner.PastDay(date: today.addingTimeInterval(-86_400), plannedFocus: nil, strain: 90, trained: true)]
    }

    @Test func aPlannedLiftAfterAHardRestDay() {
        // Low recovery score: a recovery day, as before.
        let low = TrainingDayPlanner.guidance(plannedToday: .upper, past: hardRestDay, lowRecovery: true, usualTrainingStrain: nil)
        #expect(low.kind == .recovery)
        // HRV below normal alone: the lift stays, easy.
        let hrv = TrainingDayPlanner.guidance(plannedToday: .upper, past: hardRestDay, lowRecovery: true, lowFromHRVOnly: true,
                                              usualTrainingStrain: nil)
        #expect(hrv.kind == .easyTraining)
        #expect(hrv.focus == .upper)
    }

    @Test func aPlannedLiftWithHRVBelowNormalIsEasyNotRest() {
        let hrv = TrainingDayPlanner.guidance(plannedToday: .lower, past: [], lowRecovery: true, lowFromHRVOnly: true,
                                              usualTrainingStrain: nil)
        #expect(hrv.kind == .easyTraining)
        #expect(hrv.focus == .lower)
    }

    @Test func restWorthyNeedsMoreThanHRV() {
        #expect(TrainingDayPlanner.restWorthy(lowRecovery: true, fromHRVOnly: false))
        #expect(!TrainingDayPlanner.restWorthy(lowRecovery: true, fromHRVOnly: true))
        #expect(!TrainingDayPlanner.restWorthy(lowRecovery: false, fromHRVOnly: false))
    }
}

// MARK: - Should change 10, 11: protein per meal, blood-pressure repeat

struct ProteinAndBloodPressureAuditTests {
    @Test func noPerMealCeiling() throws {
        // A 70 kg lifter eating 3 meals with a 180 g day: 60 g a meal (0.86 g/kg), no longer held at 4 meals.
        let lifter = Goals(weight: .maintain, focuses: [.muscle])
        let three = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 70, goals: lifter, loggedMeals: 3, dailyProteinGrams: 180))
        #expect(three.meals == 3 && three.grams == 60)
        // Without a daily figure: 1.6 g/kg over the meals.
        let byWeight = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 90, goals: lifter, loggedMeals: 3))
        #expect(byWeight.meals == 3 && byWeight.grams == 48)
    }

    @Test func aNormalHomeAverageRepeatsYearly() {
        #expect(HomeBloodPressure.repeatMonths(after: .normal) == 12)
        #expect(HomeBloodPressure.repeatMonths(after: .elevated) == 3)
    }
}

// MARK: - Insights feed

struct InsightsCapTests {
    @Test func atMostTwoLines() {
        #expect(DailyInsights.maxShown == 2)
        #expect(DailyInsights.maxWatch <= DailyInsights.maxShown)
    }
}
