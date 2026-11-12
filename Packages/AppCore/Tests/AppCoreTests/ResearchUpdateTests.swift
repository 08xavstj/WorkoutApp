import Foundation
import Testing
@testable import AppCore

struct WeightAndEnergyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }

    @Test func trendSmoothsNoise() {
        let weights = (0..<14).map { DayValue(date: day(-13 + $0), value: 80 + ($0.isMultiple(of: 2) ? 1.0 : -1.0)) }
        let trend = WeightTrend.smooth(weights)
        #expect(trend.count == 14)
        #expect(trend.allSatisfy { abs($0.value - 80) < 1.01 })
        #expect(abs((trend.last?.value ?? 0) - 80) < 0.6)
    }

    @Test func losingWeightShowsNegativeWeeklyChange() throws {
        let weights = (0..<21).map { DayValue(date: day(-20 + $0), value: 85 - 0.1 * Double($0)) }
        let change = try #require(WeightTrend.weeklyChange(weights))
        #expect(change < -0.4)
        #expect(change > -0.8)
    }

    @Test func maintenanceFromIntakeAndWeight() throws {
        // Eating 2,200 a day while losing ~0.5 kg a week → maintenance ≈ 2,750.
        let intake = (0..<28).map { DayValue(date: day(-27 + $0), value: 2200) }
        let weights = (0..<28).map { DayValue(date: day(-27 + $0), value: 85 - 0.5 / 7 * Double($0)) }
        let result = try #require(AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now))
        #expect(result.maintenance > 2550)
        #expect(result.maintenance < 2850)
        #expect(result.loggedDays == 28)
    }

    @Test func needsTwoWeeksOfLogging() {
        let intake = (0..<10).map { DayValue(date: day(-9 + $0), value: 2200) }
        let weights = (0..<28).map { DayValue(date: day(-27 + $0), value: 85) }
        #expect(AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now) == nil)
    }
}

struct GoalTests {
    @Test func losingSetsADeficit() {
        let goals = Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle])
        let target = GoalPlanner.calorieTarget(maintenance: 2800, bodyMassKg: 80, goals: goals, sex: .male)
        // 0.4 kg/week × 7,700 / 7 = 440 kcal a day.
        #expect(abs(target - 2360) < 0.001)
        #expect(goals.isRecomp)
        #expect(GoalPlanner.proteinPerKg(goals) == 2.2)
    }

    @Test func targetNeverGoesBelowFloor() {
        let goals = Goals(weight: .lose, weeklyRatePercent: 1.0)
        #expect(GoalPlanner.calorieTarget(maintenance: 1600, bodyMassKg: 60, goals: goals, sex: .female) == 1200)
    }

    @Test func suggestionFollowsBodyFat() {
        #expect(GoalPlanner.suggest(bodyFatPercent: 28, bmi: nil, sex: .male).weight == .lose)
        #expect(GoalPlanner.suggest(bodyFatPercent: 10, bmi: nil, sex: .male).weight == .gain)
        #expect(GoalPlanner.suggest(bodyFatPercent: nil, bmi: 23, sex: .male).weight == .maintain)
    }

    @Test func strengthStyleUsesLowReps() {
        let planner = WorkoutPlanner(gym: .commercialPounds, style: .strength)
        let plan = planner.plan(focus: .push, minutes: 45, recovery: 80, history: [:])
        #expect(plan.exercises.first?.reps == 3...6)
        #expect(plan.exercises.first?.rpe == 8)
    }
}

struct WellbeingTests {
    @Test func trainingAndHeatRaiseWaterTarget() {
        let rest = Hydration.target(sex: .male, exerciseMinutes: 0, feelsLikeC: 20)
        let hot = Hydration.target(sex: .male, exerciseMinutes: 60, feelsLikeC: 33)
        #expect(rest.liters == 3.7)
        #expect(abs(hot.liters - 5.45) < 0.001)
    }

