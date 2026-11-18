import Foundation

// The work and recovery bouts of an interval workout, each with its length,
// average and peak heart rate and, with a route, its distance and speed
// (competitor-features-2026-11.md, B10).
//
// Where the bouts come from:
// - Tensile's own interval session (`IntervalSession`). The workout says which
//   session it was in its metadata (`IntervalSession.metadataKey`). The Watch
//   saves each step it ran as a segment event carrying the step's index
//   (`IntervalSession.stepMetadataKey`): those are used as they are
//   (`recorded`), so a skipped step is left out. Workouts without them are
//   laid out from the plan from the workout's start, pushed back by pauses.
// - Another app's segments (Apple's custom workouts save segments):
//   unlabelled, so each is called hard or easy by its own intensity (below),
//   and kept only when hard and easy really alternate. Laps (a watch's
//   auto-lap every kilometre) aren't used: the splits table shows them.
//
// Evidence: strong for the session (intervals raise VO2max about 5.5
// mL/kg/min against no exercise and more than steady training; Milanović Z,
// et al. Sports Med 2015;45(10):1469-1481); none for the table itself, which
// only shows what happened. Heart rate lags effort by a minute or two, so a
// short hard bout's average reads lower than the effort was: the UI says so.

extension IntervalSession {
    /// The standard or short session for an `id` as `make` builds it ("4x4-bike", "3x4-rower").
    public static func named(_ id: String) -> IntervalSession? {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let modality = Modality(rawValue: parts[1]) else { return nil }
        switch parts[0] {
        case "4x4": return .fourByFour(modality)
        case "3x4": return .threeByFour(modality)
        default: return nil
        }
    }
}

