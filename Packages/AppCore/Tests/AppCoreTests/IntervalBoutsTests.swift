import Foundation
import Testing
@testable import AppCore

struct IntervalBoutsTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let metersPerDegree = 6_371_008.8 * .pi / 180

    /// Heart rate every 5 s from `bpm(second)`.
    func heartRate(seconds: Int, _ bpm: (Int) -> Double) -> [(date: Date, bpm: Double)] {
        stride(from: 0, through: seconds, by: 5).map { (start.addingTimeInterval(Double($0)), bpm($0)) }
    }

    @Test func sessionsAreFoundByID() {
        #expect(IntervalSession.named("4x4-bike") == .fourByFour(.bike))
        #expect(IntervalSession.named("3x4-outdoorRun") == .threeByFour(.outdoorRun))
        #expect(IntervalSession.named("5x4-bike") == nil)
        #expect(IntervalSession.named("4x4-skis") == nil)
        #expect(IntervalSession.named("") == nil)
    }

    @Test func plannedStepsFollowTheSession() {
        let session = IntervalSession.fourByFour(.bike)
        let segments = IntervalBouts.planned(session, start: start, end: start.addingTimeInterval(Double(session.totalSeconds)))
        #expect(segments.count == session.steps.count)
        #expect(segments.filter { $0.kind == .work }.count == 4)
        #expect(segments[1].start == start.addingTimeInterval(600))
        #expect(segments[1].end == start.addingTimeInterval(840))
        #expect(segments.last?.kind == .coolDown)
    }

    @Test func pausesPushLaterStepsBack() {
        let session = IntervalSession.fourByFour(.bike)
        // A two-minute pause during the warm-up.
        let pause = DateInterval(start: start.addingTimeInterval(300), duration: 120)
        let segments = IntervalBouts.planned(session, start: start, end: start.addingTimeInterval(3600), pauses: [pause])
        #expect(segments[0].end == start.addingTimeInterval(720))
        #expect(segments[1].start == start.addingTimeInterval(720))
    }

    @Test func aWorkoutStoppedEarlyCutsTheSession() {
        let session = IntervalSession.fourByFour(.bike)
        let segments = IntervalBouts.planned(session, start: start, end: start.addingTimeInterval(900))
        // Warm-up, the first hard interval, and the first minute of the easy one.
        #expect(segments.map(\.kind) == [.warmUp, .work, .recovery])
        #expect(segments[2].end == start.addingTimeInterval(900))
    }

    @Test func boutsHaveAverageAndPeakHeartRate() {
        let session = IntervalSession.threeByFour(.rower)
        let total = session.totalSeconds
        let segments = IntervalBouts.planned(session, start: start, end: start.addingTimeInterval(Double(total)))
        let work = segments.filter { $0.kind == .work }.map { DateInterval(start: $0.start, end: $0.end) }
        let readings = heartRate(seconds: total) { second in
            work.contains { $0.contains(self.start.addingTimeInterval(Double(second))) } ? 170 : 125
        }
        let bouts = IntervalBouts.bouts(segments, heartRate: readings, route: nil)
        #expect(bouts.count == segments.count)
        #expect(IntervalBouts.isIntervalWorkout(bouts))
        let firstWork = bouts.first { $0.kind == .work }
        #expect(firstWork?.peakBpm == 170)
        #expect(firstWork.flatMap(\.averageBpm).map { $0 > 160 } == true)
        #expect(firstWork?.seconds == 240)
        #expect(firstWork?.meters == nil && firstWork?.speed == nil)
        #expect(IntervalBouts.workAverages(bouts).count == 3)
    }

    @Test func noHeartRateLeavesHeartRateEmpty() {
        let segments = [IntervalBouts.Segment(start: start, end: start.addingTimeInterval(60), kind: .work)]
        let bouts = IntervalBouts.bouts(segments, heartRate: [], route: nil)
        #expect(bouts.first?.averageBpm == nil)
        #expect(bouts.first?.peakBpm == nil)
        #expect(!IntervalBouts.isIntervalWorkout(bouts))
        #expect(IntervalBouts.bouts([], heartRate: [], route: nil).isEmpty)
    }

    @Test func unlabelledSegmentsAreCalledByHeartRate() {
        // Warm-up 125, then hard 170 / easy 135 twice, then cool-down 120.
        let plan: [(Int, Double)] = [(300, 125), (240, 170), (180, 135), (240, 172), (300, 120)]
        var segments: [IntervalBouts.Segment] = []
        var at = 0
        var readings: [(date: Date, bpm: Double)] = []
        for (seconds, bpm) in plan {
            segments.append(.init(start: start.addingTimeInterval(Double(at)), end: start.addingTimeInterval(Double(at + seconds)), kind: .lap))
            readings += stride(from: at, to: at + seconds, by: 5).map { (start.addingTimeInterval(Double($0)), bpm) }
            at += seconds
        }
        let labelled = IntervalBouts.labelled(segments, heartRate: readings, route: nil)
        #expect(labelled.map(\.kind) == [.warmUp, .work, .recovery, .work, .coolDown])
    }

    @Test func evenSegmentsStayLaps() {
        let segments = (0..<4).map { index in
            IntervalBouts.Segment(start: start.addingTimeInterval(Double(index) * 600), end: start.addingTimeInterval(Double(index + 1) * 600), kind: .lap)
        }
        let readings = heartRate(seconds: 2400) { 140 + Double($0 % 3) }
        #expect(IntervalBouts.labelled(segments, heartRate: readings, route: nil).allSatisfy { $0.kind == .lap })
        // Two segments are too few to call.
        #expect(IntervalBouts.labelled(Array(segments.prefix(2)), heartRate: readings, route: nil).allSatisfy { $0.kind == .lap })
    }

    @Test func routeGivesDistanceAndSpeed() {
        // 4 m/s for 300 s, then 2 m/s for 300 s.
        var latitude = 46.0
        let points: [RoutePoint] = (0...600).map { second in
            if second > 0 { latitude += (second <= 300 ? 4 : 2) / metersPerDegree }
            return RoutePoint(latitude: latitude, longitude: 7, time: start.addingTimeInterval(Double(second)), horizontalAccuracy: 5)
        }
        let route = CardioRoute(points: points)
        let segments = [
            IntervalBouts.Segment(start: start, end: start.addingTimeInterval(300), kind: .work),
            IntervalBouts.Segment(start: start.addingTimeInterval(300), end: start.addingTimeInterval(600), kind: .recovery),
        ]
        let bouts = IntervalBouts.bouts(segments, heartRate: [], route: route)
        #expect(bouts[0].speed.map { abs($0 - 4) < 0.01 } == true)
        #expect(bouts[1].meters.map { abs($0 - 600) < 1 } == true)
        // Speed alone can call hard and easy.
        let three = segments + [IntervalBouts.Segment(start: start.addingTimeInterval(150), end: start.addingTimeInterval(200), kind: .lap)]
        #expect(IntervalBouts.labelled(three, heartRate: [], route: route).filter { $0.kind == .work }.count == 2)
    }

    @Test func routeDistanceAtATime() {
        let points = [RoutePoint(latitude: 46, longitude: 7, time: start),
                      RoutePoint(latitude: 46 + 100 / metersPerDegree, longitude: 7, time: start.addingTimeInterval(100))]
        let route = CardioRoute(points: points)
        #expect(route.meters(at: start.addingTimeInterval(50)).map { abs($0 - 50) < 0.01 } == true)
        #expect(route.meters(at: start.addingTimeInterval(-30)) == 0)
        #expect(route.meters(at: start.addingTimeInterval(-300)) == nil)
        #expect(route.meters(at: start.addingTimeInterval(500)) == nil)
        #expect(CardioRoute(points: []).meters(at: start) == nil)
    }
}
