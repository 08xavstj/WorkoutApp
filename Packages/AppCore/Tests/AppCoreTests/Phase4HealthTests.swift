import Foundation
import Testing
@testable import AppCore

// MARK: - Paced breathing

struct PacedBreathingTests {
    @Test func paceIsAboutSixBreathsAMinute() {
        // 5.5 s in + 5.5 s out (Laborde 2022; Zaccaro 2018 slow-breathing range).
        #expect(PacedBreathing.cycleSeconds == 11)
        #expect(abs(PacedBreathing.breathsPerMinute - 5.45) < 0.01)
        #expect(PacedBreathing.sessionSeconds == 300)
    }

    @Test func phasesAlternateAndScaleTurnsAround() {
        #expect(PacedBreathing.phase(at: 0).phase == .inhale)
        #expect(PacedBreathing.phase(at: 5.4).phase == .inhale)
        #expect(PacedBreathing.phase(at: 5.6).phase == .exhale)
        #expect(PacedBreathing.phase(at: 11).phase == .inhale)
        #expect(abs(PacedBreathing.phase(at: 2.75).progress - 0.5) < 1e-9)
        // Smallest at the start of a breath in, largest at the start of a breath out.
        #expect(abs(PacedBreathing.scale(at: 0) - 0.55) < 1e-9)
        #expect(abs(PacedBreathing.scale(at: 5.5) - 1.0) < 1e-9)
        #expect(abs(PacedBreathing.scale(at: 11) - 0.55) < 1e-9)
        #expect(PacedBreathing.scale(at: 2) > PacedBreathing.scale(at: 1))
        #expect(PacedBreathing.scale(at: 8) < PacedBreathing.scale(at: 7))
    }

    @Test func completionAndRemaining() {
        #expect(PacedBreathing.remaining(at: 100) == 200)
        #expect(PacedBreathing.remaining(at: 400) == 0)
        #expect(!PacedBreathing.isComplete(at: 299.9))
        #expect(PacedBreathing.isComplete(at: 300))
    }

    @Test func offeredOnEasyDaysAndStressfulEvenings() {
        #expect(PacedBreathing.isOffered(easyDay: true, eveningStress: nil))
        #expect(PacedBreathing.isOffered(easyDay: false, eveningStress: 4))
        #expect(PacedBreathing.isOffered(easyDay: false, eveningStress: 5))
        #expect(!PacedBreathing.isOffered(easyDay: false, eveningStress: 3))
        #expect(!PacedBreathing.isOffered(easyDay: false, eveningStress: nil))
    }

    @Test func heartRateAveragesOnlyInsideTheWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            HeartRateSample(date: start.addingTimeInterval(-90), bpm: 80),
            HeartRateSample(date: start.addingTimeInterval(-40), bpm: 62),
            HeartRateSample(date: start.addingTimeInterval(-10), bpm: 66),
        ]
        let window = DateInterval(start: start.addingTimeInterval(-60), end: start)
        #expect(PacedBreathing.averageHeartRate(samples, in: window) == 64)
        #expect(PacedBreathing.averageHeartRate([], in: window) == nil)
        #expect(PacedBreathing.heartRateText(before: 64, after: 58) == "Heart rate 64 → 58 bpm, down.")
        #expect(PacedBreathing.heartRateText(before: nil, after: nil).contains("No heart rate"))
        let session = BreathingSession(start: start, end: start.addingTimeInterval(300), heartRateBefore: 64, heartRateAfter: 58)
        #expect(session.minutes == 5)
        #expect(session.heartRateDrop == 6)
        #expect(PacedBreathing.evidenceNote.contains("Laborde 2022"))
    }
}

// MARK: - Movement breaks

