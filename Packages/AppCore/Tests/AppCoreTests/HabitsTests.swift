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
        // Linear by dose (Gardiner 2023): 100 mg → 8.52 h (511 min), 220 mg → 13.32 h (799 min).
        // 11 pm bedtime: coffee by 2:29 pm, pre-workout by 9:41 am.
        #expect(CaffeineTiming.cutoffMinutes(bedtimeMinutes: 23 * 60, mg: 100) == 23 * 60 - 511)
        #expect(CaffeineTiming.cutoffMinutes(bedtimeMinutes: 23 * 60, mg: 220) == 23 * 60 - 799)
        #expect(CaffeineTiming.isTooLate(minutes: 15 * 60, mg: 95, bedtimeMinutes: 23 * 60))
        #expect(!CaffeineTiming.isTooLate(minutes: 13 * 60, mg: 95, bedtimeMinutes: 23 * 60))
    }

    @Test func hoursFollowTheDoseLineAndClamp() {
        // The paper's two model points sit on the line: 107 mg → 8.8 h, 217 mg → 13.2 h.
        #expect(abs(CaffeineTiming.hoursBeforeBed(mg: 107) - 8.8) < 1e-9)
        #expect(abs(CaffeineTiming.hoursBeforeBed(mg: 217) - 13.2) < 1e-9)
        // No step at 180 mg any more: 179 and 181 mg differ by 0.08 h, not 4.4.
        #expect(abs(CaffeineTiming.hoursBeforeBed(mg: 181) - CaffeineTiming.hoursBeforeBed(mg: 179) - 0.08) < 1e-9)
        // Clamped to 6-14 h.
        #expect(CaffeineTiming.hoursBeforeBed(mg: 10) == 6)
        #expect(CaffeineTiming.hoursBeforeBed(mg: 400) == 14)
        #expect(CaffeineTiming.cautionNote.contains("conservative average"))
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
    let fresh = HeatAdvice.Acclimation.notAcclimatized
    let acclimatised = HeatAdvice.Acclimation(heatTrainingDays: 12, peakHeatTrainingDays: 12, daysSinceHeatTraining: 0)

    @Test func wbgtFromTemperatureAndHumidity() {
        // Australian BoM approximation: 30 °C at 60% RH ≈ 30.9 °C WBGT; 20 °C at 40% ≈ 19.0.
        #expect(abs(HeatAdvice.estimatedWBGT(temperatureC: 30, humidityPercent: 60) - 30.92) < 0.05)
        #expect(abs(HeatAdvice.estimatedWBGT(temperatureC: 20, humidityPercent: 40) - 18.95) < 0.05)
        // Humidity moves the band: the same 27 °C is "high" when dry and "extreme" when muggy.
        #expect(HeatAdvice.risk(wbgtC: HeatAdvice.estimatedWBGT(temperatureC: 27, humidityPercent: 30)) == .high)
        #expect(HeatAdvice.risk(wbgtC: HeatAdvice.estimatedWBGT(temperatureC: 27, humidityPercent: 85)) == .extreme)
        // Missing humidity falls back to the default instead of failing.
        #expect(HeatAdvice.estimatedWBGT(temperatureC: 25, humidityPercent: nil) == HeatAdvice.estimatedWBGT(temperatureC: 25, humidityPercent: HeatAdvice.defaultHumidityPercent))
    }

    @Test func acsmBands() {
        // Roberts et al. 2021: < 18 low, 18-23 moderate, 23-28 high, 28-30 very high, > 30 extreme.
        #expect(HeatAdvice.risk(wbgtC: 15) == .low)
        #expect(HeatAdvice.risk(wbgtC: 18) == .moderate)
        #expect(HeatAdvice.risk(wbgtC: 22.9) == .moderate)
        #expect(HeatAdvice.risk(wbgtC: 23) == .high)
        #expect(HeatAdvice.risk(wbgtC: 28) == .veryHigh)
        #expect(HeatAdvice.risk(wbgtC: 30) == .veryHigh)
        #expect(HeatAdvice.risk(wbgtC: 30.1) == .extreme)
        #expect(HeatAdvice.Risk.low < HeatAdvice.Risk.extreme)
    }

    @Test func hotDaysLowerTheTarget() {
        #expect(HeatAdvice.targetAdjustment(wbgtC: nil, acclimation: fresh) == 0)
        #expect(HeatAdvice.targetAdjustment(wbgtC: 20, acclimation: fresh) == 0)
        #expect(HeatAdvice.targetAdjustment(wbgtC: 25, acclimation: fresh) == -10)
        #expect(HeatAdvice.targetAdjustment(wbgtC: 29, acclimation: fresh) == -15)
        #expect(HeatAdvice.targetAdjustment(wbgtC: 32, acclimation: fresh) == -20)
        // Acclimatised: half the change.
        #expect(HeatAdvice.targetAdjustment(wbgtC: 25, acclimation: acclimatised) == -5)
        // Fading (15-21 days away from the heat): a quarter of it is back.
        let fading = HeatAdvice.Acclimation(heatTrainingDays: 0, peakHeatTrainingDays: 12, daysSinceHeatTraining: 18)
        #expect(HeatAdvice.targetAdjustment(wbgtC: 25, acclimation: fading) == -7.5)
        // Gone after 3 weeks (Daanen 2018).
        let lost = HeatAdvice.Acclimation(heatTrainingDays: 0, peakHeatTrainingDays: 12, daysSinceHeatTraining: 25)
        #expect(HeatAdvice.targetAdjustment(wbgtC: 25, acclimation: lost) == -10)
    }

    @Test func adviceOnlyFromTheHighBand() {
        #expect(HeatAdvice.advice(wbgtC: 21, acclimation: fresh) == nil)
        let high = HeatAdvice.advice(wbgtC: 25, acclimation: fresh) ?? ""
        #expect(high.contains("strain target is lower"))
        #expect(high.contains("7-14 days"))
        let extreme = HeatAdvice.advice(wbgtC: 32, acclimation: fresh) ?? ""
        #expect(extreme.contains("unless you're heat-acclimatised"))
        #expect((HeatAdvice.advice(wbgtC: 32, acclimation: acclimatised) ?? "").contains("largely acclimatised"))
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
        let state = HeatAdvice.acclimation(hotDays: hot, trainingDays: trained, now: .now, calendar: calendar)
        #expect(state.heatTrainingDays == 7)
        #expect(state.daysSinceHeatTraining == 0)
        #expect(!state.isAcclimatized)
    }

    @Test func acclimationIsKeptForTwoWeeksThenFades() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }
        // Two weeks of hot training that ended 7 days ago (Périard 2015: 7-14 days to adapt).
        let stint = Set((7..<21).map(day))
        let recent = HeatAdvice.acclimation(hotDays: stint, trainingDays: stint, now: .now, calendar: calendar)
        #expect(recent.peakHeatTrainingDays == 14)
        #expect(recent.heatTrainingDays == 7)
        #expect(recent.daysSinceHeatTraining == 7)
        #expect(recent.isAcclimatized)
        // The same stint 17 days ago: fading (Daanen 2018: lost over ~2-3 weeks).
        let older = Set((17..<31).map(day))
        let fading = HeatAdvice.acclimation(hotDays: older, trainingDays: older, now: .now, calendar: calendar)
        #expect(fading.level == 0.5)
        #expect(!fading.isAcclimatized)
        // 25 days ago: gone.
        let oldest = Set((25..<39).map(day))
        #expect(HeatAdvice.acclimation(hotDays: oldest, trainingDays: oldest, now: .now, calendar: calendar).level == 0)
        // Hot days without training don't count.
        #expect(HeatAdvice.acclimation(hotDays: stint, trainingDays: [], now: .now, calendar: calendar) == .notAcclimatized)
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

