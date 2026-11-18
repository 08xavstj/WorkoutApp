import Foundation
import Testing
@testable import AppCore

struct RouteSeriesTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let metersPerDegree = 6_371_008.8 * .pi / 180

    func route(seconds: Int, speed: (Int) -> Double, altitude: ((Int) -> Double?)? = nil,
               heartRate: [(date: Date, bpm: Double)] = []) -> CardioRoute {
        var latitude = 46.0
        let points: [RoutePoint] = (0...seconds).map { second in
            if second > 0 { latitude += speed(second) / metersPerDegree }
            return RoutePoint(latitude: latitude, longitude: 7, altitude: altitude?(second),
                              time: start.addingTimeInterval(Double(second)), horizontalAccuracy: 5)
        }
        return CardioRoute(points: points, heartRate: heartRate)
    }

    @Test func thinsToTheRequestedCount() {
        let points = RouteSeries.points(route(seconds: 3000) { _ in 3 }, count: 100)
        #expect(points.count == 100)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.meters < $1.meters && $0.seconds < $1.seconds })
        #expect(points.compactMap(\.speed).allSatisfy { abs($0 - 3) < 0.05 })
        #expect(!RouteSeries.hasAltitude(points))
        #expect(!RouteSeries.hasHeartRate(points))
    }

    @Test func timeAxisSplitsByTime() {
        // Stopped for the middle 200 s: by time, the stop has its own points with no speed.
        let points = RouteSeries.points(route(seconds: 600) { $0 > 200 && $0 <= 400 ? 0 : 3 }, axis: .time, count: 30)
        #expect(points.count == 30)
        #expect(points.contains { $0.speed == nil })
    }

    @Test func altitudeAndHeartRateAreAveraged() {
        let readings = (0...60).map { (date: start.addingTimeInterval(Double($0 * 10)), bpm: 150.0) }
        let points = RouteSeries.points(route(seconds: 600, speed: { _ in 3 }, altitude: { 400 + Double($0 % 2) }, heartRate: readings), count: 20)
        #expect(RouteSeries.hasAltitude(points))
        #expect(points.compactMap(\.altitude).allSatisfy { $0 >= 400 && $0 <= 401 })
        #expect(points.compactMap(\.bpm).allSatisfy { $0 == 150 })
    }

    @Test func tooLittleRouteGivesNothing() {
        #expect(RouteSeries.points(CardioRoute(points: [])).isEmpty)
        #expect(RouteSeries.points(CardioRoute(points: [RoutePoint(latitude: 46, longitude: 7, time: start)])).isEmpty)
        // Fewer fixes than requested points: one point per fix at most.
        #expect(RouteSeries.points(route(seconds: 10) { _ in 3 }, count: 240).count <= 11)
    }

    @Test func paceFromSpeed() {
        #expect(RouteSeries.pace(speed: 4, unitMeters: 1000) == 250)
        #expect(RouteSeries.pace(speed: 0.1, unitMeters: 1000) == nil)
        #expect(RouteSeries.pace(speed: 4, unitMeters: 0) == nil)
    }
}

struct YearInReviewTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func activity(_ id: String, _ kind: ActivityKind, _ month: Int, _ day: Int, year: Int = 2026, minutes: Double = 30, km: Double? = nil) -> ActivityCalendar.Activity {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
        return ActivityCalendar.Activity(id: id, kind: kind, title: kind.title, start: start, end: start.addingTimeInterval(minutes * 60),
                                         distanceMeters: km.map { $0 * 1000 })
    }

    @Test func totalsPerKindAndBusiestMonth() {
        let all = [
            activity("1", .run, 3, 1, km: 5), activity("2", .run, 3, 4, km: 8), activity("3", .lifting, 3, 4, minutes: 60),
            activity("4", .ride, 7, 2, minutes: 90, km: 30), activity("5", .lifting, 7, 9, minutes: 60),
            activity("6", .run, 5, 1, year: 2025, km: 10),
        ]
        let summary = YearInReview.summary(year: 2026, activities: all, records: 4, calendar: calendar)
        #expect(summary.sessions == 5)
        #expect(summary.activeDays == 4)
        #expect(summary.busiestMonth == 3)
        #expect(summary.sessionsPerMonth[2] == 3 && summary.sessionsPerMonth[6] == 2)
        #expect(summary.byKind.map(\.kind) == [.lifting, .run, .ride])
        #expect(summary.byKind.first { $0.kind == .run }?.meters == 13_000)
        #expect(summary.byKind.first { $0.kind == .lifting }?.meters == nil)
        #expect(summary.meters == 43_000)
        #expect(summary.seconds == (30 + 30 + 60 + 90 + 60) * 60)
        #expect(summary.records == 4)
        #expect(YearInReview.years(all, calendar: calendar) == [2026, 2025])
    }

    @Test func emptyYear() {
        let summary = YearInReview.summary(year: 2026, activities: [], records: 0, calendar: calendar)
        #expect(summary.sessions == 0)
        #expect(summary.busiestMonth == nil)
        #expect(summary.byKind.isEmpty)
        #expect(summary.sessionsPerMonth == Array(repeating: 0, count: 12))
    }

    @Test func aTieGoesToTheEarlierMonth() {
        let summary = YearInReview.summary(year: 2026, activities: [activity("a", .walk, 9, 1), activity("b", .walk, 2, 1)],
                                           records: 0, calendar: calendar)
        #expect(summary.busiestMonth == 2)
    }
}

