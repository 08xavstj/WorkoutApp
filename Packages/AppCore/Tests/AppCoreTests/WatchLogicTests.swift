import Foundation
import Testing
@testable import AppCore

/// The Watch redesign's pure logic: the crown's load steps, laps and pace,
/// rest cues, and the heart-rate series behind the small charts.
struct LoadStepperTests {
    @Test func stepsThroughTheGymsLoadsOnly() {
        let stepper = LoadStepper(achievableKg: [60, 62.5, 65, 67.5, 70], weightKg: 65, stepKg: 2.5)
        #expect(stepper.step(from: 65, by: 1) == 67.5)
        #expect(stepper.step(from: 65, by: -2) == 60)
        // Held at the ends rather than wrapping.
        #expect(stepper.step(from: 70, by: 3) == 70)
        #expect(stepper.step(from: 60, by: -1) == 60)
    }

    @Test func aTypedInWeightIsKeptSoTheCrownStartsOnIt() {
        let stepper = LoadStepper(achievableKg: [60, 62.5, 65], weightKg: 61, stepKg: 2.5)
        #expect(stepper.loads == [60, 61, 62.5, 65])
        #expect(stepper.loads[stepper.nearestIndex(to: 61)] == 61)
    }

    @Test func fallsBackToTheSmallestJumpWithoutALoadList() {
        let stepper = LoadStepper(achievableKg: nil, weightKg: 40, stepKg: 2.5)
        #expect(stepper.loads.first == 0)
        #expect(stepper.loads.last == 90)
        #expect(stepper.step(from: 40, by: 1) == 42.5)
        // Never below zero.
        #expect(stepper.loads.allSatisfy { $0 >= 0 })
    }

    @Test func nearestIndexPicksTheClosestLoad() {
        let stepper = LoadStepper(achievableKg: [20, 30, 40], weightKg: 30, stepKg: 5)
        #expect(stepper.nearestIndex(to: 34) == 1)
        #expect(stepper.nearestIndex(to: 36) == 2)
        #expect(stepper.load(atCrown: 1.4) == 30)
        #expect(stepper.load(atCrown: 99) == 40)
    }

    @Test func repsStayBetweenZeroAndFifty() {
        #expect(LoadStepper.reps(8, by: -2) == 6)
        #expect(LoadStepper.reps(1, by: -3) == 0)
        #expect(LoadStepper.reps(49, by: 5) == 50)
    }

    @Test(arguments: [(32, 1, 35), (30, 1, 35), (32, -1, 30), (30, -1, 25), (30, -2, 20), (0, -1, 0), (3, -1, 0)])
    func holdSecondsSnapToFiveSecondSteps(start: Int, steps: Int, expected: Int) {
        #expect(LoadStepper.holdSeconds(start, by: steps) == expected)
    }
}

