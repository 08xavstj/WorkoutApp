import Foundation
import Testing
@testable import AppCore

struct HeartHealthTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 60, maxHeartRateOverride: 190)

    func perMinute(_ values: [Double], from origin: Date) -> [HeartRateSample] {
        values.enumerated().map { HeartRateSample(date: origin.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element) }
    }

    @Test func recoveryMeasuresDropFromPeak() throws {
        let end = start.addingTimeInterval(600)
        // Minutes 8-12; the workout ends at minute 10, at the peak.
        let samples = perMinute([150, 160, 165, 140, 125], from: start.addingTimeInterval(480))
        let result = try #require(HeartRateRecovery.measure(samples, workoutEnd: end))
        #expect(result.peak == 165)
        #expect(result.oneMinuteDrop == 25)
        #expect(result.twoMinuteDrop == 40)
        #expect(HeartRateRecovery.label(oneMinuteDrop: 25) == "Good")
    }

    @Test func recoveryNeedsDataAfterTheWorkout() {
        let end = start.addingTimeInterval(600)
        let samples = perMinute([150, 160, 165], from: start.addingTimeInterval(480))
        #expect(HeartRateRecovery.measure(samples, workoutEnd: end) == nil)
    }

    @Test func stressIsLowAtRestAndHigherWhenElevated() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 9))!
        let calm = perMinute(Array(repeating: 62, count: 60), from: morning)
        let tense = perMinute(Array(repeating: 100, count: 60), from: morning)
        let low = try #require(StressEstimate.estimate(calm, profile: profile, calendar: calendar))
        let high = try #require(StressEstimate.estimate(tense, profile: profile, calendar: calendar))
        #expect(low.score < 26)
        #expect(high.score > 75)
        #expect(StressEstimate.label(for: low.score) == "Resting")
    }

    @Test func stressSkipsWorkoutsAndNight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let night = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 2))!
        let samples = perMinute(Array(repeating: 100, count: 60), from: night)
        #expect(StressEstimate.estimate(samples, profile: profile, calendar: calendar) == nil)
    }

    @Test func intensityMinutesCountVigorousDouble() {
        // Reserve is 130 bpm: 40 % = 112, 60 % = 138.
        let samples = perMinute([100, 115, 120, 140, 150], from: start)
        let result = IntensityMinutes.count(samples, profile: profile)
        #expect(result.moderate == 2)
        #expect(result.vigorous == 2)
        #expect(result.total == 6)
    }

    @Test func sparseReadingsStillCountTheTimeBetweenThem() {
        // A watch sampling every 2 minutes for 30 minutes of brisk exercise.
        let samples = (0..<15).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 120), bpm: 125) }
        let result = IntensityMinutes.count(samples, profile: profile)
        #expect(result.moderate == 29)
    }

    @Test func longGapsDontCountAsExercise() {
        let samples = [HeartRateSample(date: start, bpm: 125), HeartRateSample(date: start.addingTimeInterval(3600), bpm: 125)]
        #expect(IntensityMinutes.count(samples, profile: profile).moderate == 2)
    }

    @Test func sleepingHeartRateUsesOnlyAsleepTime() throws {
        let values: [Double] = [70, 70] + Array(repeating: 52, count: 10) + [48, 48, 48, 48, 48] + [80, 80]
        let samples = perMinute(values, from: start)
        let sleep = [SleepSample(stage: .core, start: start.addingTimeInterval(120), end: start.addingTimeInterval(17 * 60 - 1))]
        let result = try #require(SleepingHeartRate.measure(samples, during: sleep))
        #expect(result.lowest == 48)
        #expect(result.average < 52)
        #expect(result.average > 48)
    }
}