public nonisolated enum IntervalBouts {
    public nonisolated enum Kind: String, Codable, Sendable {
        case warmUp, work, recovery, coolDown
        /// A segment or lap that couldn't be called hard or easy.
        case lap

        public var title: String {
            switch self {
            case .warmUp: "Warm-up"
            case .work: "Hard"
            case .recovery: "Easy"
            case .coolDown: "Cool-down"
            case .lap: "Lap"
            }
        }
    }

    /// A stretch of the workout before its numbers are worked out.
    public nonisolated struct Segment: Sendable, Equatable {
        public var start: Date
        public var end: Date
        public var kind: Kind

        public init(start: Date, end: Date, kind: Kind) {
            self.start = start
            self.end = max(start, end)
            self.kind = kind
        }
    }

    /// One bout with its numbers.
    public nonisolated struct Bout: Sendable, Equatable, Identifiable {
        /// From 1, in time order.
        public var index: Int
        public var kind: Kind
        public var start: Date
        public var end: Date
        public var averageBpm: Double?
        public var peakBpm: Double?
        /// Metres covered, when the workout has a route.
        public var meters: Double?
        public var id: Int { index }

        public var seconds: TimeInterval { end.timeIntervalSince(start) }
        /// Metres per second; nil without a route or distance.
        public var speed: Double? {
            guard let meters, meters > 0, seconds > 0 else { return nil }
            return meters / seconds
        }
    }

    // MARK: From a planned session

    /// The session's steps from `start`, each pushed back by pauses that
    /// begin before it ends (a paused step resumes where it stopped). Steps
    /// that start after `end` are left out; the last one is cut at `end`.
    public static func planned(_ session: IntervalSession, start: Date, end: Date, pauses: [DateInterval] = []) -> [Segment] {
        let sortedPauses = pauses.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        // Active seconds since `start` at a wall-clock time.
        func wallClock(activeSeconds: Double) -> Date {
            var time = start.addingTimeInterval(activeSeconds)
            for pause in sortedPauses where pause.start < time { time = time.addingTimeInterval(pause.duration) }
            return time
        }
        var result: [Segment] = []
        var elapsed = 0.0
        for step in session.steps {
            let from = wallClock(activeSeconds: elapsed)
            elapsed += Double(step.seconds)
            let to = min(end, wallClock(activeSeconds: elapsed))
            guard from < end, to > from else { break }
            result.append(Segment(start: from, end: to, kind: kind(of: step.phase)))
        }
        return result
    }

    /// One step the Watch recorded: its index in the session's `steps`.
    public nonisolated struct RecordedStep: Sendable, Equatable {
        public var index: Int
        public var start: Date
        public var end: Date

        public init(index: Int, start: Date, end: Date) {
            self.index = index
            self.start = start
            self.end = end
        }
    }

    /// The steps the Watch recorded, each labelled by its step's phase, in
    /// time order. Steps with an index the session doesn't have are left out.
    public static func recorded(_ session: IntervalSession, steps: [RecordedStep]) -> [Segment] {
        steps.filter { $0.end > $0.start && session.steps.indices.contains($0.index) }
            .sorted { $0.start < $1.start }
            .map { Segment(start: $0.start, end: $0.end, kind: kind(of: session.steps[$0.index].phase)) }
    }

    static func kind(of phase: IntervalSession.Phase) -> Kind {
        switch phase {
        case .warmUp: .warmUp
        case .work: .work
        case .recovery: .recovery
        case .coolDown: .coolDown
        }
    }

    // MARK: From unlabelled segments

    /// Bouts must differ by at least this much average heart rate (bpm), or
    /// by `minimumSpeedSpread` in speed, to be called hard and easy; else
    /// they stay laps. The app's choice: about one zone's width.
    public static let minimumHeartRateSpread = 10.0
    /// 20% faster than the slowest bout (the app's choice).
    public static let minimumSpeedSpread = 0.2
    /// Hard and easy must take turns at least this often (hard after easy or
    /// easy after hard, warm-up and cool-down counting as easy) to be called
    /// intervals: warm-up, hard, easy, hard is three. Fewer, as in a run with
    /// a fast finish or a hilly stretch, stay laps. The app's choice.
    public static let minimumSwitches = 3

    /// Calls each of another app's segments hard or easy: above the midpoint
    /// between the easiest and hardest average heart rate (or speed, without
    /// heart rate) is hard. An easy first or last segment is the warm-up or
    /// cool-down. Fewer than three segments, too little spread, or fewer than
    /// `minimumSwitches` turns between hard and easy, stay laps.
    public static func labelled(_ segments: [Segment], heartRate: [(date: Date, bpm: Double)], route: CardioRoute?) -> [Segment] {
        let sorted = segments.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard sorted.count >= 3 else { return sorted.map { Segment(start: $0.start, end: $0.end, kind: .lap) } }
        let readings = validReadings(heartRate)
        let bpms = sorted.map { average(readings, from: $0.start, to: $0.end) }
        let speeds = sorted.map { segment in route.flatMap { meters($0, from: segment.start, to: segment.end) }
            .map { $0 / segment.end.timeIntervalSince(segment.start) } }
        let intensity: [Double?]
        if bpms.allSatisfy({ $0 != nil }), let low = bpms.compactMap({ $0 }).min(), let high = bpms.compactMap({ $0 }).max(),
           high - low >= minimumHeartRateSpread {
            intensity = bpms
        } else if speeds.allSatisfy({ $0 != nil }), let low = speeds.compactMap({ $0 }).min(), let high = speeds.compactMap({ $0 }).max(),
                  low > 0, high / low - 1 >= minimumSpeedSpread {
            intensity = speeds
        } else {
            return sorted.map { Segment(start: $0.start, end: $0.end, kind: .lap) }
        }
        let known = intensity.compactMap { $0 }
        let threshold = ((known.min() ?? 0) + (known.max() ?? 0)) / 2
        let hard = intensity.map { ($0 ?? 0) >= threshold }
        let switches = zip(hard, hard.dropFirst()).filter { $0 != $1 }.count
        guard switches >= minimumSwitches else { return sorted.map { Segment(start: $0.start, end: $0.end, kind: .lap) } }
        return sorted.enumerated().map { index, segment in
            let kind: Kind = hard[index] ? .work : (index == 0 ? .warmUp : (index == sorted.count - 1 ? .coolDown : .recovery))
            return Segment(start: segment.start, end: segment.end, kind: kind)
        }
    }

    // MARK: Numbers

    /// Each segment's numbers, in time order.
    public static func bouts(_ segments: [Segment], heartRate: [(date: Date, bpm: Double)], route: CardioRoute?) -> [Bout] {
        let readings = validReadings(heartRate)
        return segments.filter { $0.end > $0.start }.sorted { $0.start < $1.start }.enumerated().map { index, segment in
            let inside = readings.filter { $0.date >= segment.start && $0.date <= segment.end }
            return Bout(index: index + 1, kind: segment.kind, start: segment.start, end: segment.end,
                        averageBpm: CardioHeartSummary.timeWeightedAverage(inside),
                        peakBpm: inside.map(\.bpm).max(),
                        meters: route.flatMap { meters($0, from: segment.start, to: segment.end) })
        }
    }

    /// At least two hard bouts: worth a table of its own.
    public static func isIntervalWorkout(_ bouts: [Bout]) -> Bool {
        bouts.filter { $0.kind == .work }.count >= 2
    }

    /// Whether the bouts card shows: two bouts or more, and not plain laps
    /// on a workout whose splits table already shows the same distance.
    public static func showsCard(_ bouts: [Bout], fromSession: Bool, hasSplits: Bool) -> Bool {
        guard bouts.count >= 2 else { return false }
        return fromSession || isIntervalWorkout(bouts) || !hasSplits
    }

    /// The interval evidence line (Milanović 2015) belongs only under real
    /// intervals: a Tensile session, or hard and easy bouts that alternate.
    public static func showsIntervalEvidence(_ bouts: [Bout], fromSession: Bool) -> Bool {
        fromSession || isIntervalWorkout(bouts)
    }

    /// Hard bouts' average heart rate, first to last: a rise shows heart rate
    /// catching up with the effort, as expected in 4-minute intervals.
    public static func workAverages(_ bouts: [Bout]) -> [Double] {
        bouts.filter { $0.kind == .work }.compactMap(\.averageBpm)
    }

    static func validReadings(_ readings: [(date: Date, bpm: Double)]) -> [(date: Date, bpm: Double)] {
        readings.filter { $0.bpm.isFinite && $0.bpm > 0 }.sorted { $0.date < $1.date }
    }

    static func average(_ readings: [(date: Date, bpm: Double)], from start: Date, to end: Date) -> Double? {
        CardioHeartSummary.timeWeightedAverage(readings.filter { $0.date >= start && $0.date <= end })
    }

    /// Metres covered between two times; nil when the route doesn't span them.
    static func meters(_ route: CardioRoute, from start: Date, to end: Date) -> Double? {
        guard let a = route.meters(at: start), let b = route.meters(at: end) else { return nil }
        return max(0, b - a)
    }
}

extension CardioRoute {
    /// Distance from the start at a time, interpolated between fixes; nil
    /// outside the route's time span (or more than a minute past either end).
    public func meters(at time: Date) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        let slack: TimeInterval = 60
        if time <= first.time { return first.time.timeIntervalSince(time) <= slack ? 0 : nil }
        if time >= last.time { return time.timeIntervalSince(last.time) <= slack ? distanceMeters : nil }
        // Binary search for the last fix at or before `time`.
        var low = 0, high = points.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if points[middle].time <= time { low = middle } else { high = middle }
        }
        let span = points[high].time.timeIntervalSince(points[low].time)
        let fraction = span > 0 ? time.timeIntervalSince(points[low].time) / span : 0
        return cumulativeMeters[low] + fraction * (cumulativeMeters[high] - cumulativeMeters[low])
    }
}
