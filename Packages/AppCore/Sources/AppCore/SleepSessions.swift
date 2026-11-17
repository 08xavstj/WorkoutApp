import Foundation

/// Splits a night's asleep intervals into separate sleep sessions, so an
/// afternoon nap or an evening doze on the couch isn't merged into the night.
public enum SleepSessions {
    /// A gap awake longer than this ends a session. Night-time awakenings are
    /// almost always shorter; a nap is usually hours away from the night.
    public static let defaultGap: TimeInterval = 90 * 60
    /// Two sessions up to this far apart are still one night when both are
    /// real blocks of sleep (`splitNightMinimumBlock`): a night broken by a
    /// long spell awake (a child, a flight, insomnia). With only the 90-minute
    /// rule, 3 h + 100 minutes awake + 3 h was scored as a 3 h night while 80
    /// minutes awake made it a 6 h one. Three hours and the one-hour block are
    /// the app's choice, not a published rule; a nap further than this from
    /// the night stays separate.
    public static let splitNightGap: TimeInterval = 180 * 60
    /// Least time asleep on each side for a 90-180-minute gap to be bridged,
    /// so an evening doze on the couch isn't pulled into the night (app choice).
    public static let splitNightMinimumBlock: TimeInterval = 60 * 60

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

    /// Merges overlapping intervals, then groups them into sessions: pieces up
    /// to `gap` apart always belong together, and two sessions up to
    /// `splitNightGap` apart are joined when each has at least
    /// `splitNightMinimumBlock` asleep (a split night).
    public static func sessions(_ intervals: [DateInterval], gap: TimeInterval = defaultGap,
                                splitNightGap: TimeInterval = SleepSessions.splitNightGap) -> [Session] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var grouped: [Session] = []
        for interval in merged {
            if let last = grouped.last, interval.start.timeIntervalSince(last.end) <= gap {
                grouped[grouped.count - 1].intervals.append(interval)
            } else {
                grouped.append(Session(intervals: [interval]))
            }
        }
        // Split nights: bridge a longer gap between two substantial blocks.
        var result: [Session] = []
        for session in grouped {
            if let last = result.last, session.start.timeIntervalSince(last.end) <= splitNightGap,
               last.asleep >= splitNightMinimumBlock, session.asleep >= splitNightMinimumBlock {
                result[result.count - 1].intervals.append(contentsOf: session.intervals)
            } else {
                result.append(session)
            }
        }
        return result
    }

    /// The main sleep: the session with the most time asleep.
    public static func main(_ intervals: [DateInterval], gap: TimeInterval = defaultGap,
                            splitNightGap: TimeInterval = SleepSessions.splitNightGap) -> Session? {
        sessions(intervals, gap: gap, splitNightGap: splitNightGap).max { $0.asleep < $1.asleep }
    }
}
