import Foundation
import Testing
@testable import AppCore

struct StrainCalculatorTests {
    let calculator = StrainCalculator()
    let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55)
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// One sample per minute at a steady heart rate.
    func steady(bpm: Double, minutes: Int, from start: Date) -> [HeartRateSample] {
        (0...minutes).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: bpm) }
    }

    /// Heart rate at a given fraction of reserve for `profile`.
    func bpm(atReserve fraction: Double) -> Double {
        profile.restingHeartRate + fraction * (profile.maxHeartRate - profile.restingHeartRate)
    }

    @Test func noDataMeansZeroStrain() {
        let result = calculator.dailyStrain(heartRate: [], strengthSessions: [], profile: profile)
        #expect(result.strain == 0)
        #expect(result.totalLoad == 0)
    }

    @Test func restingHeartRateAddsNoLoad() {
        let samples = steady(bpm: 58, minutes: 600, from: start)
        let result = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect(result.strain == 0)
    }

    @Test func moderateHourRunIsAroundSixtyPercent() {
        let samples = steady(bpm: bpm(atReserve: 0.75), minutes: 60, from: start)
        let result = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect((57...67).contains(result.strain))
        #expect(result.liftingLoad == 0)
    }

    @Test func strainNeverExceedsOneHundred() {
        #expect(calculator.strain(forLoad: 10_000) <= 100)
        #expect(calculator.strain(forLoad: 300) < 100)
    }

    @Test func strainCurveFlattensAtTheTop() {
        let lowStep = calculator.load(forStrain: 43) - calculator.load(forStrain: 38)
        let highStep = calculator.load(forStrain: 90) - calculator.load(forStrain: 85)
        #expect(highStep > lowStep * 3)
    }

    @Test func liftingCountsEvenWithLowHeartRate() {
        // An hour in the gym with heart rate barely above resting.
        let samples = steady(bpm: 80, minutes: 60, from: start)
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(3600), sessionRPE: 8)
        let result = calculator.dailyStrain(heartRate: samples, strengthSessions: [session], profile: profile)
        #expect(result.liftingLoad == calculator.rpeLoad(for: session))
        #expect(result.cardioLoad == 0)
        // 480 sRPE units x 0.33 ≈ 158 TRIMP ≈ 72%.
        #expect((66...77).contains(result.strain))
    }

    @Test func liftingAndCardioThatFeelEquallyHardCountAboutTheSame() {
        // An hour of cardio at 75% of reserve feels "hard" (CR-10 ~6); an hour
        // of lifting rated 6 should carry about the same load (sRPE is meant
        // to compare across exercise modes).
        let run = calculator.dailyStrain(heartRate: steady(bpm: bpm(atReserve: 0.75), minutes: 60, from: start), strengthSessions: [], profile: profile)
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(3600), sessionRPE: 6)
        let lift = calculator.rpeLoad(for: session)
        #expect(abs(lift - run.totalLoad) / run.totalLoad < 0.15)
    }

    @Test func gymHeartRateIsNotCountedTwice() {
        // Hard circuit session: heart-rate load beats RPE load, and must replace it, not add to it.
        let samples = steady(bpm: bpm(atReserve: 0.85), minutes: 60, from: start)
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(3600), sessionRPE: 3)
        let withSession = calculator.dailyStrain(heartRate: samples, strengthSessions: [session], profile: profile)
        let withoutSession = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect(abs(withSession.totalLoad - withoutSession.totalLoad) < 0.001)
    }

    @Test func setRPEsDontStandInForSessionRPE() {
        let end = start.addingTimeInterval(3600)
        let fromSets = StrengthSessionSummary(start: start, end: end, setRPEs: [7, 9])
        let fromDefault = StrengthSessionSummary(start: start, end: end)
        #expect(calculator.rpeLoad(for: fromSets) == calculator.defaultRPE * 60 * calculator.rpeToTrimp)
        #expect(calculator.rpeLoad(for: fromDefault) == calculator.defaultRPE * 60 * calculator.rpeToTrimp)
    }

    @Test func longGapsAreIgnored() {
        let samples = [
            HeartRateSample(date: start, bpm: bpm(atReserve: 0.8)),
            HeartRateSample(date: start.addingTimeInterval(3 * 3600), bpm: bpm(atReserve: 0.8))
        ]
        let result = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect(result.totalLoad == 0)
    }

    @Test func zoneMinutesAddUp() {
        let samples = steady(bpm: bpm(atReserve: 0.75), minutes: 30, from: start)
        let result = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect(abs(result.zoneMinutes[2] - 30) < 0.001)
        #expect(result.zoneMinutes.reduce(0, +) - 30 < 0.001)
    }

    @Test(arguments: [(10, 20.0...45.0), (50, 50.0...70.0), (90, 50.0...70.0)])
    func targetStrainFollowsRecovery(recovery: Int, expected: ClosedRange<Double>) {
        #expect(StrainCalculator.targetStrain(forRecovery: recovery) == expected)
    }

    @Test func maxHeartRateOverrideIsUsed() {
        let custom = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55, maxHeartRateOverride: 200)
        #expect(custom.maxHeartRate == 200)
        #expect(profile.maxHeartRate == 187)
    }

    @Test func everydayLivingAddsLittleStrain() {
        // Eight hours at 25% of reserve (standing, pottering about).
        let samples = steady(bpm: bpm(atReserve: 0.25), minutes: 8 * 60, from: start)
        let result = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect(result.strain == 0)
    }

    @Test func briskWalkIsLight() {
        let samples = steady(bpm: bpm(atReserve: 0.35), minutes: 60, from: start)
        let result = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect((10...30).contains(result.strain))
    }

    @Test func sparseReadingsDontFillLongGaps() {
        // One reading every 8 minutes: each counts for at most 2 minutes.
        let sparse = (0..<10).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 480), bpm: bpm(atReserve: 0.6)) }
        let dense = steady(bpm: bpm(atReserve: 0.6), minutes: 19, from: start)
        let sparseLoad = calculator.dailyStrain(heartRate: sparse, strengthSessions: [], profile: profile).totalLoad
        let denseLoad = calculator.dailyStrain(heartRate: dense, strengthSessions: [], profile: profile).totalLoad
        #expect(sparseLoad < denseLoad * 1.05)
    }

    /// Start times of consecutive one-minute Apple Watch exercise minutes.
    func exerciseMinutes(_ count: Int, from start: Date) -> [Date] {
        (0..<count).map { start.addingTimeInterval(Double($0) * 60) }
    }

    @Test func exerciseMinutesWithoutHeartRateAddLightStrain() {
        // 12 brisk minutes with no heart-rate readings: credited at 40% of
        // reserve, a few percent (a 60-minute brisk walk is about 20%).
        let result = calculator.dailyStrain(heartRate: [], strengthSessions: [], profile: profile,
                                            movementMinutes: exerciseMinutes(12, from: start))
        #expect(result.movementMinutes == 12)
        #expect((3...7).contains(result.strain))
        #expect(result.cardioLoad == result.totalLoad)
    }

    @Test func exerciseMinutesWithoutHeartRateAddNoZoneMinutes() {
        // Zone minutes come from heart rate only: a day credited from Apple
        // Watch exercise minutes (and a rated gym session) has strain but no
        // time in zones. The app says so instead of showing an empty chart.
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(45 * 60), sessionRPE: 7)
        let result = calculator.dailyStrain(heartRate: [], strengthSessions: [session], profile: profile,
                                            movementMinutes: exerciseMinutes(30, from: start.addingTimeInterval(3 * 3600)))
        #expect(result.strain > 0)
        #expect(result.movementMinutes == 30)
        #expect(result.zoneMinutes == [0, 0, 0, 0, 0])
    }

    @Test func exerciseMinutesCoveredByHeartRateAreNotCountedTwice() {
        let heartRate = steady(bpm: bpm(atReserve: 0.6), minutes: 30, from: start)
        let alone = calculator.dailyStrain(heartRate: heartRate, strengthSessions: [], profile: profile)
        let both = calculator.dailyStrain(heartRate: heartRate, strengthSessions: [], profile: profile,
                                          movementMinutes: exerciseMinutes(30, from: start))
        #expect(both.movementMinutes == 0)
        #expect(abs(both.totalLoad - alone.totalLoad) < 0.0001)
    }

    @Test func exerciseMinutesFillOnlyTheGapsHeartRateMissed() {
        // Readings every 5 minutes (the watch outside workouts): each covers
        // 2 minutes, so 3 of every 5 exercise minutes are credited.
        let sparse = (0..<5).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 300), bpm: bpm(atReserve: 0.5)) }
        let result = calculator.dailyStrain(heartRate: sparse, strengthSessions: [], profile: profile,
                                            movementMinutes: exerciseMinutes(20, from: start))
        #expect(result.movementMinutes == 12)
    }

    @Test func exerciseMinutesDuringAGymSessionAddNothing() {
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(3600), sessionRPE: 7)
        let withSession = calculator.dailyStrain(heartRate: [], strengthSessions: [session], profile: profile)
        let withMinutes = calculator.dailyStrain(heartRate: [], strengthSessions: [session], profile: profile,
                                                 movementMinutes: exerciseMinutes(40, from: start))
        #expect(withMinutes.movementMinutes == 0)
        #expect(withMinutes.totalLoad == withSession.totalLoad)
    }

    @Test func repeatedExerciseMinutesCountOnce() {
        let minutes = exerciseMinutes(5, from: start)
        let result = calculator.dailyStrain(heartRate: [], strengthSessions: [], profile: profile,
                                            movementMinutes: minutes + minutes)
        #expect(result.movementMinutes == 5)
    }
}

struct RPEScaleTests {
    @Test func describesRepsLeft() {
        // Changed on purpose: reps left lead, RPE is the secondary label.
        #expect(RPEScale.summary(8) == "2 reps left · RPE 8")
        #expect(RPEScale.summary(9) == "1 rep left · RPE 9")
        #expect(RPEScale.level(for: 6.5)?.rpe == 6 || RPEScale.level(for: 6.5)?.rpe == 7)
        // Foster's CR-10 anchors (Foster et al. 2001): 3 moderate, 5 hard, 7 very hard.
        #expect(RPEScale.sessionLabel(3) == "Moderate")
        #expect(RPEScale.sessionLabel(5) == "Hard")
        #expect(RPEScale.sessionLabel(7) == "Very hard")
        #expect(RPEScale.sessionLabel(8) == "Very hard")
        #expect(RPEScale.sessionLabel(10) == "Maximal")
    }
}
