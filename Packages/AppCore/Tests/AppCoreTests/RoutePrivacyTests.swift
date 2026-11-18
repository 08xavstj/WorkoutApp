import Foundation
import Testing
@testable import AppCore

struct RoutePrivacyTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let metersPerDegree = 6_371_008.8 * .pi / 180
    let home = (latitude: 46.0, longitude: 7.0)

    /// A straight line north from `home`, one fix every 2 s at 3 m/s (6 m apart).
    func line(meters: Double, from latitude: Double = 46.0) -> [RoutePoint] {
        let count = Int(meters / 6)
        return (0...count).map { index in
            RoutePoint(latitude: latitude + Double(index) * 6 / metersPerDegree, longitude: home.longitude,
                       altitude: 400, time: start.addingTimeInterval(Double(index) * 2), horizontalAccuracy: 5)
        }
    }

    /// Metres along the line to each point.
    func along(_ points: [RoutePoint]) -> [Double] { RoutePrivacy.cumulativeMeters(points) }

    var homeZone: PrivacyZone {
        PrivacyZone(name: "Home", latitude: home.latitude, longitude: home.longitude, radiusMeters: 500)
    }

    // MARK: Zones

    @Test func nothingHiddenWithoutZonesOrEndpointTrim() {
        let points = line(meters: 3000)
        let result = RoutePrivacy.trim(points, zones: [], hideEndpoints: false, seed: 1)
        #expect(result.visibleRanges == [0...(points.count - 1)])
        #expect(!result.isTrimmed)
    }

    @Test func routeLeavingHomeIsHiddenPastTheRadiusByTheRandomExtra() {
        let points = line(meters: 3000)
        let result = RoutePrivacy.trim(points, zones: [homeZone], hideEndpoints: false, seed: 42)
        #expect(result.isTrimmed)
        let first = try! #require(result.visibleRanges.first)
        let distances = along(points)
        // The first visible point is past the 500 m edge by 50-200 m (±one fix).
        let shownFrom = distances[first.lowerBound]
        #expect(shownFrom > 500 + 50 - 6)
        #expect(shownFrom <= 500 + 200 + 6)
        // And no visible point is inside the zone.
        for range in result.visibleRanges {
            for index in range { #expect(homeZone.distance(to: points[index]) > homeZone.radiusMeters) }
        }
    }

    @Test func theExtraLengthDiffersBetweenWorkoutsButNotBetweenExports() {
        let points = line(meters: 3000)
        let seedA = RoutePrivacy.seed(workoutID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, salt: "s")
        let seedB = RoutePrivacy.seed(workoutID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, salt: "s")
        let a1 = RoutePrivacy.trim(points, zones: [homeZone], hideEndpoints: true, seed: seedA)
        let a2 = RoutePrivacy.trim(points, zones: [homeZone], hideEndpoints: true, seed: seedA)
        let b = RoutePrivacy.trim(points, zones: [homeZone], hideEndpoints: true, seed: seedB)
        #expect(a1 == a2)
        #expect(a1.visibleRanges != b.visibleRanges || a1.endTrimMeters != b.endTrimMeters)
    }

    @Test func extraLengthsCoverTheRangeAcrossManyWorkouts() {
        // Over many workouts the endpoint trim spreads over 250-400 m, not one value.
        var trims: [Double] = []
        for index in 0..<200 {
            let seed = RoutePrivacy.seed(workoutID: UUID(), salt: "salt-\(index)")
            trims.append(RoutePrivacy.trim(line(meters: 2000), zones: [], hideEndpoints: true, seed: seed).startTrimMeters)
        }
        #expect(trims.allSatisfy { (250...400).contains($0) })
        #expect((trims.max() ?? 0) - (trims.min() ?? 0) > 100)
    }

    @Test func aRouteThroughAZoneSplitsIntoTwoPieces() {
        // Starts 2 km south of home, runs 4 km north through it.
        let points = line(meters: 4000, from: home.latitude - 2000 / metersPerDegree)
        let result = RoutePrivacy.trim(points, zones: [homeZone], hideEndpoints: false, seed: 7)
        #expect(result.visibleRanges.count == 2)
        let distances = along(points)
        let gapStart = distances[result.visibleRanges[0].upperBound]
        let gapEnd = distances[result.visibleRanges[1].lowerBound]
        // Hidden: the 1 km across the zone plus 50-200 m each side.
        #expect(gapEnd - gapStart >= 1000 + 100 - 12)
        #expect(gapEnd - gapStart <= 1000 + 400 + 12)
        let segments = RoutePrivacy.segments(points, result)
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.count >= 2 })
    }

    @Test func aRouteFarFromEveryZoneIsUntouched() {
        let far = PrivacyZone(name: "Work", latitude: 47, longitude: 8)
        let points = line(meters: 3000)
        let result = RoutePrivacy.trim(points, zones: [far], hideEndpoints: false, seed: 3)
        #expect(result.visibleRanges == [0...(points.count - 1)])
        #expect(!result.isTrimmed)
    }

    @Test func aWorkoutEntirelyAtHomeShowsNothing() {
        let points = line(meters: 300)
        let result = RoutePrivacy.trim(points, zones: [homeZone], hideEndpoints: false, seed: 9)
        #expect(result.hidesEverything)
        #expect(result.isTrimmed)
    }

    // MARK: Start and end

    @Test func startAndEndAreTrimmedEvenWithoutZones() {
        let points = line(meters: 3000)
        let result = RoutePrivacy.trim(points, zones: [], hideEndpoints: true, seed: 11)
        let range = try! #require(result.visibleRanges.first)
        #expect(result.visibleRanges.count == 1)
        let distances = along(points)
        let total = distances.last!
        #expect(abs(distances[range.lowerBound] - result.startTrimMeters) <= 6)
        #expect(abs(total - distances[range.upperBound] - result.endTrimMeters) <= 6)
        #expect(result.startTrimMeters != result.endTrimMeters)
    }

    @Test func aShortRouteIsHiddenEntirely() {
        // 550 m: 250-400 m off each end leaves under 100 m.
        let result = RoutePrivacy.trim(line(meters: 550), zones: [], hideEndpoints: true, seed: 5)
        #expect(result.hidesEverything)
    }

    @Test func tinyPiecesBetweenZonesAreDropped() {
        // Two zones 1.1 km apart on the route leave under 100 m between their trims.
        let points = line(meters: 3000)
        let second = PrivacyZone(name: "Work", latitude: home.latitude + 1150 / metersPerDegree, longitude: home.longitude,
                                 radiusMeters: 200)
        let result = RoutePrivacy.trim(points, zones: [homeZone, second], hideEndpoints: false, seed: 13)
        let distances = along(points)
        for range in result.visibleRanges {
            #expect(distances[range.upperBound] - distances[range.lowerBound] >= RoutePrivacy.minimumVisibleMeters)
        }
    }

    @Test func emptyAndSinglePointRoutes() {
        #expect(RoutePrivacy.trim([], zones: [homeZone], hideEndpoints: true, seed: 1).hidesEverything)
        let one = Array(line(meters: 6).prefix(1))
        #expect(RoutePrivacy.trim(one, zones: [], hideEndpoints: false, seed: 1).hidesEverything)
        #expect(RoutePrivacy.untrimmed(one).visibleRanges.isEmpty)
        #expect(RoutePrivacy.untrimmed(line(meters: 60)).visibleRanges.count == 1)
    }

    // MARK: Settings, rounding, seeds

    @Test func radiusIsClampedAndStepped() {
        #expect(RoutePrivacy.clampedRadius(50) == 200)
        #expect(RoutePrivacy.clampedRadius(5000) == 1000)
        #expect(RoutePrivacy.clampedRadius(530) == 550)
        #expect(RoutePrivacy.clampedRadius(.nan) == RoutePrivacy.defaultRadiusMeters)
        #expect(PrivacyZone(name: "x", latitude: 0, longitude: 0, radiusMeters: 10).radiusMeters == 200)
        #expect(PrivacyZone(name: "x", latitude: 0, longitude: 0).radiusMeters == 500)
    }

    @Test func distanceIsRoundedToATenth() {
        #expect(RoutePrivacy.roundedDistanceText(meters: 5_037, miles: false) == "5.0 km")
        #expect(RoutePrivacy.roundedDistanceText(meters: 5_071, miles: false) == "5.1 km")
        #expect(RoutePrivacy.roundedDistanceText(meters: 5_000, miles: true) == "3.1 mi")
        #expect(RoutePrivacy.roundedDistanceText(meters: 0, miles: false) == "0.0 km")
        #expect(abs(RoutePrivacy.roundedDistance(meters: 10_049, unitMeters: 1000) - 10.0) < 1e-9)
        #expect(RoutePrivacy.roundedDistance(meters: .infinity, unitMeters: 1000) == 0)
    }

    @Test func seedDependsOnSaltAndWorkout() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        #expect(RoutePrivacy.seed(workoutID: id, salt: "a") == RoutePrivacy.seed(workoutID: id, salt: "a"))
        #expect(RoutePrivacy.seed(workoutID: id, salt: "a") != RoutePrivacy.seed(workoutID: id, salt: "b"))
        #expect(RoutePrivacy.seed(workoutID: id, salt: "a") != RoutePrivacy.seed(workoutID: UUID(), salt: "a"))
    }

    @Test func seededGeneratorIsRepeatableAndInRange() {
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)
        let first = (0..<20).map { _ in a.next(in: 50...200) }
        let second = (0..<20).map { _ in b.next(in: 50...200) }
        #expect(first == second)
        #expect(first.allSatisfy { (50...200).contains($0) })
        #expect(Set(first).count > 15)
    }

    @Test func zonesRoundTripAsJSON() throws {
        let zone = homeZone
        let data = try JSONEncoder().encode([zone])
        let decoded = try JSONDecoder().decode([PrivacyZone].self, from: data)
        #expect(decoded == [zone])
    }

    // MARK: Projection

    @Test func projectionFitsTheUnitSquareKeepingTheShape() {
        let points = line(meters: 1000)
        let pieces = RouteProjection.normalized([points])
        let all = pieces.flatMap { $0 }
        #expect(all.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        // A line north: x stays centred, y runs from the bottom (south) to the top.
        #expect(all.allSatisfy { abs($0.x - 0.5) < 1e-9 })
        #expect(abs((all.first?.y ?? 0) - 1) < 1e-9)
        #expect(abs(all.last?.y ?? 1) < 1e-9)
    }

    @Test func projectionOfEmptyOrOnePoint() {
        #expect(RouteProjection.normalized([]).isEmpty)
        #expect(RouteProjection.normalized([[]]).isEmpty)
        let one = Array(line(meters: 6).prefix(1))
        #expect(RouteProjection.normalized([one]) == [[RouteProjection.Point(x: 0.5, y: 0.5)]])
    }
}
