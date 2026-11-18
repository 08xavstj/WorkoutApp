import Foundation
import Testing
@testable import AppCore

/// Saturated fat, the fitness check and the Longevity rows for the
/// evidence audit's gaps 2, 3 and 5.
struct HealthGapsTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func day(_ n: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: n, hour: 12))!
    }

    func week(kcal: Double, grams: Double?, days: Int = 7) -> [SaturatedFat.Day] {
        (1...days).map { SaturatedFat.Day(date: day($0), energyKcal: kcal, saturatedGrams: grams) }
    }

    // MARK: Saturated fat

    @Test func shareIsSaturatedEnergyOverAllEnergy() {
        // 25 g × 9 = 225 kcal of 2,500 = 9%.
        let result = SaturatedFat.week(week(kcal: 2500, grams: 25))
        #expect(result?.share == 9)
        #expect(result?.status == .under)
        #expect(result?.shareText == "9% of energy")
    }

    @Test func boundariesAtTenAndTwelvePercent() {
        // 2,700 kcal: 30 g = 10.0% exactly is not under the line.
        #expect(SaturatedFat.week(week(kcal: 2700, grams: 30))?.status == .close)
        #expect(SaturatedFat.week(week(kcal: 2700, grams: 29.9))?.status == .under)
        // 36 g = 12% is over.
        #expect(SaturatedFat.week(week(kcal: 2700, grams: 36))?.status == .over)
        #expect(SaturatedFat.week(week(kcal: 2700, grams: 35.9))?.status == .close)
    }

    @Test func aShareJustUnderTheLineNeverReadsAsTen() {
        // 29.9 g of 2,700 kcal = 9.97%: under, shown as 9.9, not 10.
        let under = SaturatedFat.week(week(kcal: 2700, grams: 29.9))
        #expect(under?.status == .under)
        #expect(under?.percentText == "9.9")
        #expect(SaturatedFat.week(week(kcal: 2700, grams: 30))?.percentText == "10.0")
        #expect(SaturatedFat.week(week(kcal: 2700, grams: 33))?.percentText == "11")
    }

    @Test func noSaturatedFatFromTheFoodAppShowsNothingNotZero() {
        #expect(SaturatedFat.week(week(kcal: 2500, grams: nil)) == nil)
    }

    @Test func needsFourLoggedDaysAndEightyPercentCoverage() {
        #expect(SaturatedFat.week(week(kcal: 2500, grams: 25, days: 3)) == nil)
        #expect(SaturatedFat.week(week(kcal: 2500, grams: 25, days: 4)) != nil)
        // 7 logged days, saturated fat on 5: under 80%, left out.
        var days = week(kcal: 2500, grams: 25)
        days[5].saturatedGrams = nil
        days[6].saturatedGrams = nil
        #expect(SaturatedFat.week(days) == nil)
        // On 6 of 7 (86%): used, over those 6 days only.
        days[5].saturatedGrams = 25
        #expect(SaturatedFat.week(days)?.days == 6)
    }

    @Test func barelyLoggedDaysDontCount() {
        var days = week(kcal: 2500, grams: 25, days: 4)
        // A 500 kcal day (one meal logged) with lots of butter would skew the week.
        days.append(SaturatedFat.Day(date: day(6), energyKcal: 500, saturatedGrams: 40))
        #expect(SaturatedFat.week(days)?.share == 9)
    }

    @Test func aRealisticWeekWithAWeekendBlowout() {
        // Weekdays 22 g on 2,400 kcal; Saturday pizza and Sunday roast.
        var days = (1...5).map { SaturatedFat.Day(date: day($0), energyKcal: 2400, saturatedGrams: 22) }
        days.append(SaturatedFat.Day(date: day(6), energyKcal: 3400, saturatedGrams: 60))
        days.append(SaturatedFat.Day(date: day(7), energyKcal: 3000, saturatedGrams: 45))
        let result = SaturatedFat.week(days)
        // (110 + 105) × 9 / 18,400 = 10.5%: a little over across the week, not a failed day.
        #expect(result?.status == .close)
        #expect(result.map { abs($0.share - 10.516) < 0.01 } == true)
        #expect(result?.line.contains("olive oil") == true)
    }

    // MARK: Fitness check

    @Test func mileWalkMatchesKlineEquation() {
        // 80 kg (176.4 lb) man, 35, 15:00 min, HR 140.
        let pounds: Double = 80 * 2.20462
        let partial: Double = 6.9652 + 0.0091 * pounds - 0.0257 * 35
        let litres: Double = partial + 0.5955 - 0.2240 * 15 - 0.0115 * 140
        let value = FitnessCheck.mileWalk(minutes: 15, heartRate: 140, age: 35, sex: .male, weightKg: 80)
        #expect(value.map { abs($0 - litres * 1000 / 80) < 0.001 } == true)
        // About 42 mL/kg/min: a plausible value for a fit 35-year-old.
        #expect(value.map { (38...46).contains($0) } == true)
        // Faster walk, lower heart rate → higher estimate.
        #expect((FitnessCheck.mileWalk(minutes: 13, heartRate: 130, age: 35, sex: .male, weightKg: 80) ?? 0) > (value ?? 0))
    }

    @Test func treadmillWalkMatchesEbbelingEquation() {
        let speed: Double = 3.5, heartRate: Double = 130, age: Double = 30
        let base: Double = 15.1 + 21.8 * speed - 0.327 * heartRate
        let expected: Double = base - 0.263 * speed * age + 0.00504 * heartRate * age + 5.98
        let value = FitnessCheck.treadmillWalk(speedMph: 3.5, heartRate: 130, age: 30, sex: .male)
        #expect(value.map { abs($0 - expected) < 0.0001 } == true)
        // Outside the tested speeds: no estimate.
        #expect(FitnessCheck.treadmillWalk(speedMph: 5, heartRate: 130, age: 30, sex: .male) == nil)
        #expect(FitnessCheck.treadmillWalk(speedMph: 1.9, heartRate: 130, age: 30, sex: .male) == nil)
    }

    @Test func impossibleInputsGiveNoEstimate() {
        #expect(FitnessCheck.mileWalk(minutes: 3, heartRate: 140, age: 35, sex: .male, weightKg: 80) == nil)
        #expect(FitnessCheck.mileWalk(minutes: 15, heartRate: 20, age: 35, sex: .male, weightKg: 80) == nil)
    }

    @Test func suggestedTestsFollowTheStudiesAgesAndTheGym() {
        #expect(FitnessCheck.suggested(age: 25, hasTreadmill: true) == [.treadmillWalk])
        #expect(FitnessCheck.suggested(age: 30, hasTreadmill: true) == [.mileWalk, .treadmillWalk])
        #expect(FitnessCheck.suggested(age: 30, hasTreadmill: false) == [.mileWalk])
        #expect(FitnessCheck.suggested(age: 65, hasTreadmill: true) == [.mileWalk])
        // 25 with no treadmill: the walk, though outside its study's ages.
        #expect(FitnessCheck.suggested(age: 25, hasTreadmill: false) == [.mileWalk])
    }

    @Test func dueEveryThreeMonths() {
        let checked = FitnessCheck.Result(test: .mileWalk, date: day(1), vo2Max: 42)
        #expect(FitnessCheck.isDue([], now: day(1), calendar: calendar))
        let next = calendar.date(byAdding: .day, value: 91, to: calendar.startOfDay(for: day(1)))!
        #expect(!FitnessCheck.isDue([checked], now: next.addingTimeInterval(-1), calendar: calendar))
        #expect(FitnessCheck.isDue([checked], now: next, calendar: calendar))
    }

    @Test func changeComparesTheSameTestOnly() {
        let results = [
            FitnessCheck.Result(test: .mileWalk, date: day(1), vo2Max: 40),
            FitnessCheck.Result(test: .treadmillWalk, date: day(2), vo2Max: 47),
            FitnessCheck.Result(test: .mileWalk, date: day(3), vo2Max: 42.5),
        ]
        #expect(FitnessCheck.change(results) == 2.5)
        #expect(FitnessCheck.change(Array(results.prefix(2))) == nil)
    }

    // MARK: Longevity rows

    @Test func bloodTestRowOnlyWhenSomethingIsDue() {
        var inputs = Longevity.Inputs(age: 30, sex: .male)
        #expect(Longevity.assess(inputs).measure(.bloodTests) == nil)
        inputs.bloodTests = BloodTestSchedule.schedule(results: [], age: 30, now: day(17), calendar: calendar)
        let row = Longevity.assess(inputs).measure(.bloodTests)
        #expect(row?.status == .noData)
        #expect(row?.area == .bodyMetabolic)
        #expect(row?.standing == "Cholesterol panel and Lp(a) are due.")
        #expect(row?.nextStep.contains("doctor may advise") == true)
        // All up to date: no row.
        let tested = [BloodTestSchedule.Result(markerID: "ldl", value: 90, unit: "mg/dL", date: day(1), status: .inRange),
                      BloodTestSchedule.Result(markerID: "lpa", value: 10, unit: "mg/dL", date: day(1), status: .inRange)]
        inputs.bloodTests = BloodTestSchedule.schedule(results: tested, age: 30, now: day(17), calendar: calendar)
        #expect(Longevity.assess(inputs).measure(.bloodTests) == nil)
    }

    @Test func saturatedFatRowFollowsTheWeekAndIsAbsentWithoutData() {
        var inputs = Longevity.Inputs(age: 30, sex: .male)
        #expect(Longevity.assess(inputs).measure(.saturatedFat) == nil)
        inputs.saturatedFat = SaturatedFat.week(week(kcal: 2500, grams: 25))
        #expect(Longevity.assess(inputs).measure(.saturatedFat)?.status == .onTarget)
        inputs.saturatedFat = SaturatedFat.week(week(kcal: 2500, grams: 40))
        let over = Longevity.assess(inputs).measure(.saturatedFat)
        #expect(over?.status == .off)
        #expect(over?.valueText == "14% of energy")
        #expect(over?.area == .nutrition)
    }
}
