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
        #expect(plan.exercises.first?.repsInReserve == "2 reps in reserve")
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

    @Test func twoRaisedVitalsMeanLikelyIllness() throws {
        let alert = try #require(IllnessWatch.evaluate(.init(
            restingHeartRate: 62, rhrBaseline: (54, 1.5),
            respiratoryRate: 16.5, respiratoryBaseline: (14.5, 0.4)
        )))
        #expect(alert.level == .likely)
        #expect(alert.signals.count == 2)
    }

    @Test func alcoholDowngradesTheAlert() throws {
        let alert = try #require(IllnessWatch.evaluate(.init(
            restingHeartRate: 62, rhrBaseline: (54, 1.5),
            respiratoryRate: 16.5, respiratoryBaseline: (14.5, 0.4), drinksLastNight: 4
        )))
        #expect(alert.level == .watch)
        #expect(alert.message.contains("Alcohol"))
    }

    @Test func symptomsAloneGiveAWatchAlert() throws {
        let alert = try #require(IllnessWatch.evaluate(.init(restingHeartRate: 55, rhrBaseline: (54, 1.5), reportedSymptoms: true)))
        #expect(alert.level == .watch)
        #expect(alert.signals.isEmpty)
    }

    @Test func normalVitalsNoAlert() {
        #expect(IllnessWatch.evaluate(.init(restingHeartRate: 55, rhrBaseline: (54, 1.5))) == nil)
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
        let findings = Micronutrients.assess(averages: [.iron: 9], daysLogged: 7, sex: .female)
        #expect(findings.first?.kind == .low)
    }

    @Test func needsFourDaysOfLogging() {
        #expect(Micronutrients.assess(averages: [.vitaminC: 10], daysLogged: 3, sex: .male).isEmpty)
    }
}
