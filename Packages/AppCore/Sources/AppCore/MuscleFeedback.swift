import Foundation

/// Optional per-muscle answers after a session, in the style of the
/// Renaissance Periodization (RP) feedback loop: pump (low / OK / great),
/// soreness from the last session that trained it (none / mild / still
/// sore), and joint pain (no / yes). One tap each, all skippable.
///
/// Evidence, plainly: this is coaching **practice**, not a tested rule.
/// - RP's volume landmarks and its pump/soreness questionnaire come from
///   practice (Israetel M, Hoffmann J, Smith CW. Scientific Principles of
///   Hypertrophy Training. Renaissance Periodization, 2021); no trial has
///   compared feedback-steered volume with a fixed ramp.
/// - The pump is a proposed, not shown, signal for growth (Schoenfeld BJ,
///   Contreras B. The muscle pump: potential mechanisms and applications for
///   enhancing hypertrophic adaptations. Strength Cond J 2014;36(3):21-25).
/// - Soreness tracks muscle damage and novelty, not growth (Schoenfeld BJ,
///   Contreras B. Is postexercise muscle soreness a valid indicator of
///   muscular adaptations? Strength Cond J 2013;35(5):16-21; Nosaka K, Newton
///   M, Sacco P. Delayed-onset muscle soreness does not reflect the magnitude
///   of eccentric exercise-induced muscle damage. Scand J Med Sci Sports
///   2002;12:337-346; Damas F et al., J Physiol 2016: growth tracked protein
///   synthesis only once damage had faded).
/// - What the weekly sets do is better shown (Schoenfeld, Ogborn & Krieger,
///   J Sports Sci 2017; Pelland et al., Sports Med 2026), so performance
///   stays the main rule in `VolumeProgression` and the answers can only
///   hold a muscle, take one set off when it keeps coming back sore or
///   painful, or allow one set when you say it has recovered while the
///   recovery model still thinks it's tired. All of these are app choices.
/// - Joint pain is handled by the pain log (`PainGuard`); the answer here
///   only holds the muscle's volume and points to that log.
public enum MuscleFeedback {
    public enum Pump: String, Codable, Sendable, CaseIterable {
        case low, ok, great

        public var title: String {
            switch self {
            case .low: "Low"
            case .ok: "OK"
            case .great: "Great"
            }
        }
    }

    public enum Soreness: String, Codable, Sendable, CaseIterable {
        /// "None". Not named `none`: as an optional it would read as nil.
        case notSore, mild, stillSore

        public var title: String {
            switch self {
            case .notSore: "None"
            case .mild: "Mild"
            case .stillSore: "Still sore"
            }
        }

        /// None or mild: recovered enough to train it again (RP practice).
        public var isRecovered: Bool { self != .stillSore }
    }

    /// One muscle's answers for one session (keyed by the session's start).
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var sessionStart: Date
        public var muscle: Muscle
        public var pump: Pump?
        public var soreness: Soreness?
        public var jointPain: Bool?

        public init(sessionStart: Date, muscle: Muscle, pump: Pump? = nil, soreness: Soreness? = nil, jointPain: Bool? = nil) {
            self.sessionStart = sessionStart
            self.muscle = muscle
            self.pump = pump
            self.soreness = soreness
            self.jointPain = jointPain
        }

