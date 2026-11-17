import Foundation
import Testing
@testable import AppCore

/// The numbers audit (Nov 2026): realistic people run through the calculators.
/// Each test uses the auditor's inputs for one finding (N1-N16). The owner
/// persona is a man of 30, 80 kg, 180 cm, resting heart rate 55 (max 187 by
/// Tanaka), lifting 4-5 times a week for 60-75 minutes at 100-135 bpm, 9,000
/// steps a day, with an occasional 90-minute match at 150 bpm.
enum AuditPersona {
    static let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55)
    static let body = EnergyCalculator.Body(weightKg: 80, heightCm: 180, age: 30, sex: .male, trainingStatus: .advanced)
    /// Midnight UTC.
    static let day = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400))
    static let endOfDay = day.addingTimeInterval(86_400)
    static let onFeetStart = day.addingTimeInterval(9 * 3600)
    static let liftStart = day.addingTimeInterval(18 * 3600)

    /// One reading a minute at a steady heart rate.
    static func steady(bpm: Double, minutes: Int, from start: Date) -> [HeartRateSample] {
        (0...minutes).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: bpm) }
    }

    /// 70 minutes swinging between 100 and 135 bpm (sets and rests).
    static func lifting(minutes: Int = 70) -> [HeartRateSample] {
        (0...minutes).map { minute in
            HeartRateSample(date: liftStart.addingTimeInterval(Double(minute) * 60), bpm: 100 + 35 * Double(minute % 6) / 5)
        }
    }

    static func session(rpe: Double?, minutes: Double = 70) -> StrengthSessionSummary {
        StrengthSessionSummary(start: liftStart, end: liftStart.addingTimeInterval(minutes * 60), sessionRPE: rpe)
    }

    static func energy(heartRate: [HeartRateSample], sessions: [StrengthSessionSummary] = [], steps: Double = 9_000,
                       body: EnergyCalculator.Body = body, profile: HeartRateProfile = profile,
                       workouts: [DateInterval] = []) -> EnergyCalculator.Result {
        EnergyCalculator().estimate(body: body, profile: profile, heartRate: heartRate, strengthSessions: sessions,
                                    stepsOutsideWorkouts: steps, intake: nil, dayStart: day, now: endOfDay, workouts: workouts)
    }
}

// MARK: - N1 Calories burned

struct AuditEnergyTests {
    let calc = EnergyCalculator()

    @Test func fiveHoursOnHisFeetIsMovementNotExercise() {
        // Was: 96 bpm → 1,552 kcal of "exercise" and no steps; 93 bpm → 0.
        for bpm in [93.0, 96, 100, 105] {
            let result = AuditPersona.energy(heartRate: AuditPersona.steady(bpm: bpm, minutes: 300, from: AuditPersona.onFeetStart))
            #expect(result.exercise == 0)
            #expect(abs(result.everydayMovement - 9_000 * 0.00042 * 80) < 0.01) // 302 kcal of steps
            #expect(abs(result.projectedTotal - 2_291.6) < 1) // ten Haaf 1,989 + 302
        }
    }

    @Test func noCliffWhereTheEquationStarts() {
        // 40% of reserve is 107.8 bpm. One beat either side must not be worth
        // hundreds of kcal (a plain 40% switch: 302 → about 2,100).
        func total(_ bpm: Double) -> Double {
            AuditPersona.energy(heartRate: AuditPersona.steady(bpm: bpm, minutes: 300, from: AuditPersona.onFeetStart)).projectedTotal
        }
        #expect(total(108) - total(107) < 60)
        var previous = total(104)
        for bpm in stride(from: 105.0, through: 125, by: 1) {
            let now = total(bpm)
            #expect(now >= previous - 0.001)
            #expect(now - previous < 250)
            previous = now
        }
        // From 50% of reserve (121 bpm) the equation counts in full.
        #expect(calc.everydayExerciseWeight(reserveFraction: 0.5) == 1)
        #expect(calc.everydayExerciseWeight(reserveFraction: 0.45) == 0.5)
        #expect(calc.everydayExerciseWeight(reserveFraction: 0.39) == 0)
    }

    @Test func liftingSessionIsCountedByMETsAlone() {
        // Was 585-609 kcal (the heart-rate equation, about 7.5 METs with rests).
        // Now 4.75 METs at session RPE 7: (4.75 − 1) × 80 kg × 70/60 h = 350.
        let result = AuditPersona.energy(heartRate: AuditPersona.lifting(), sessions: [AuditPersona.session(rpe: 7)], steps: 0)
        #expect(abs(result.exercise - 350) < 0.01)
        #expect((250...400).contains(result.exercise))
        // Heart rate inside the session changes nothing.
        let quiet = AuditPersona.energy(heartRate: [], sessions: [AuditPersona.session(rpe: 7)], steps: 0)
        #expect(quiet.exercise == result.exercise)
    }

    @Test func sessionCaloriesRiseSmoothlyWithRPE() {
        // Was 233 kcal at RPE 6.9 and 467 at RPE 7.
        let body = AuditPersona.body
        #expect(abs(calc.strengthKcal(minutes: 70, rpe: 7, body: body) - calc.strengthKcal(minutes: 70, rpe: 6.9, body: body)) < 7)
        #expect(calc.strengthMETs(rpe: 3) == 3.5)
        #expect(calc.strengthMETs(rpe: 5) == 3.5)
        #expect(calc.strengthMETs(rpe: 7) == 4.75)
        #expect(calc.strengthMETs(rpe: 9) == 6.0)
        #expect(calc.strengthMETs(rpe: 10) == 6.0)
        var previous = 0.0
        for rpe in stride(from: 1.0, through: 10, by: 0.1) {
            let kcal = calc.strengthKcal(minutes: 70, rpe: rpe, body: body)
            #expect(kcal >= previous)
            #expect(kcal - previous < 7 || previous == 0)
            previous = kcal
        }
    }

    @Test func unratedSessionUsesTheSharedDefault() {
        // N5: one default, 5.5, for strain and calories (was 6.5 and 7).
        #expect(StrainCalculator.defaultSessionRPE == 5.5)
        #expect(StrainCalculator().defaultRPE == 5.5)
        #expect(calc.strengthMETs(rpe: nil) == calc.strengthMETs(rpe: 5.5))
        #expect(abs(calc.strengthKcal(minutes: 70, rpe: nil, body: AuditPersona.body) - 262.5) < 0.01)
        let unrated = AuditPersona.session(rpe: nil)
        #expect(StrainCalculator().rpeLoad(for: unrated) == 5.5 * 70 * 0.33)
    }

    @Test func aMatchNoLongerCancelsTheDaysSteps() {
        // 90 minutes at 150 bpm, 9,000 steps outside it. Was: movement 0.
        let match = DateInterval(start: AuditPersona.liftStart, duration: 90 * 60)
        let heartRate = AuditPersona.steady(bpm: 150, minutes: 90, from: AuditPersona.liftStart)
        let result = AuditPersona.energy(heartRate: heartRate, workouts: [match])
        #expect(abs(result.everydayMovement - 302.4) < 0.01)
        #expect((1_100...1_300).contains(result.exercise)) // Keytel, about 13 kcal a minute net
        // Without the workout window the equation still counts it (150 bpm is
        // 72% of reserve), but its minutes are treated as unlogged walking.
        let unwired = AuditPersona.energy(heartRate: heartRate)
        #expect(abs(unwired.exercise - result.exercise) < 0.01)
        #expect(unwired.everydayMovement == 0)
    }

