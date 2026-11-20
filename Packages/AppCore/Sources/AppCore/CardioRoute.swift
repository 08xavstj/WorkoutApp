import Foundation

// The numbers behind an outdoor workout's map and summary: distance, speed,
// elevation, heart rate along the route, splits, and the heart-rate summary.
// Pure Foundation (no CoreLocation), so the Watch app compiles it on its own
// (project.yml, `TensileWatch: sources:`) and it is tested on Linux.

/// One GPS fix along a workout's route.
public nonisolated struct RoutePoint: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// Metres above sea level; nil when the fix has none.
    public var altitude: Double?
    public var time: Date
    /// Radius of uncertainty in metres (CLLocation's `horizontalAccuracy`); nil if unknown.
    public var horizontalAccuracy: Double?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil, time: Date, horizontalAccuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.time = time
        self.horizontalAccuracy = horizontalAccuracy
    }
}

/// What the map can colour the route by.
public nonisolated enum RouteMetric: String, Sendable, CaseIterable, Identifiable {
    case speed, heartRate, elevation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .speed: "Speed"
        case .heartRate: "Heart rate"
        case .elevation: "Elevation"
        }
    }
}

/// An outdoor workout's route with the numbers worked out along it.
public nonisolated struct CardioRoute: Sendable, Equatable {
    /// Fixes kept: in time order, accurate enough, and no jumps.
    public private(set) var points: [RoutePoint]
    /// Metres from the start to each point.
    public private(set) var cumulativeMeters: [Double]
    /// Speed at each point in metres per second, averaged over
    /// `speedWindowSeconds` around it; nil where the window has too little.
    public private(set) var speeds: [Double?]
    /// Heart rate at each point: the nearest reading within
    /// `heartRateMatchSeconds`, else nil.
    public private(set) var heartRates: [Double?]

    /// Fixes less accurate than this are dropped. Apple's Workout app and
    /// most running apps do the same with their own limits; 50 m is this
    /// app's choice (a fix that uncertain moves the line more than the
    /// runner did between fixes a few seconds apart).
    public static let maximumAccuracyMeters = 50.0
    /// A fix implying faster than this since the last kept one is a GPS jump
    /// and is dropped: 40 m/s (144 km/h) is above any downhill skier's
    /// typical speed, so real movement is never thrown away.
    public static let maximumPlausibleSpeed = 40.0
    /// Speed is averaged over this many seconds around each point: second-by-
    /// second GPS speed swings with each fix's error. The app's choice.
    public static let speedWindowSeconds = 20.0
    /// A heart-rate reading this close in time stands for a point.
    public static let heartRateMatchSeconds = 30.0
    /// Elevation changes smaller than this are treated as noise when adding
    /// up the climb (hysteresis). The Watch's altitude is barometric, with
    /// noise of about a metre; 3 m is the app's choice so a flat loop
    /// doesn't climb.
    public static let elevationThresholdMeters = 3.0

    public init(points raw: [RoutePoint], heartRate: [(date: Date, bpm: Double)] = []) {
        let sorted = raw.sorted { $0.time < $1.time }
        var kept: [RoutePoint] = []
        var cumulative: [Double] = []
        for point in sorted {
            if let accuracy = point.horizontalAccuracy, accuracy < 0 || accuracy > Self.maximumAccuracyMeters { continue }
            guard point.latitude.isFinite, point.longitude.isFinite,
                  abs(point.latitude) <= 90, abs(point.longitude) <= 180 else { continue }
            guard let last = kept.last else {
                kept.append(point)
                cumulative.append(0)
                continue
            }
            let seconds = point.time.timeIntervalSince(last.time)
            guard seconds > 0 else { continue }
            let meters = Self.meters(from: last, to: point)
            if meters / seconds > Self.maximumPlausibleSpeed { continue }
            kept.append(point)
            cumulative.append((cumulative.last ?? 0) + meters)
        }
        points = kept
        cumulativeMeters = cumulative
        speeds = Self.windowSpeeds(points: kept, cumulative: cumulative)
        heartRates = Self.match(heartRate: heartRate, to: kept)
    }

    // MARK: Totals

    public var distanceMeters: Double { cumulativeMeters.last ?? 0 }

    public var duration: TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.time.timeIntervalSince(first.time)
    }

    /// The fastest averaged speed (m/s); spikes are already smoothed out.
    public var maximumSpeed: Double? { speeds.compactMap { $0 }.max() }

    /// Metres climbed and descended, counting only changes past
    /// `elevationThresholdMeters` from the last turning point.
    public var elevation: (gain: Double, loss: Double)? {
        let altitudes = points.compactMap(\.altitude).filter(\.isFinite)
        guard altitudes.count >= 2 else { return nil }
        var gain = 0.0
        var loss = 0.0
        var reference = altitudes[0]
        for altitude in altitudes.dropFirst() {
            let change = altitude - reference
            if change >= Self.elevationThresholdMeters {
                gain += change
                reference = altitude
            } else if change <= -Self.elevationThresholdMeters {
                loss -= change
                reference = altitude
            }
        }
        return (gain, loss)
    }

    /// Lowest and highest altitude on the route.
    public var altitudeRange: ClosedRange<Double>? {
        let altitudes = points.compactMap(\.altitude).filter(\.isFinite)
        guard let low = altitudes.min(), let high = altitudes.max() else { return nil }
        return low...high
    }

    // MARK: Splits

    /// One kilometre (or mile) of the route.
    public nonisolated struct Split: Sendable, Equatable, Identifiable {
        /// 1 for the first km or mile.
        public var index: Int
        public var meters: Double
        public var seconds: TimeInterval
        public var averageBpm: Double?
        /// Altitude at the end minus at the start, in metres.
        public var elevationChange: Double?
        /// True for the last, shorter piece.
        public var isPartial: Bool
        public var id: Int { index }

        /// Metres per second over the split.
        public var speed: Double { seconds > 0 ? meters / seconds : 0 }
    }

    /// The route cut every `unitMeters` (1000, or 1609.344 for miles). A
    /// last piece shorter than a tenth of a unit is left out: its pace is noise.
    public func splits(unitMeters: Double) -> [Split] {
        guard unitMeters > 0, points.count >= 2 else { return [] }
        var result: [Split] = []
        var startIndex = 0
        var startMeters = 0.0
        var startTime = points[0].time
        var next = unitMeters
        for index in points.indices.dropFirst() {
            let here = cumulativeMeters[index]
            guard here >= next || index == points.count - 1 else { continue }
            // Where the boundary falls between this point and the one before.
            let isBoundary = here >= next
            let endMeters = isBoundary ? next : here
            let previous = cumulativeMeters[index - 1]
            let fraction = here > previous ? (endMeters - previous) / (here - previous) : 1
            let endTime = points[index - 1].time.addingTimeInterval(
                fraction * points[index].time.timeIntervalSince(points[index - 1].time))
            let meters = endMeters - startMeters
            if isBoundary || meters >= unitMeters / 10 {
                let range = startIndex...index
                let bpms = range.compactMap { heartRates[$0] }
                let change: Double? = {
                    guard let a = points[startIndex].altitude, let b = points[index].altitude else { return nil }
                    return b - a
                }()
                result.append(Split(
                    index: result.count + 1, meters: meters, seconds: endTime.timeIntervalSince(startTime),
                    averageBpm: bpms.isEmpty ? nil : bpms.reduce(0, +) / Double(bpms.count),
                    elevationChange: change, isPartial: !isBoundary
                ))
            }
            startIndex = index
            startMeters = endMeters
            startTime = endTime
            next += unitMeters
            // A long gap between fixes can cross more than one boundary: the
            // next split starts at this point either way.
            while cumulativeMeters[index] >= next { next += unitMeters }
        }
        return result
    }

    // MARK: Colouring the map

    /// The value at each point for `metric` (m/s, bpm, or metres).
    public func values(for metric: RouteMetric) -> [Double?] {
        switch metric {
        case .speed: speeds
        case .heartRate: heartRates
        case .elevation: points.map(\.altitude)
        }
    }

    /// A stretch of the route drawn in one colour.
    public nonisolated struct Stretch: Sendable, Equatable {
        /// Index of the first and last point (they overlap the next stretch by one, so the line has no gaps).
        public var range: ClosedRange<Int>
        /// 0...(levels-1), low to high; nil where the value is unknown.
        public var level: Int?
    }

    /// The route in stretches of equal colour. Levels split the workout's own
    /// range evenly (slowest to fastest, lowest to highest), so the map shows
    /// where you were faster or slower that day; with `zones`, heart rate
    /// uses zones 1-5 instead (level = zone - 1, below zone 1 = 0).
    ///
    /// A stretch shorter than `minimumPoints` joins the one before it, so a
    /// value flickering across a level boundary doesn't cut the line into
    /// hundreds of pieces.
    public func stretches(for metric: RouteMetric, levels: Int = 5, zones: HeartRateZoneScheme? = nil, minimumPoints: Int = 5) -> [Stretch] {
        guard points.count >= 2, levels >= 1 else { return [] }
        let values = values(for: metric)
        let known = values.compactMap { $0 }.filter(\.isFinite)
        let low = known.min() ?? 0
        let high = known.max() ?? 0
        func level(_ value: Double?) -> Int? {
            guard let value, value.isFinite else { return nil }
            if metric == .heartRate, let zones {
                return min(levels - 1, max(0, (zones.zone(for: value) ?? 0) - 1))
            }
            guard high > low else { return levels / 2 }
            return min(levels - 1, Int((value - low) / (high - low) * Double(levels)))
        }
        var stretches: [Stretch] = []
        var start = 0
        var current = level(values[0])
        for index in 1..<points.count {
            let here = level(values[index])
            if here != current {
                stretches.append(Stretch(range: start...index, level: current))
                start = index
                current = here
            }
        }
        if start < points.count - 1 || stretches.isEmpty {
            stretches.append(Stretch(range: start...(points.count - 1), level: current))
        }
        guard minimumPoints > 1 else { return stretches }
        var merged: [Stretch] = []
        for stretch in stretches {
            if let last = merged.last,
               stretch.range.count < minimumPoints || last.level == stretch.level {
                merged[merged.count - 1].range = last.range.lowerBound...stretch.range.upperBound
            } else {
                merged.append(stretch)
            }
        }
        return merged
    }

    /// The lowest and highest value of `metric` on the route, for the legend.
    public func range(for metric: RouteMetric) -> ClosedRange<Double>? {
        let known = values(for: metric).compactMap { $0 }.filter(\.isFinite)
        guard let low = known.min(), let high = known.max() else { return nil }
        return low...high
    }

    // MARK: Helpers

    /// Great-circle distance in metres (haversine, mean Earth radius).
    public static func meters(from a: RoutePoint, to b: RoutePoint) -> Double {
        let radius = 6_371_008.8
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    private static func windowSpeeds(points: [RoutePoint], cumulative: [Double]) -> [Double?] {
        guard points.count >= 2 else { return points.map { _ in nil } }
        let half = speedWindowSeconds / 2
        var speeds: [Double?] = []
        speeds.reserveCapacity(points.count)
        var low = 0
        var high = 0
        for index in points.indices {
            let time = points[index].time
            while low < index, time.timeIntervalSince(points[low].time) > half { low += 1 }
            if high < index { high = index }
            while high + 1 < points.count, points[high + 1].time.timeIntervalSince(time) <= half { high += 1 }
            let seconds = points[high].time.timeIntervalSince(points[low].time)
            // Less than a quarter of the window: too little to average.
            guard seconds >= speedWindowSeconds / 4 else {
                speeds.append(nil)
                continue
            }
            speeds.append((cumulative[high] - cumulative[low]) / seconds)
        }
        return speeds
    }

    private static func match(heartRate: [(date: Date, bpm: Double)], to points: [RoutePoint]) -> [Double?] {
        let readings = heartRate.filter { $0.bpm.isFinite && $0.bpm > 0 }.sorted { $0.date < $1.date }
        guard !readings.isEmpty else { return points.map { _ in nil } }
        var result: [Double?] = []
        result.reserveCapacity(points.count)
        var cursor = 0
        for point in points {
            while cursor + 1 < readings.count, readings[cursor + 1].date <= point.time { cursor += 1 }
            var best: (gap: TimeInterval, bpm: Double)?
            for candidate in [cursor, cursor + 1] where candidate < readings.count {
                let gap = abs(readings[candidate].date.timeIntervalSince(point.time))
                if gap <= heartRateMatchSeconds, best == nil || gap < best!.gap {
                    best = (gap, readings[candidate].bpm)
                }
            }
            result.append(best?.bpm)
        }
        return result
    }
}

