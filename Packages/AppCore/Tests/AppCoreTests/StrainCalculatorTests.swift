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
        #expect((57...69).contains(result.strain))
    }

    @Test func gymHeartRateIsNotCountedTwice() {
        // Hard circuit session: heart-rate load beats RPE load, and must replace it, not add to it.
        let samples = steady(bpm: bpm(atReserve: 0.85), minutes: 60, from: start)
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(3600), sessionRPE: 3)
        let withSession = calculator.dailyStrain(heartRate: samples, strengthSessions: [session], profile: profile)
        let withoutSession = calculator.dailyStrain(heartRate: samples, strengthSessions: [], profile: profile)
        #expect(abs(withSession.totalLoad - withoutSession.totalLoad) < 0.001)
    }

    @Test func rpeFallsBackToSetAverageThenDefault() {
        let end = start.addingTimeInterval(3600)
        let fromSets = StrengthSessionSummary(start: start, end: end, setRPEs: [7, 9])
        let fromDefault = StrengthSessionSummary(start: start, end: end)
        #expect(calculator.rpeLoad(for: fromSets) == 8 * 60 * calculator.rpeToTrimp)
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

    @Test(arguments: [(10, 20.0...45.0), (50, 45.0...65.0), (90, 65.0...85.0)])
    func targetStrainFollowsRecovery(recovery: Int, expected: ClosedRange<Double>) {
        #expect(StrainCalculator.targetStrain(forRecovery: recovery) == expected)
    }

    @Test func maxHeartRateOverrideIsUsed() {
        let custom = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55, maxHeartRateOverride: 200)
        #expect(custom.maxHeartRate == 200)
        #expect(profile.maxHeartRate == 187)
    }
}
