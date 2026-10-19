import Foundation
import Testing
@testable import AppCore

struct CaffeineTimingTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func cutoffsBeforeBed() {
        // 11 pm bedtime: coffee by 2:12 pm, pre-workout by 9:48 am.
        #expect(CaffeineTiming.cutoffMinutes(bedtimeMinutes: 23 * 60, mg: 100) == 23 * 60 - 528)
        #expect(CaffeineTiming.cutoffMinutes(bedtimeMinutes: 23 * 60, mg: 220) == 23 * 60 - 792)
        #expect(CaffeineTiming.isTooLate(minutes: 15 * 60, mg: 95, bedtimeMinutes: 23 * 60))
        #expect(!CaffeineTiming.isTooLate(minutes: 13 * 60, mg: 95, bedtimeMinutes: 23 * 60))
    }

    @Test func usualBedtimeHandlesMidnight() {
        let base = utc.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 23, minute: 30))!
        let onsets = [base, base.addingTimeInterval(86_400 + 3600), base.addingTimeInterval(2 * 86_400 + 1800)]
        // 23:30, 00:30, 00:00 → median midnight = 1440 minutes.
        #expect(CaffeineTiming.usualBedtimeMinutes(onsets, calendar: utc) == 24 * 60)
        #expect(CaffeineTiming.usualBedtimeMinutes([], calendar: utc) == CaffeineTiming.defaultBedtimeMinutes)
    }
}

struct AlcoholEffectTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func comparesYourOwnNights() throws {
        let nights = (0..<12).map { index -> AlcoholEffect.Night in
            let drank = index < 6
            let wobble = index.isMultiple(of: 2) ? 1.0 : -1.0
            return AlcoholEffect.Night(morning: start.addingTimeInterval(Double(index) * 86_400), drinks: drank ? 3 : 0,
                                       restingHeartRate: (drank ? 62 : 56) + wobble, hrv: nil, sleepScore: nil)
        }
        let findings = AlcoholEffect.compare(nights)
        let rhr = try #require(findings.first { $0.measure == .restingHeartRate })
        #expect(abs(rhr.difference - 6) < 0.001)
        #expect(rhr.isWorse)
        #expect(rhr.isClear)
        #expect(!findings.contains { $0.measure == .hrv })
    }

    @Test func needsFiveNightsEachSide() {
        let nights = (0..<6).map { AlcoholEffect.Night(morning: start.addingTimeInterval(Double($0) * 86_400), drinks: $0 < 2 ? 2 : 0, restingHeartRate: 60, hrv: 50, sleepScore: 80) }
        #expect(AlcoholEffect.compare(nights).isEmpty)
    }
}

struct ProteinMealsTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func groupsEntriesIntoMeals() throws {
        let entries: [(date: Date, grams: Double)] = [
            (start, 20), (start.addingTimeInterval(20 * 60), 15),          // breakfast: 35 g
            (start.addingTimeInterval(5 * 3600), 40),                       // lunch
            (start.addingTimeInterval(10 * 3600), 12),                      // snack
        ]
        let result = try #require(ProteinMeals.assess(entries, bodyMassKg: 80))
        guard case let .meals(meals, goodMeals: good, perMealTarget: target) = result else {
            Issue.record("expected meals")
            return
        }
        #expect(meals.count == 3)
        #expect(abs(target - 32) < 0.001)
        #expect(good == 2)
    }

    @Test func oneTimestampMeansNoMealTimes() {
        let entries: [(date: Date, grams: Double)] = [(start, 50), (start, 60)]
        #expect(ProteinMeals.assess(entries, bodyMassKg: 80) == .noMealTimes)
    }
}

struct WeightPaceTests {
    @Test func flagsFastLoss() {
        // 1.2 kg a week at 80 kg = 1.5%.
        guard case let .losingTooFast(percent) = WeightPace.check(weeklyChangeKg: -1.2, bodyMassKg: 80, goals: Goals(weight: .lose, weeklyRatePercent: 1)) else {
            Issue.record("expected losing too fast")
            return
        }
        #expect(abs(percent - 1.5) < 0.001)
        #expect(WeightPace.check(weeklyChangeKg: -0.5, bodyMassKg: 80, goals: Goals(weight: .lose)) == .fine)
    }

    @Test func flagsGainFasterThanPlanned() {
        let goals = Goals(weight: .gain, weeklyRatePercent: 0.25)
        #expect(WeightPace.check(weeklyChangeKg: 0.6, bodyMassKg: 80, goals: goals) != .fine)
        #expect(WeightPace.check(weeklyChangeKg: 0.2, bodyMassKg: 80, goals: goals) == .fine)
    }
}

