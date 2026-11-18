import Foundation

// Where an interval session stands at a moment of the workout: which step,
// how far into it, what's left and what comes next. Needs only Foundation
// and `IntervalSession.swift`, so the Watch app compiles it with that file
// (project.yml) and runs the session step by step (docs/research/watch-app-redesign-2026-11.md §4.6).

extension IntervalSession {
    /// The step running and its timing.
    public nonisolated struct Progress: Sendable, Equatable {
        /// Index into `steps`.
        public var index: Int
        public var step: Step
        /// Whole seconds into the step.
        public var elapsedInStep: Int
        /// Whole seconds left in the step (at least 1 while it runs).
        public var remaining: Int
        /// The step after this one; nil for the last.
        public var next: Step?

        /// Share of the step still to go, 0-1, for its ring.
        public var fractionLeft: Double {
            step.seconds > 0 ? min(1, max(0, Double(remaining) / Double(step.seconds))) : 0
        }
    }

    /// Seconds from the session's start to the start of step `index`.
    public nonisolated func startOffset(ofStep index: Int) -> Int {
        steps.prefix(max(0, min(index, steps.count))).reduce(0) { $0 + $1.seconds }
    }

    /// The step running `elapsed` seconds in; nil once the session is over.
    public nonisolated func progress(at elapsed: TimeInterval) -> Progress? {
        guard elapsed.isFinite, !steps.isEmpty else { return nil }
        let at = max(0, elapsed)
        var start = 0.0
        for (index, step) in steps.enumerated() {
            let end = start + Double(step.seconds)
            if at < end {
                let into = Int((at - start).rounded(.down))
                return Progress(index: index, step: step, elapsedInStep: into,
                                remaining: max(1, Int((end - at).rounded(.up))),
                                next: index + 1 < steps.count ? steps[index + 1] : nil)
            }
            start = end
        }
        return nil
    }

    /// Seconds to add to the clock to start the next step now ("Skip step"),
    /// or nil after the last.
    public nonisolated func skipSeconds(at elapsed: TimeInterval) -> TimeInterval? {
        guard let progress = progress(at: elapsed) else { return nil }
        return Double(startOffset(ofStep: progress.index + 1)) - max(0, elapsed)
    }
}