struct OneRepMaxDisplayTests {
    @Test func onlyShortSetsGiveAnEstimate() {
        #expect(OneRepMax.displayEstimate(weight: 100, reps: 5, rpe: 10).map { abs($0 - 116.67) < 0.01 } == true)
        #expect(OneRepMax.displayEstimate(weight: 100, reps: 10, rpe: nil) != nil)
        #expect(OneRepMax.displayEstimate(weight: 100, reps: 11, rpe: nil) == nil)
        #expect(OneRepMax.displayEstimate(weight: 0, reps: 5, rpe: nil) == nil)
        #expect(OneRepMax.displayEstimate(weight: 100, reps: 0, rpe: nil) == nil)
        // The planner's estimate is unchanged for high-rep sets.
        #expect(OneRepMax.estimate(weight: 50, reps: 15, rpe: nil) > 50)
        #expect(LiftGoalProjection.maximumReps == OneRepMax.maximumReliableReps)
    }

    @Test func highRepSetsDontSetOneRepMaxRecords() {
        let earlier = [LiftProgress.LoggedSession(date: .distantPast, sets: [.init(weight: 60, reps: 8, rpe: 9)])]
        // 15 reps at 60 kg would be a higher Epley estimate, but it's past 10 reps.
        let records = SetFeedback.records(today: [.init(weight: 60, reps: 15, rpe: 10)], earlier: earlier)
        #expect(!records.contains { if case .estimatedOneRepMax = $0 { true } else { false } })
        // A short set that beats the old estimate still counts.
        let short = SetFeedback.records(today: [.init(weight: 70, reps: 6, rpe: 9)], earlier: earlier)
        #expect(short.contains { if case .estimatedOneRepMax = $0 { true } else { false } })
    }

    @Test func liftProgressUsesShortSetsOnly() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = [
            LiftProgress.LoggedSession(date: day, sets: [.init(weight: 50, reps: 15, rpe: 8)]),
            LiftProgress.LoggedSession(date: day.addingTimeInterval(86_400 * 3), sets: [.init(weight: 60, reps: 8, rpe: 8), .init(weight: 40, reps: 20)]),
            LiftProgress.LoggedSession(date: day.addingTimeInterval(86_400 * 6), sets: [.init(weight: 62.5, reps: 8, rpe: 8)]),
        ]
        let points = LiftProgress.points(sessions)
        #expect(points.count == 3)
        // No set of 10 or fewer: no estimate, the heaviest set stands for it.
        #expect(points[0].estimatedOneRepMax == 0)
        #expect(points[0].bestWeight == 50)
        #expect(points[1].bestWeight == 60)
        #expect(!points[1].isPR) // nothing estimated before it
        #expect(points[2].isPR)
    }

    @Test func summaryBestSetHasNoEstimatePastTenReps() {
        let set = WorkoutSummary.LoggedSet(weightKg: 40, reps: 12, rpe: 8, completedAt: .now)
        #expect(set.estimatedOneRepMaxKg == 0)
        #expect(WorkoutSummary.LoggedSet(weightKg: 40, reps: 8, rpe: 8, completedAt: .now).estimatedOneRepMaxKg > 40)
    }
}