    @Test func heavyWomansBriskWalkIsNeverUnderHerSteps() {
        // 125 kg woman of 45, an unlogged hour at 125 bpm with 6,000 steps.
        // Was: 251 kcal from heart rate, less than the 315 her steps alone give.
        let body = EnergyCalculator.Body(weightKg: 125, heightCm: 165, age: 45, sex: .female)
        let profile = HeartRateProfile(age: 45, sex: .female, restingHeartRate: 70)
        let stepsAlone = 6_000 * 0.00042 * 125
        let walk = AuditPersona.steady(bpm: 125, minutes: 60, from: AuditPersona.onFeetStart)
        let result = AuditPersona.energy(heartRate: walk, steps: 6_000, body: body, profile: profile)
        #expect(result.exercise + result.everydayMovement >= stepsAlone - 0.01)
        // As a logged workout, every raised minute gets at least the bottom of
        // its ACSM band: 3 METs gross from 40% of reserve, so 2 × 125 kg / 60 a minute.
        for weight in [110.0, 125, 140] {
            let heavy = EnergyCalculator.Body(weightKg: weight, heightCm: 165, age: 45, sex: .female)
            let logged = AuditPersona.energy(heartRate: walk, steps: 0, body: heavy, profile: profile,
                                             workouts: [DateInterval(start: AuditPersona.onFeetStart, duration: 3600)])
            #expect(logged.exercise >= 2 * weight - 0.01)
        }
    }

    @Test func ownerRestDayAndLiftDayTotals() {
        // Five hours on his feet at 96 bpm, 9,000 steps. Was 3,541 on a rest
        // day and 4,126 with a 70-minute RPE 7 session.
        let onFeet = AuditPersona.steady(bpm: 96, minutes: 300, from: AuditPersona.onFeetStart)
        let rest = AuditPersona.energy(heartRate: onFeet)
        #expect(abs(rest.projectedTotal - 2_291.6) < 1)
        let lift = AuditPersona.energy(heartRate: onFeet + AuditPersona.lifting(), sessions: [AuditPersona.session(rpe: 7)])
        #expect(abs(lift.projectedTotal - 2_641.6) < 1)
    }

    @Test func noBodyWeightGivesNoRestingFigure() {
        // N16: weight 0 used to return about 980 kcal from height and age alone.
        let empty = EnergyCalculator.Body(weightKg: 0, heightCm: 180, age: 30, sex: .male)
        #expect(calc.bmr(empty).kcal == 0)
        #expect(calc.bmr(empty).method == EnergyCalculator.missingWeightMethod)
        #expect(calc.strengthKcal(minutes: 60, rpe: 7, body: empty) == 0)
        let result = AuditPersona.energy(heartRate: AuditPersona.steady(bpm: 150, minutes: 30, from: AuditPersona.liftStart), body: empty)
        #expect(result.restingFullDay == 0)
        #expect(result.everydayMovement == 0)
    }
}

// MARK: - N11 Resting-energy equation choice

struct AuditRestingEnergyTests {
    let calc = EnergyCalculator()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func body(age: Int) -> EnergyCalculator.Body {
        EnergyCalculator.Body(weightKg: 80, heightCm: 180, age: age, sex: .male, trainingStatus: .advanced)
    }

    @Test func noBirthdayStepBetweenTheEquations() {
        // Was 1,949 at 35 and 1,750 at 36.
        #expect(abs(calc.bmr(body(age: 35)).kcal - 1_948.6) < 0.5)
        #expect(calc.bmr(body(age: 35)).method == EnergyCalculator.tenHaafMethod)
        #expect(abs(calc.bmr(body(age: 36)).kcal - 1_902.3) < 0.5)
        #expect(calc.bmr(body(age: 36)).method == EnergyCalculator.blendedMethod)
        #expect(calc.bmr(body(age: 40)).kcal == 1_730)
        #expect(calc.bmr(body(age: 40)).method == "Mifflin-St Jeor")
        for age in 30..<45 {
            let drop = calc.bmr(body(age: age)).kcal - calc.bmr(body(age: age + 1)).kcal
            #expect(drop > 0 && drop < 50)
        }
        #expect(EnergyCalculator.athleteEquationWeight(age: 17) == 0)
        #expect(EnergyCalculator.athleteEquationWeight(age: 18) == 1)
        #expect(EnergyCalculator.athleteEquationWeight(age: 38) == 0.4)
    }

    /// Sessions on the given weekdays for `days` back from now, leaving out
    /// any whose age in days is in `skipping`.
    func sessions(days: Int, on weekdays: [Int], skipping: ClosedRange<Int>? = nil) -> [Date] {
        (0..<days).compactMap { back -> Date? in
            guard weekdays.contains(back % 7), skipping?.contains(back) != true else { return nil }
            return now.addingTimeInterval(-Double(back) * 86_400 - 3600)
        }
    }

    @Test func aThreeWeekBreakDoesNotMakeAnAdvancedLifterANovice() {
        // Three sessions a week for 2.5 years, then 21 days off: 15 sessions in
        // the last 8 weeks (1.9 a week) used to read novice.
        let history = sessions(days: 913, on: [0, 2, 4], skipping: 0...20)
        #expect(TrainingStatus.estimate(sessionDates: history, now: now) == .advanced)
        // Twice a week with the same break: the 12-week average (1.5) holds it.
        let twice = sessions(days: 913, on: [0, 3], skipping: 0...20)
        #expect(TrainingStatus.estimate(sessionDates: twice, now: now) == .advanced)
        // And in the weeks after coming back.
        for backAt in [7, 14, 28, 42] {
            let resumed = sessions(days: 913, on: [0, 3], skipping: backAt...(backAt + 20))
            #expect(TrainingStatus.estimate(sessionDates: resumed, now: now) == .advanced)
        }
    }

    @Test func oneMissedSessionDoesNotChangeTheStatus() {
        // Twice a week for 2.5 years with one session missed 10 days ago: 15 in 8 weeks.
        let history = sessions(days: 913, on: [0, 3], skipping: 10...10)
        #expect(history.filter { now.timeIntervalSince($0) < 56 * 86_400 }.count == 15)
        #expect(TrainingStatus.estimate(sessionDates: history, now: now) == .advanced)
    }

    @Test func aSustainedStopStillLowersIt() {
        // Seven weeks off: under 1.5 a week on both windows, so no longer "trained".
        let sevenWeeks = sessions(days: 913, on: [0, 2, 4], skipping: 0...48)
        #expect(TrainingStatus.estimate(sessionDates: sevenWeeks, now: now) == .novice)
        // Ten weeks off: under one a week on both, untrained.
        let tenWeeks = sessions(days: 913, on: [0, 2, 4], skipping: 0...69)
        #expect(TrainingStatus.estimate(sessionDates: tenWeeks, now: now) == .untrained)
    }
}