struct AlcoholWeekTests {
    @Test func canadianTiers() {
        // CCSA 2023: 0–2 low, 3–6 moderate, 7+ increasingly high.
        #expect(AlcoholWeek.tier(drinks: 0) == .low)
        #expect(AlcoholWeek.tier(drinks: 2) == .low)
        #expect(AlcoholWeek.tier(drinks: 2.5) == .moderate)
        #expect(AlcoholWeek.tier(drinks: 3) == .moderate)
        #expect(AlcoholWeek.tier(drinks: 6.9) == .moderate)
        #expect(AlcoholWeek.tier(drinks: 7) == .high)
        #expect(AlcoholWeek.Tier.high.range == "7+")
    }

    @Test func weeklyTotalPrefersItemisedDrinks() {
        var itemised = EveningCheckIn(day: .now)
        itemised.alcohol = [AlcoholEntry(kind: .beer, millilitres: 355, abv: 10)]
        itemised.syncDrinksFromAlcohol()
        var quick = EveningCheckIn(day: .now)
        quick.drinks = 1
        let empty = EveningCheckIn(day: .now)
        let total = AlcoholWeek.total(evenings: [itemised, quick, empty])
        // Two standard drinks from the strong beer plus one quick count; the blank evening isn't logged.
        #expect(abs(total.drinks - 3) < 0.05)
        #expect(total.nightsLogged == 2)
        #expect(total.tier == .moderate)
        #expect(AlcoholWeek.sentence(total).contains("moderate risk"))
    }
}
