import Foundation
import Testing
@testable import AppCore

struct LongevityTests {
    // MARK: Personas

    /// A 30-year-old man who lifts four days a week, walks 9,000 steps and sleeps 6.5 hours.
    private var lifter: Longevity.Inputs {
        var i = Longevity.Inputs(age: 30, sex: .male, goals: Goals(weight: .maintain, focuses: [.muscle, .strength]))
        i.vo2Max = 44
        i.restingHeartRate = 56
        i.dailySteps = 9_000
        i.moderateMinutes = 120
        i.vigorousMinutes = 40
        i.strengthDaysByWeek = [4, 4, 3, 4]
        i.sleepHours = 6.5
        i.sleepNights = 14
        i.sleepRegularity = 78
        i.waistToHeight = 0.46
        i.fiberGrams = 18
        i.proteinGrams = 150
        i.proteinTargetGrams = 160
        i.drinksPerWeek = 4
        i.drinkNightsLogged = 7
        i.headphoneBudgetPercent = 40
        i.moodValence = 0.3
        i.moodEntries = 12
        return i
    }

    /// A 50-year-old woman who sits most of the day and doesn't train.
    private var sedentary: Longevity.Inputs {
        var i = Longevity.Inputs(age: 50, sex: .female, goals: Goals(weight: .lose, focuses: [.health]))
        i.vo2Max = 17
        i.restingHeartRate = 84
        i.systolic = 136
        i.diastolic = 86
        i.bloodPressureIsHomeAverage = true
        i.dailySteps = 3_200
        i.moderateMinutes = 30
        i.vigorousMinutes = 0
        i.strengthDaysByWeek = [0, 0, 0, 0]
        i.sleepHours = 7.4
        i.sleepNights = 14
        i.sleepRegularity = 70
        i.waistToHeight = 0.63
        i.fiberGrams = 14
        i.drinksPerWeek = 9
        i.drinkNightsLogged = 6
        return i
    }

    @Test func lifterIsOnTargetWhereHeTrainsAndCloseOnSleep() {
        let result = Longevity.assess(lifter)
        #expect(result.measure(.strengthDays)?.status == .onTarget)
        #expect(result.measure(.steps)?.status == .onTarget)
        #expect(result.measure(.restingHeartRate)?.status == .onTarget)
        #expect(result.measure(.waistToHeight)?.status == .onTarget)
        #expect(result.measure(.protein)?.status == .onTarget)
        #expect(result.measure(.activeMinutes)?.status == .onTarget) // 120 + 2 x 40 = 200
        // 6.5 h is inside the "may be appropriate" band, under the recommended 7.
        #expect(result.measure(.sleepDuration)?.status == .close)
        #expect(result.measure(.sleepDuration)?.nextStep.contains("30 minutes") == true)
        #expect(result.measure(.sleepRegularity)?.status == .close)
        #expect(result.measure(.alcohol)?.status == .close)
        #expect(result.measure(.fiber)?.status == .off)
        // 44 at 30 is a little under the median for men (FRIEND).
        #expect(result.measure(.vo2Max)?.status == .close)
        // No reading: asks for one instead of judging.
        #expect(result.measure(.bloodPressure)?.status == .noData)
        #expect(result.measure(.gripStrength)?.status == .noData)
        // Mood is tracked, never judged.
        #expect(result.measure(.mood)?.status == .tracking)
        // The one thing off is fibre, so that's the focus.
        #expect(result.focus?.id == .fiber)
        #expect(result.summary == "7 on target · 4 close · 1 off target")
    }

    @Test func liftersNextStepForStrengthSaysTheHealthBenefitLevelledOff() {
        let step = Longevity.assess(lifter).measure(.strengthDays)?.nextStep ?? ""
        #expect(step.contains("past the health line"))
        var general = lifter
        general.goals = Goals(weight: .maintain, focuses: [.health])
        #expect(Longevity.assess(general).measure(.strengthDays)?.nextStep.contains("Keep two sessions") == true)
    }