// MARK: - N3 Strain

struct AuditStrainTests {
    let calculator = StrainCalculator()

    func onFeet(_ bpm: Double) -> StrainCalculator.Result {
        calculator.dailyStrain(heartRate: AuditPersona.steady(bpm: bpm, minutes: 300, from: AuditPersona.onFeetStart),
                               strengthSessions: [], profile: AuditPersona.profile)
    }

    @Test func noCliffAtThirtyPercentOfReserve() {
        // Was 0% at 93 bpm and 57.7% at 96 bpm (30% of reserve is 94.6 bpm).
        #expect(onFeet(93).strain == 0)
        #expect(onFeet(96).strain < 12)
        var previous = onFeet(90).strain
        for bpm in stride(from: 91.0, through: 112, by: 1) {
            let now = onFeet(bpm).strain
            #expect(now >= previous)
            #expect(now - previous < 12)
            previous = now
        }
    }

    @Test func taperRunsFromThirtyToFortyPercent() {
        #expect(calculator.everydayWeight(reserveFraction: 0.29) == 0)
        #expect(calculator.everydayWeight(reserveFraction: 0.30) == 0)
        #expect(calculator.everydayWeight(reserveFraction: 0.35) == 0.5)
        #expect(calculator.everydayWeight(reserveFraction: 0.40) == 1)
        #expect(calculator.everydayWeight(reserveFraction: 0.75) == 1)
        // From 40% of reserve up, everyday minutes count exactly as before.
        let bpm = AuditPersona.profile.heartRate(atReserve: 0.6)
        let hour = calculator.dailyStrain(heartRate: AuditPersona.steady(bpm: bpm, minutes: 60, from: AuditPersona.onFeetStart),
                                          strengthSessions: [], profile: AuditPersona.profile)
        #expect(abs(hour.cardioLoad - calculator.trimp(minutes: 60, reserveFraction: 0.6, sex: .male)) < 0.001)
    }

    @Test func loggedWorkoutsAndExerciseMinutesCountAsBefore() {
        // An easy logged workout at 33% of reserve keeps the full Banister weight.
        let bpm = AuditPersona.profile.heartRate(atReserve: 0.33)
        let heartRate = AuditPersona.steady(bpm: bpm, minutes: 60, from: AuditPersona.onFeetStart)
        let full = calculator.trimp(minutes: 60, reserveFraction: 0.33, sex: .male)
        let workout = DateInterval(start: AuditPersona.onFeetStart, duration: 3600)
        let logged = calculator.dailyStrain(heartRate: heartRate, strengthSessions: [], profile: AuditPersona.profile, workouts: [workout])
        #expect(abs(logged.cardioLoad - full) < 0.001)
        let minutes = (0..<60).map { AuditPersona.onFeetStart.addingTimeInterval(Double($0) * 60) }
        let counted = calculator.dailyStrain(heartRate: heartRate, strengthSessions: [], profile: AuditPersona.profile, movementMinutes: minutes)
        #expect(abs(counted.cardioLoad - full) < 0.001)
        let unlogged = calculator.dailyStrain(heartRate: heartRate, strengthSessions: [], profile: AuditPersona.profile)
        #expect(abs(unlogged.cardioLoad - 0.3 * full) < 0.001)
        // Exercise minutes with no heart rate are still credited at 40%, in full.
        let credited = calculator.dailyStrain(heartRate: [], strengthSessions: [], profile: AuditPersona.profile, movementMinutes: minutes)
        #expect(abs(credited.cardioLoad - calculator.trimp(minutes: 60, reserveFraction: 0.4, sex: .male)) < 0.001)
    }

    @Test func ownerLiftDayStrain() {
        // 70 minutes at session RPE 7 is unchanged: 7 × 70 × 0.33 = 161.7 → 72.3%.
        let rated = calculator.dailyStrain(heartRate: AuditPersona.lifting(), strengthSessions: [AuditPersona.session(rpe: 7)],
                                           profile: AuditPersona.profile)
        #expect(rated.strain == 72.3)
        // Unrated: 5.5 instead of 6.5, 63.5% instead of 69.6%.
        let unrated = calculator.dailyStrain(heartRate: AuditPersona.lifting(), strengthSessions: [AuditPersona.session(rpe: nil)],
                                             profile: AuditPersona.profile)
        #expect(unrated.strain == 63.5)
        // With five hours on his feet at 96 bpm the day read 88.3%; now 74.7%.
        let onFeet = AuditPersona.steady(bpm: 96, minutes: 300, from: AuditPersona.onFeetStart)
        let day = calculator.dailyStrain(heartRate: onFeet + AuditPersona.lifting(), strengthSessions: [AuditPersona.session(rpe: 7)],
                                         profile: AuditPersona.profile)
        #expect(day.strain == 74.7)
    }

    @Test func headerCalibrationFigures() {
        // The figures quoted in StrainCalculator's header (30-year-old man, resting 60, max 187).
        let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 60)
        func strain(reserve: Double, minutes: Int, workout: Bool = false) -> Double {
            let start = AuditPersona.onFeetStart
            let heartRate = AuditPersona.steady(bpm: profile.heartRate(atReserve: reserve), minutes: minutes, from: start)
            return calculator.dailyStrain(heartRate: heartRate, strengthSessions: [], profile: profile,
                                          workouts: workout ? [DateInterval(start: start, duration: Double(minutes) * 60)] : []).strain
        }
        #expect(abs(strain(reserve: 0.75, minutes: 60) - 62) < 1)
        #expect(abs(strain(reserve: 0.35, minutes: 60, workout: true) - 19) < 1)
        #expect(abs(strain(reserve: 0.35, minutes: 60) - 10) < 1)
        #expect(strain(reserve: 0.29, minutes: 300) == 0)
        #expect(abs(strain(reserve: 0.31, minutes: 300) - 8) < 1)
        #expect(abs(strain(reserve: 0.35, minutes: 300) - 41) < 1)
        #expect(abs(strain(reserve: 0.40, minutes: 300) - 73) < 1)
        #expect(abs(calculator.strain(forLoad: 8 * 60 * 0.33) - 72) < 1)
        #expect(abs(calculator.strain(forLoad: 7 * 45 * 0.33) - 56) < 1)
        #expect(abs(calculator.strain(forLoad: 5.5 * 60 * 0.33) - 58) < 1)
    }
}

// MARK: - N6 Strain target

struct AuditStrainTargetTests {
    @Test func activeRestDaysAreNotTrainingDays() {
        // Three lifting days a week at 72% and four active rest days at 27%
        // for four weeks. Was "usual 27" (16 of the 28 "training days" were
        // rest days), a 25-40 target for good, and every lifting day "above".
        let week: [Double] = [72, 27, 72, 27, 72, 27, 27]
        let days = Array(repeating: week, count: 4).flatMap { $0 }
        #expect(StrainCalculator.usualTrainingStrain(days) == 72)
        let target = StrainCalculator.targetStrain(forRecovery: 60, usualTrainingStrain: StrainCalculator.usualTrainingStrain(days))
        #expect(target == 57...77)
        #expect(target.contains(72))
        // The line is the planner's own.
        #expect(StrainCalculator.usualTrainingStrain(Array(repeating: 34.9, count: 10)) == nil)
        #expect(StrainCalculator.usualTrainingStrain(Array(repeating: TrainingDayPlanner.trainingDayStrain, count: 6)) == 35)
    }

