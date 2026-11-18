import Foundation

// Pace or speed, elevation and heart rate along a route, thinned to a few
// hundred points for a chart (competitor-features-2026-11.md, B11). No
// health evidence: the charts only show data the route already has.
//
// Smoothing: speed is already averaged over `CardioRoute.speedWindowSeconds`;
// each chart point then averages the fixes in its stretch of the route.
// Altitude is averaged the same way, which takes out most of the barometer's
// metre of noise. Both are the app's choices.

public nonisolated enum RouteSeries {
    public nonisolated enum Axis: String, Sendable, CaseIterable, Identifiable {
        case distance, time

        public var id: String { rawValue }
        public var title: String { self == .distance ? "Distance" : "Time" }
    }

    public nonisolated struct Point: Sendable, Equatable, Identifiable {
        public var index: Int
        /// Metres from the start (stretch midpoint).
        public var meters: Double
        /// Seconds from the start (stretch midpoint).
        public var seconds: Double
        /// m/s; nil when stopped or unknown.
        public var speed: Double?
        public var altitude: Double?
        public var bpm: Double?
        public var id: Int { index }

        public func x(_ axis: Axis) -> Double { axis == .distance ? meters : seconds }
    }

    /// Chart points (the app's choice: enough for a phone-width chart).
    public static let defaultPoints = 240
    /// Slower than this is standing still, not a pace: it would plot as an
    /// endless pace. 0.5 m/s is well under a slow walk (about 1 m/s; the app's choice).
    public static let minimumMovingSpeed = 0.5

    /// The route in up to `count` equal stretches of distance (of time when
    /// `axis` is time, or when the route barely moves), each averaged.
    public static func points(_ route: CardioRoute, axis: Axis = .distance, count: Int = defaultPoints) -> [Point] {
        let fixes = route.points
        guard fixes.count >= 2, count >= 1, let first = fixes.first else { return [] }
        let seconds = fixes.map { $0.time.timeIntervalSince(first.time) }
        let byTime = axis == .time || route.distanceMeters < 10
        let xs = byTime ? seconds : route.cumulativeMeters
        guard let total = xs.last, total > 0 else { return [] }
        let buckets = min(count, fixes.count)
        let width = total / Double(buckets)
        var result: [Point] = []
        var cursor = 0
        for bucket in 0..<buckets {
            let upper = bucket == buckets - 1 ? total + 1 : Double(bucket + 1) * width
            var indices: [Int] = []
            while cursor < fixes.count, xs[cursor] < upper {
                indices.append(cursor)
                cursor += 1
            }
            guard !indices.isEmpty else { continue }
            let speeds = indices.compactMap { route.speeds[$0] }.filter(\.isFinite)
            let altitudes = indices.compactMap { fixes[$0].altitude }.filter(\.isFinite)
            let bpms = indices.compactMap { route.heartRates[$0] }.filter(\.isFinite)
            let speed = mean(speeds)
            result.append(Point(
                index: result.count,
                meters: mean(indices.map { route.cumulativeMeters[$0] }) ?? 0,
                seconds: mean(indices.map { seconds[$0] }) ?? 0,
                speed: speed.flatMap { $0 >= minimumMovingSpeed ? $0 : nil },
                altitude: mean(altitudes),
                bpm: mean(bpms)
            ))
        }
        return result
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Pace (seconds per km or mile) from speed in m/s.
    public static func pace(speed: Double, unitMeters: Double) -> Double? {
        guard speed >= minimumMovingSpeed, unitMeters > 0 else { return nil }
        return unitMeters / speed
    }

    /// Has enough to draw: two points with a value.
    public static func hasSpeed(_ points: [Point]) -> Bool { points.compactMap(\.speed).count >= 2 }
    public static func hasAltitude(_ points: [Point]) -> Bool { points.compactMap(\.altitude).count >= 2 }
    public static func hasHeartRate(_ points: [Point]) -> Bool { points.compactMap(\.bpm).count >= 2 }
}