    @Test func sedentaryFiftyYearOldIsOffOnMovementAndTheFocusHasStrongEvidence() {
        let result = Longevity.assess(sedentary)
        for id in [Longevity.MeasureID.vo2Max, .restingHeartRate, .steps, .activeMinutes, .strengthDays,
                   .sleepRegularity, .waistToHeight, .bloodPressure, .fiber, .alcohol] {
            #expect(result.measure(id)?.status == .off, "\(id)")
        }
        #expect(result.measure(.sleepDuration)?.status == .onTarget)
        // Off before close, strong evidence first, then page order: VO₂ max leads.
        #expect(result.focus?.id == .vo2Max)
        #expect(result.focus?.grade == .strong)
        #expect(result.toWorkOn.first { $0.grade != .strong }.map { result.toWorkOn.firstIndex(of: $0) ?? 0 } ?? 99 >= 7)
        // Stage 1 blood pressure uses the guideline's own advice text.
        #expect(result.measure(.bloodPressure)?.nextStep == HomeBloodPressure.advice(.stage1))
    }

    @Test func almostNoDataJudgesNothingAndSaysHowToAddEachMeasure() {
        var inputs = Longevity.Inputs(age: 41, sex: .male)
        inputs.dailySteps = 6_400
        let result = Longevity.assess(inputs)
        #expect(result.count(.noData) == Longevity.MeasureID.allCases.count - Longevity.conditionalMeasures.count - 1)
        #expect(result.measure(.steps)?.status == .close)
        #expect(result.focus?.id == .steps)
        #expect(result.summary == "1 close")
        for measure in result.measures where measure.status == .noData {
            #expect(measure.valueText == nil)
            #expect(!measure.nextStep.isEmpty)
            #expect(!measure.targetText.isEmpty)
        }
        // Nothing at all: no summary line, no focus.
        let empty = Longevity.assess(Longevity.Inputs(age: 41, sex: .male))
        #expect(empty.summary == nil)
        #expect(empty.focus == nil)
    }

    // MARK: Structure

    @Test func everyMeasureHasAnAreaASourceAndAGradeNote() {
        let result = Longevity.assess(lifter)
        // The conditional ones (blood tests due, saturated fat) only appear when they apply.
        let always = Longevity.MeasureID.allCases.count - Longevity.conditionalMeasures.count
        #expect(result.measures.count == always)
        #expect(Set(result.measures.map(\.id)).count == always)
        #expect(result.areas.map(\.area) == Longevity.Area.allCases)
        for area in result.areas {
            #expect((1...3).contains(area.measures.count), "\(area.area)")
        }
        for measure in result.measures {
            #expect(!measure.sources.isEmpty, "\(measure.id)")
            #expect(!measure.gradeNote.isEmpty)
            #expect(!measure.why.isEmpty)
            for source in measure.sources {
                #expect(!source.finding.isEmpty && !source.kind.isEmpty)
            }
        }
    }

    @Test func copyNeverPromisesYearsOrCallsAnythingAScore() {
        for inputs in [lifter, sedentary] {
            for measure in Longevity.assess(inputs).measures {
                let text = [measure.why, measure.nextStep, measure.standing, measure.targetText, measure.gradeNote].joined(separator: " ").lowercased()
                #expect(!text.contains("adds years"), "\(measure.id)")
                #expect(!text.contains("years to your life"))
                #expect(!text.contains("longevity score"))
                #expect(!text.contains("you will live"))
            }
        }
    }

    @Test func observationalMeasuresSayLinkedAndTheTrialOnesSayTrials() {
        let result = Longevity.assess(lifter)
        for id in [Longevity.MeasureID.vo2Max, .steps, .strengthDays, .sleepRegularity, .restingHeartRate] {
            let measure = result.measure(id)
            #expect(measure?.why.contains("linked") == true, "\(id)")
            #expect(measure?.gradeNote.contains("Observational") == true, "\(id)")
        }
        #expect(result.measure(.bloodPressure)?.why.contains("trials") == true)
        #expect(result.measure(.mood)?.grade == .limited)
    }