/// The heart-rate side of a cardio workout's summary.
public nonisolated struct CardioHeartSummary: Sendable, Equatable {
    public var averageBpm: Double?
    public var maximumBpm: Double?
    public var minimumBpm: Double?
    /// Minutes in zones 1-5 (index 0 = zone 1), as the Today page counts them.
    public var zoneMinutes: [Double]
    /// Beats per minute heart rate fell in the first minute after the end,
    /// when readings exist for both moments; nil otherwise.
    public var recoveryDrop: Double?
    /// True when heart rate had already come down before the workout was
    /// ended (`slowedBeforeEndBpm`), so no recovery is shown.
    public var slowedBeforeEnd = false

    /// Heart-rate recovery under this many beats in the first minute after
    /// exercise was linked with higher mortality (Cole et al., N Engl J Med
    /// 1999;341:1351-7: HRR ≤ 12 bpm after a treadmill test with a walking
    /// cool-down). After a workout with no set cool-down the number is only
    /// a rough guide, so the app shows it but makes no verdict below this.
    public static let lowRecoveryDrop = 12.0
    /// The reading at the end counts if it is this close before the end.
    public static let endReadingSeconds = 30.0
    /// The one-minute reading counts if it is between these times after the end.
    public static let recoveryWindow: ClosedRange<TimeInterval> = 45...90
    /// Recovery is measured from the end of effort (Cole 1999 started the
    /// clock at peak exercise). When the reading at the end is more than this
    /// below the highest of the last 3 minutes, the workout was ended after
    /// walking off or cooling down, and a "drop" from there says nothing
    /// (a squash match ended at 125 bpm after rallies at 175 read "down
    /// 4 bpm"). The 15 bpm is the app's choice.
    public static let slowedBeforeEndBpm = 15.0

    /// `readings` may run past the end: those after it are used only for the recovery.
    public init(readings: [(date: Date, bpm: Double)], start: Date, end: Date, zones: HeartRateZoneScheme?) {
        let valid = readings.filter { $0.bpm.isFinite && $0.bpm > 0 }.sorted { $0.date < $1.date }
        let during = valid.filter { $0.date >= start && $0.date <= end }
        let bpms = during.map(\.bpm)
        averageBpm = bpms.isEmpty ? nil : Self.timeWeightedAverage(during)
        maximumBpm = bpms.max()
        minimumBpm = bpms.min()
        zoneMinutes = zones?.zoneMinutes(during) ?? []
        let atEnd = during.last { end.timeIntervalSince($0.date) <= Self.endReadingSeconds }
        let after = valid.first { Self.recoveryWindow.contains($0.date.timeIntervalSince(end)) }
        let lastMinutesPeak = during.filter { end.timeIntervalSince($0.date) <= 180 }.map(\.bpm).max()
        if let atEnd, let peak = lastMinutesPeak, peak - atEnd.bpm > Self.slowedBeforeEndBpm {
            recoveryDrop = nil
            slowedBeforeEnd = true
        } else if let atEnd, let after {
            recoveryDrop = atEnd.bpm - after.bpm
        } else {
            recoveryDrop = nil
        }
    }

    /// Each reading stands for the time to the next one (capped at two
    /// minutes, as in `HeartRateZoneScheme.zoneMinutes`), so a burst of
    /// readings during a sprint doesn't outweigh the rest.
    static func timeWeightedAverage(_ readings: [(date: Date, bpm: Double)]) -> Double? {
        guard let last = readings.last else { return nil }
        guard readings.count >= 2 else { return last.bpm }
        var weighted = 0.0
        var total = 0.0
        for (current, next) in zip(readings, readings.dropFirst()) {
            let gap = min(max(0, next.date.timeIntervalSince(current.date)), HeartRateZoneScheme.maxMinutesPerSample * 60)
            weighted += current.bpm * gap
            total += gap
        }
        return total > 0 ? weighted / total : readings.map(\.bpm).reduce(0, +) / Double(readings.count)
    }
}
