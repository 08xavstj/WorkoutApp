import Foundation

// Heart rate (and altitude) over a workout, kept on the Watch for its small
// charts: the Heart page's last 10 minutes, the summary's whole-session line,
// and the Elevation page's last 30 minutes. Needs only Foundation and
// `HeartRateZoneScheme.swift`, so the Watch app compiles both files on its
// own (project.yml, `TensileWatch: sources:`).
//
// - The summary chart has at most 60 points, each at least one minute: the
//   app's choice, matching the phone's per-minute convention; a watch chart
//   should read at a glance and leave detail to the iPhone (HIG Charts).
// - The Heart page shows 10 minutes (app's choice) and the Elevation page 30,
//   as Apple's Elevation view does (Apple Watch User Guide, Workout views).
// - Elevation gain counts only changes past `CardioRoute.elevationThresholdMeters`
//   (3 m) from the last turning point, the same hysteresis as the map, so a
//   flat loop doesn't climb. The value is restated here, as this file can't
//   depend on CardioRoute.swift.

/// One value at one time.
public nonisolated struct SeriesPoint: Sendable, Equatable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A run of time in one heart-rate zone, for a zone-coloured line.
public nonisolated struct ZoneRun: Sendable, Equatable {
    /// 1-5, or nil under zone 1.
    public var zone: Int?
    public var start: Date
    public var end: Date
}

/// Readings in time order, bounded in size.
public nonisolated struct HeartRateSeries: Sendable, Equatable {
    /// Points kept. Past this, neighbouring pairs are merged (a 3-hour workout
    /// at a reading every 5 s is about 2,200), so memory stays small.
    public static let capacity = 4_000
    /// The summary chart (see above).
    public static let summaryPoints = 60
    public static let summaryBucketSeconds: TimeInterval = 60
    /// The Heart page's sparkline.
    public static let recentSeconds: TimeInterval = 10 * 60

    public private(set) var points: [SeriesPoint] = []

    public init(points: [SeriesPoint] = []) {
        for point in points { add(point.value, at: point.date) }
    }

    public var isEmpty: Bool { points.isEmpty }

    /// Adds a reading; a repeat or an out-of-order one is dropped.
    public mutating func add(_ value: Double, at date: Date) {
        guard value.isFinite, value > 0 else { return }
        if let last = points.last, date <= last.date { return }
        points.append(SeriesPoint(date: date, value: value))
        if points.count > Self.capacity {
            points = Self.halved(points)
        }
    }

    /// The points within `seconds` before `now`.
    public func recent(_ seconds: TimeInterval, now: Date) -> [SeriesPoint] {
        let from = now.addingTimeInterval(-seconds)
        return points.filter { $0.date >= from && $0.date <= now }
    }

    /// Averages over buckets at least `minimumBucket` long, widened so there
    /// are at most `maxPoints`. Each point is at its bucket's middle.
    public static func downsample(_ points: [SeriesPoint], maxPoints: Int,
                                  minimumBucket: TimeInterval) -> [SeriesPoint] {
        guard let first = points.first, let last = points.last, maxPoints > 0 else { return [] }
        let span = last.date.timeIntervalSince(first.date)
        let bucket = max(minimumBucket, span / Double(maxPoints), 1)
        var sums: [Int: (total: Double, count: Int)] = [:]
        for point in points {
            let index = min(maxPoints - 1, Int(point.date.timeIntervalSince(first.date) / bucket))
            let current = sums[index] ?? (0, 0)
            sums[index] = (current.total + point.value, current.count + 1)
        }
        return sums.keys.sorted().compactMap { index in
            guard let entry = sums[index], entry.count > 0 else { return nil }
            return SeriesPoint(date: first.date.addingTimeInterval((Double(index) + 0.5) * bucket),
                               value: entry.total / Double(entry.count))
        }
    }

    /// The whole series for the summary chart.
    public var summary: [SeriesPoint] {
        Self.downsample(points, maxPoints: Self.summaryPoints, minimumBucket: Self.summaryBucketSeconds)
    }

    /// Lowest and highest value, or nil when empty.
    public static func range(of points: [SeriesPoint]) -> ClosedRange<Double>? {
        guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else { return nil }
        return low...high
    }

    /// Consecutive points in the same zone, as runs (for a zone-coloured line).
    public static func zoneRuns(_ points: [SeriesPoint], scheme: HeartRateZoneScheme) -> [ZoneRun] {
        var runs: [ZoneRun] = []
        for point in points {
            let zone = scheme.zone(for: point.value)
            if var last = runs.last, last.zone == zone {
                last.end = point.date
                runs[runs.count - 1] = last
            } else {
                runs.append(ZoneRun(zone: zone, start: point.date, end: point.date))
            }
        }
        return runs
    }

    /// Merges neighbouring pairs (keeps the later time, averages the value).
    private static func halved(_ points: [SeriesPoint]) -> [SeriesPoint] {
        stride(from: 0, to: points.count, by: 2).map { index in
            guard index + 1 < points.count else { return points[index] }
            return SeriesPoint(date: points[index + 1].date, value: (points[index].value + points[index + 1].value) / 2)
        }
    }
}

/// Altitude as it comes in during an outdoor workout: the current value, the
/// climb so far (with the map's 3 m hysteresis) and a series for the profile.
public nonisolated struct RunningElevation: Sendable, Equatable {
    /// Changes smaller than this are noise (the same as `CardioRoute.elevationThresholdMeters`).
    public static let thresholdMeters = 3.0
    /// The Elevation page's profile span.
    public static let profileSeconds: TimeInterval = 30 * 60

    public private(set) var current: Double?
    public private(set) var gain = 0.0
    public private(set) var loss = 0.0
    public private(set) var series = HeartRateSeries()
    private var reference: Double?

    public init() {}

    public mutating func add(altitude: Double, at date: Date) {
        guard altitude.isFinite else { return }
        current = altitude
        // Negative altitudes (below sea level) are real; the series wants positive values.
        series.add(altitude + 1_000, at: date)
        guard let reference else {
            self.reference = altitude
            return
        }
        // The same rule as `CardioRoute.elevation`, so the live climb matches the summary's.
        let change = altitude - reference
        if change >= Self.thresholdMeters {
            gain += change
            self.reference = altitude
        } else if change <= -Self.thresholdMeters {
            loss -= change
            self.reference = altitude
        }
    }

    /// The last `profileSeconds` of altitude, in metres.
    public func profile(now: Date) -> [SeriesPoint] {
        series.recent(Self.profileSeconds, now: now).map { SeriesPoint(date: $0.date, value: $0.value - 1_000) }
    }
}
