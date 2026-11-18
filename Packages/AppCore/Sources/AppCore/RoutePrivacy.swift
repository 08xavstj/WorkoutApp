import Foundation

// Route privacy for anything that leaves the app (share images, GPX files):
// hide the route near the user's saved places, trim the start and end by a
// length that varies from workout to workout, and round the distance shown.
// The in-app map still shows the owner the full route.
//
// Why simple start/end hiding is not enough (docs/research/competitor-features-2026-11.md §4c):
// - An attack on fitness-network privacy zones recovered the protected
//   location for 84% of users who had set one, by fitting the circle the
//   visible route ends on (Hassan, Hussain & Bates, USENIX Security 2018).
// - A distance-and-street-grid attack on 1.4 million activities recovered the
//   hidden place for up to 85% of zones; bigger zones lowered success and
//   exact distance values (0.1 m precision) drove the attack (Dhondt et al.,
//   ACM CCS 2022).
// So the visible route stops a varied length *along the route* past each
// zone's edge (not on the circle), the extra length changes per workout, and
// shared distances are rounded. The evidence is for the risk; there is no
// trial of these countermeasures, so they lower the risk, not remove it.

/// A place whose surroundings are never shown on a shared route (home, work).
/// Stored on the phone only (`RoutePrivacyStore`).
public nonisolated struct PrivacyZone: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var radiusMeters: Double

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double,
                radiusMeters: Double = RoutePrivacy.defaultRadiusMeters) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = RoutePrivacy.clampedRadius(radiusMeters)
    }

    /// Metres from the zone's centre to `point`.
    public func distance(to point: RoutePoint) -> Double {
        CardioRoute.meters(from: RoutePoint(latitude: latitude, longitude: longitude, time: point.time), to: point)
    }
}