    @Test func noHistoryDoesNotCallAnOrdinaryLiftingDayAbove() {
        // The owner's typical lifting day is about 76%; the default band stopped at 70.
        let target = StrainCalculator.targetStrain(forRecovery: 60, usualTrainingStrain: nil)
        for strain in [70.0, 72.3, 76, 78] { #expect(target.contains(strain)) }
        #expect(target.lowerBound == 50)
        // Low recovery is unchanged.
        #expect(StrainCalculator.targetStrain(forRecovery: 20, usualTrainingStrain: nil) == 20...45)
    }
}

// MARK: - N4 Sleep debt and bedtime window

struct AuditSleepDebtTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test func steadySevenHoursIsLowNotHigh() throws {
        // 7.0 h a night on a 7.5 h need. Was: 7.0 h, "High", "+60 min for 7 nights".
        let debt = try #require(SleepDebt.compute(nightlyHours: Array(repeating: 7.0, count: 14), needHours: 7.5))
        #expect(debt.hours == 7.0) // the number shown is still the running total
        #expect(debt.level == .low)
        #expect(debt.statusLabel == "Low")
        #expect(debt.averageShortfallHours == 0.5)
        #expect(debt.extraMinutesPerNight == 30)
        #expect(debt.paybackNights == 14)
        #expect(!debt.isEarly)
        #expect(debt.windowLabel == "14 nights")
    }

    @Test func ownerSleepIsLowNotModerate() throws {
        // 6.5-8 h, mean 7.25 h, on a 7.5 h need. Was 3.5 h, "Moderate".
        let nights = [6.5, 8, 7, 7.5, 6.5, 8, 7.25, 6.5, 8, 7, 7.5, 6.5, 8, 7.25]
        let debt = try #require(SleepDebt.compute(nightlyHours: nights, needHours: 7.5))
        #expect(debt.hours == 3.5)
        #expect(debt.level == .low)
    }

    @Test func levelsFollowTheAverageShortfall() throws {
        func level(_ hours: Double, need: Double = 7.5) throws -> SleepDebt.Level {
            try #require(SleepDebt.compute(nightlyHours: Array(repeating: hours, count: 14), needHours: need)).level
        }
        #expect(try level(7.5) == .none)
        #expect(try level(7.45) == .none) // 0.7 h in total: "Under 1 h"
        #expect(try level(7.25) == .low)
        #expect(try level(6.9) == .moderate) // 36 minutes a night
        #expect(try level(6.6) == .moderate)
        #expect(try level(6.5) == .high) // an hour a night (Belenky 2003's mildest restriction)
        #expect(try level(5.6) == .high) // the 5.6 h sleeper
        #expect(SleepDebt.level(debtHours: 0.9) == .none)
        #expect(SleepDebt.level(debtHours: 7) == .low)
        #expect(SleepDebt.level(debtHours: 7.1) == .moderate)
        #expect(SleepDebt.level(debtHours: 14) == .high)
    }

    @Test func aFirstReadingIsMarkedEarly() throws {
        // Five 5.6 h nights on a 7.5 h need: 9.5 h. On the old total-based
        // scale that was already "High"; against the 14-night window it is
        // 41 minutes a night, Moderate, and marked as an early reading.
        let debt = try #require(SleepDebt.compute(nightlyHours: Array(repeating: 5.6, count: 5), needHours: 7.5))
        #expect(debt.hours == 9.5)
        #expect(debt.level == .moderate)
        #expect(debt.isEarly)
        #expect(debt.windowLabel == "first 5 of 14 nights")
        #expect(SleepDebt.compute(nightlyHours: Array(repeating: 5.6, count: 4), needHours: 7.5) == nil)
    }

    @Test func bedtimeWindowAllowsForTimeAwakeInBed() throws {
        // 7.5 h need, up at 6:30, no debt. Was 23:00-23:30: 7.0-7.5 h in bed,
        // about 6.3-6.7 h asleep at 90%. Now 22:10-22:40.
        let now = calendar.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 20))!
        let window = try #require(BedtimeWindow.compute(sleepNeedHours: 7.5, sleepDebt: nil, usualWakeMinutes: 6 * 60 + 30,
                                                        regularity: 85, now: now, calendar: calendar))
        #expect(window.windowText.isEmpty == false)
        #expect(calendar.dateComponents([.hour, .minute], from: window.start) == DateComponents(hour: 22, minute: 10))
        #expect(calendar.dateComponents([.hour, .minute], from: window.end) == DateComponents(hour: 22, minute: 40))
        // Even from the end of the window, 90% of the time in bed is at least 7 h asleep.
        let shortest = window.wake.timeIntervalSince(window.end) / 3600
        #expect(shortest * BedtimeWindow.assumedSleepEfficiency >= 7)
        #expect(abs(window.wake.timeIntervalSince(window.start) / 3600 - 7.5 / 0.9) < 5.0 / 60)
        #expect(window.reason.contains("7.5 h need (about 8 h 20 min in bed)"))
        // The steady 7.0 h sleeper repays 30 minutes a night, not 60.
        let debt = SleepDebt.compute(nightlyHours: Array(repeating: 7.0, count: 14), needHours: 7.5)
        let repaying = try #require(BedtimeWindow.compute(sleepNeedHours: 7.5, sleepDebt: debt, usualWakeMinutes: 6 * 60 + 30,
                                                          regularity: 85, now: now, calendar: calendar))
        #expect(repaying.repaymentMinutes == 30)
        #expect(calendar.dateComponents([.hour, .minute], from: repaying.start) == DateComponents(hour: 21, minute: 40))
    }
}

// MARK: - N7 Sleep score

struct AuditSleepScoreTests {
    let night = AuditPersona.day.addingTimeInterval(23 * 3600)

    /// A clean sleep: 20% deep, 22% REM, the rest core, no awakenings.
    func clean(hours: Double) -> [SleepSample] {
        let deepEnd = night.addingTimeInterval(hours * 3600 * 0.2)
        let remEnd = deepEnd.addingTimeInterval(hours * 3600 * 0.22)
        return [
            SleepSample(stage: .deep, start: night, end: deepEnd),
            SleepSample(stage: .rem, start: deepEnd, end: remEnd),
            SleepSample(stage: .core, start: remEnd, end: night.addingTimeInterval(hours * 3600)),
        ]
    }

    func score(_ hours: Double) throws -> Int {
        try #require(SleepCalculator().score(samples: clean(hours: hours))).score
    }