struct MovementBreaksTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2027-01-04 at `hour`:`minute` UTC.
    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: hour, minute: minute))!
    }

    func hours(_ counts: [Int: Double]) -> [MovementBreaks.HourSteps] {
        counts.map { MovementBreaks.HourSteps(start: at($0.key), steps: $0.value) }
    }

    @Test func twoStillHoursTriggerABreak() {
        let steps = hours([9: 900, 10: 120, 11: 80, 12: 40])
        // At 12:30 the complete hours 10 and 11 were under 250 (hour 12 isn't over).
        #expect(MovementBreaks.assess(hourlySteps: steps, mealTimes: [], now: at(12, 30), calendar: utc) == .sedentary(hours: 2))
        // One still hour isn't enough.
        let oneHour = hours([9: 900, 10: 600, 11: 80])
        #expect(MovementBreaks.assess(hourlySteps: oneHour, mealTimes: [], now: at(12, 10), calendar: utc) == nil)
        // A walk resets the run.
        let walked = hours([9: 100, 10: 100, 11: 700])
        #expect(MovementBreaks.assess(hourlySteps: walked, mealTimes: [], now: at(12, 10), calendar: utc) == nil)
    }

    @Test func wakeAndQuietHoursBoundTheCheck() {
        let steps = hours([5: 0, 6: 0, 7: 0])
        // Hours before getting up don't count as sitting.
        #expect(MovementBreaks.assess(hourlySteps: steps, mealTimes: [], now: at(8, 5), wake: at(7), calendar: utc) == nil)
        // Default wake is 7:00, so 7 and 8 count at 9:05.
        let later = hours([7: 0, 8: 0])
        #expect(MovementBreaks.assess(hourlySteps: later, mealTimes: [], now: at(9, 5), calendar: utc) == .sedentary(hours: 2))
        // Nothing after 22:00.
        let evening = hours([20: 0, 21: 0])
        #expect(MovementBreaks.assess(hourlySteps: evening, mealTimes: [], now: at(22, 30), calendar: utc) == nil)
    }

    @Test func postMealWalkComesFirstAndNeedsAMealWithinTheWindow() {
        let meal = at(13)
        let steps = hours([7: 500, 8: 500, 9: 500, 10: 500, 11: 50, 12: 40, 13: 60])
        // 13:40, 40 minutes after eating, under 250 steps since: the walk nudge wins over the sitting one.
        #expect(MovementBreaks.assess(hourlySteps: steps, mealTimes: [meal], now: at(13, 40), calendar: utc) == .postMealWalk(meal: meal))
        // Walked already: no post-meal nudge, and the active hour 12 breaks the sitting run.
        let walked = hours([7: 500, 8: 500, 9: 500, 10: 500, 11: 500, 12: 400, 13: 600])
        #expect(MovementBreaks.assess(hourlySteps: walked, mealTimes: [meal], now: at(13, 40), calendar: utc) == nil)
        // Too long after the meal (Buffey 2022: within 60-90 min): back to the sitting rule (hours 11-13).
        #expect(MovementBreaks.assess(hourlySteps: steps, mealTimes: [meal], now: at(14, 30), calendar: utc) == .sedentary(hours: 3))
        // Hours with no step data count as still.
        let gaps = hours([7: 500, 8: 500, 9: 500])
        #expect(MovementBreaks.assess(hourlySteps: gaps, mealTimes: [], now: at(12, 5), calendar: utc) == .sedentary(hours: 2))
    }

    @Test func sedentaryBreaksFollowTheGoal() {
        #expect(MovementBreaks.sedentaryBreaksOn(goals: nil))
        #expect(MovementBreaks.sedentaryBreaksOn(goals: Goals(weight: .lose, focuses: [.muscle])))
        #expect(MovementBreaks.sedentaryBreaksOn(goals: Goals(weight: .maintain, focuses: [.health])))
        #expect(!MovementBreaks.sedentaryBreaksOn(goals: Goals(weight: .gain, focuses: [.muscle, .strength])))
        let steps = hours([10: 0, 11: 0])
        let lifter = Goals(weight: .maintain, focuses: [.strength])
        #expect(MovementBreaks.assess(hourlySteps: steps, mealTimes: [], now: at(12, 10), goals: lifter, calendar: utc) == nil)
        // The post-meal walk still applies to lifters.
        #expect(MovementBreaks.assess(hourlySteps: steps, mealTimes: [at(11, 30)], now: at(12, 10), goals: lifter, calendar: utc) == .postMealWalk(meal: at(11, 30)))
        #expect(MovementBreaks.postMealDetail.contains("Buffey 2022"))
    }
}