struct HeatAdviceTests {
    @Test func hotDaysLowerTheTarget() {
        #expect(HeatAdvice.targetAdjustment(feelsLikeC: 25, heatTrainingDays: 0) == 0)
        #expect(HeatAdvice.targetAdjustment(feelsLikeC: 30, heatTrainingDays: 0) == -10)
        #expect(HeatAdvice.targetAdjustment(feelsLikeC: 36, heatTrainingDays: 0) == -15)
        // Acclimatised: half the change.
        #expect(HeatAdvice.targetAdjustment(feelsLikeC: 30, heatTrainingDays: 12) == -5)
    }

    @Test func adjustedRangeStaysValid() {
        #expect(HeatAdvice.adjustTarget(65...85, by: -10) == 65...75)
        let tight = HeatAdvice.adjustTarget(20...25, by: -15)
        #expect(tight.lowerBound <= tight.upperBound - 5)
        #expect(HeatAdvice.adjustTarget(45...65, by: 0) == 45...65)
    }

    @Test func countsHotTrainingDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = (0..<20).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let hot = Set(days)
        let trained = Set(days.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element))
        // Even offsets 0...12 fall inside the last 14 days: 7 days.
        #expect(HeatAdvice.heatTrainingDays(hotDays: hot, trainingDays: trained, now: .now, calendar: calendar) == 7)
    }
}

struct LightTipTests {
    @Test func morningAndEveningLight() {
        let sunrise = Date(timeIntervalSince1970: 1_800_000_000)
        let sunset = sunrise.addingTimeInterval(11 * 3600)
        let morning = WeatherAdvice.tips(for: .init(sunrise: sunrise, sunset: sunset, now: sunrise.addingTimeInterval(3600)))
        #expect(morning.contains { $0.id == "morningLight" })
        let evening = WeatherAdvice.tips(for: .init(sunrise: sunrise, sunset: sunset, now: sunset.addingTimeInterval(3600)))
        #expect(evening.contains { $0.id == "eveningLight" })
        let midday = WeatherAdvice.tips(for: .init(sunrise: sunrise, sunset: sunset, now: sunrise.addingTimeInterval(5 * 3600)))
        #expect(!midday.contains { $0.id.hasSuffix("Light") })
    }
}

struct ProteinTargetTests {
    @Test func leanMassWhenLosingWithBodyFat() {
        // 100 kg at 30% fat: 70 kg lean x 2.6 = 182 g (vs 220 g from 2.2 x total weight).
        let goals = Goals(weight: .lose)
        #expect(GoalPlanner.proteinGrams(goals: goals, bodyMassKg: 100, bodyFatPercent: 30, heightCm: 180) == 182)
    }

    @Test func adjustedWeightWhenBMIOver30() {
        // 120 kg, 175 cm (BMI 39): BMI-25 weight 76.6 kg; adjusted 76.6 + 0.4 x 43.4 = 93.9 kg; x 2.2 ≈ 207 g.
        let grams = GoalPlanner.proteinGrams(goals: Goals(weight: .lose), bodyMassKg: 120, bodyFatPercent: nil, heightCm: 175) ?? 0
        #expect((205...209).contains(grams))
    }

    @Test func goalWeightWhenLower() {
        let goals = Goals(weight: .lose, targetWeightKg: 75)
        #expect(GoalPlanner.proteinGrams(goals: goals, bodyMassKg: 85, bodyFatPercent: nil, heightCm: 180) == 165)
    }

    @Test func maintenanceUsesCurrentWeightAndMedicationFloor() {
        let goals = Goals(weight: .maintain, focuses: [.muscle])
        #expect(GoalPlanner.proteinGrams(goals: goals, bodyMassKg: 80, bodyFatPercent: 15, heightCm: 180) == 128)
        #expect(GoalPlanner.proteinGrams(goals: goals, bodyMassKg: 80, bodyFatPercent: 15, heightCm: 180, minimumPerKg: 2.0) == 160)
    }
}

struct BodyAgeConfidenceTests {
    @Test func moreFreshFactorsMeanMoreConfidence() throws {
        let full = try #require(BodyAge.estimate(BodyAge.Inputs(
            age: 30, sex: .male, vo2Max: 48, restingHeartRate: 58, sleepHours: 7.5, dailySteps: 9000, bodyFatPercent: 18,
            vo2MaxAgeDays: 10, bodyCompositionAgeDays: 5
        )))
        #expect(full.confidence == .high)
        let thin = try #require(BodyAge.estimate(BodyAge.Inputs(age: 30, sex: .male, restingHeartRate: 58, sleepHours: 7.5)))
        #expect(thin.confidence == .low)
        let stale = try #require(BodyAge.estimate(BodyAge.Inputs(
            age: 30, sex: .male, vo2Max: 48, restingHeartRate: 58, sleepHours: 7.5, dailySteps: 9000, bodyFatPercent: 18,
            vo2MaxAgeDays: 200
        )))
        #expect(stale.confidence == .medium)
        #expect(stale.confidenceReason.contains("VO₂ max"))
    }
}
