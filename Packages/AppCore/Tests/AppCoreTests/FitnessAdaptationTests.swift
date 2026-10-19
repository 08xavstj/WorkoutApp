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
        #expect(StrainCalculator.targetStrain(forRecovery: 80, usualTrainingStrain: nil) == 65...85)
        #expect(StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: nil) == 45...65)
        #expect(StrainCalculator.targetStrain(forRecovery: 20, usualTrainingStrain: nil) == 20...45)
    }

    @Test func targetsRiseAsYourTrainingDaysGetHarder() {
        let beginner = StrainCalculator.targetStrain(forRecovery: 80, usualTrainingStrain: 40)
        let fitter = StrainCalculator.targetStrain(forRecovery: 80, usualTrainingStrain: 75)
        #expect(beginner == 40...60)
        #expect(fitter == 75...95)
    }

    @Test func usualStrainNeedsSixTrainingDays() {
        #expect(StrainCalculator.usualTrainingStrain([60, 62, 5, 70, 10]) == nil)
        // Rest days (under 25%) are left out.
        #expect(StrainCalculator.usualTrainingStrain([50, 55, 60, 65, 70, 75, 3, 8]) == 62.5)
    }
}

struct StepGoalTests {
    @Test func needsTwoWeeksOfData() {
        #expect(StepGoal.personal(dailySteps: [5000, 6000]) == 10_000)
    }

    @Test func growsWithYourHabit() {
        #expect(StepGoal.personal(dailySteps: Array(repeating: 7_200, count: 20)) == 8_000)
        #expect(StepGoal.personal(dailySteps: Array(repeating: 3_000, count: 20)) == 6_000)
        #expect(StepGoal.personal(dailySteps: Array(repeating: 15_000, count: 20)) == 12_000)
    }
}
