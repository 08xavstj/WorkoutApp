import Foundation
import Testing
@testable import AppCore

struct CardioRouteTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// Metres per degree of latitude (mean Earth radius).
    let metersPerDegree = 6_371_008.8 * .pi / 180

    /// A straight line north at `speed` m/s, one fix a second.
    func line(seconds: Int, speed: Double, altitude: (Int) -> Double? = { _ in nil }) -> [RoutePoint] {
        (0...seconds).map { second in
            RoutePoint(
                latitude: 46 + Double(second) * speed / metersPerDegree, longitude: 7,
                altitude: altitude(second), time: start.addingTimeInterval(Double(second)), horizontalAccuracy: 5
            )
        }
    }

    @Test func distanceAndSpeedOfASteadyLine() {
        let route = CardioRoute(points: line(seconds: 600, speed: 4))
        #expect(abs(route.distanceMeters - 2400) < 1)
        #expect(route.duration == 600)
        #expect(abs((route.maximumSpeed ?? 0) - 4) < 0.01)
        // Every point in the middle has a full window.
        #expect(route.speeds[300].map { abs($0 - 4) < 0.01 } == true)
    }

    @Test func inaccurateFixesAndJumpsAreDropped() {
        var points = line(seconds: 100, speed: 3)
        points[50].horizontalAccuracy = 120
        points[60].latitude += 0.01 // about 1.1 km off: a jump
        points[70].horizontalAccuracy = -1 // invalid
        let route = CardioRoute(points: points)
        #expect(route.points.count == 98)
        #expect(abs(route.distanceMeters - 300) < 1)
    }

    @Test func outOfOrderAndDuplicateTimesAreHandled() {
        var points = line(seconds: 10, speed: 2)
        points.swapAt(2, 7)
        points.append(points[0]) // same time as the first
        let route = CardioRoute(points: points)
        #expect(route.points.count == 11)
        #expect(zip(route.points, route.points.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    @Test func elevationIgnoresNoiseButCountsClimbs() {
        // ±1 m noise on flat ground: no climb.
        let flat = CardioRoute(points: line(seconds: 300, speed: 3) { $0 % 2 == 0 ? 500 : 501 })
        #expect(flat.elevation?.gain == 0)
        #expect(flat.elevation?.loss == 0)
        // Up 60 m then down 40 m.
        let hill = CardioRoute(points: line(seconds: 100, speed: 3) { second in
            second <= 60 ? 500 + Double(second) : 560 - Double(second - 60)
        })
        #expect(abs((hill.elevation?.gain ?? 0) - 60) <= 3)
        #expect(abs((hill.elevation?.loss ?? 0) - 40) <= 3)
        #expect(hill.altitudeRange == 500...560)
    }

    @Test func noAltitudeMeansNoElevation() {
        #expect(CardioRoute(points: line(seconds: 50, speed: 3)).elevation == nil)
    }

    @Test func heartRateIsMatchedToNearbyPointsOnly() {
        let readings: [(date: Date, bpm: Double)] = [
            (start.addingTimeInterval(10), 120), (start.addingTimeInterval(100), 150),
        ]
        let route = CardioRoute(points: line(seconds: 200, speed: 3), heartRate: readings)
        #expect(route.heartRates[0] == 120)
        #expect(route.heartRates[12] == 120)
        #expect(route.heartRates[95] == 150)
        // More than 30 s from any reading.
        #expect(route.heartRates[55] == nil)
        #expect(route.heartRates[200] == nil)
    }

    @Test func kilometreSplits() {
        // 2.5 km at 4 m/s, heart rate 140 throughout.
        let readings = (0...625).map { (date: start.addingTimeInterval(Double($0)), bpm: 140.0) }
        let route = CardioRoute(points: line(seconds: 625, speed: 4), heartRate: readings)
        let splits = route.splits(unitMeters: 1000)
        #expect(splits.count == 3)
        #expect(abs(splits[0].meters - 1000) < 0.01)
        #expect(abs(splits[0].seconds - 250) < 0.5)
        #expect(splits[0].averageBpm == 140)
        #expect(!splits[0].isPartial)
        #expect(splits[2].isPartial)
        #expect(abs(splits[2].meters - 500) < 1)
        #expect(abs(splits.map(\.meters).reduce(0, +) - route.distanceMeters) < 1)
    }

    @Test func aTinyLastPieceIsLeftOut() {
        // 1,050 m: the last 50 m is under a tenth of a kilometre.
        let splits = CardioRoute(points: line(seconds: 210, speed: 5)).splits(unitMeters: 1000)
        #expect(splits.count == 1)
    }

    @Test func mileSplits() {
        let splits = CardioRoute(points: line(seconds: 1000, speed: 4)).splits(unitMeters: 1609.344)
        #expect(splits.count == 3)
        #expect(splits[0].index == 1)
        #expect(abs(splits[0].meters - 1609.344) < 0.01)
    }

    @Test func stretchesFollowSpeedAndCoverTheRoute() {
        // Slow then fast.
        let slow = line(seconds: 120, speed: 2)
        let last = slow.last!
        let fast = (1...120).map { second in
            RoutePoint(
                latitude: last.latitude + Double(second) * 6 / metersPerDegree, longitude: 7,
                time: last.time.addingTimeInterval(Double(second)), horizontalAccuracy: 5
            )
        }
        let route = CardioRoute(points: slow + fast)
        let stretches = route.stretches(for: .speed)
        #expect(stretches.first?.range.lowerBound == 0)
        #expect(stretches.last?.range.upperBound == route.points.count - 1)
        // Consecutive stretches share their joining point.
        for (a, b) in zip(stretches, stretches.dropFirst()) {
            #expect(a.range.upperBound == b.range.lowerBound)
        }
        let levels = stretches.compactMap(\.level)
        #expect(levels.first == 0)
        #expect(levels.last == 4)
    }

    @Test func flickeringValuesDontShatterTheLine() {
        // Heart rate alternating across a zone boundary every few seconds.
        let scheme = HeartRateZoneScheme.ageEstimate(age: 35)
        let readings = (0...600).map { (date: start.addingTimeInterval(Double($0)), bpm: ($0 / 2) % 2 == 0 ? 120.0 : 175.0) }
        let route = CardioRoute(points: line(seconds: 600, speed: 3), heartRate: readings)
        let raw = route.stretches(for: .heartRate, zones: scheme, minimumPoints: 1)
        let merged = route.stretches(for: .heartRate, zones: scheme)
        #expect(raw.count > 100)
        #expect(merged.count < 5)
        #expect(merged.first?.range.lowerBound == 0)
        #expect(merged.last?.range.upperBound == route.points.count - 1)
    }

    @Test func heartRateStretchesUseZones() {
        let scheme = HeartRateZoneScheme.ageEstimate(age: 35)
        let readings = (0...200).map { (date: start.addingTimeInterval(Double($0)), bpm: $0 < 100 ? 120.0 : 175.0) }
        let route = CardioRoute(points: line(seconds: 200, speed: 3), heartRate: readings)
        let stretches = route.stretches(for: .heartRate, zones: scheme)
        #expect(stretches.first?.level == (scheme.zone(for: 120) ?? 1) - 1)
        #expect(stretches.last?.level == (scheme.zone(for: 175) ?? 1) - 1)
    }

    @Test func tooFewPointsGiveEmptyResults() {
        let one = CardioRoute(points: Array(line(seconds: 0, speed: 3)))
        #expect(one.distanceMeters == 0)
        #expect(one.splits(unitMeters: 1000).isEmpty)
        #expect(one.stretches(for: .speed).isEmpty)
        #expect(one.maximumSpeed == nil)
        #expect(CardioRoute(points: []).range(for: .elevation) == nil)
    }

    // MARK: Heart summary

    @Test func heartSummaryWithRecovery() {
        let end = start.addingTimeInterval(1800)
        var readings = (0...360).map { (date: start.addingTimeInterval(Double($0) * 5), bpm: 150.0) }
        readings.append((end.addingTimeInterval(60), 125))
        let summary = CardioHeartSummary(readings: readings, start: start, end: end, zones: .ageEstimate(age: 35))
        #expect(summary.averageBpm == 150)
        #expect(summary.maximumBpm == 150)
        #expect(summary.recoveryDrop == 25)
        #expect(abs(summary.zoneMinutes.reduce(0, +) - 30) < 0.01)
    }

    @Test func noRecoveryWithoutAReadingAMinuteLater() {
        let end = start.addingTimeInterval(600)
        let readings = (0...120).map { (date: start.addingTimeInterval(Double($0) * 5), bpm: 140.0) }
        let summary = CardioHeartSummary(readings: readings, start: start, end: end, zones: nil)
        #expect(summary.recoveryDrop == nil)
        #expect(summary.zoneMinutes.isEmpty)
    }

    @Test func averageIsWeightedByTime() {
        // Ten minutes at 120 with one reading a minute, then a minute of
        // readings every second at 180: the burst must not dominate.
        var readings = (0...10).map { (date: start.addingTimeInterval(Double($0) * 60), bpm: 120.0) }
        readings += (1...60).map { (date: start.addingTimeInterval(600 + Double($0)), bpm: 180.0) }
        let summary = CardioHeartSummary(readings: readings, start: start, end: start.addingTimeInterval(660), zones: nil)
        let average = summary.averageBpm ?? 0
        #expect(average > 120 && average < 135)
    }

    @Test func emptyHeartSummary() {
        let summary = CardioHeartSummary(readings: [], start: start, end: start.addingTimeInterval(60), zones: nil)
        #expect(summary.averageBpm == nil)
        #expect(summary.recoveryDrop == nil)
    }
}