// MARK: - Strength for health

struct StrengthForHealthTests {
    @Test func bandsFollowTheCutPoints() {
        // Men, bench: Building from 0.6 ×, Good from 1.0 ×, Strong from 1.5 ×, Very strong from 1.9 × body weight at 40 or under.
        #expect(StrengthForHealth.band(ratio: 0.4, lift: .bench, sex: .male, age: 30) == .startingOut)
        #expect(StrengthForHealth.band(ratio: 0.75, lift: .bench, sex: .male, age: 30) == .building)
        #expect(StrengthForHealth.band(ratio: 1.1, lift: .bench, sex: .male, age: 30) == .good)
        #expect(StrengthForHealth.band(ratio: 1.5, lift: .bench, sex: .male, age: 30) == .strong)
        #expect(StrengthForHealth.band(ratio: 2.1, lift: .bench, sex: .male, age: 30) == .veryStrong)
        // Women's deadlift: 1.25 × is "good"; for a man that's still "building".
        #expect(StrengthForHealth.band(ratio: 1.3, lift: .deadlift, sex: .female, age: 28) == .good)
        #expect(StrengthForHealth.band(ratio: 1.3, lift: .deadlift, sex: .male, age: 28) == .building)
    }

    @Test func thresholdsEaseWithAge() {
        #expect(StrengthForHealth.ageFactor(25) == 1)
        #expect(StrengthForHealth.ageFactor(40) == 1)
        #expect(abs(StrengthForHealth.ageFactor(50) - 0.9) < 1e-9)
        #expect(abs(StrengthForHealth.ageFactor(80) - 0.7) < 1e-9)
        // A 1.2 × squat is "good" at 50 (cut 1.25 × 0.9 = 1.125) but "building" at 30 (cut 1.25).
        #expect(StrengthForHealth.band(ratio: 1.2, lift: .squat, sex: .male, age: 50) == .good)
        #expect(StrengthForHealth.band(ratio: 1.2, lift: .squat, sex: .male, age: 30) == .building)
    }

    @Test func recognisesTheBigLiftsOnly() {
        #expect(StrengthForHealth.lift(forExerciseName: "Barbell Bench Press - Medium Grip") == .bench)
        #expect(StrengthForHealth.lift(forExerciseName: "Bench Press - Powerlifting") == .bench)
        #expect(StrengthForHealth.lift(forExerciseName: "Barbell Incline Bench Press - Medium Grip") == nil)
        #expect(StrengthForHealth.lift(forExerciseName: "Dumbbell Bench Press") == nil)
        #expect(StrengthForHealth.lift(forExerciseName: "Barbell Squat") == .squat)
        #expect(StrengthForHealth.lift(forExerciseName: "Barbell Full Squat") == .squat)
        #expect(StrengthForHealth.lift(forExerciseName: "Barbell Hack Squat") == nil)
        #expect(StrengthForHealth.lift(forExerciseName: "Bodyweight Squat") == nil)
        #expect(StrengthForHealth.lift(forExerciseName: "Barbell Deadlift") == .deadlift)
        #expect(StrengthForHealth.lift(forExerciseName: "Romanian Deadlift") == nil)
        #expect(StrengthForHealth.lift(forExerciseName: "Deadlift with Bands") == nil)
        #expect(StrengthForHealth.lift(forExerciseName: "Bench Dips") == nil)
    }

