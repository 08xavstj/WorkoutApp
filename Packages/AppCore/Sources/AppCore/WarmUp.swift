import Foundation

/// Ramp sets before a loaded lift, rounded to what the gym can load.
///
/// A specific warm-up of a few lighter sets of the lift itself improved
/// strength and power performance in most measures (Ribeiro et al., J
/// Strength Cond Res 2020, review; Fradkin, Zazryn & Smoliga, J Strength
/// Cond Res 2010, meta-analysis: better in ~79% of criteria). The ACSM's
/// position stand recommends a specific warm-up before heavy multi-joint
/// lifts (Med Sci Sports Exerc 2009). The 50/70/85% ramp is the common
/// coaching pattern, not a tested optimum, so the UI calls it a suggestion.
/// Injury-prevention evidence for warm-ups is weaker (competitors.md §2a.4).
public enum WarmUp {
    public struct RampSet: Codable, Sendable, Equatable {
        /// In the gym's unit (per hand for dumbbells).
        public var load: Double
        public var reps: Int

        public init(load: Double, reps: Int) {
            self.load = load
            self.reps = reps
        }
    }

    /// Where a lift sits in the session.
    public enum Role: Sendable, Equatable {
        /// The first multi-joint lift: a full ramp.
        case firstCompound
        /// Later multi-joint lifts: one feeler set, the muscles are warm.
        case laterCompound
        /// Isolation work: no ramp sets.
        case isolation
    }

    /// Full ramp: about 50% × 8, 70% × 5, 85% × 2 of the working load.
    public static let fullRamp: [(fraction: Double, reps: Int)] = [(0.5, 8), (0.7, 5), (0.85, 2)]
    /// One set at about 70% × 3 for later compound lifts.
    public static let shortRamp: [(fraction: Double, reps: Int)] = [(0.7, 3)]

    /// Ramp sets for a working load, each rounded down to a load the gym can
    /// make. Sets that would be the empty bar, that repeat the one before, or
    /// that reach the working load are skipped, so a light lift gets fewer.
    public static func sets(workingLoad: Double, kind: EquipmentKind?, gym: GymProfile, role: Role = .firstCompound) -> [RampSet] {
        guard let kind, workingLoad > 0, role != .isolation else { return [] }
        let ramp = role == .firstCompound ? fullRamp : shortRamp
        let bar = barWeight(kind, gym: gym)
        var result: [RampSet] = []
        for step in ramp {
            guard let load = gym.load(atMost: workingLoad * step.fraction, on: kind) else { continue }
            if let bar, load <= bar + 0.001 { continue }
            if load >= workingLoad - 0.001 { continue }
            if let last = result.last, abs(last.load - load) < 0.001 { continue }
            result.append(RampSet(load: load, reps: step.reps))
        }
        return result
    }

    /// "95 × 8, 135 × 5, 165 × 2"
    public static func summary(_ sets: [RampSet]) -> String {
        sets.map { "\($0.load.formatted(.number.precision(.fractionLength(0...2)))) × \($0.reps)" }.joined(separator: ", ")
    }

    static func barWeight(_ kind: EquipmentKind, gym: GymProfile) -> Double? {
        switch kind {
        case .barbell: gym.barbellWeight
        case .ezBar: gym.ezBarWeight
        case .smithMachine: gym.smithBarWeight
        default: nil
        }
    }
}
