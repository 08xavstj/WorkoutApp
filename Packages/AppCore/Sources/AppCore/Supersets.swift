import Foundation

/// Pairs exercises that don't share muscles so a set of one is done straight
/// after a set of the other, with one rest after both.
///
/// Agonist-antagonist and upper-lower paired sets keep muscle growth and most
/// strength gains while cutting session time by roughly 35-40% (Iversen et
/// al., Sports Med 2021, "No Time to Lift?", review of RCTs; Weakley et al.,
/// Eur J Appl Physiol 2017: paired sets kept performance with less time).
/// Pairs here count at about 60% of their separate time
/// (`WorkoutPlanner.estimatedMinutes`). Goal tailoring from
/// docs/research/competitors.md §2a.3: strength keeps its big lifts as
/// straight sets and pairs only accessories; other styles pair freely.
public enum Supersets {
    /// Muscles a movement pattern loads enough to compete for recovery
    /// between sets. Two slots pair when these don't overlap.
    public static func muscles(_ slot: MovementSlot) -> Set<String> {
        switch slot {
        case .horizontalPress, .inclinePress: ["chest", "front delts", "triceps"]
        case .verticalPress: ["front delts", "side delts", "triceps"]
        case .chestFly: ["chest"]
        case .lateralRaise: ["side delts"]
        case .triceps: ["triceps"]
        case .verticalPull: ["lats", "biceps"]
        case .horizontalRow: ["lats", "upper back", "biceps"]
        case .rearDelt: ["rear delts", "upper back"]
        case .biceps: ["biceps"]
        case .hammerCurl: ["biceps", "forearms"]
        case .squat: ["quads", "glutes", "lower back"]
        case .hinge: ["hamstrings", "glutes", "lower back"]
        case .singleLeg: ["quads", "glutes"]
        case .legCurl: ["hamstrings"]
        case .legExtension: ["quads"]
        case .calves: ["calves"]
        case .core: ["core"]
        case .hipThrust: ["glutes", "hamstrings"]
        }
    }

    /// True when the two movements can share a superset: no muscle in
    /// common (push with pull, upper with lower, a compound with a distant
    /// isolation), and for the strength style no compound lift at all.
    public static func canPair(_ a: MovementSlot, _ b: MovementSlot, style: TrainingStyle = .balanced) -> Bool {
        guard a != b else { return false }
        if style == .strength, a.isCompound || b.isCompound { return false }
        return muscles(a).isDisjoint(with: muscles(b))
    }

    /// Greedy pairing in session order: each unpaired exercise takes the next
    /// compatible one, which moves up to sit right after it. Pairs get
    /// `supersetGroup` 1, 2, …; exercises outside the catalog stay as they are.
    public static func pair(exercises: [PlannedExercise], style: TrainingStyle = .balanced) -> [PlannedExercise] {
        var remaining = exercises.map { exercise -> PlannedExercise in
            var copy = exercise
            copy.supersetGroup = nil
            return copy
        }
        var result: [PlannedExercise] = []
        var group = 0
        while !remaining.isEmpty {
            var first = remaining.removeFirst()
            guard let slot = ExerciseCatalog.slot(for: first.exerciseID),
                  let partnerIndex = remaining.firstIndex(where: { candidate in
                      guard let other = ExerciseCatalog.slot(for: candidate.exerciseID) else { return false }
                      return canPair(slot, other, style: style)
                  }) else {
                result.append(first)
                continue
            }
            var partner = remaining.remove(at: partnerIndex)
            group += 1
            first.supersetGroup = group
            partner.supersetGroup = group
            result.append(first)
            result.append(partner)
        }
        return result
    }

    /// Clears a group that lost its partner (e.g. to `WorkoutPlanner.fit`).
    public static func dropOrphans(_ exercises: inout [PlannedExercise]) {
        let counts = Dictionary(grouping: exercises.compactMap(\.supersetGroup), by: { $0 }).mapValues(\.count)
        for index in exercises.indices {
            if let group = exercises[index].supersetGroup, counts[group, default: 0] < 2 {
                exercises[index].supersetGroup = nil
            }
        }
    }

    /// "A1" / "A2" for group 1, "B1" / "B2" for group 2 …
    public static func label(group: Int, position: Int) -> String {
        let letters = Array("ABCDEFGH")
        let letter = letters[max(0, min(letters.count - 1, group - 1))]
        return "\(letter)\(position)"
    }

    /// The label for an exercise in a list, from its group and whether it's
    /// the first of its pair; nil when it isn't in a superset.
    public static func label(for index: Int, in exercises: [PlannedExercise]) -> String? {
        guard index < exercises.count, let group = exercises[index].supersetGroup else { return nil }
        let position = exercises[..<index].contains { $0.supersetGroup == group } ? 2 : 1
        return label(group: group, position: position)
    }

    /// How much of its separate time a paired set takes.
    public static let timeFraction = 0.6
}