    // MARK: Boundaries

    private func status(_ id: Longevity.MeasureID, _ change: (inout Longevity.Inputs) -> Void) -> Longevity.Status? {
        var inputs = Longevity.Inputs(age: 30, sex: .male)
        change(&inputs)
        return Longevity.assess(inputs).measure(id)?.status
    }

    @Test func vo2BandsFollowTheAgeAndSexPercentiles() {
        let cuts = VO2Norms.cutPoints(age: 30, sex: .male)
        let (low, median, high) = (cuts[2], cuts[3], cuts[4])
        #expect(status(.vo2Max) { $0.vo2Max = median } == .onTarget)
        #expect(status(.vo2Max) { $0.vo2Max = median - 0.1 } == .close)
        #expect(status(.vo2Max) { $0.vo2Max = low } == .close)
        #expect(status(.vo2Max) { $0.vo2Max = low - 0.1 } == .off)
        // A stamina goal aims at the top quarter; the low line doesn't move.
        let stamina = Goals(weight: .maintain, focuses: [.endurance])
        #expect(status(.vo2Max) { $0.goals = stamina; $0.vo2Max = median } == .close)
        #expect(status(.vo2Max) { $0.goals = stamina; $0.vo2Max = high } == .onTarget)
        #expect(status(.vo2Max) { $0.goals = stamina; $0.vo2Max = low - 0.1 } == .off)
        // The same value is judged against the person's own age and sex.
        var older = Longevity.Inputs(age: 65, sex: .female)
        older.vo2Max = 30
        #expect(Longevity.assess(older).measure(.vo2Max)?.status == .onTarget)
        #expect(status(.vo2Max) { $0.vo2Max = 30 } == .off)
        // An estimate is labelled.
        var estimated = Longevity.Inputs(age: 30, sex: .male)
        estimated.vo2Max = 45
        estimated.vo2IsEstimate = true
        #expect(Longevity.assess(estimated).measure(.vo2Max)?.valueText == "45 ml/kg/min (estimate)")
    }

    @Test func restingHeartRateBandsAreTheMetaAnalysisGroups() {
        #expect(status(.restingHeartRate) { $0.restingHeartRate = 59.9 } == .onTarget)
        #expect(status(.restingHeartRate) { $0.restingHeartRate = 60 } == .close)
        #expect(status(.restingHeartRate) { $0.restingHeartRate = 80 } == .close)
        #expect(status(.restingHeartRate) { $0.restingHeartRate = 80.1 } == .off)
    }

    /// The line is the health floor the weekly review ticks too
    /// (`HealthFloors.dailySteps`, 7,000 at every age; it was 8,000 under 60).
    @Test func stepsUseTheSharedFloorAtEveryAge() {
        #expect(status(.steps) { $0.dailySteps = 8_000 } == .onTarget)
        #expect(status(.steps) { $0.dailySteps = 7_000 } == .onTarget)
        #expect(status(.steps) { $0.dailySteps = 6_999 } == .close)
        #expect(status(.steps) { $0.dailySteps = 5_000 } == .close)
        #expect(status(.steps) { $0.dailySteps = 4_999 } == .off)
        var older = Longevity.Inputs(age: 64, sex: .male)
        older.dailySteps = 7_000
        #expect(Longevity.assess(older).measure(.steps)?.status == .onTarget)
        #expect(Longevity.assess(older).measure(.steps)?.targetText == "7,000 a day or more")
    }