    @Test func shortSleepsNoLongerShareOneScore() throws {
        // Was: 20 minutes 50, 3 h 50, 4 h 50, 6 h 73, 7.5 h 95 (8 h need).
        #expect(try score(20.0 / 60) == 3)
        #expect(try score(3) == 31)
        #expect(try score(4) == 42)
        #expect(try score(6) == 73)
        #expect(try score(7.5) == 95)
        #expect(try score(8) == 100)
        var previous = -1
        for hours in stride(from: 0.5, through: 9, by: 0.25) {
            let now = try score(hours)
            #expect(now >= previous)
            previous = now
        }
    }

    @Test func qualityMarksScaleWithSleepLength() {
        let need = 8.0 * 3600
        #expect(SleepCalculator.shortSleepFactor(asleep: 0.6 * need, need: need) == 1)
        #expect(SleepCalculator.shortSleepFactor(asleep: 8 * 3600, need: need) == 1)
        #expect(abs(SleepCalculator.shortSleepFactor(asleep: 3 * 3600, need: need) - 0.625) < 0.0001)
        #expect(SleepCalculator.shortSleepFactor(asleep: 0, need: need) == 0)
        // Regularity is scaled too: a 20-minute doze with perfect habits isn't a 15-point night.
        let doze = SleepCalculator().score(samples: clean(hours: 20.0 / 60), consistency: 95)
        #expect((doze?.score ?? 100) < 10)
    }

    func splitNight(gapMinutes: Double) -> [DateInterval] {
        let first = DateInterval(start: night, duration: 3 * 3600)
        return [first, DateInterval(start: first.end.addingTimeInterval(gapMinutes * 60), duration: 3 * 3600)]
    }

    @Test func aNightSplitByALongWakeIsOneNight() throws {
        // 3 h asleep, awake, 3 h asleep. Was: 80 minutes awake → 6 h counted,
        // 100 minutes → only the first 3 h.
        for gap in [80.0, 100, 150, 180] {
            let main = try #require(SleepSessions.main(splitNight(gapMinutes: gap)))
            #expect(main.asleep == 6 * 3600)
        }
        // More than three hours apart is two sleeps.
        #expect(try #require(SleepSessions.main(splitNight(gapMinutes: 200))).asleep == 3 * 3600)
        // The score follows: 100 minutes awake is a 6 h night with poor efficiency, not a 3 h one.
        func scored(_ gap: Double) throws -> SleepCalculator.Result {
            let samples = splitNight(gapMinutes: gap).map { SleepSample(stage: .unspecified, start: $0.start, end: $0.end) }
            return try #require(SleepCalculator().score(samples: samples))
        }
        #expect(try scored(100).asleep == 6 * 3600)
        #expect(try scored(100).score <= scored(80).score)
        #expect(try scored(100).score > scored(200).score)
    }

    @Test func napsAndEveningDozesStaySeparate() throws {
        let sleep = DateInterval(start: night, duration: 7 * 3600)
        // A 40-minute doze on the couch two hours before bed: under an hour, so not bridged.
        let doze = DateInterval(start: night.addingTimeInterval(-160 * 60), duration: 40 * 60)
        #expect(SleepSessions.sessions([doze, sleep]).count == 2)
        #expect(try #require(SleepSessions.main([doze, sleep])).asleep == 7 * 3600)
        // A 90-minute afternoon nap five hours before bed: well away from the night.
        let nap = DateInterval(start: night.addingTimeInterval(-6.5 * 3600), duration: 90 * 60)
        #expect(SleepSessions.sessions([nap, sleep]).count == 2)
        // Ordinary awakenings (under 90 minutes) are bridged whatever the block lengths.
        let early = DateInterval(start: night.addingTimeInterval(-75 * 60), duration: 30 * 60)
        #expect(SleepSessions.sessions([early, sleep]).count == 1)
    }
}

// MARK: - N8 VO₂ max estimate

struct AuditVO2Tests {
    @Test func heartRateRatioIsCappedAtTheTableTop() throws {
        // A resting rate of 30: 15.3 × 187 / 30 = 95 mL/kg/min before.
        let capped = try #require(VO2MaxEstimate.heartRateRatio(maxHeartRate: 187, restingHeartRate: 30, measuredMax: false, age: 30, sex: .male))
        let top = try #require(VO2Norms.cutPoints(age: 30, sex: .male).last)
        #expect(capped.value == top)
        #expect(abs(top - 63.05) < 0.01) // FRIEND 95th percentile, between the 20s (66.3) and 30s (59.8)
        #expect(capped.isCapped)
        // The older signature has no age, so it uses the table's highest 95th percentile.
        #expect(VO2MaxEstimate.heartRateRatio(maxHeartRate: 187, restingHeartRate: 30, measuredMax: false)?.value == 66.3)
        // An ordinary reading isn't touched: the owner, 187 / 55.
        let owner = try #require(VO2MaxEstimate.heartRateRatio(maxHeartRate: 187, restingHeartRate: 55, measuredMax: false, age: 30, sex: .male))
        #expect(abs(owner.value - 52.02) < 0.01)
        #expect(!owner.isCapped && owner.weight == 1)
    }

    @Test func womenGetTheirOwnFactorAtHalfWeight() throws {
        // 52 kg woman of 28, 165 cm, resting 62, age-predicted max 188.4. Was 46.5 at full weight.
        let heart = try #require(VO2MaxEstimate.heartRateRatio(maxHeartRate: 208 - 0.7 * 28, restingHeartRate: 62, measuredMax: false, age: 28, sex: .female))
        #expect(abs(heart.value - 14.5 * 188.4 / 62) < 0.01) // 44.1
        #expect(heart.weight == 0.5)
        let bmi = 52 / (1.65 * 1.65)
        let activity = try #require(VO2MaxEstimate.activity(rating: 3, age: 28, sex: .female, bmi: bmi, bodyFatPercent: nil))
        let combined = try #require(VO2MaxEstimate.combined([heart, activity]))
        #expect(abs(combined.value - (0.5 * heart.value + activity.value) / 1.5) < 0.001)
        // The plain mean of the old figures was 41.8; the weighted one sits nearer the activity model.
        #expect(combined.value < 40.5)
        // Men are unchanged: equal votes.
        let man = try #require(VO2MaxEstimate.heartRateRatio(maxHeartRate: 187, restingHeartRate: 55, measuredMax: false, age: 30, sex: .male))
        let manActivity = try #require(VO2MaxEstimate.activity(rating: 4, age: 30, sex: .male, bmi: 80 / 3.24, bodyFatPercent: nil))
        #expect(abs(try #require(VO2MaxEstimate.combined([man, manActivity])).value - (man.value + manActivity.value) / 2) < 0.001)
    }