    @Test func behindOnWaterInTheAfternoon() {
        let target = Hydration.target(sex: .female, exerciseMinutes: 0, feelsLikeC: nil)
        #expect(Hydration.assess(drank: 0.5, target: target, hour: 15).status == .low)
        #expect(Hydration.assess(drank: 2.0, target: target, hour: 15).status == .onTrack)
        #expect(Hydration.assess(drank: 7, target: target, hour: 15).status == .high)
    }

    /// Two raised vitals are "major" once one of them has been up two days
    /// running (Mishra 2020; Quer 2021); the first day is held at "minor".
    @Test func twoRaisedVitalsMeanLikelyIllnessOnTheSecondDay() throws {
        let firstDay = try #require(IllnessWatch.evaluate(.init(
            restingHeartRate: 62, rhrBaseline: (54, 1.5),
            respiratoryRate: 16.5, respiratoryBaseline: (14.5, 0.4)
        )))
        #expect(firstDay.level == .minor)
        #expect(firstDay.awaitingSecondDay)
        #expect(firstDay.signals.count == 2)
        #expect(firstDay.message.contains("tomorrow"))

        let secondDay = try #require(IllnessWatch.evaluate(.init(
            restingHeartRate: 62, rhrBaseline: (54, 1.5),
            respiratoryRate: 16.5, respiratoryBaseline: (14.5, 0.4),
            previousDay: .init(restingHeartRate: 60)
        )))
        #expect(secondDay.level == .major)
        #expect(!secondDay.awaitingSecondDay)
        #expect(secondDay.signals.count == 2)

        // Yesterday was normal: still the first day.
        let normalYesterday = try #require(IllnessWatch.evaluate(.init(
            restingHeartRate: 62, rhrBaseline: (54, 1.5),
            respiratoryRate: 16.5, respiratoryBaseline: (14.5, 0.4),
            previousDay: .init(restingHeartRate: 55, respiratoryRate: 14.6)
        )))
        #expect(normalYesterday.level == .minor)
        #expect(normalYesterday.awaitingSecondDay)
    }

    /// Within 16 days of a logged period the temperature bar is +0.8 °C and
    /// resting heart rate gets 3 bpm of room (luteal rise ≈ 0.3-0.5 °C, 2-4 bpm).
    @Test func cycleRaisesTheIllnessBar() throws {
        func inputs(daysSinceLastPeriod: Int?) -> IllnessWatch.Inputs {
            .init(restingHeartRate: 59, rhrBaseline: (54, 1.5), temperatureDelta: 0.6,
                  previousDay: .init(restingHeartRate: 59, temperatureDelta: 0.6),
                  daysSinceLastPeriod: daysSinceLastPeriod)
        }
        let untracked = try #require(IllnessWatch.evaluate(inputs(daysSinceLastPeriod: nil)))
        #expect(untracked.level == .major)
        // Luteal phase (about 10-32 days after a period): the small rise is expected.
        #expect(IllnessWatch.evaluate(inputs(daysSinceLastPeriod: 20)) == nil)
        // Just after a period the bar is the normal one.
        let follicular = try #require(IllnessWatch.evaluate(inputs(daysSinceLastPeriod: 3)))
        #expect(follicular.level == .major)

        // A real fever still shows: +0.9 °C and +8 bpm clear the higher bar.
        let fever = try #require(IllnessWatch.evaluate(.init(
            restingHeartRate: 62, rhrBaseline: (54, 1.5), temperatureDelta: 0.9,
            previousDay: .init(temperatureDelta: 0.9), daysSinceLastPeriod: 20
        )))
        #expect(fever.level == .major)
        #expect(fever.message.contains("cycle"))
    }

    @Test func alcoholDowngradesTheAlert() throws {
        let alert = try #require(IllnessWatch.evaluate(.init(
            restingHeartRate: 62, rhrBaseline: (54, 1.5),
            respiratoryRate: 16.5, respiratoryBaseline: (14.5, 0.4), drinksLastNight: 4
        )))
        #expect(alert.level == .minor)
        #expect(alert.message.contains("Alcohol"))
    }

    @Test func symptomsAloneGiveAWatchAlert() throws {
        let alert = try #require(IllnessWatch.evaluate(.init(restingHeartRate: 55, rhrBaseline: (54, 1.5), reportedSymptoms: true)))
        #expect(alert.level == .minor)
        #expect(alert.signals == ["You feel unwell"])
    }

    @Test func oneSignalPlusSymptomsIsMajor() throws {
        let alert = try #require(IllnessWatch.evaluate(.init(restingHeartRate: 62, rhrBaseline: (54, 1.5), reportedSymptoms: true)))
        #expect(alert.level == .major)
        let alone = try #require(IllnessWatch.evaluate(.init(restingHeartRate: 62, rhrBaseline: (54, 1.5))))
        #expect(alone.level == .minor)
    }

    @Test func normalVitalsNoAlert() {
        #expect(IllnessWatch.evaluate(.init(restingHeartRate: 55, rhrBaseline: (54, 1.5))) == nil)
    }

    /// Temperature is judged against your own night-to-night spread (+1.5 SD,
    /// TemPredict: Mason 2022; per-person residuals: Mishra 2020) once the SD
    /// is known; the fixed +0.5 °C (Smarr 2020) stays the fallback.
    @Test func temperatureUsesYourOwnSpread() throws {
        #expect(abs(IllnessWatch.temperatureBar(baselineSD: nil, luteal: false) - 0.5) < 0.001)
        #expect(abs(IllnessWatch.temperatureBar(baselineSD: nil, luteal: true) - 0.8) < 0.001)
        #expect(abs(IllnessWatch.temperatureBar(baselineSD: 0.2, luteal: false) - 0.3) < 0.001)
        #expect(abs(IllnessWatch.temperatureBar(baselineSD: 0.2, luteal: true) - 0.6) < 0.001)
        // A very steady baseline can't trip on noise: the 0.2 °C floor.
        #expect(abs(IllnessWatch.temperatureBar(baselineSD: 0.05, luteal: false) - 0.2) < 0.001)

        // Steady sleeper (SD 0.15): +0.36 °C is 2.4 SD and counts, where the fixed bar missed it.
        let steady = try #require(IllnessWatch.evaluate(.init(temperatureDelta: 0.36, reportedSymptoms: true, temperatureBaselineSD: 0.15)))
        #expect(steady.signals.contains("Temperature +0.4 °C"))
        #expect(steady.level == .major)
        #expect(IllnessWatch.evaluate(.init(temperatureDelta: 0.36)) == nil)
        // Variable sleeper (SD 0.4): +0.5 °C is only 1.25 SD, so it doesn't count.
        #expect(IllnessWatch.evaluate(.init(temperatureDelta: 0.5, temperatureBaselineSD: 0.4)) == nil)
        // The luteal allowance is added to the z-score bar too.
        #expect(IllnessWatch.evaluate(.init(temperatureDelta: 0.5, daysSinceLastPeriod: 20, temperatureBaselineSD: 0.15)) == nil)
        let lutealFever = try #require(IllnessWatch.evaluate(.init(temperatureDelta: 0.7, daysSinceLastPeriod: 20, temperatureBaselineSD: 0.15)))
        #expect(lutealFever.signals == ["Temperature +0.7 °C"])
    }

    /// The last 7 nights' breathing disturbances well above the 30 before
    /// (one SD of nightly values) count as one sign (watch-features.md 1.2).
    @Test func breathingDisturbanceTrend() throws {
        let quiet = Array(repeating: [4.0, 5.0, 6.0, 5.0, 4.5, 5.5, 5.0, 4.0, 6.0, 5.0], count: 3).flatMap { $0 }
        #expect(!IllnessWatch.breathingDisturbancesRising(nightly: quiet))
        // Baseline SD here is about 0.7; a week averaging 7 is almost 3 SD up.
        #expect(IllnessWatch.breathingDisturbancesRising(nightly: quiet + Array(repeating: 7.0, count: 7)))
        // One odd night in the week isn't a trend.
        #expect(!IllnessWatch.breathingDisturbancesRising(nightly: quiet + [5.0, 5, 5, 8, 5, 5, 5]))
        // Too little history.
        #expect(!IllnessWatch.breathingDisturbancesRising(nightly: Array(repeating: 5.0, count: 10) + Array(repeating: 9.0, count: 3)))

        // As a signal it already spans a week, so RHR up + the trend is "major" without yesterday's data.
        let alert = try #require(IllnessWatch.evaluate(.init(restingHeartRate: 62, rhrBaseline: (54, 1.5), breathingDisturbancesRising: true)))
        #expect(alert.level == .major)
        #expect(alert.signals.contains("Breathing disturbances up this week"))
        // Alone it's one quiet sign.
        let alone = try #require(IllnessWatch.evaluate(.init(breathingDisturbancesRising: true)))
        #expect(alone.level == .minor)
    }

    @Test func stalledLiftsWithLowHRVSuggestDeload() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func point(_ name: String, daysAgo: Double, _ value: Double) -> DeloadAdvisor.LiftPoint {
            .init(exercise: name, date: now.addingTimeInterval(-daysAgo * 86_400), estimatedOneRepMax: value)
        }
        let lifts = [
            point("Bench", daysAgo: 25, 100), point("Bench", daysAgo: 18, 102), point("Bench", daysAgo: 10, 101), point("Bench", daysAgo: 3, 102),
            point("Squat", daysAgo: 24, 140), point("Squat", daysAgo: 17, 142), point("Squat", daysAgo: 9, 141), point("Squat", daysAgo: 2, 140),
        ]
        let advice = try #require(DeloadAdvisor.evaluate(lifts, hrvBelowNormal: true, now: now))
        #expect(advice.strong)
        #expect(advice.stalledLifts == ["Bench", "Squat"])
        let progressing = lifts.map { p in DeloadAdvisor.LiftPoint(exercise: p.exercise, date: p.date,
            estimatedOneRepMax: p.estimatedOneRepMax + (p.date > now.addingTimeInterval(-14 * 86_400) ? 8 : 0)) }
        #expect(DeloadAdvisor.evaluate(progressing, hrvBelowNormal: true, now: now) == nil)
    }
}

