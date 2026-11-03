import Foundation
import Testing
@testable import AppCore

struct ObservedMaxHeartRateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ bpms: [Double]) -> [HeartRateSample] {
        bpms.enumerated().map { HeartRateSample(date: start.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element) }
    }

    @Test func ignoresShortSpikes() {
        #expect(ObservedMaxHeartRate.peak(minutes([150, 210, 208, 152, 155, 153])) == 152)
    }

    @Test func sustainedPeakCounts() {
        #expect(ObservedMaxHeartRate.peak(minutes([170, 188, 191, 189, 175])) == 188)
    }

    @Test func implausiblePeaksAreIgnored() {
        #expect(ObservedMaxHeartRate.plausible(200, estimate: 187) == 200)
        #expect(ObservedMaxHeartRate.plausible(205, estimate: 187) == nil)
    }

    @Test func keepsTheHigherPeakAndExpiresAfterAYear() {
        let stored = ObservedMaxHeartRate.Learned(bpm: 192, date: start)
        #expect(ObservedMaxHeartRate.update(stored, peak: 185, at: start.addingTimeInterval(86_400))?.bpm == 192)
        #expect(ObservedMaxHeartRate.update(stored, peak: 195, at: start.addingTimeInterval(86_400))?.bpm == 195)
        let later = start.addingTimeInterval(400 * 86_400)
        #expect(ObservedMaxHeartRate.update(stored, peak: 180, at: later)?.bpm == 180)
    }

    @Test func onlyOverridesWhenAboveTheEstimate() {
        let learned = ObservedMaxHeartRate.Learned(bpm: 195, date: start)
        #expect(ObservedMaxHeartRate.override(learned: learned, estimate: 187, now: start) == 195)
        #expect(ObservedMaxHeartRate.override(learned: learned, estimate: 198, now: start) == nil)
    }
}

struct AdaptiveTargetTests {
    @Test func defaultMatchesTheFixedBands() {
        // HRV-guided: normal or high recovery trains as planned; low goes easy.
        #expect(StrainCalculator.targetStrain(forRecovery: 80, usualTrainingStrain: nil) == 50...70)
        #expect(StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: nil) == 50...70)
        #expect(StrainCalculator.targetStrain(forRecovery: 20, usualTrainingStrain: nil) == 20...45)
    }

    @Test func targetsRiseAsYourTrainingDaysGetHarder() {
        let beginner = StrainCalculator.targetStrain(forRecovery: 80, usualTrainingStrain: 40)
        let fitter = StrainCalculator.targetStrain(forRecovery: 80, usualTrainingStrain: 75)
        #expect(beginner == 25...45)
        #expect(fitter == 60...80)
    }

    @Test func usualStrainNeedsSixTrainingDays() {
        #expect(StrainCalculator.usualTrainingStrain([60, 62, 5, 70, 10]) == nil)
        // Rest days (under 25%) are left out.
        #expect(StrainCalculator.usualTrainingStrain([50, 55, 60, 65, 70, 75, 3, 8]) == 62.5)
    }
}

struct StepGoalTests {
    @Test func startsByAgeUntilTwoWeeksOfData() {
        #expect(StepGoal.personal(dailySteps: [5000, 6000], age: 30) == 8_000)
        #expect(StepGoal.personal(dailySteps: [5000, 6000], age: 65) == 7_000)
    }

    @Test func growsWithYourHabitFromASevenThousandFloor() {
        #expect(StepGoal.personal(dailySteps: Array(repeating: 7_200, count: 20)) == 8_000)
        #expect(StepGoal.personal(dailySteps: Array(repeating: 3_000, count: 20)) == 7_000)
        #expect(StepGoal.personal(dailySteps: Array(repeating: 15_000, count: 20)) == 12_000)
    }
}

