import Foundation

// Best efforts: the fastest 400 m, 1 km, mile, 5 km and 10 km inside each
// run (and set distances inside rides), from the GPS route, and the personal
// bests across workouts (competitor-features-2026-11.md, B7).
//
// Evidence, weak to moderate: feedback on performance and goal review help
// (Michie S, et al. Health Psychol 2009;28(6):690-701; Weakley J, et al.
// Sports Med 2023;53(9):1789-1803, for lifting), but no trial tests cardio
// best efforts themselves. They are plain facts about your own past, never a
// comparison with others.
//
// Measurement: GPS watches measured distance with a mean absolute error of
// 3.2-6.1%, and under trees and buildings up to 9% short (Gilgen-Ammann R,
// et al. JMIR mHealth uHealth 2020;8(6):e17118). So a best effort, above all
// a short one, is approximate; the UI says so.
//
// Method: first the route's distance is added up again, counting a stretch
// between two fixes only when they are at most `maximumFixGap` apart and
// the speed between them is possible for the sport (`movingMeters`), so a
// GPS jump or a train ride while paused can't become a best. Then a window
// slides along that distance twice: once ending at each fix, the start
// exactly `distance` metres earlier with its time interpolated between the
// two fixes around it, and once starting at each fix with the end
// interpolated. Time is elapsed time, pauses included, as the doc's spec says.