struct LapTrackerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Runs at `speed` m/s, a sample every `step` seconds, from `from` to `to` seconds.
    func run(_ tracker: inout LapTracker, from: Double, to: Double, speed: Double, step: Double = 5,
             startMeters: Double = 0) -> [LapTracker.Lap] {
        var laps: [LapTracker.Lap] = []
        var seconds = from
        while seconds <= to {
            laps += tracker.add(meters: startMeters + (seconds - from) * speed, at: start.addingTimeInterval(seconds))
            seconds += step
        }
        return laps
    }

    @Test func autoLapsAtEachKilometreWithInterpolatedTimes() {
        var tracker = LapTracker(start: start, autoLapMeters: LapTracker.autoLapMeters(miles: false))
        // 4 m/s for 600 s: 2.4 km, so two auto laps at 250 s and 500 s.
        let laps = run(&tracker, from: 0, to: 600, speed: 4, step: 7)
        #expect(laps.count == 2)
        #expect(laps.map(\.number) == [1, 2])
        #expect(abs(laps[0].seconds - 250) < 0.01)
        #expect(abs(laps[0].meters - 1000) < 0.01)
        #expect(abs(laps[1].seconds - 250) < 0.01)
        #expect(laps.allSatisfy { $0.isAuto })
        #expect(abs((laps[0].pace(miles: false) ?? 0) - 250) < 0.01)
    }

    @Test func milesLapEveryMile() {
        var tracker = LapTracker(start: start, autoLapMeters: LapTracker.autoLapMeters(miles: true))
        let laps = run(&tracker, from: 0, to: 900, speed: 4)
        #expect(laps.count == 2)
        #expect(abs(laps[0].meters - LapTracker.metersPerMile) < 0.01)
    }

    @Test func aManualLapClosesTheLapNow() throws {
        var tracker = LapTracker(start: start, autoLapMeters: nil)
        _ = run(&tracker, from: 0, to: 300, speed: 3)
        let marked = tracker.markLap(at: start.addingTimeInterval(300))
        let lap = try #require(marked)
        #expect(lap.number == 1)
        #expect(!lap.isAuto)
        #expect(abs(lap.meters - 900) < 0.01)
        #expect(tracker.currentLapNumber == 2)
        // A second tap straight away has no time in it.
        let again = tracker.markLap(at: start.addingTimeInterval(300.5))
        #expect(again == nil)
    }

    @Test func pausesCountTowardNoLapOrPace() throws {
        var tracker = LapTracker(start: start, autoLapMeters: nil)
        _ = run(&tracker, from: 0, to: 100, speed: 3)
        tracker.pause(at: start.addingTimeInterval(100))
        #expect(tracker.currentSpeed(at: start.addingTimeInterval(130)) == nil)
        tracker.resume(at: start.addingTimeInterval(160))
        _ = run(&tracker, from: 165, to: 200, speed: 3, startMeters: 300)
        let marked = tracker.markLap(at: start.addingTimeInterval(200))
        let lap = try #require(marked)
        // 200 s on the clock, 60 of them paused.
        #expect(abs(lap.seconds - 140) < 0.01)
        #expect(abs(tracker.activeSeconds(at: start.addingTimeInterval(200)) - 140) < 0.01)
    }

    @Test func currentPaceFollowsTheLastTwentySeconds() throws {
        var tracker = LapTracker(start: start, autoLapMeters: nil)
        _ = run(&tracker, from: 0, to: 120, speed: 2.5)
        _ = run(&tracker, from: 125, to: 180, speed: 4, startMeters: 300 + 12.5)
        let pace = try #require(tracker.currentPace(at: start.addingTimeInterval(180), miles: false))
        // 4 m/s is 250 s per km.
        #expect(abs(pace - 250) < 1)
        // Standing still for longer than the window: no pace.
        #expect(tracker.currentPace(at: start.addingTimeInterval(240), miles: false) == nil)
    }

    @Test func fastestLapIsTheQuickestPerMetre() {
        var tracker = LapTracker(start: start, autoLapMeters: 1000)
        _ = run(&tracker, from: 0, to: 250, speed: 4, step: 5)
        _ = run(&tracker, from: 255, to: 500, speed: 5, step: 5, startMeters: 1020)
        #expect(tracker.laps.count == 2)
        #expect(tracker.fastestLapNumber == 2)
    }
}

struct RestCuesTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func warnsTenSecondsBeforeTheEnd() {
        let end = now.addingTimeInterval(90)
        let cues = RestCues.schedule(endsAt: end, startedAt: now, now: now)
        #expect(cues.map(\.cue) == [.warning, .end])
        #expect(cues[0].at == now.addingTimeInterval(80))
        #expect(cues[1].at == end)
    }

    @Test func aShortRestHasNoWarning() {
        let cues = RestCues.schedule(endsAt: now.addingTimeInterval(15), startedAt: now, now: now)
        #expect(cues.map(\.cue) == [.end])
    }

    @Test func aWarningAlreadyPastIsSkipped() {
        let started = now.addingTimeInterval(-85)
        let cues = RestCues.schedule(endsAt: now.addingTimeInterval(5), startedAt: started, now: now)
        #expect(cues.map(\.cue) == [.end])
        #expect(RestCues.schedule(endsAt: now.addingTimeInterval(-1), startedAt: started, now: now).isEmpty)
    }

    @Test func minusFifteenNeverGoesBelowZero() {
        let end = now.addingTimeInterval(10)
        #expect(RestCues.adjusted(endsAt: end, by: -15, now: now) == nil)
        #expect(RestCues.adjusted(endsAt: end, by: 15, now: now) == now.addingTimeInterval(25))
        #expect(RestCues.adjusted(endsAt: now.addingTimeInterval(60), by: -15, now: now) == now.addingTimeInterval(45))
    }

    @Test func ringLengthNeverDropsUnderWhatIsLeft() {
        #expect(RestCues.adjustedLength(90, by: 15, remaining: 50) == 105)
        #expect(RestCues.adjustedLength(90, by: -15, remaining: 80) == 80)
        #expect(RestCues.fractionLeft(endsAt: now.addingTimeInterval(45), length: 90, now: now) == 0.5)
        #expect(RestCues.fractionLeft(endsAt: now.addingTimeInterval(-5), length: 90, now: now) == 0)
    }

    @Test func standaloneRestSitsBetweenTheGrowthAndStrengthEvidence() {
        #expect((90...180).contains(RestCues.standaloneRestSeconds))
    }
}

