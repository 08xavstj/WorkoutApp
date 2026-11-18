import Foundation
import Testing
@testable import AppCore

struct CardioBestsTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let metersPerDegree = 6_371_008.8 * .pi / 180

    /// A line north, one fix a second, at the speed `speed(second)` gives.
    func route(seconds: Int, speed: (Int) -> Double) -> CardioRoute {
        var latitude = 46.0
        var points: [RoutePoint] = []
        for second in 0...seconds {
            if second > 0 { latitude += speed(second) / metersPerDegree }
            points.append(RoutePoint(latitude: latitude, longitude: 7, time: start.addingTimeInterval(Double(second)), horizontalAccuracy: 5))
        }
        return CardioRoute(points: points)
    }

    @Test func steadyPaceGivesExactTimes() {
        // 3,000 s at 4 m/s: 12 km.
        let efforts = CardioBests.efforts(route: route(seconds: 3000) { _ in 4 }, sport: .run)
        #expect(efforts.map(\.distanceMeters) == CardioBests.footDistances)
        #expect(abs(efforts[0].seconds - 100) < 0.5)   // 400 m
        #expect(abs(efforts[1].seconds - 250) < 0.5)   // 1 km
        #expect(abs(efforts[2].seconds - 402.3) < 0.5) // 1 mile
        #expect(abs(efforts[4].seconds - 2500) < 1)    // 10 km
    }

    @Test func findsTheFastestStretchInTheMiddle() {
        // Easy at 3 m/s, then 5 m/s from 600 s to 800 s (1 km fast), then easy.
        let efforts = CardioBests.efforts(route: route(seconds: 1500) { $0 > 600 && $0 <= 800 ? 5 : 3 }, sport: .run)
        let kilometre = efforts.first { $0.distanceMeters == 1000 }
        #expect(kilometre.map { abs($0.seconds - 200) < 0.5 } == true)
        #expect(kilometre.map { abs($0.startMeters - 1800) < 2 } == true)
        let fourHundred = efforts.first { $0.distanceMeters == 400 }
        #expect(fourHundred.map { abs($0.seconds - 80) < 0.5 } == true)
    }

    @Test func distancesLongerThanTheRouteAreLeftOut() {
        // 1,200 m: 400 m and 1 km only.
        let efforts = CardioBests.efforts(route: route(seconds: 400) { _ in 3 }, sport: .run)
        #expect(efforts.map(\.distanceMeters) == [400, 1000])
    }

    @Test func emptyAndSinglePointRoutesHaveNoEfforts() {
        #expect(CardioBests.efforts(route: CardioRoute(points: []), sport: .run).isEmpty)
        let one = CardioRoute(points: [RoutePoint(latitude: 46, longitude: 7, time: start)])
        #expect(CardioBests.efforts(route: one, sport: .run).isEmpty)
        #expect(CardioBests.fastest(distance: 400, meters: [0], seconds: [0]) == nil)
        #expect(CardioBests.fastest(distance: 0, meters: [0, 500], seconds: [0, 100]) == nil)
    }

    @Test func exactlyTheDistanceCounts() {
        let effort = CardioBests.fastest(distance: 400, meters: [0, 200, 400], seconds: [0, 50, 100])
        #expect(effort?.seconds == 100)
        #expect(effort?.startMeters == 0)
    }

    @Test func interpolatesBetweenSparseFixes() {
        // Fixes every 100 m, the fast 100 m in the middle.
        let effort = CardioBests.fastest(distance: 150, meters: [0, 100, 200, 300], seconds: [0, 30, 45, 75])
        // Best: from 50 m (15 s) to 200 m (45 s) = 30 s, or 100 m to 250 m (30 → 60) = 30 s.
        #expect(effort.map { abs($0.seconds - 30) < 0.001 } == true)
    }

    @Test func implausiblyFastWindowsAreSkipped() {
        // A GPS glitch: 400 m "covered" in 20 s (20 m/s) inside an easy run.
        let meters: [Double] = [0, 500, 900, 1400]
        let seconds: [Double] = [0, 150, 170, 320]
        let effort = CardioBests.fastest(distance: 400, meters: meters, seconds: seconds, maximumSpeed: CardioBests.Sport.run.maximumSpeed)
        #expect(effort != nil)
        #expect((effort?.speed ?? 99) <= CardioBests.Sport.run.maximumSpeed)
    }

    @Test func ridesUseRideDistances() {
        let efforts = CardioBests.efforts(route: route(seconds: 1800) { _ in 10 }, sport: .ride) // 18 km
        #expect(efforts.map(\.distanceMeters) == [5000, 10_000])
    }

    @Test func theEndIsInterpolatedToo() {
        // 400 m from the first fix ends three quarters of the way to the
        // third: 10 s + 75 s = 85 s, faster than any window ending at a fix.
        let effort = CardioBests.fastest(distance: 400, meters: [0, 100, 500], seconds: [0, 10, 110])
        #expect(effort.map { abs($0.seconds - 85) < 0.001 } == true)
        #expect(effort?.startMeters == 0)
    }

    @Test func movingMetersSkipGapsAndImpossibleSpeeds() {
        // A 10 s stretch, a 40 s gap, a 30 m/s jump, then a normal stretch.
        let meters: [Double] = [0, 40, 400, 430, 460]
        let seconds: [Double] = [0, 10, 50, 51, 61]
        let moving = CardioBests.movingMeters(meters: meters, seconds: seconds, maximumSpeed: CardioBests.Sport.run.maximumSpeed)
        #expect(moving == [0, 40, 40, 40, 70])
        // A stretch exactly `maximumFixGap` long still counts.
        #expect(CardioBests.movingMeters(meters: [0, 90], seconds: [0, CardioBests.maximumFixGap], maximumSpeed: 10.5) == [0, 90])
        #expect(CardioBests.movingMeters(meters: [], seconds: [], maximumSpeed: 10.5).isEmpty)
    }

    @Test func aTrainRideWhilePausedIsNotABest() {
        // 600 s at 3 m/s, then the watch paused for 5 minutes on a train
        // that covered 3 km (10 m/s, under both the route's and the run's
        // limits), then 600 s more at 3 m/s.
        var latitude = 46.0
        var points: [RoutePoint] = []
        func add(_ second: Double) {
            points.append(RoutePoint(latitude: latitude, longitude: 7, time: start.addingTimeInterval(second), horizontalAccuracy: 5))
        }
        for second in 0...600 {
            if second > 0 { latitude += 3 / metersPerDegree }
            add(Double(second))
        }
        latitude += 3000 / metersPerDegree
        for second in 900...1500 {
            if second > 900 { latitude += 3 / metersPerDegree }
            add(Double(second))
        }
        let route = CardioRoute(points: points)
        #expect(route.distanceMeters > 6500)
        let efforts = CardioBests.efforts(route: route, sport: .run)
        let kilometre = efforts.first { $0.distanceMeters == 1000 }
        #expect(kilometre.map { abs($0.seconds - 1000.0 / 3) < 1 } == true)
        // 3.6 km of running: no 5 km.
        #expect(!efforts.contains { $0.distanceMeters == 5000 })
    }

    func workout(_ id: String, daysAgo: Double, _ efforts: [(Double, Double)], sport: CardioBests.Sport = .run) -> CardioBests.WorkoutEfforts {
        CardioBests.WorkoutEfforts(workoutID: id, date: start.addingTimeInterval(-daysAgo * 86_400), sport: sport,
                                   efforts: efforts.map { CardioBests.Effort(distanceMeters: $0.0, seconds: $0.1, startMeters: 0) })
    }

    @Test func personalBestsPickTheFastestPerSportAndDistance() {
        let all = [
            workout("a", daysAgo: 30, [(1000, 260), (5000, 1400)]),
            workout("b", daysAgo: 10, [(1000, 250)]),
            workout("c", daysAgo: 5, [(1000, 500)], sport: .walk),
        ]
        let bests = CardioBests.personalBests(all)
        #expect(bests[.run]?.map(\.workoutID) == ["b", "a"])
        #expect(bests[.walk]?.first?.effort.seconds == 500)
        // Only the last two weeks: workout a is outside.
        let recent = CardioBests.personalBests(all, in: DateInterval(start: start.addingTimeInterval(-14 * 86_400), end: start))
        #expect(recent[.run]?.map(\.workoutID) == ["b"])
    }

    @Test func recordsAreImprovementsNotFirsts() {
        let all = [
            workout("a", daysAgo: 30, [(1000, 260), (5000, 1400)]),
            workout("b", daysAgo: 20, [(1000, 270)]),
            workout("c", daysAgo: 10, [(1000, 255), (5000, 1390)]),
        ]
        let records = CardioBests.recordsSet(all)
        #expect(records.map(\.workoutID) == ["c", "c"])
        #expect(CardioBests.newBests(for: all[2], among: all) == [1000, 5000])
        #expect(CardioBests.newBests(for: all[1], among: all).isEmpty)
        // Alone, nothing to beat.
        #expect(CardioBests.newBests(for: all[0], among: [all[0]]).isEmpty)
    }

    @Test func wording() {
        #expect(CardioBests.distanceLabel(400) == "400 m")
        #expect(CardioBests.distanceLabel(1609.344) == "1 mile")
        #expect(CardioBests.distanceLabel(10_000) == "10 km")
        #expect(CardioBests.timeText(92) == "1:32")
        #expect(CardioBests.timeText(3730) == "1:02:10")
        #expect(CardioBests.timeText(.nan) == "–")
    }

    @Test func effortsRoundTripThroughJSON() throws {
        let entry = workout("a", daysAgo: 1, [(400, 90)])
        let decoded = try JSONDecoder().decode(CardioBests.WorkoutEfforts.self, from: JSONEncoder().encode(entry))
        #expect(decoded == entry)
    }
}