    @Test func activityLevelReadsTheMonthAndKeepsLiftingAtModest() {
        // The older entry point, one week: 25 vigorous minutes is level 4, 35
        // is level 5, and a lifting session's vigorous heart rate counts.
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 25, moderateMinutes: 100, liftingMinutes: 300) == 4)
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 35, moderateMinutes: 100, liftingMinutes: 300) == 5)
        // The 28-day entry point: lifting only ever reaches the "modest" levels...
        #expect(VO2MaxEstimate.activityRating(aerobicVigorousMinutes: 0, aerobicModerateMinutes: 0, liftingMinutes: 1_200) == 3)
        #expect(VO2MaxEstimate.activityRating(aerobicVigorousMinutes: 0, aerobicModerateMinutes: 0, liftingMinutes: 100) == 2)
        // ...and one more hard session moves a month's average by a quarter as much.
        #expect(VO2MaxEstimate.activityRating(aerobicVigorousMinutes: 60, aerobicModerateMinutes: 400, liftingMinutes: 1_200) == 4)
        #expect(VO2MaxEstimate.activityRating(aerobicVigorousMinutes: 70, aerobicModerateMinutes: 400, liftingMinutes: 1_200) == 4)
        // The owner (BMI 24.7, heart-rate ratio 52.0). The old weekly reading was
        // level 3 in a week without a match and level 6 in a week with one:
        // 47.5 ↔ 50.4 combined. One 90-minute match in the month is 22.5 vigorous
        // minutes a week, level 4, whichever week it fell in: 48.5.
        func combined(level: Int) -> Double {
            let heart = VO2MaxEstimate.heartRateRatio(maxHeartRate: 187, restingHeartRate: 55, measuredMax: false, age: 30, sex: .male)
            let activity = VO2MaxEstimate.activity(rating: level, age: 30, sex: .male, bmi: 80 / 3.24, bodyFatPercent: nil)
            return VO2MaxEstimate.combined([heart, activity].compactMap { $0 })?.value ?? 0
        }
        let quietWeek = VO2MaxEstimate.activityRating(vigorousMinutes: 0, moderateMinutes: 60, liftingMinutes: 300)
        let matchWeek = VO2MaxEstimate.activityRating(vigorousMinutes: 90, moderateMinutes: 60, liftingMinutes: 300)
        #expect(quietWeek == 3 && matchWeek == 6)
        #expect(abs(combined(level: quietWeek) - 47.5) < 0.1 && abs(combined(level: matchWeek) - 50.4) < 0.1)
        let month = VO2MaxEstimate.activityRating(aerobicVigorousMinutes: 90, aerobicModerateMinutes: 240, liftingMinutes: 1_200)
        #expect(month == 4)
        #expect(abs(combined(level: month) - 48.5) < 0.1)
        // A month with a 90-minute match most weeks: 300 vigorous minutes, 75 a week, level 6.
        #expect(VO2MaxEstimate.activityRating(aerobicVigorousMinutes: 300, aerobicModerateMinutes: 200, liftingMinutes: 1_200) == 6)
        #expect(VO2MaxEstimate.activityRating(aerobicVigorousMinutes: 75, aerobicModerateMinutes: 50, liftingMinutes: 300, overDays: 7) == 6)
    }
}

// MARK: - N9 Measured maintenance

struct AuditMaintenanceTests {
    let now = AuditPersona.endOfDay

    func intake(days: Int = 28, kcal: Double = 2_900) -> [DayValue] {
        (0..<days).map { DayValue(date: now.addingTimeInterval(-Double($0) * 86_400 - 3600), value: kcal) }
    }

    /// Weigh-ins `daysAgo` back, 80 kg with the given scale noise.
    func weights(_ daysAgo: [Int], noise: [Double]) -> [DayValue] {
        zip(daysAgo, noise).map { DayValue(date: now.addingTimeInterval(-Double($0) * 86_400 - 7200), value: 80 + $1) }
    }

    @Test func fourWeighInsOverTenDaysAreNotEnough() {
        // The same steady 80 kg, eating 2,900: ordinary ±0.6 kg scale noise
        // across four weigh-ins swung "maintenance" by over 1,000 kcal.
        let up = weights([10, 7, 3, 0], noise: [-0.6, -0.2, 0.3, 0.6])
        let down = weights([10, 7, 3, 0], noise: [0.6, 0.2, -0.3, -0.6])
        let riseKcal = (WeightTrend.weeklyChange(up) ?? 0) / 7 * AdaptiveTDEE.kcalPerKg
        let fallKcal = (WeightTrend.weeklyChange(down) ?? 0) / 7 * AdaptiveTDEE.kcalPerKg
        #expect(riseKcal - fallKcal > 1_000) // what the old rule would have accepted
        #expect(AdaptiveTDEE.estimate(intake: intake(), weights: up, now: now) == nil)
        #expect(AdaptiveTDEE.estimate(intake: intake(), weights: down, now: now) == nil)
        // Eight weigh-ins bunched into ten days aren't enough either.
        let bunched = weights([10, 9, 8, 6, 5, 3, 1, 0], noise: [0.2, -0.3, 0.1, 0.4, -0.2, 0.3, -0.4, 0.1])
        #expect(AdaptiveTDEE.estimate(intake: intake(), weights: bunched, now: now) == nil)
        // The chart's weekly trend still needs only 4 over 10 days.
        #expect(WeightTrend.weeklyChange(up) != nil)
        #expect(WeightTrend.weeklyChange(up, minimumWeighIns: 8, minimumSpanDays: 14) == nil)
    }

    @Test func eightOverFourteenDaysGiveAnEstimateWithItsError() throws {
        let steady = weights([14, 12, 10, 8, 6, 4, 2, 0], noise: [0.3, -0.4, 0.2, -0.1, 0.4, -0.3, 0.1, -0.2])
        let result = try #require(AdaptiveTDEE.estimate(intake: intake(), weights: steady, now: now))
        #expect(result.weighIns == 8)
        #expect(abs(result.maintenance - 2_900) < 300)
        let error = try #require(result.uncertaintyKcal)
        #expect((100...400).contains(error))
        #expect(result.uncertaintyText?.hasPrefix("about ±") == true)
        #expect(AdaptiveTDEE.minimumWeighIns == 8 && AdaptiveTDEE.minimumWeighInSpanDays == 14)
    }

    @Test func progressSaysWhatIsStillNeeded() throws {
        let few = AdaptiveTDEE.progress(intake: intake(days: 11), weights: weights([10, 7, 3, 0], noise: [0, 0, 0, 0]), now: now)
        #expect(few.daysNeeded == 3)
        #expect(few.weighInsNeeded == 4)
        #expect(!few.isComplete)
        let text = try #require(few.stillNeeded)
        #expect(text.contains("3 more fully logged days of food (11 of 14)"))
        #expect(text.contains("4 more weigh-ins (4 of 8)"))
        // Enough weigh-ins, but all within ten days.
        let bunched = AdaptiveTDEE.progress(intake: intake(), weights: weights([10, 9, 8, 6, 5, 3, 1, 0], noise: Array(repeating: 0, count: 8)), now: now)
        #expect(bunched.weighInsNeeded == 0 && bunched.spanDaysNeeded == 4)
        #expect(try #require(bunched.stillNeeded).contains("weigh-ins over 4 more days"))
        let done = AdaptiveTDEE.progress(intake: intake(), weights: weights([14, 12, 10, 8, 6, 4, 2, 0], noise: Array(repeating: 0, count: 8)), now: now)
        #expect(done.isComplete)
        #expect(done.stillNeeded == nil)
    }
}