struct CardioFitnessNormTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }

    @Test func normFollowsTheLoeDeclineLine() {
        // Loe 2013: 54.4 at 25 for men, falling 0.40 a year.
        #expect(abs(CardioFitness.norm(age: 25, sex: .male) - 54.4) < 0.001)
        #expect(abs(CardioFitness.norm(age: 35, sex: .male) - 50.4) < 0.001)
        #expect(abs(CardioFitness.norm(age: 45, sex: .female) - 37.0) < 0.001)
        #expect(CardioFitness.norm(age: 120, sex: .male) == 15)
    }

    @Test func fitnessAgeIsTheAgeWithYourAverage() {
        #expect(CardioFitness.fitnessAge(vo2Max: 54.4, sex: .male) == 25)
        #expect(CardioFitness.fitnessAge(vo2Max: 50.4, sex: .male) == 35)
        #expect(CardioFitness.fitnessAge(vo2Max: 43.0, sex: .female) == 25)
        // Clamped at both ends.
        #expect(CardioFitness.fitnessAge(vo2Max: 70, sex: .male) == 18)
        #expect(CardioFitness.fitnessAge(vo2Max: 10, sex: .female) == 90)
    }

    private func series(early: Double?, late: Double?) -> [DayValue] {
        var points: [DayValue] = []
        if let early { points += (-85...(-65)).map { DayValue(date: day($0), value: early) } }
        if let late { points += (-20...0).map { DayValue(date: day($0), value: late) } }
        return points
    }

    @Test func ninetyDayTrendDirections() throws {
        let flat = try #require(CardioFitness.trend(series(early: 45, late: 45.2), now: now))
        #expect(flat.direction == .flat)
        #expect(CardioFitness.nudge(for: flat) != nil)
        let rising = try #require(CardioFitness.trend(series(early: 45, late: 46), now: now))
        #expect(rising.direction == .rising)
        #expect(abs((rising.change ?? 0) - 1) < 0.001)
        #expect(CardioFitness.nudge(for: rising) == nil)
        let falling = try #require(CardioFitness.trend(series(early: 45, late: 44), now: now))
        #expect(falling.direction == .falling)
        #expect(CardioFitness.nudge(for: falling) != nil)
    }

    @Test func trendNeedsBothEndsOfTheWindow() throws {
        let onlyRecent = try #require(CardioFitness.trend(series(early: nil, late: 45), now: now))
        #expect(onlyRecent.direction == .unknown)
        #expect(onlyRecent.change == nil)
        #expect(onlyRecent.latest == 45)
        #expect(CardioFitness.nudge(for: onlyRecent) == nil)
        #expect(CardioFitness.trend([], now: now) == nil)
        // Readings older than 90 days are ignored.
        let old = [DayValue(date: day(-120), value: 40)]
        #expect(CardioFitness.trend(old, now: now) == nil)
    }
}

struct WeeklyActivityBandTests {
    @Test func emphasisFollowsTheGoal() {
        #expect(WeeklyActivityBand.emphasis(for: Goals(weight: .maintain, focuses: [.health])) == .primary)
        #expect(WeeklyActivityBand.emphasis(for: Goals(weight: .gain, focuses: [.endurance])) == .primary)
        #expect(WeeklyActivityBand.emphasis(for: Goals(weight: .lose, focuses: [.muscle])) == .primary)
        #expect(WeeklyActivityBand.emphasis(for: Goals(weight: .gain, focuses: [.muscle, .strength])) == .secondary)
        #expect(WeeklyActivityBand.emphasis(for: nil) == .primary)
        #expect(WeeklyActivityBand.target(for: Goals(weight: .maintain, focuses: [.strength])) == 150)
        #expect(WeeklyActivityBand.target(for: Goals(weight: .maintain, focuses: [.health])) == 300)
    }

    @Test func bandEdges() {
        // WHO floor 150, Lee 2022's lowest-risk band from 300.
        #expect(WeeklyActivityBand.status(total: 149) == .belowFloor)
        #expect(WeeklyActivityBand.status(total: 150) == .inBand)
        #expect(WeeklyActivityBand.status(total: 299) == .inBand)
        #expect(WeeklyActivityBand.status(total: 300) == .atBest)
        #expect(WeeklyActivityBand.line(total: 90, goals: nil).hasPrefix("90 of the 150-minute"))
    }
}

struct StrengthHealthFloorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func session(daysAgo: Int, minutes: Double) -> StrengthSessionSummary {
        let start = now.addingTimeInterval(-Double(daysAgo) * 86_400 - minutes * 60)
        return StrengthSessionSummary(start: start, end: start.addingTimeInterval(minutes * 60), workingSets: 10)
    }

    @Test func twoShortSessionsMeetTheFloor() {
        // Momma 2022: 2+ days and 30+ min a week.
        let result = StrengthHealthFloor.assess([session(daysAgo: 1, minutes: 20), session(daysAgo: 3, minutes: 20)], now: now)
        #expect(result.days == 2)
        #expect(result.minutes == 40)
        #expect(result.isMet)
        #expect(result.summary == "Met this week: 2 days, 40 min")
    }

    @Test func oneLongSessionDoesNot() {
        let result = StrengthHealthFloor.assess([session(daysAgo: 2, minutes: 90)], now: now)
        #expect(result.days == 1)
        #expect(!result.isMet)
        #expect(result.summary == "Not yet this week: 1 day, 90 min")
    }

    @Test func twoTinySessionsDoNot() {
        let result = StrengthHealthFloor.assess([session(daysAgo: 1, minutes: 10), session(daysAgo: 4, minutes: 10)], now: now)
        #expect(result.days == 2)
        #expect(!result.isMet)
    }

    @Test func oldAndRunawaySessionsAreBounded() {
        let result = StrengthHealthFloor.assess([session(daysAgo: 8, minutes: 60), session(daysAgo: 1, minutes: 400)], now: now)
        #expect(result.days == 1)
        #expect(result.minutes == 180)
    }
}