struct MicronutrientTests {
    @Test func flagsLowAndHigh() {
        let findings = Micronutrients.assess(
            averages: [.vitaminC: 30, .vitaminD: 16, .sodium: 3500, .iron: 9],
            daysLogged: 7, sex: .male
        )
        #expect(findings.first { $0.nutrient == .vitaminC }?.kind == .low)
        #expect(findings.first { $0.nutrient == .vitaminD }?.kind == .ok)
        #expect(findings.first { $0.nutrient == .sodium }?.kind == .high)
        #expect(findings.first { $0.nutrient == .iron }?.kind == .ok)
        #expect(Micronutrients.notes(findings, area: .immune).count == 1)
    }

    @Test func ironTargetIsHigherForWomen() {
        // Below the women's EAR (8.1 mg) is low; the same intake is fine for men.
        let findings = Micronutrients.assess(averages: [.iron: 7], daysLogged: 7, sex: .female)
        #expect(findings.first?.kind == .low)
        #expect(Micronutrients.assess(averages: [.iron: 7], daysLogged: 7, sex: .male).first?.kind == .ok)
    }

    @Test func needsFourDaysOfLogging() {
        #expect(Micronutrients.assess(averages: [.vitaminC: 10], daysLogged: 3, sex: .male).isEmpty)
    }
}