    @Test func assessUsesTheBestLiftPerMovement() throws {
        let lifts: [(name: String, estimatedOneRepMaxKg: Double)] = [
            ("Barbell Bench Press - Medium Grip", 90), ("Bench Press - Powerlifting", 100),
            ("Barbell Deadlift", 160), ("Barbell Incline Bench Press - Medium Grip", 120),
        ]
        let results = StrengthForHealth.assess(lifts: lifts, bodyMassKg: 80, sex: .male, age: 35)
        #expect(results.map(\.lift) == [.bench, .deadlift])
        let bench = try #require(results.first { $0.lift == .bench })
        #expect(bench.estimatedOneRepMaxKg == 100)
        #expect(abs(bench.ratio - 1.25) < 1e-9)
        #expect(bench.band == .good)
        #expect(bench.nextThreshold == 1.5)
        let deadlift = try #require(results.first { $0.lift == .deadlift })
        #expect(deadlift.band == .strong)
        #expect(StrengthForHealth.assess(lifts: lifts, bodyMassKg: 0, sex: .male, age: 35).isEmpty)
        #expect(StrengthForHealth.evidenceNote.contains("app choice"))
        #expect(StrengthForHealth.evidenceNote.contains("García-Hermoso 2018"))
    }

    @Test func summaryFollowsTheGoal() {
        let lifts: [(name: String, estimatedOneRepMaxKg: Double)] = [("Barbell Bench Press - Medium Grip", 60), ("Barbell Deadlift", 170)]
        let results = StrengthForHealth.assess(lifts: lifts, bodyMassKg: 80, sex: .male, age: 35)
        let health = StrengthForHealth.summary(results, goals: Goals(weight: .maintain, focuses: [.health]))
        #expect(health.contains("Bench press below \"Good\""))
        let strength = StrengthForHealth.summary(results, goals: Goals(weight: .maintain, focuses: [.strength]))
        #expect(strength.contains("Bench press is the next one up"))
        #expect(strength.contains("Good from 1.00"))
        #expect(StrengthForHealth.summary([], goals: nil).contains("Log bench press"))
    }
}

// MARK: - Estimated intake

struct EstimatedIntakeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }

    @Test func estimateOnlyDaysBecomePartialDays() {
        var intake = (1...27).map { DayValue(date: day(-$0), value: 2200) }
        intake.append(DayValue(date: day(-28), value: 2300))
        let flagged: Set<Date> = [day(-3), day(-10)]
        let weighted = EstimatedIntake.downWeight(intake, estimatedOnlyDays: flagged)
        #expect(weighted.count == intake.count)
        #expect(weighted.first { $0.date == day(-3) }?.value == EstimatedIntake.partialMarkerKcal)
        #expect(weighted.first { $0.date == day(-5) }?.value == 2200)
        let weights = (0..<28).map { DayValue(date: day(-27 + $0), value: 85) }
        let progress = AdaptiveTDEE.progress(intake: weighted, weights: weights, now: now)
        #expect(progress.partialDays == 2)
        #expect(progress.fullyLoggedDays == 26)
        // Maintenance ignores the two estimated days rather than averaging 800 kcal in.
        let result = AdaptiveTDEE.estimate(intake: weighted, weights: weights, now: now)
        #expect(result?.partialDaysSkipped == 2)
        #expect((result?.maintenance ?? 0) > 2150)
    }

    @Test func mostlyEstimatedLogsAreDroppedNotMarked() {
        let intake = (1...10).map { DayValue(date: day(-$0), value: 2000) }
        let flagged = Set((1...6).map { day(-$0) })
        let weighted = EstimatedIntake.downWeight(intake, estimatedOnlyDays: flagged)
        #expect(weighted.count == 4)
        #expect(weighted.allSatisfy { $0.value == 2000 })
        #expect(EstimatedIntake.downWeight(intake, estimatedOnlyDays: []) == intake)
    }

    @Test func plausibilityAndRangeText() {
        let estimate = EstimatedIntake.Estimate(summary: "Chicken and rice", calories: 650, proteinGrams: 45, carbsGrams: 70, fatGrams: 15, fibreGrams: 4, confidence: "medium")
        #expect(estimate.isPlausible)
        #expect(estimate.calorieRangeText == "about 650 kcal (455-845)")
        let silly = EstimatedIntake.Estimate(summary: "", calories: 9000, proteinGrams: 10, carbsGrams: 10, fatGrams: 10, fibreGrams: 0, confidence: "low")
        #expect(!silly.isPlausible)
        #expect(EstimatedIntake.caveat.contains("±30%"))
    }
}