    @Test func activeMinutesCountHardMinutesDoubleAndRiseWithAStaminaGoal() {
        #expect(status(.activeMinutes) { $0.moderateMinutes = 150; $0.vigorousMinutes = 0 } == .onTarget)
        #expect(status(.activeMinutes) { $0.moderateMinutes = 0; $0.vigorousMinutes = 75 } == .onTarget)
        #expect(status(.activeMinutes) { $0.moderateMinutes = 149; $0.vigorousMinutes = 0 } == .close)
        #expect(status(.activeMinutes) { $0.moderateMinutes = 75; $0.vigorousMinutes = 0 } == .close)
        #expect(status(.activeMinutes) { $0.moderateMinutes = 74; $0.vigorousMinutes = 0 } == .off)
        let stamina = Goals(weight: .maintain, focuses: [.endurance])
        #expect(status(.activeMinutes) { $0.goals = stamina; $0.moderateMinutes = 200; $0.vigorousMinutes = 0 } == .close)
        #expect(status(.activeMinutes) { $0.goals = stamina; $0.moderateMinutes = 100; $0.vigorousMinutes = 100 } == .onTarget)
        // Only one of the two numbers: not judged.
        #expect(status(.activeMinutes) { $0.moderateMinutes = 200 } == .noData)
    }

    @Test func strengthDaysUseTheFourWeekAverage() {
        #expect(status(.strengthDays) { $0.strengthDaysByWeek = [2, 2, 2, 2] } == .onTarget)
        // A deload week doesn't drop a regular lifter under the line.
        #expect(status(.strengthDays) { $0.strengthDaysByWeek = [3, 3, 1, 3] } == .onTarget)
        #expect(status(.strengthDays) { $0.strengthDaysByWeek = [2, 1, 2, 2] } == .close)
        #expect(status(.strengthDays) { $0.strengthDaysByWeek = [1, 1, 1, 1] } == .close)
        #expect(status(.strengthDays) { $0.strengthDaysByWeek = [1, 0, 1, 1] } == .off)
        #expect(status(.strengthDays) { $0.strengthDaysByWeek = [] } == .noData)
    }

    @Test func sleepBandsAreTheFoundationsRangesAndNeedAWeekOfNights() {
        func sleep(_ hours: Double, age: Int = 30, nights: Int = 14) -> Longevity.Status? {
            var inputs = Longevity.Inputs(age: age, sex: .male)
            inputs.sleepHours = hours
            inputs.sleepNights = nights
            return Longevity.assess(inputs).measure(.sleepDuration)?.status
        }
        #expect(sleep(7) == .onTarget)
        #expect(sleep(9) == .onTarget)
        #expect(sleep(6.99) == .close)
        #expect(sleep(6) == .close)
        #expect(sleep(5.9) == .off)
        #expect(sleep(9.5) == .close)
        #expect(sleep(10.5) == .off)
        // From 65 the recommended range is 7-8 h.
        #expect(sleep(8.5, age: 70) == .close)
        #expect(sleep(5.5, age: 70) == .close)
        #expect(sleep(4.9, age: 70) == .off)
        // Four nights is not an average.
        #expect(sleep(5, nights: 4) == .noData)
    }

    @Test func sleepRegularityLinesComeFromTheCohortsSpread() {
        // Windred 2024's fifths: on target in the most regular (87+), off in the least (under 72).
        #expect(status(.sleepRegularity) { $0.sleepRegularity = 87 } == .onTarget)
        #expect(status(.sleepRegularity) { $0.sleepRegularity = 86 } == .close)
        #expect(status(.sleepRegularity) { $0.sleepRegularity = 81 } == .close)
        #expect(status(.sleepRegularity) { $0.sleepRegularity = 72 } == .close)
        #expect(status(.sleepRegularity) { $0.sleepRegularity = 71 } == .off)
    }

    @Test func waistAndBloodPressureReuseTheExistingCategories() {
        #expect(status(.waistToHeight) { $0.waistToHeight = 0.49 } == .onTarget)
        #expect(status(.waistToHeight) { $0.waistToHeight = 0.55 } == .close)
        #expect(status(.waistToHeight) { $0.waistToHeight = 0.38 } == .close)
        #expect(status(.waistToHeight) { $0.waistToHeight = 0.62 } == .off)
        func pressure(_ systolic: Double, _ diastolic: Double, home: Bool = true) -> Longevity.Status? {
            status(.bloodPressure) { $0.systolic = systolic; $0.diastolic = diastolic; $0.bloodPressureIsHomeAverage = home }
        }
        #expect(pressure(118, 76) == .onTarget)
        #expect(pressure(124, 78) == .close)
        #expect(pressure(124, 82) == .off)
        #expect(pressure(131, 70) == .off)
        // One reading shows its value but isn't classed.
        var single = Longevity.Inputs(age: 30, sex: .male)
        single.systolic = 150
        single.diastolic = 95
        let measure = Longevity.assess(single).measure(.bloodPressure)
        #expect(measure?.status == .noData)
        #expect(measure?.valueText == "150/95 mmHg")
        #expect(measure?.nextStep.contains("7-day home check") == true)
    }