        public var id: String { "\(sessionStart.timeIntervalSince1970)|\(muscle.rawValue)" }
        public var isEmpty: Bool { pump == nil && soreness == nil && jointPain == nil }
    }

    /// What one week's answers say about a muscle (`signals`).
    public struct Signal: Sendable, Equatable {
        /// The newest pump answer in the week.
        public var pump: Pump?
        /// The newest soreness answer in the week.
        public var soreness: Soreness?
        /// Sessions in the week where it was still sore.
        public var soreReports: Int
        /// The session the newest "still sore" was left over from (the one
        /// before it that trained the muscle), if known.
        public var soreFrom: Date?
        /// Sessions in the week with joint pain for it.
        public var jointPainReports: Int

        public init(pump: Pump? = nil, soreness: Soreness? = nil, soreReports: Int = 0, soreFrom: Date? = nil,
                    jointPainReports: Int = 0) {
            self.pump = pump
            self.soreness = soreness
            self.soreReports = soreReports
            self.soreFrom = soreFrom
            self.jointPainReports = jointPainReports
        }

        /// Still sore at the newest answer.
        public var isStillSore: Bool { soreness == .stillSore }

        /// Still sore at two or more sessions, the newest included: one set
        /// fewer (`repeatedReports`, app choice).
        public var soreRepeatedly: Bool { isStillSore && soreReports >= MuscleFeedback.repeatedReports }

        /// Joint pain at two or more sessions: one set fewer (app choice).
        public var painRepeatedly: Bool { jointPainReports >= MuscleFeedback.repeatedReports }

        /// You said it had recovered (no or mild soreness) and the pump was
        /// low or OK: the one case where an answer can add a set, and only
        /// one, when the recovery model alone would hold it (RP practice; app choice).
        public var allowsStepWhenTired: Bool {
            guard let soreness, soreness.isRecovered, let pump else { return false }
            return pump != .great
        }
    }

    /// Answers at this many sessions in a week count as "repeated" (app choice:
    /// one sore day can be a new exercise or a bad night; two in a week is a pattern).
    public static let repeatedReports = 2

    /// The card asks about at most this many muscles (app choice: one tap per
    /// question stays quick).
    public static let maximumMuscles = 4

    /// A muscle needs this many hard sets in the session to be asked about
    /// (app choice: a muscle that only helped isn't "trained" for this).
    public static let minimumSets = 2.0

    /// The session's main muscles, most sets first: tracked muscles
    /// (`MuscleCoverage.tracked`) with at least `minimumSets` hard sets, at
    /// most `maximumMuscles`.
    public static func mainMuscles(_ sets: [Muscle: Double]) -> [Muscle] {
        let tracked = MuscleCoverage.tracked
        return sets.filter { tracked.contains($0.key) && $0.value >= minimumSets - 0.001 }
            .sorted { a, b in
                if abs(a.value - b.value) > 0.001 { return a.value > b.value }
                return (tracked.firstIndex(of: a.key) ?? 0) < (tracked.firstIndex(of: b.key) ?? 0)
            }
            .prefix(maximumMuscles)
            .map(\.key)
    }

    /// Each muscle's answers from sessions in the week starting `weekStart`.
    /// `sets` (logged working sets) find the session a "still sore" was left
    /// over from: the newest earlier session, within `soreLookbackDays`, that
    /// trained the muscle as a main muscle.
    public static func signals(_ entries: [Entry], sets: [VolumeProgression.LoggedSet], weekStart: Date,
                               calendar: Calendar = .current) -> [Muscle: Signal] {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart.addingTimeInterval(7 * 86_400)
        let inWeek = entries.filter { $0.sessionStart >= weekStart && $0.sessionStart < weekEnd && !$0.isEmpty }
            .sorted { $0.sessionStart < $1.sessionStart }
        var result: [Muscle: Signal] = [:]
        for entry in inWeek {
            var signal = result[entry.muscle] ?? Signal()
            if let pump = entry.pump { signal.pump = pump }
            if let soreness = entry.soreness {
                signal.soreness = soreness
                if soreness == .stillSore {
                    signal.soreReports += 1
                    signal.soreFrom = previousSession(training: entry.muscle, before: entry.sessionStart, sets: sets)
                }
            }
            if entry.jointPain == true { signal.jointPainReports += 1 }
            result[entry.muscle] = signal
        }
        return result
    }

    /// How far back a "still sore" looks for the session it came from.
    static let soreLookbackDays = 7.0

    static func previousSession(training muscle: Muscle, before start: Date, sets: [VolumeProgression.LoggedSet]) -> Date? {
        let earliest = start.addingTimeInterval(-soreLookbackDays * 86_400)
        return sets.filter { $0.primary.contains(muscle) && $0.isCompleted && $0.sessionStart < start && $0.sessionStart >= earliest }
            .map(\.sessionStart)
            .max()
    }
}
