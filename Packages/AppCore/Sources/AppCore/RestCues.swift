import Foundation

// When the Watch taps the wrist during a rest between sets, and how −15/+15
// moves the rest (docs/research/watch-app-redesign-2026-11.md §4.4.3).
// Foundation only, with no reference to anything else in AppCore, so the
// Watch app compiles this file on its own (project.yml).
//
// Rest lengths themselves come from the phone (`RestTimer` in
// TrainingTools.swift: Singer 2024, Schoenfeld 2016, Grgic 2018, ACSM 2009);
// these are only the cues around them:
// - a light tap 10 s before the end, so the lifter can get set: the app's
//   choice (usability only; no study tests a warning lead time);
// - a strong tap at the end (as before);
// - ±15 s steps (the existing app's choice). A rest never goes below zero:
//   taking off more than is left ends it.
// - A lift logged on the Watch alone, with no plan from the phone, rests
//   120 s: the app's choice between the ~90 s past which longer rest showed no
//   clear extra benefit for muscle growth (Singer et al., Front Sports Act
//   Living 2024, meta-analysis) and the 2-3 min heavy multi-joint lifts want
//   (Schoenfeld et al., J Strength Cond Res 2016; Grgic et al., Sports Med 2018).

public nonisolated enum RestCues {
    /// Seconds before the end of the warning tap.
    public static let warningSeconds: TimeInterval = 10
    /// The −/+ buttons' step.
    public static let stepSeconds = 15
    /// Rest for a standalone lift with no rest from the phone.
    public static let standaloneRestSeconds = 120

    /// A tap to play during a rest.
    public nonisolated enum Cue: Sendable, Equatable {
        /// Get set: the rest is nearly over.
        case warning
        /// The rest is over.
        case end
    }

    /// The taps still to come for a rest ending at `end`, in order, with when
    /// each is due. A rest shorter than the warning lead gets no warning
    /// (it would land at its start).
    public static func schedule(endsAt end: Date, startedAt start: Date, now: Date) -> [(cue: Cue, at: Date)] {
        guard end > now else { return [] }
        var cues: [(cue: Cue, at: Date)] = []
        let warning = end.addingTimeInterval(-warningSeconds)
        if warning > now, end.timeIntervalSince(start) > warningSeconds * 2 {
            cues.append((.warning, warning))
        }
        cues.append((.end, end))
        return cues
    }

    /// The rest moved by `seconds` (negative shortens it). Nil when that ends
    /// it: a rest never runs below zero.
    public static func adjusted(endsAt end: Date, by seconds: Int, now: Date) -> Date? {
        let moved = end.addingTimeInterval(Double(seconds))
        return moved > now ? moved : nil
    }

    /// The full length after a move, for the ring: never less than what's
    /// left, and at least one step.
    public static func adjustedLength(_ length: Int, by seconds: Int, remaining: TimeInterval) -> Int {
        max(stepSeconds, Int(remaining.rounded(.up)), length + seconds)
    }

    /// Share of the rest still to go, 0-1, for the ring.
    public static func fractionLeft(endsAt end: Date, length: Int, now: Date) -> Double {
        guard length > 0 else { return 0 }
        return min(1, max(0, end.timeIntervalSince(now) / Double(length)))
    }
}
