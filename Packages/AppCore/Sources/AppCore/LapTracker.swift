import Foundation

// Laps, splits and current pace for the Watch's cardio pages
// (docs/research/watch-app-redesign-2026-11.md §4.5.3). Foundation only, with
// no reference to anything else in AppCore, so the Watch app compiles this
// file on its own (project.yml, `TensileWatch: sources:`).
//
// - Auto Lap every 1 km, or 1 mi where distances are in miles: the app's
//   choice, following the Garmin Auto Lap convention and Apple's Workout app
//   splits. Saved as `HKWorkoutEvent(.lap)` with a start and end.
// - A manual lap (the Lap button) closes the current lap at once and is saved
//   as `.segment`, a period of interest, since it isn't an equal distance.
// - Current pace is the distance over the last 20 s, the same window the map
//   smooths speed over (`CardioRoute.speedWindowSeconds`, app's choice):
//   second-by-second distance swings with each GPS fix.
// - Time while paused (by hand or auto-pause) counts toward no lap and no pace.

/// Laps and current pace from cumulative distance samples.
public nonisolated struct LapTracker: Sendable, Equatable {
    /// One finished lap.
    public nonisolated struct Lap: Sendable, Equatable, Identifiable {
        /// 1-based.
        public var number: Int
        public var start: Date
        public var end: Date
        public var meters: Double
        /// Time running in the lap, without pauses.
        public var seconds: Double
        /// True for an auto lap at a whole kilometre or mile.
        public var isAuto: Bool

        public var id: Int { number }

        /// Seconds per km (or mi), or nil for a lap too short to have a pace.
        public func pace(miles: Bool) -> Double? {
            guard meters >= LapTracker.minimumMetersForPace, seconds > 0 else { return nil }
            return seconds / (meters / (miles ? LapTracker.metersPerMile : 1000))
        }

        /// km/h (or mph), or nil for a lap too short.
        public func speed(miles: Bool) -> Double? {
            guard meters >= LapTracker.minimumMetersForPace, seconds > 0 else { return nil }
            return (meters / (miles ? LapTracker.metersPerMile : 1000)) / (seconds / 3600)
        }
    }

    public static let metersPerMile = 1609.344
    /// Window for the current pace, in seconds of running time (see above).
    public static let rollingWindowSeconds = 20.0
    /// Below this, a lap or a window has no pace: over a few metres it is noise
    /// (app's choice; the end screen uses 100 m for the whole workout).
    public static let minimumMetersForPace = 20.0
    /// Distance samples older than this (in running time) are dropped.
    private static let keepSeconds = 120.0

    /// Auto Lap distance: 1 km, or 1 mile.
    public static func autoLapMeters(miles: Bool) -> Double {
        miles ? metersPerMile : 1000
    }

    private nonisolated struct Sample: Sendable, Equatable {
        var active: Double
        var date: Date
        var meters: Double
    }

    /// Nil for no auto laps (sports, machines).
    public let autoLapMeters: Double?
    public let start: Date
    public private(set) var laps: [Lap] = []
    /// Distance so far, in metres.
    public private(set) var meters = 0.0

    private var pausedSeconds = 0.0
    private var pausedAt: Date?
    private var lapStartActive = 0.0
    private var lapStartDate: Date
    private var lapStartMeters = 0.0
    private var samples: [Sample] = []

    public init(start: Date, autoLapMeters: Double?) {
        self.start = start
        self.autoLapMeters = autoLapMeters.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        lapStartDate = start
    }

    public var isPaused: Bool { pausedAt != nil }

    /// Running time since the start, without pauses.
    public func activeSeconds(at date: Date) -> Double {
        let running = pausedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, date.timeIntervalSince(start) - pausedSeconds - running)
    }

    /// The number of the lap now running (1-based).
    public var currentLapNumber: Int { laps.count + 1 }

    /// Seconds and metres in the lap now running.
    public func currentLap(at date: Date) -> (seconds: Double, meters: Double) {
        (max(0, activeSeconds(at: date) - lapStartActive), max(0, meters - lapStartMeters))
    }

    /// The new total distance at `date`. Returns the auto laps it completed
    /// (usually none, at most one per sample unless a sample jumps kilometres).
    @discardableResult
    public mutating func add(meters total: Double, at date: Date) -> [Lap] {
        guard total.isFinite, total >= meters, date >= start else { return [] }
        let active = activeSeconds(at: date)
        let previous = samples.last ?? Sample(active: lapStartActive, date: lapStartDate, meters: meters)
        var finished: [Lap] = []
        if !isPaused, let every = autoLapMeters {
            var boundary = (floor(lapStartMeters / every) + 1) * every
            while total >= boundary {
                // When the boundary was crossed, between the last sample and this one.
                let span = total - previous.meters
                let share = span > 0 ? min(1, max(0, (boundary - previous.meters) / span)) : 1
                let crossedActive = previous.active + (active - previous.active) * share
                let crossedDate = previous.date.addingTimeInterval(date.timeIntervalSince(previous.date) * share)
                finished.append(close(atActive: crossedActive, date: crossedDate, meters: boundary, isAuto: true))
                boundary += every
            }
        }
        meters = total
        if !isPaused {
            samples.append(Sample(active: active, date: date, meters: total))
            samples.removeAll { active - $0.active > Self.keepSeconds }
        }
        return finished
    }

    /// The Lap button: closes the lap now running. Nil when it has no time in it.
    @discardableResult
    public mutating func markLap(at date: Date) -> Lap? {
        let active = activeSeconds(at: date)
        guard active - lapStartActive >= 1 else { return nil }
        return close(atActive: active, date: date, meters: meters, isAuto: false)
    }

    private mutating func close(atActive active: Double, date: Date, meters end: Double, isAuto: Bool) -> Lap {
        let lap = Lap(number: laps.count + 1, start: lapStartDate, end: max(lapStartDate, date),
                      meters: max(0, end - lapStartMeters), seconds: max(0, active - lapStartActive), isAuto: isAuto)
        laps.append(lap)
        lapStartActive = active
        lapStartDate = max(lapStartDate, date)
        lapStartMeters = end
        return lap
    }

    public mutating func pause(at date: Date) {
        guard pausedAt == nil else { return }
        pausedAt = date
    }

    /// Running again: the pace window starts over, so the stop isn't in it.
    public mutating func resume(at date: Date) {
        guard let since = pausedAt else { return }
        pausedSeconds += max(0, date.timeIntervalSince(since))
        pausedAt = nil
        samples = [Sample(active: activeSeconds(at: date), date: date, meters: meters)]
    }

    /// Metres per second over the last `rollingWindowSeconds` of running, or
    /// nil without enough distance or time in the window.
    public func currentSpeed(at date: Date) -> Double? {
        guard !isPaused, let last = samples.last else { return nil }
        let now = max(last.active, activeSeconds(at: date))
        // Stale: no new distance for longer than the window means standing still.
        guard now - last.active <= Self.rollingWindowSeconds else { return 0 }
        let windowStart = now - Self.rollingWindowSeconds
        guard let first = samples.first(where: { $0.active >= windowStart }) ?? samples.first,
              last.active - first.active >= Self.rollingWindowSeconds / 2 else { return nil }
        let meters = last.meters - first.meters
        let seconds = last.active - first.active
        guard seconds > 0 else { return nil }
        return meters / seconds
    }

    /// Current pace in seconds per km (or mi), or nil when standing still or unknown.
    public func currentPace(at date: Date, miles: Bool) -> Double? {
        guard let speed = currentSpeed(at: date), speed > 0 else { return nil }
        return (miles ? Self.metersPerMile : 1000) / speed
    }

    /// Pace of the lap now running, in seconds per km (or mi).
    public func currentLapPace(at date: Date, miles: Bool) -> Double? {
        let lap = currentLap(at: date)
        guard lap.meters >= Self.minimumMetersForPace, lap.seconds > 0 else { return nil }
        return lap.seconds / (lap.meters / (miles ? Self.metersPerMile : 1000))
    }

    /// The fastest finished lap by pace (auto laps only when there are any).
    public var fastestLapNumber: Int? {
        let pool = laps.contains(where: \.isAuto) ? laps.filter(\.isAuto) : laps
        return pool.filter { $0.meters >= Self.minimumMetersForPace && $0.seconds > 0 }
            .min { $0.seconds / $0.meters < $1.seconds / $1.meters }?.number
    }
}
