import Foundation

/// Splits a night's asleep intervals into separate sleep sessions, so an
/// afternoon nap or an evening doze on the couch isn't merged into the night.
public enum SleepSessions {
    /// A gap awake longer than this ends a session. Night-time awakenings are
    /// almost always shorter; a nap is usually hours away from the night.
    public static let defaultGap: TimeInterval = 90 * 60

    public struct Session: Sendable, Equatable {
        /// Asleep intervals in the session, merged so overlapping sources
        /// (e.g. iPhone and watch) aren't counted twice. Sorted by time.
        public var intervals: [DateInterval]

        public init(intervals: [DateInterval]) {
            self.intervals = intervals
        }

        public var start: Date { intervals.first?.start ?? .distantPast }
        public var end: Date { intervals.last?.end ?? .distantPast }
        public var asleep: TimeInterval { intervals.map(\.duration).reduce(0, +) }
    }

    /// Merges overlapping intervals, then groups them into sessions.
    public static func sessions(_ intervals: [DateInterval], gap: TimeInterval = defaultGap) -> [Session] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var result: [Session] = []
        for interval in merged {
            if let last = result.last, interval.start.timeIntervalSince(last.end) <= gap {
                result[result.count - 1].intervals.append(interval)
            } else {
                result.append(Session(intervals: [interval]))
            }
        }
        return result
    }

    /// The main sleep: the session with the most time asleep.
    public static func main(_ intervals: [DateInterval], gap: TimeInterval = defaultGap) -> Session? {
        sessions(intervals, gap: gap).max { $0.asleep < $1.asleep }
    }
}