// MARK: - N10 Goals

struct AuditGoalTests {
    @Test func weeksToTargetUseTheTargetInForce() throws {
        // 118 kg beginner, "1% a week" down to 100 kg: 15 weeks on paper. The
        // 2,411 kcal minimum held his target 610 kcal under a 3,021 maintenance,
        // which is 0.47% a week: 32 weeks.
        let goals = Goals(weight: .lose, weeklyRatePercent: 1, focuses: [.muscle], targetWeightKg: 100)
        #expect(abs(try #require(GoalPlanner.weeksToTarget(currentKg: 118, goals: goals)) - 15.25) < 0.01)
        let rate = try #require(GoalPlanner.deliveredWeeklyRatePercent(bodyMassKg: 118, goals: goals, maintenance: 3_021, calorieTarget: 2_411))
        #expect(abs(rate - 0.47) < 0.005)
        let weeks = try #require(GoalPlanner.weeksToTarget(currentKg: 118, goals: goals, maintenance: 3_021, calorieTarget: 2_411))
        #expect(abs(weeks - 32.5) < 0.5)
        // When the target delivers the chosen rate the two agree.
        let unheld = GoalPlanner.calorieTarget(maintenance: 3_021, bodyMassKg: 118, goals: goals, sex: .male)
        #expect(abs(try #require(GoalPlanner.weeksToTarget(currentKg: 118, goals: goals, maintenance: 3_021, calorieTarget: unheld)) - 15.25) < 0.01)
        // The owner: 80 kg on 1% a week with a target held at 0.74%.
        let owner = Goals(weight: .lose, weeklyRatePercent: 1, focuses: [.muscle], targetWeightKg: 74)
        let held = 2_900 - 0.0074 * 80 * AdaptiveTDEE.kcalPerKg / 7
        #expect(abs(try #require(GoalPlanner.weeksToTarget(currentKg: 80, goals: owner, maintenance: 2_900, calorieTarget: held)) - 6 / 0.592) < 0.01)
        // A target at or above maintenance never gets there; no target weight, no answer.
        #expect(GoalPlanner.weeksToTarget(currentKg: 118, goals: goals, maintenance: 2_400, calorieTarget: 2_411) == nil)
        #expect(GoalPlanner.weeksToTarget(currentKg: 99, goals: goals, maintenance: 3_021, calorieTarget: 2_411) == 0)
        #expect(GoalPlanner.weeksToTarget(currentKg: 118, goals: Goals(weight: .maintain), maintenance: 3_021, calorieTarget: 3_021) == nil)
        // Gaining works the same way round.
        let gain = Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.muscle], targetWeightKg: 82)
        #expect(abs(try #require(GoalPlanner.weeksToTarget(currentKg: 80, goals: gain, maintenance: 2_900, calorieTarget: 3_120)) - 10) < 0.01)
    }

    @Test func athleteFloorIsNotAppliedToHighBodyFat() {
        // 118 kg, 179 cm man (BMI 37), about 110 kcal of exercise a day. Was a 2,411 kcal floor.
        #expect(CalorieSafety.minimumTarget(sex: .male, weightKg: 118, heightCm: 179, bodyFatPercent: 35, exerciseKcalPerDay: 113) == 1_500)
        // No body-fat reading: BMI 35 or more does the same.
        #expect(CalorieSafety.minimumTarget(sex: .male, weightKg: 118, heightCm: 179, bodyFatPercent: nil, exerciseKcalPerDay: 113) == 1_500)
        #expect(CalorieSafety.minimumTarget(sex: .female, weightKg: 100, heightCm: 165, bodyFatPercent: 40, exerciseKcalPerDay: 100) == 1_200)
        // Lean and average people keep the 30 kcal/kg floor: the owner at 18% body fat.
        let owner = CalorieSafety.minimumTarget(sex: .male, weightKg: 80, heightCm: 180, bodyFatPercent: 18, exerciseKcalPerDay: 300)
        #expect(owner == (30 * 80 * 0.82 + 300).rounded())
        // A muscular man with a BMI of 31 and no body-fat reading keeps it too.
        #expect(CalorieSafety.energyAvailabilityFloorApplies(sex: .male, weightKg: 100, heightCm: 180, bodyFatPercent: nil))
        // The line is the app's own "high body fat" one (22% men, 32% women).
        #expect(CalorieSafety.energyAvailabilityFloorApplies(sex: .male, weightKg: 90, heightCm: 180, bodyFatPercent: 22))
        #expect(!CalorieSafety.energyAvailabilityFloorApplies(sex: .male, weightKg: 90, heightCm: 180, bodyFatPercent: 22.5))
        #expect(CalorieSafety.energyAvailabilityFloorApplies(sex: .female, weightKg: 70, heightCm: 165, bodyFatPercent: 30))
    }
}

// MARK: - N14 Nutrition

