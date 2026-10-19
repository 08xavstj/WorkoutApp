import Foundation

/// Muscle groups, named as in the exercise library (free-exercise-db).
public enum Muscle: String, CaseIterable, Sendable, Codable {
    case chest, shoulders, triceps, biceps, forearms
    case lats, middleBack = "middle back", lowerBack = "lower back", traps, neck
    case abdominals, quadriceps, hamstrings, glutes, calves, adductors, abductors

    public var name: String {
        switch self {
        case .middleBack: "Upper back"
        case .lowerBack: "Lower back"
        case .abdominals: "Abs"
        case .quadriceps: "Quads"
        default: rawValue.capitalized
        }
    }

    /// Big muscles take longer to recover than small ones.
    var recoveryHours: Double {
        switch self {
        case .quadriceps, .hamstrings, .glutes, .lats, .middleBack, .lowerBack, .chest, .adductors: 36
        default: 26
        }
    }

    public var isLowerBody: Bool {
        [.quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors].contains(self)
    }

    static let push: [Muscle] = [.chest, .shoulders, .triceps]
    static let pull: [Muscle] = [.lats, .middleBack, .biceps, .traps]
    static let legs: [Muscle] = [.quadriceps, .hamstrings, .glutes]
}

/// How recovered each muscle is and how much it has trained this week.
///
/// - Recovery: each hard set adds fatigue to the muscles it works (helper
///   muscles count half) and fades exponentially. Big muscles take about
///   72 h to recover from a hard session, small ones about 48 h, in line with
///   the 48-72 h recovery window in the research (Bishop et al., J Strength
///   Cond Res 2008; Schoenfeld et al., Sports Med 2016 on training each muscle
///   about twice a week).
/// - Weekly volume: about 10-20 hard sets a muscle a week builds the most
///   muscle (Schoenfeld et al., J Sports Sci 2017; Baz-Valle et al., J Hum
///   Kinet 2022). More can still add muscle with diminishing returns (Pelland
///   et al., Sports Med 2026), so 20+ is "high: fine if you recover", and a
///   muscle is only flagged when high volume meets poor recovery. Recovery
///   times are a model built on the commonly taught 48-72 h window, not a
///   measured value; soreness check-ins override them.
public enum MuscleRecovery {
    /// One working set, with the muscles of its exercise.
    public struct WorkSet: Sendable, Equatable {
        public var date: Date
        public var primary: [String]
        public var secondary: [String]
        public var rpe: Double?

        public init(date: Date, primary: [String], secondary: [String] = [], rpe: Double? = nil) {
            self.date = date
            self.primary = primary
            self.secondary = secondary
            self.rpe = rpe
        }
    }

    /// A run, ride or other cardio session that also tires the legs.
    public struct Cardio: Sendable, Equatable {
        public enum Kind: Sendable { case run, ride, row, hike, other }
        public var kind: Kind
        public var end: Date
        public var minutes: Double

        public init(kind: Kind, end: Date, minutes: Double) {
            self.kind = kind
            self.end = end
            self.minutes = minutes
        }
    }

    public enum Status: String, Sendable {
        case fresh = "Fresh"
        case recovering = "Recovering"
        case fatigued = "Fatigued"
    }

    public enum Volume: String, Sendable {
        case none = "Not trained"
        case low = "Low"
        case productive = "Productive"
        case high = "High"
    }

    public struct State: Sendable, Equatable, Identifiable {
        public var muscle: Muscle
        /// 0 (just hammered) ... 100 (fully recovered).
        public var recovery: Double
        /// Hard sets in the last 7 days (helper muscles count half).
        public var weeklySets: Double
        public var lastTrained: Date?
        public var id: Muscle { muscle }

        public var status: Status {
            recovery >= 85 ? .fresh : (recovery >= 50 ? .recovering : .fatigued)
        }

        public var volume: Volume {
            switch weeklySets {
            case ..<0.5: .none
            case ..<10: .low
            case ...20: .productive
            default: .high
            }
        }

        /// Trained a lot this week and still not recovered.
        public var isOverworked: Bool { weeklySets > 20 && recovery < 60 }

        /// Hours until about 85% recovered (nil if already there).
        public var hoursUntilFresh: Double? {
            guard recovery < 85 else { return nil }
            let fatigue = 100 - recovery
            return muscle.recoveryHours * log(fatigue / 15)
        }
    }

    /// Fatigue units one hard set leaves on a muscle (10 hard sets ≈ 80%).
    static let fatiguePerSet = 8.0

    public static func evaluate(sets: [WorkSet], cardio: [Cardio] = [], now: Date = .now) -> [Muscle: State] {
        var fatigue: [Muscle: Double] = [:]
        var weekly: [Muscle: Double] = [:]
        var last: [Muscle: Date] = [:]
        let weekAgo = now.addingTimeInterval(-7 * 86_400)

        func add(_ muscle: Muscle, weight: Double, at date: Date) {
            guard date <= now else { return }
            let hours = now.timeIntervalSince(date) / 3600
            fatigue[muscle, default: 0] += fatiguePerSet * weight * exp(-hours / muscle.recoveryHours)
            if date >= weekAgo { weekly[muscle, default: 0] += weight }
            if last[muscle].map({ date > $0 }) ?? true { last[muscle] = date }
        }

        for set in sets {
            // Easy sets (RPE under 7) tire muscles less.
            let effort = (set.rpe ?? 8) >= 7 ? 1.0 : 0.6
            for name in set.primary {
                if let muscle = Muscle(rawValue: name.lowercased()) { add(muscle, weight: effort, at: set.date) }
            }
            for name in set.secondary {
                if let muscle = Muscle(rawValue: name.lowercased()) { add(muscle, weight: effort * 0.5, at: set.date) }
            }
        }
        for session in cardio {
            // About one hard set's worth per 10 minutes for the main muscles.
            let units = min(6, session.minutes / 10)
            let muscles: [Muscle] = switch session.kind {
            case .run, .hike: [.quadriceps, .hamstrings, .calves, .glutes]
            case .ride: [.quadriceps, .glutes, .calves]
            case .row: [.lats, .middleBack, .quadriceps, .biceps]
            case .other: []
            }
            for muscle in muscles {
                add(muscle, weight: units * 0.5, at: session.end)
            }
        }

        var result: [Muscle: State] = [:]
        for muscle in Muscle.allCases {
            result[muscle] = State(
                muscle: muscle,
                recovery: max(0, 100 - min(100, fatigue[muscle] ?? 0)),
                weeklySets: ((weekly[muscle] ?? 0) * 10).rounded() / 10,
                lastTrained: last[muscle]
            )
        }
        return result
    }

    /// A focus that trains fresh muscles and rests tired ones, or nil if all is fine.
    public static func suggestedFocus(_ states: [Muscle: State]) -> WorkoutFocus? {
        func average(_ muscles: [Muscle]) -> Double {
            let values = muscles.compactMap { states[$0]?.recovery }
            return values.isEmpty ? 100 : values.reduce(0, +) / Double(values.count)
        }
        let legs = average(Muscle.legs)
        let push = average(Muscle.push)
        let pull = average(Muscle.pull)
        let threshold = 60.0
        if legs < threshold, push >= threshold, pull >= threshold { return .upper }
        if legs >= threshold, push < threshold, pull < threshold { return .lower }
        if push < threshold, pull >= threshold { return .pull }
        if pull < threshold, push >= threshold { return .push }
        return nil
    }
}