    @Test func nutritionAlcoholAndHearingBoundaries() {
        #expect(status(.fiber) { $0.fiberGrams = 25 } == .onTarget)
        #expect(status(.fiber) { $0.fiberGrams = 24.9 } == .close)
        #expect(status(.fiber) { $0.fiberGrams = 19.9 } == .off)
        func protein(_ grams: Double) -> Longevity.Status? {
            status(.protein) { $0.proteinGrams = grams; $0.proteinTargetGrams = 160 }
        }
        #expect(protein(144) == .onTarget)
        #expect(protein(143) == .close)
        #expect(protein(112) == .close)
        #expect(protein(111) == .off)
        // No target (no goal or weight yet): not judged.
        #expect(status(.protein) { $0.proteinGrams = 150 } == .noData)
        func drinks(_ count: Double, nights: Int = 7) -> Longevity.Status? {
            status(.alcohol) { $0.drinksPerWeek = count; $0.drinkNightsLogged = nights }
        }
        #expect(drinks(0) == .onTarget)
        #expect(drinks(2) == .onTarget)
        #expect(drinks(2.5) == .close)
        #expect(drinks(6.5) == .close)
        #expect(drinks(7) == .off)
        // Three logged evenings can't speak for a week.
        #expect(drinks(0, nights: 3) == .noData)
        #expect(status(.headphoneSound) { $0.headphoneBudgetPercent = 79 } == .onTarget)
        #expect(status(.headphoneSound) { $0.headphoneBudgetPercent = 80 } == .close)
        #expect(status(.headphoneSound) { $0.headphoneBudgetPercent = 100 } == .off)
    }

    @Test func moodIsTrackedNotJudgedAndLowMoodGetsTheTwoWeekLine() {
        var inputs = Longevity.Inputs(age: 30, sex: .female)
        inputs.moodValence = -0.5
        inputs.moodEntries = 4
        #expect(Longevity.assess(inputs).measure(.mood)?.status == .noData)
        inputs.moodEntries = 9
        let low = Longevity.assess(inputs).measure(.mood)
        #expect(low?.status == .tracking)
        #expect(low?.valueText == "Meh")
        #expect(low?.nextStep.contains("two weeks") == true)
        inputs.moodValence = 0.5
        #expect(Longevity.assess(inputs).measure(.mood)?.nextStep.contains("two weeks") == false)
        // Tracking never counts as on, close or off.
        #expect(Longevity.assess(inputs).summary == nil)
    }

    @Test func gripUsesTheAgeBandAndTheLowStrengthLine() {
        #expect(status(.gripStrength) { $0.gripKg = 50 } != .noData)
        #expect(status(.gripStrength) { $0.gripKg = 20 } == .off)
        #expect(status(.gripStrength) { $0.gripKg = GripStrength.band(age: 30, sex: .male).mean } == .onTarget)
    }

    @Test func textHelpersAreLocaleFree() {
        #expect(Longevity.grouped(9_049) == "9,000")
        #expect(Longevity.grouped(10_060) == "10,100")
        #expect(Longevity.grouped(12_004) == "12,000")
        #expect(Longevity.grouped(640) == "600")
        #expect(Longevity.two(0.466) == "0.47")
        #expect(Longevity.two(0.5) == "0.50")
        #expect(Longevity.one(3.5) == "3.5")
        #expect(Longevity.one(4.04) == "4")
        #expect(Longevity.hoursText(6.5) == "6 h 30 min")
        #expect(Longevity.hoursText(7) == "7 h")
    }
}