struct AuditNutritionTests {
    @Test func carbBandStaysInsideTheCalorieTarget() throws {
        // 118 kg, 179 cm beginner on 3,030 kcal with a muscle goal: the per-kg
        // band said 354-590 g beside a split of about 416 g.
        let goals = Goals(weight: .maintain, focuses: [.muscle])
        let split = try #require(MacroSplit.make(calorieTarget: 3_030, bodyMassKg: 118, bodyFatPercent: nil, heightCm: 179,
                                                 goals: goals, sex: .male, trainingStatus: .novice))
        #expect(split.proteinGrams == 152)
        #expect(abs(split.carbsGrams - 416) < 3)
        #expect(NutritionTargets.carbsGrams(bodyMassKg: 118, trainingDay: true, goals: goals) == 354...590)
        let band = try #require(NutritionTargets.carbsGrams(bodyMassKg: 118, trainingDay: true, goals: goals, split: split))
        #expect(band.lowerBound == 354)
        #expect(band.upperBound <= NutritionTargets.maximumCarbsGrams(split: split))
        #expect(band.contains(split.carbsGrams))
        #expect(band.upperBound * 4 + split.proteinGrams * 4 + split.fatFloorGrams * 9 <= split.calorieTarget + 4)
        // Endurance goal: 590-826 g, 3,304 kcal of carbohydrate on a 3,030 kcal day, before.
        let endurance = Goals(weight: .maintain, focuses: [.endurance])
        let enduranceSplit = try #require(MacroSplit.make(calorieTarget: 3_030, bodyMassKg: 118, bodyFatPercent: nil, heightCm: 179,
                                                          goals: endurance, sex: .male, trainingStatus: .novice))
        #expect(try #require(NutritionTargets.carbsGrams(bodyMassKg: 118, trainingDay: true, goals: endurance)).upperBound * 4 > 3_030)
        let capped = try #require(NutritionTargets.carbsGrams(bodyMassKg: 118, trainingDay: true, goals: endurance, split: enduranceSplit))
        #expect(capped.upperBound * 4 + enduranceSplit.proteinGrams * 4 + enduranceSplit.fatFloorGrams * 9 <= 3_030 + 4)
        #expect(capped.contains(enduranceSplit.carbsGrams))
        let text = try #require(NutritionTargets.carbsText(bodyMassKg: 118, trainingDay: true, goals: endurance, split: enduranceSplit))
        #expect(!text.contains("826"))
        // A lean lifter with room to spare keeps the plain band; no split, no change.
        let ownerGoals = Goals(weight: .maintain, focuses: [.muscle])
        let ownerSplit = try #require(MacroSplit.make(calorieTarget: 2_900, bodyMassKg: 80, bodyFatPercent: nil, heightCm: 180,
                                                      goals: ownerGoals, sex: .male, trainingStatus: .advanced))
        #expect(NutritionTargets.carbsGrams(bodyMassKg: 80, trainingDay: true, goals: ownerGoals, split: ownerSplit) == 240...400)
        #expect(NutritionTargets.carbsText(bodyMassKg: 80, trainingDay: true, goals: ownerGoals, split: nil)
            == NutritionTargets.carbsText(bodyMassKg: 80, trainingDay: true, goals: ownerGoals))
    }

    @Test func proteinPerMealAddsUpToTheDailyTarget() throws {
        // Health or stamina goals: 3 × 0.3 g/kg = 0.9 g/kg against a 1.2 g/kg day, before.
        for goals in [Goals(weight: .maintain, focuses: [.health]), Goals(weight: .maintain, focuses: [.endurance])] {
            let daily = try #require(GoalPlanner.proteinGrams(goals: goals, bodyMassKg: 80, bodyFatPercent: nil, heightCm: 180))
            #expect(daily == 96)
            let meal = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: goals))
            #expect(meal.grams * Double(meal.meals) == daily)
            let fromDaily = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: goals, dailyProteinGrams: daily))
            #expect(fromDaily.grams == 32 && fromDaily.meals == 3)
        }
        // The heavy beginner: 4 × 47 g = 188 g against a 152 g daily target, before.
        let muscle = Goals(weight: .maintain, focuses: [.muscle])
        let daily = try #require(GoalPlanner.proteinGrams(goals: muscle, bodyMassKg: 118, bodyFatPercent: nil, heightCm: 179))
        #expect(daily == 152)
        #expect(NutritionTargets.proteinPerMeal(bodyMassKg: 118, goals: muscle)?.grams == 47) // per kg of body weight: no daily figure
        let meal = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 118, goals: muscle, dailyProteinGrams: daily))
        #expect(meal.meals == 4)
        #expect(meal.grams == 38)
        #expect(abs(meal.grams * Double(meal.meals) - daily) <= 2)
        // Three logged meals: 152 / 3 = 51 g, under the 0.55 g/kg ceiling, so three it is.
        let three = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 118, goals: muscle, loggedMeals: 3, dailyProteinGrams: daily))
        #expect(three.meals == 3 && three.grams == 51)
        // A cutting 80 kg lifter at 176 g a day: 3 meals would be 59 g (0.73 g/kg), so it stays at 4 × 44.
        let cut = Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle])
        let cutting = try #require(NutritionTargets.proteinPerMeal(bodyMassKg: 80, goals: cut, loggedMeals: 3, dailyProteinGrams: 176))
        #expect(cutting.meals == 4 && cutting.grams == 44)
    }
}

// MARK: - N15 Hydration

struct AuditHydrationTests {
    @Test func drinksBaseAndALenientEvening() {
        // Owner on a 70-minute lifting day: the target was 3.7 + 0.875 = 4.6 L,
        // and 3.2 L by 21:00 read "Behind".
        let target = Hydration.target(sex: .male, exerciseMinutes: 70, feelsLikeC: 18)
        #expect(target.base == 3.0)
        #expect(abs(target.liters - 3.875) < 0.001)
        #expect(Hydration.target(sex: .female, exerciseMinutes: 0, feelsLikeC: nil).liters == 2.2)
        #expect(Hydration.assess(drank: 3.2, target: target, hour: 21).status == .onTrack)
        // Even against the old total-water target, 3.2 L at 21:00 is no longer "Behind".
        let total = Hydration.target(sex: .male, exerciseMinutes: 70, feelsLikeC: 18, includesWaterInFood: true)
        #expect(abs(total.liters - 4.575) < 0.001)
        #expect(Hydration.assess(drank: 3.2, target: total, hour: 21).status == .onTrack)
        // The evening bar is 60% of the target: 2.3 L here.
        #expect(Hydration.assess(drank: 2.4, target: target, hour: 21).status == .onTrack)
        #expect(Hydration.assess(drank: 2.2, target: target, hour: 21).status == .low)
        // Earlier in the day the pace rule is unchanged: 70% of what's expected by now.
        #expect(Hydration.assess(drank: 0.6, target: target, hour: 15).status == .low)
        #expect(Hydration.assess(drank: 1.7, target: target, hour: 15).status == .onTrack)
    }
}

// MARK: - N16 Unguarded inputs

struct AuditInputGuardTests {
    @Test func waistTypedInInchesIsRejected() {
        // 34 (inches) typed as centimetres at 180 cm was ratio 0.19, "Low".
        #expect(WaistToHeightRatio.ratio(waistCm: 34, heightCm: 180) == nil)
        #expect(WaistToHeightRatio.looksLikeInches(waistCm: 34, heightCm: 180))
        #expect(WaistToHeightRatio.ratio(waistCm: 34 * 2.54, heightCm: 180) != nil)
        #expect(WaistToHeightRatio.ratio(waistCm: 52, heightCm: 180) == nil) // 52 in typed as cm
        #expect(WaistToHeightRatio.ratio(waistCm: 84, heightCm: 180) == 84.0 / 180)
        #expect(!WaistToHeightRatio.looksLikeInches(waistCm: 84, heightCm: 180))
        #expect(WaistToHeightRatio.ratio(waistCm: 60, heightCm: 160) == 0.375) // a small real waist still counts
        #expect(WaistToHeightRatio.ratio(waistCm: 200, heightCm: 180) == nil)
        #expect(WaistToHeightRatio.ratio(waistCm: 84, heightCm: 1_800) == nil)
    }

    @Test func aLiftGoalOfZeroIsNotReached() {
        let now = AuditPersona.endOfDay
        let samples = (0..<8).map { LiftGoalProjection.Sample(date: now.addingTimeInterval(-Double($0) * 7 * 86_400), kg: 100 - Double($0)) }
        let projection = LiftGoalProjection.project(samples: samples, targetKg: 0, now: now)
        #expect(projection.status == .needsMoreData)
        #expect(projection.progress == nil)
        #expect(LiftGoalProjection.headline(projection, weight: { "\(Int($0)) kg" }, month: { _ in "June" }, now: now)
            == "Set a target above zero to see a projection.")
        #expect(LiftGoalProjection.project(samples: samples, targetKg: -5, now: now).status == .needsMoreData)
        // A real target the lifter has passed still reads reached.
        #expect(LiftGoalProjection.project(samples: samples, targetKg: 95, now: now).status == .reached)
        #expect(LiftGoal(exerciseID: "x", name: "Bench", targetKg: 0).resolvedTargetKg(bodyMassKg: 80) == nil)
    }
}
