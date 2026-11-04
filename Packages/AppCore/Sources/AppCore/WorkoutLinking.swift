import Foundation

/// Pairs a logged gym session with the workout another device recorded at the
/// same time (an Apple Watch, a Garmin synced through its app), so history
/// shows one entry with the watch's heart rate and calories attached instead
/// of two workouts.
public enum WorkoutLinking {
    /// A workout in Apple Health from another app or device.
    public struct Candidate: Sendable, Equatable, Identifiable {
        public var id: UUID
        public var start: Date
        public var end: Date
        /// Where it came from, as Apple Health names it ("Apple Watch", "Garmin Connect").
        public var source: String
        public var isStrength: Bool

        public init(id: UUID, start: Date, end: Date, source: String, isStrength: Bool) {
            self.id = id
            self.start = start
            self.end = end
            self.source = source
            self.isStrength = isStrength
        }

        public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
    }

    /// The overlap has to cover at least half of the shorter workout. App
    /// choice: a watch started late or stopped early still matches, while a
    /// warm-up walk next to the gym session doesn't.
    public static let minimumOverlapFraction = 0.5

    /// Overlap as a fraction of the shorter of the two intervals (0-1).
    public static func overlapFraction(_ a: DateInterval, _ b: DateInterval) -> Double {
        let shorter = min(a.duration, b.duration)
        guard shorter > 0, let overlap = a.intersection(with: b) else { return 0 }
        return min(1, overlap.duration / shorter)
    }

    /// The candidate that shares the most time with `session`, among those
    /// covering at least half of the shorter one. Ties (within a second) go
    /// to strength workouts, then to the earlier start.
    public static func match(session: DateInterval, candidates: [Candidate]) -> Candidate? {
        var best: (candidate: Candidate, overlap: TimeInterval)?
        for candidate in candidates {
            guard overlapFraction(session, candidate.interval) >= minimumOverlapFraction else { continue }
            let overlap = session.intersection(with: candidate.interval)?.duration ?? 0
            guard let current = best else {
                best = (candidate, overlap)
                continue
            }
            let tie = abs(overlap - current.overlap) <= 1
            let betterTie = tie && (
                (candidate.isStrength && !current.candidate.isStrength)
                || (candidate.isStrength == current.candidate.isStrength && candidate.start < current.candidate.start)
            )
            if overlap > current.overlap + 1 || betterTie {
                best = (candidate, overlap)
            }
        }
        return best?.candidate
    }

    /// The phone session a watch recording belongs to when their ids don't
    /// agree (or the watch sent none): the one sharing the most time with the
    /// recording, covering at least half of the shorter of the two. A watch
    /// left running after the phone finished still matches. Nil when none
    /// overlaps enough, so a workout started on the watch alone stays its own.
    public static func sessionIndex(for recording: DateInterval, sessions: [DateInterval]) -> Int? {
        var best: (index: Int, overlap: TimeInterval)?
        for (index, session) in sessions.enumerated() {
            guard overlapFraction(recording, session) >= minimumOverlapFraction else { continue }
            let overlap = recording.intersection(with: session)?.duration ?? 0
            if overlap > (best?.overlap ?? -1) { best = (index, overlap) }
        }
        return best?.index
    }
}