public nonisolated enum RoutePrivacy {
    // MARK: Settings and their sources

    /// Radius of a saved place: 200 m to 1 km, 500 m by default (spec B2 in
    /// competitor-features-2026-11.md). Bigger zones lowered the success of
    /// the distance attack (Dhondt 2022); a mile is the most a leading
    /// fitness network offers (DC Rainmaker on Strava privacy, 2021).
    public static let radiusRange: ClosedRange<Double> = 200...1000
    public static let defaultRadiusMeters = 500.0
    public static let radiusStep = 50.0
    /// "A few" places: home, work, a partner's or parent's home, the school
    /// run. The app's choice; each zone costs nothing to check.
    public static let maximumZones = 5

    /// Extra route length hidden past a zone's edge, drawn per workout from
    /// this range (spec B2: "plus a random 50–200 m beyond it, per workout,
    /// kept stable for that workout"). Fixed trimming leaves the visible ends
    /// on one circle around the home, which the Hassan 2018 attack fits.
    public static let extraTrimRange: ClosedRange<Double> = 50...200

    /// Start and end trimmed even with no saved place ("hide start and end
    /// everywhere", spec B2b): the smallest zone radius plus the same random
    /// extra, so 250–400 m, different at each end and for each workout.
    public static let endpointBaseMeters = radiusRange.lowerBound

    /// Shown distances on a trimmed route are rounded to a tenth of a km or
    /// mile (spec rule 4; Dhondt 2022: exact distances drive the attack).
    public static let distanceRoundingUnits = 0.1

    /// A visible piece shorter than this is dropped: a few metres of line
    /// next to a hidden area say more about it than about the workout. The
    /// app's choice.
    public static let minimumVisibleMeters = 100.0

    public static func clampedRadius(_ meters: Double) -> Double {
        guard meters.isFinite else { return defaultRadiusMeters }
        let stepped = (meters / radiusStep).rounded() * radiusStep
        return min(radiusRange.upperBound, max(radiusRange.lowerBound, stepped))
    }

    // MARK: Trimming

    /// What is left of a route once private parts are hidden.
    public struct Result: Sendable, Equatable {
        /// Index ranges into the points passed in, each a piece to show
        /// (2+ points); empty when nothing can be shown.
        public var visibleRanges: [ClosedRange<Int>]
        /// True when anything was hidden.
        public var isTrimmed: Bool
        /// The extra lengths drawn for this workout, for tests and the UI note.
        public var startTrimMeters: Double
        public var endTrimMeters: Double

        public var hidesEverything: Bool { visibleRanges.isEmpty }
    }

    /// Hides the route inside each zone (plus a per-workout random length
    /// along the route past each edge) and, with `hideEndpoints`, the first
    /// and last 250–400 m.
    ///
    /// - Parameters:
    ///   - points: the route in time order (`CardioRoute.points`).
    ///   - seed: per-workout seed (`seed(workoutID:salt:)`), so the same
    ///     workout is always trimmed the same way and two exports can't be
    ///     compared to undo the randomness.
    public static func trim(_ points: [RoutePoint], zones: [PrivacyZone], hideEndpoints: Bool, seed: UInt64) -> Result {
        var generator = SeededGenerator(seed: seed)
        // Drawn in a fixed order, whatever the route, so the values are stable.
        let startTrim = endpointBaseMeters + generator.next(in: extraTrimRange)
        let endTrim = endpointBaseMeters + generator.next(in: extraTrimRange)
        let zoneExtras = zones.map { zoneExtra($0, seed: seed) }

        guard points.count >= 2 else {
            return Result(visibleRanges: [], isTrimmed: !points.isEmpty, startTrimMeters: startTrim, endTrimMeters: endTrim)
        }
        let cumulative = cumulativeMeters(points)
        let total = cumulative.last ?? 0
        var hidden = [Bool](repeating: false, count: points.count)

        if hideEndpoints {
            for index in points.indices where cumulative[index] < startTrim || total - cumulative[index] < endTrim {
                hidden[index] = true
            }
        }

        for (zone, extra) in zip(zones, zoneExtras) {
            let inside = points.map { zone.distance(to: $0) <= zone.radiusMeters }
            // Each pass through the zone, widened along the route.
            var index = 0
            while index < points.count {
                guard inside[index] else { index += 1; continue }
                var end = index
                while end + 1 < points.count, inside[end + 1] { end += 1 }
                let from = cumulative[index] - extra.entry
                let to = cumulative[end] + extra.exit
                for other in points.indices where cumulative[other] >= from && cumulative[other] <= to {
                    hidden[other] = true
                }
                index = end + 1
            }
        }

        var ranges: [ClosedRange<Int>] = []
        var start: Int?
        for index in points.indices {
            if !hidden[index] {
                if start == nil { start = index }
            } else if let first = start {
                ranges.append(first...(index - 1))
                start = nil
            }
        }
        if let first = start { ranges.append(first...(points.count - 1)) }
        let kept = ranges.filter { $0.count >= 2 && cumulative[$0.upperBound] - cumulative[$0.lowerBound] >= minimumVisibleMeters }
        let trimmed = hidden.contains(true) || kept != [0...(points.count - 1)]
        return Result(visibleRanges: kept, isTrimmed: trimmed, startTrimMeters: startTrim, endTrimMeters: endTrim)
    }

    /// The extra lengths hidden before and after each pass through `zone` on
    /// one workout. Drawn from the zone's own ID, not its place in the list,
    /// so adding, removing or reordering places never changes another
    /// place's trim on a workout already shared (comparing the two images
    /// would undo the randomness).
    static func zoneExtra(_ zone: PrivacyZone, seed: UInt64) -> (entry: Double, exit: Double) {
        var generator = SeededGenerator(seed: seed ^ Self.seed(workoutID: zone.id, salt: "zone"))
        let entry = generator.next(in: extraTrimRange)
        return (entry, generator.next(in: extraTrimRange))
    }

    /// The visible pieces as points.
    public static func segments(_ points: [RoutePoint], _ result: Result) -> [[RoutePoint]] {
        result.visibleRanges.map { Array(points[$0]) }
    }

    /// No trimming at all: the whole route as one piece ("Full route" switch).
    public static func untrimmed(_ points: [RoutePoint]) -> Result {
        Result(visibleRanges: points.count >= 2 ? [0...(points.count - 1)] : [], isTrimmed: false,
               startTrimMeters: 0, endTrimMeters: 0)
    }

    // MARK: Rounding

    /// Distance in km (or miles) rounded to `distanceRoundingUnits`.
    public static func roundedDistance(meters: Double, unitMeters: Double) -> Double {
        guard unitMeters > 0, meters.isFinite else { return 0 }
        let units = max(0, meters) / unitMeters
        return (units / distanceRoundingUnits).rounded() * distanceRoundingUnits
    }

    /// "5.0 km" or "3.1 mi".
    public static func roundedDistanceText(meters: Double, miles: Bool) -> String {
        let value = roundedDistance(meters: meters, unitMeters: miles ? CardioSummary.metersPerMile : 1000)
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(tenths % 10) \(miles ? "mi" : "km")"
    }

    // MARK: Seeding

    /// A stable seed for one workout: FNV-1a over a per-phone random salt and
    /// the workout's ID. The salt stays on the phone, so someone who knows
    /// the method and the workout can't redo the draw.
    public static func seed(workoutID: UUID, salt: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array((salt + "|" + workoutID.uuidString).utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func cumulativeMeters(_ points: [RoutePoint]) -> [Double] {
        var result = [0.0]
        result.reserveCapacity(points.count)
        for (previous, point) in zip(points, points.dropFirst()) {
            result.append(result[result.count - 1] + CardioRoute.meters(from: previous, to: point))
        }
        return result
    }
}

/// SplitMix64: a small, fast generator with a fixed seed, so a workout's
/// random trim is the same every time it is shared (Steele, Lea & Flood,
/// OOPSLA 2014). Not for cryptography; the secrecy is in the salt.
public nonisolated struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `range` (inclusive), uniform to 53 bits.
    public mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