public nonisolated enum CardioBests {
    /// Which bests a workout counts toward.
    public nonisolated enum Sport: String, Codable, Sendable, CaseIterable, Identifiable {
        case run, walk, ride

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .run: "Running"
            case .walk: "Walking & hiking"
            case .ride: "Cycling"
            }
        }

        /// The distances looked for, in metres.
        public var distances: [Double] {
            switch self {
            case .run, .walk: CardioBests.footDistances
            case .ride: CardioBests.rideDistances
            }
        }

        /// Faster than this over a whole effort is a GPS error, not a best.
        /// On foot: 10.5 m/s, above the 400 m world record's 9.3 m/s
        /// (43.03 s, World Athletics records). On a bike: 25 m/s (90 km/h),
        /// above the flat-road hour record's ~15 m/s (UCI records) with room
        /// for descents. Both are the app's sanity limits, not research.
        public var maximumSpeed: Double {
            switch self {
            case .run, .walk: 10.5
            case .ride: 25
            }
        }

        /// The sport for an activity kind; nil when bests don't apply.
        public static func of(_ kind: ActivityKind) -> Sport? {
            switch kind {
            case .run: .run
            case .walk: .walk
            case .ride: .ride
            default: nil
            }
        }
    }

    public static let metersPerMile = 1609.344
    /// 400 m, 1 km, 1 mile, 5 km and 10 km: the distances runners race and
    /// most apps list (the doc's B7).
    public static let footDistances: [Double] = [400, 1000, metersPerMile, 5000, 10_000]
    /// 5, 10, 20 and 40 km for rides (the doc's B7; shorter ones say little on a bike).
    public static let rideDistances: [Double] = [5000, 10_000, 20_000, 40_000]

    /// The fastest stretch of one distance in one workout.
    public nonisolated struct Effort: Codable, Sendable, Equatable {
        public var distanceMeters: Double
        public var seconds: Double
        /// Where it started, metres from the route's start.
        public var startMeters: Double

        public init(distanceMeters: Double, seconds: Double, startMeters: Double) {
            self.distanceMeters = distanceMeters
            self.seconds = seconds
            self.startMeters = startMeters
        }

        public var speed: Double { seconds > 0 ? distanceMeters / seconds : 0 }
    }

    /// Fixes further apart than this don't add distance: the watch was
    /// paused or lost GPS, and the straight line between them says nothing
    /// about how fast the user moved. 30 s is the app's choice; the Watch
    /// saves a fix every few seconds while it is recording.
    public static let maximumFixGap: Double = 30

    /// The fastest effort at each of the sport's distances the route covers.
    public static func efforts(route: CardioRoute, sport: Sport) -> [Effort] {
        guard let first = route.points.first else { return [] }
        let seconds = route.points.map { $0.time.timeIntervalSince(first.time) }
        let meters = movingMeters(meters: route.cumulativeMeters, seconds: seconds, maximumSpeed: sport.maximumSpeed)
        return sport.distances.compactMap {
            fastest(distance: $0, meters: meters, seconds: seconds, maximumSpeed: sport.maximumSpeed)
        }
    }

    /// Cumulative metres again, adding a stretch between two fixes only when
    /// time moved forward, by at most `maximumFixGap`, and at no more than
    /// `maximumSpeed`. Same length as the input; never decreases.
    public static func movingMeters(meters: [Double], seconds: [Double], maximumSpeed: Double) -> [Double] {
        let count = min(meters.count, seconds.count)
        guard count > 0 else { return [] }
        var result = [meters[0]]
        result.reserveCapacity(count)
        for index in 1..<count {
            let step = meters[index] - meters[index - 1]
            let dt = seconds[index] - seconds[index - 1]
            let counts = dt > 0 && dt <= maximumFixGap && step >= 0 && step / dt <= maximumSpeed
            result.append(result[index - 1] + (counts ? step : 0))
        }
        return result
    }

    /// The fastest `distance` metres along a route given as cumulative metres
    /// and elapsed seconds at each fix (both increasing). Nil when the route
    /// is shorter, or every window is faster than `maximumSpeed`.
    public static func fastest(distance: Double, meters: [Double], seconds: [Double], maximumSpeed: Double = .infinity) -> Effort? {
        let count = min(meters.count, seconds.count)
        guard distance > 0, count >= 2, meters[count - 1] - meters[0] >= distance - 0.001 else { return nil }
        var best: Effort?
        func consider(elapsed: Double, startMeters: Double) {
            guard elapsed > 0, distance / elapsed <= maximumSpeed else { return }
            if elapsed < best?.seconds ?? .infinity {
                best = Effort(distanceMeters: distance, seconds: elapsed, startMeters: max(0, startMeters - meters[0]))
            }
        }
        // Each fix as the end; the start interpolated.
        var low = 0
        for end in 1..<count {
            let target = meters[end] - distance
            guard target >= meters[0] - 0.001 else { continue }
            // The last fix at or before the start point.
            while low + 1 < end, meters[low + 1] <= target { low += 1 }
            let span = meters[low + 1] - meters[low]
            let fraction = span > 0 ? min(1, max(0, (target - meters[low]) / span)) : 0
            let startTime = seconds[low] + fraction * (seconds[low + 1] - seconds[low])
            consider(elapsed: seconds[end] - startTime, startMeters: target)
        }
        // Each fix as the start; the end interpolated.
        var high = 1
        for start in 0..<(count - 1) {
            let target = meters[start] + distance
            guard target <= meters[count - 1] + 0.001 else { break }
            // The first fix at or past the end point.
            if high <= start { high = start + 1 }
            while high < count - 1, meters[high] < target { high += 1 }
            let span = meters[high] - meters[high - 1]
            let fraction = span > 0 ? min(1, max(0, (target - meters[high - 1]) / span)) : 1
            let endTime = seconds[high - 1] + fraction * (seconds[high] - seconds[high - 1])
            consider(elapsed: endTime - seconds[start], startMeters: meters[start])
        }
        return best
    }

    // MARK: Across workouts

    /// One workout's efforts, as cached.
    public nonisolated struct WorkoutEfforts: Codable, Sendable, Equatable, Identifiable {
        /// The Health workout's UUID string.
        public var workoutID: String
        public var date: Date
        public var sport: Sport
        public var efforts: [Effort]

        public init(workoutID: String, date: Date, sport: Sport, efforts: [Effort]) {
            self.workoutID = workoutID
            self.date = date
            self.sport = sport
            self.efforts = efforts
        }

        public var id: String { workoutID }
    }

    /// A best at one distance, and the workout it came from.
    public nonisolated struct Record: Sendable, Equatable, Identifiable {
        public var sport: Sport
        public var effort: Effort
        public var workoutID: String
        public var date: Date
        public var id: String { "\(sport.rawValue)-\(effort.distanceMeters)" }
    }

    /// The fastest effort per sport and distance among workouts in
    /// `interval` (nil: all time), shortest distance first.
    public static func personalBests(_ workouts: [WorkoutEfforts], in interval: DateInterval? = nil) -> [Sport: [Record]] {
        var best: [Sport: [Double: Record]] = [:]
        for workout in workouts where interval.map({ $0.contains(workout.date) }) ?? true {
            for effort in workout.efforts where effort.seconds > 0 {
                let current = best[workout.sport]?[effort.distanceMeters]
                if current == nil || effort.seconds < current!.effort.seconds {
                    best[workout.sport, default: [:]][effort.distanceMeters] =
                        Record(sport: workout.sport, effort: effort, workoutID: workout.workoutID, date: workout.date)
                }
            }
        }
        return best.mapValues { $0.values.sorted { $0.effort.distanceMeters < $1.effort.distanceMeters } }
    }

    /// Every time an all-time best was beaten, oldest first. A workout's
    /// first effort at a distance isn't a record: there was nothing to beat
    /// (as `PRHistory` does for lifts).
    public static func recordsSet(_ workouts: [WorkoutEfforts]) -> [Record] {
        var best: [Sport: [Double: Double]] = [:]
        var result: [Record] = []
        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            for effort in workout.efforts where effort.seconds > 0 {
                if let previous = best[workout.sport]?[effort.distanceMeters] {
                    guard effort.seconds < previous else { continue }
                    result.append(Record(sport: workout.sport, effort: effort, workoutID: workout.workoutID, date: workout.date))
                }
                best[workout.sport, default: [:]][effort.distanceMeters] = effort.seconds
            }
        }
        return result
    }

    /// The distances where `workout` is the fastest among `all` of its sport
    /// (ties go to the earlier workout); empty when it's the first of its sport.
    public static func newBests(for workout: WorkoutEfforts, among all: [WorkoutEfforts]) -> [Double] {
        let others = all.filter { $0.sport == workout.sport && $0.workoutID != workout.workoutID }
        guard !others.isEmpty else { return [] }
        return workout.efforts.filter { effort in
            let rivals = others.flatMap { other in
                other.efforts.filter { $0.distanceMeters == effort.distanceMeters }
                    .map { (seconds: $0.seconds, date: other.date) }
            }
            guard !rivals.isEmpty else { return false }
            return rivals.allSatisfy { effort.seconds < $0.seconds || (effort.seconds == $0.seconds && workout.date < $0.date) }
        }.map(\.distanceMeters)
    }

    // MARK: Wording

    /// "400 m", "1 km", "1 mile", "5 km".
    public static func distanceLabel(_ meters: Double) -> String {
        if abs(meters - metersPerMile) < 1 { return "1 mile" }
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        let km = meters / 1000
        return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
    }

    /// "1:32", "21:05", "1:02:10".
    public static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "–" }
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// What the bests can and can't say, for the UI.
    public static let evidenceNote = "Evidence: weak to moderate. Seeing your own progress helps people keep going, but no trial has tested best efforts themselves. GPS distance is typically off by 3–6% (more under trees and buildings), so short efforts like 400 m are approximate. Times include pauses."
}