struct HeartRateSeriesTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let scheme = HeartRateZoneScheme.reserve(resting: 55, maximum: 185)

    @Test func dropsRepeatsAndOutOfOrderReadings() {
        var series = HeartRateSeries()
        series.add(120, at: start)
        series.add(121, at: start)
        series.add(119, at: start.addingTimeInterval(-5))
        series.add(.nan, at: start.addingTimeInterval(5))
        series.add(125, at: start.addingTimeInterval(5))
        #expect(series.points.map(\.value) == [120, 125])
    }

    @Test func summaryHasAtMostSixtyPointsOfAtLeastAMinute() {
        var series = HeartRateSeries()
        // Two hours at a reading every 5 s.
        for second in stride(from: 0, to: 7200, by: 5) {
            series.add(100 + Double(second % 60), at: start.addingTimeInterval(Double(second)))
        }
        let summary = series.summary
        #expect(summary.count <= HeartRateSeries.summaryPoints)
        #expect(summary.count >= 55)
        let gaps = zip(summary, summary.dropFirst()).map { $1.date.timeIntervalSince($0.date) }
        #expect(gaps.allSatisfy { $0 >= 60 })
    }

    @Test func aShortSessionGetsOnePointAMinute() {
        var series = HeartRateSeries()
        for second in stride(from: 0, to: 600, by: 10) {
            series.add(130, at: start.addingTimeInterval(Double(second)))
        }
        #expect(series.summary.count == 10)
        #expect(series.summary.allSatisfy { $0.value == 130 })
    }

    @Test func recentKeepsTheLastTenMinutes() {
        var series = HeartRateSeries()
        for minute in 0..<30 {
            series.add(110, at: start.addingTimeInterval(Double(minute) * 60))
        }
        let recent = series.recent(HeartRateSeries.recentSeconds, now: start.addingTimeInterval(29 * 60))
        #expect(recent.count == 11)
    }

    @Test func staysBoundedOnAVeryLongWorkout() {
        var series = HeartRateSeries()
        for second in 0..<(HeartRateSeries.capacity * 3) {
            series.add(120, at: start.addingTimeInterval(Double(second)))
        }
        #expect(series.points.count <= HeartRateSeries.capacity)
        #expect(series.points.last?.date == start.addingTimeInterval(Double(HeartRateSeries.capacity * 3 - 1)))
    }

    @Test func zoneRunsGroupConsecutiveReadings() {
        // Zones start at 120, 133, 146, 159, 172.
        let points = [125.0, 128, 140, 141, 100].enumerated().map {
            SeriesPoint(date: start.addingTimeInterval(Double($0.offset) * 60), value: $0.element)
        }
        let runs = HeartRateSeries.zoneRuns(points, scheme: scheme)
        #expect(runs.map(\.zone) == [1, 2, nil])
        #expect(runs[0].end == start.addingTimeInterval(60))
    }

    @Test func elevationIgnoresNoiseUnderThreeMetres() {
        var elevation = RunningElevation()
        let altitudes = [100.0, 101, 99.5, 100.5, 104, 108, 107, 103]
        for (index, altitude) in altitudes.enumerated() {
            elevation.add(altitude: altitude, at: start.addingTimeInterval(Double(index) * 10))
        }
        #expect(elevation.gain == 8)
        #expect(elevation.loss == 5)
        #expect(elevation.current == 103)
        #expect(elevation.profile(now: start.addingTimeInterval(70)).map(\.value) == altitudes)
    }

    @Test func elevationMatchesTheMapsRule() {
        let altitudes = [10.0, 12, 15, 14, 9, 9.5, 20]
        var elevation = RunningElevation()
        let points = altitudes.enumerated().map { index, altitude in
            elevation.add(altitude: altitude, at: start.addingTimeInterval(Double(index) * 10))
            return RoutePoint(latitude: 51.5 + Double(index) * 0.0001, longitude: 0, altitude: altitude,
                              time: start.addingTimeInterval(Double(index) * 10), horizontalAccuracy: 5)
        }
        let route = CardioRoute(points: points)
        #expect(elevation.gain == route.elevation?.gain)
        #expect(elevation.loss == route.elevation?.loss)
    }
}
