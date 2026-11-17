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
        // No "Low / Fair / Good" label any more (evidence audit M3): Cole 1999's
        // 12 bpm cut-off comes from symptom-limited clinical tests.
    }

    /// Profile reserve is 130 bpm (60 to 190): 80% of reserve = 164 bpm.
    @Test func onlySustainedHardEffortsAreMeasured() {
        let workoutStart = start
        let workout = DateInterval(start: workoutStart, duration: 20 * 60)
        // 15 easy minutes, 4 hard minutes (170), then the end at minute 20 and recovery.
        let hard = perMinute(Array(repeating: 130, count: 16) + [170, 172, 171, 170, 168, 140, 128], from: workoutStart)
        #expect(HeartRateRecovery.isSustainedHardEffort(hard, during: workout, profile: profile))
        let measured = HeartRateRecovery.measureHardEfforts(hard, workouts: [workout], lifting: [], profile: profile)
        #expect(measured.count == 1)
        #expect(measured.first?.result.oneMinuteDrop == 32)

        // Two hard minutes are not enough (3 needed).
        let brief = perMinute(Array(repeating: 130, count: 18) + [170, 168, 140, 128], from: workoutStart)
        #expect(!HeartRateRecovery.isSustainedHardEffort(brief, during: workout, profile: profile))
        #expect(HeartRateRecovery.measureHardEfforts(brief, workouts: [workout], lifting: [], profile: profile).isEmpty)
    }

    @Test func liftingIsNeverMeasuredEvenWhenHeartRateRunsHigh() {
        let workout = DateInterval(start: start, duration: 50 * 60)
        // A hard leg day: long stretches above 80% of reserve between sets.
        let samples = perMinute(Array(repeating: 168, count: 50) + [150, 140], from: start)
        let lifting = [DateInterval(start: start.addingTimeInterval(-60), duration: 52 * 60)]
        #expect(HeartRateRecovery.measureHardEfforts(samples, workouts: [workout], lifting: lifting, profile: profile).isEmpty)
        // The same heart rate on a run (no lifting window) counts.
        #expect(HeartRateRecovery.measureHardEfforts(samples, workouts: [workout], lifting: [], profile: profile).count == 1)
    }

    @Test func shortWorkoutsAreSkipped() {
        let workout = DateInterval(start: start, duration: 8 * 60)
        let samples = perMinute([170, 170, 170, 170, 170, 170, 170, 170, 172, 140, 130], from: start)
        #expect(HeartRateRecovery.measureHardEfforts(samples, workouts: [workout], lifting: [], profile: profile).isEmpty)
    }

    @Test func usualRangeIsTheMiddleHalfOfYourOwnValues() {
        #expect(HeartRateRecovery.usualRange([20, 22]) == nil)
        #expect(HeartRateRecovery.usualText([20, 22]) == "Your usual range shows after 1 more hard session")
        #expect(HeartRateRecovery.usualText([]) == "Your usual range shows after 3 more hard sessions")
        // 17, 18, 21, 24, 25: 25th percentile 18, 75th 24.
        #expect(HeartRateRecovery.usualRange([24, 17, 21, 25, 18]) == 18...24)
        #expect(HeartRateRecovery.usualText([24, 17, 21, 25, 18]) == "Your usual 18-24")
        #expect(HeartRateRecovery.usualText([20, 20, 20]) == "Your usual 20")
        #expect(HeartRateRecovery.clinicalNote.contains("maximal treadmill tests"))
    }

    /// Evidence audit M1: heart rate inside lifting windows isn't aerobic activity.
    @Test func intensityMinutesLeaveOutLifting() {
        // An hour at 120 bpm (moderate, 46% of reserve), the middle 50 minutes in a gym session.
        let samples = perMinute(Array(repeating: 120, count: 60), from: start)
        let lifting = [DateInterval(start: start.addingTimeInterval(5 * 60), duration: 50 * 60)]
        let all = IntensityMinutes.count(samples, profile: profile)
        let outside = IntensityMinutes.count(IntensityMinutes.outsideLifting(samples, lifting: lifting), profile: profile)
        #expect(all.moderate == 60)
        #expect(outside.moderate < 15)
        #expect(IntensityMinutes.outsideLifting(samples, lifting: []).count == 60)
        #expect(IntensityMinutes.title == "Cardio minutes (outside lifting)")
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
        #expect(StressEstimate.label(for: low.score) == "Near resting")
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
