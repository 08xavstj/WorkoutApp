import Foundation
import Testing
@testable import AppCore

/// A squash match on an Apple Watch with an Oura ring also writing heart
/// rate: the watch's readings, not the ring's and not per-minute averages,
/// carry the zones and the strain.
struct WorkoutHeartRateTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55, maxHeartRateOverride: 190)

    /// 40 minutes of squash every 5 s: 40 s rallies near 182 bpm, 20 s between at 150.
    var watchReadings: [HeartRateSample] {
        stride(from: 0.0, to: 40 * 60, by: 5).map { second in
            let inRally = second.truncatingRemainder(dividingBy: 60) < 40
            return HeartRateSample(date: start.addingTimeInterval(second), bpm: inRally ? 182 : 150)
        }
    }

    /// The ring: one smoothed reading a minute, steady and low.
    var ringReadings: [HeartRateSample] {
        stride(from: 0.0, to: 40 * 60, by: 60).map { HeartRateSample(date: start.addingTimeInterval($0), bpm: 128) }
    }

    var watch: HeartRateMerge.Source { HeartRateMerge.Source(name: "Apple Watch", samples: watchReadings, bundleID: "com.apple.health.ABC") }
    var ring: HeartRateMerge.Source { HeartRateMerge.Source(name: "Oura", samples: ringReadings, bundleID: "com.ouraring.oura") }
    var window: DateInterval { DateInterval(start: start, duration: 40 * 60) }

    @Test func theRingNeverWinsAMinuteTheWatchHas() {
        let merged = HeartRateMerge.merge(sources: [ring, watch], liftingWindows: [])
        #expect(Set(merged.chosenSource.values) == ["Apple Watch"])
        #expect(merged.samples.allSatisfy { $0.bpm > 128 })
    }

    @Test func theRingStillFillsMinutesNothingElseHas() {
        let later = HeartRateMerge.Source(name: "Oura", samples: [HeartRateSample(date: start.addingTimeInterval(3 * 3600), bpm: 70)],
                                          bundleID: "com.ouraring.oura")
        let merged = HeartRateMerge.merge(sources: [later, watch], liftingWindows: [])
        #expect(merged.chosenSource.values.contains("Oura"))
    }

    @Test func workoutReadingsComeFromTheWatch() throws {
        let readings = try #require(HeartRateMerge.workoutReadings(sources: [ring, watch], window: window))
        #expect(readings.count == watchReadings.count)
    }

    @Test func aSparseSeriesDoesNotReplaceTheMerge() {
        let sparse = HeartRateMerge.Source(name: "Garmin Connect", samples: Array(watchReadings.enumerated().filter { $0.offset % 24 == 0 }.map(\.element)))
        #expect(HeartRateMerge.workoutReadings(sources: [sparse], window: window) == nil)
    }

    @Test func everyReadingShowsZoneFiveThatMinuteAveragesHide() throws {
        let merged = HeartRateMerge.merge(sources: [ring, watch], liftingWindows: [])
        let readings = try #require(HeartRateMerge.workoutReadings(sources: [ring, watch], window: window))
        let detailed = HeartRateMerge.withWorkoutReadings(merged.samples, workouts: [(window: window, readings: readings)])
        let calculator = StrainCalculator()
        let averaged = calculator.dailyStrain(heartRate: merged.samples, strengthSessions: [], profile: profile, workouts: [window])
        let fine = calculator.dailyStrain(heartRate: detailed, strengthSessions: [], profile: profile, workouts: [window])
        // 182 bpm is 94% of reserve (zone 5); the minute average, 171, is 85% (zone 4).
        #expect(averaged.zoneMinutes[4] < 1)
        #expect(fine.zoneMinutes[4] > 20)
        #expect(fine.cardioLoad > averaged.cardioLoad)
    }

    @Test func readingsOutsideTheWorkoutStayMerged() {
        let before = HeartRateSample(date: start.addingTimeInterval(-600), bpm: 70)
        let result = HeartRateMerge.withWorkoutReadings([before], workouts: [(window: window, readings: watchReadings)])
        #expect(result.first == before)
        #expect(result.count == watchReadings.count + 1)
    }
}
