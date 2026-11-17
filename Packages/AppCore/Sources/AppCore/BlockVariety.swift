import Foundation

/// Chosen variety at the end of a block: "Change one or two accessory lifts?"
/// beside the report's fixes for stalled lifts (`BlockReport.NextChange`).
///
/// Evidence (weak to moderate):
/// - 21 trained men, eight weeks: varying the exercises gave the same strength
///   and size gains as fixed ones, with better intrinsic motivation
///   (Baz-Valle E et al., PLoS One 2019;14(12):e0226989).
/// - 121 inactive students: a high-variety programme was kept to better over
///   six weeks (Sylvester BD et al., J Behav Med 2016;39(2):214-224).
/// - Review of 8 studies: systematic variation is fine; frequent random
///   rotation may hinder gains (Kassiano W et al., J Strength Cond Res
///   2022;36(6):1753-1762).
/// All three as read for docs/research/healthy-living-2026-11.md (PubMed
/// abstracts), not re-verified here.
///
/// So the rules, which are the app's choice inside that evidence:
/// - **Main lifts stay.** Only accessory (single-joint) lifts are offered;
///   the multi-joint lifts keep their history and their progression.
/// - **At most two**, and only at a block boundary, for the whole next block.
/// - **Never random.** Each accessory's replacement is the first alternative
///   in the planner's own order that the block didn't use, so the same report
///   always offers the same change.
/// - **Only what the gym supports**: alternatives come from
///   `WorkoutPlanner.alternatives(for:)` (equipment, loads, the never-again
///   list, pain); without them nothing is offered.
/// - **The old lift's record stays.** A change is a preference for the next
///   block (`NextBlockAdjustments.swaps`); nothing logged is removed, and the
///   old lift's history is there when it comes back.
public enum BlockVariety {
    /// The most accessory lifts changed at one block boundary.
    public static let maximumChanges = 2
    /// Lifts offered, at most: a short list to pick from.
    public static let maximumOptions = 4
    /// Sessions in the block before a lift counts as part of it.
    public static let minimumSessions = 2

    public struct Option: Sendable, Equatable, Identifiable {
        public var fromID: String
        public var fromName: String
        public var toID: String
        public var toName: String
        /// Sessions the old lift had in the block.
        public var sessions: Int

        public var id: String { fromID }
        /// "Cable Lateral Raise in place of Dumbbell Lateral Raise".
        public var text: String { "\(toName) in place of \(fromName)" }
    }

    /// An accessory lift: single-joint, and not core (the abs finisher
    /// already rotates its moves, `AbsFinisher`).
    public static func isAccessory(_ exerciseID: String) -> Bool {
        guard let slot = ExerciseCatalog.slot(for: exerciseID) else { return false }
        return !slot.isCompound && slot != .core
    }

    /// The accessory lifts of the block from `start` to `end` that could
    /// change, each with its replacement, most-done first.
    /// - Parameters:
    ///   - sessions: finished sessions (any dates; the block's are picked out).
    ///   - alternatives: per exercise ID, what the gym supports for its
    ///     movement, best first (`WorkoutPlanner.alternatives(for:)`).
    ///   - excluding: exercise IDs the report already changes (a stalled
    ///     lift's swap, either side of it).
    public static func options(sessions: [WorkoutSummary.LoggedSession], start: Date, end: Date,
                               alternatives: [String: [CatalogExercise]], excluding: Set<String> = []) -> [Option] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for session in sessions where session.start >= start && session.start < end {
            for id in Set(session.exercises.map(\.exerciseID)) { counts[id, default: 0] += 1 }
            for exercise in session.exercises { names[exercise.exerciseID] = exercise.name }
        }
        let used = Set(counts.keys)
        var taken = excluding
        var result: [Option] = []
        let candidates = counts
            .filter { $0.value >= minimumSessions && isAccessory($0.key) && !excluding.contains($0.key) }
            .sorted { a, b in a.value != b.value ? a.value > b.value : (names[a.key] ?? a.key) < (names[b.key] ?? b.key) }
        for (id, count) in candidates {
            guard result.count < maximumOptions,
                  let next = (alternatives[id] ?? []).first(where: { $0.id != id && !used.contains($0.id) && !taken.contains($0.id) })
            else { continue }
            taken.insert(next.id)
            result.append(Option(fromID: id, fromName: names[id] ?? id, toID: next.id, toName: next.name, sessions: count))
        }
        return result
    }
}

extension NextBlockAdjustments {
    /// These adjustments with the chosen accessory changes added as swaps, at
    /// most `BlockVariety.maximumChanges` of them and accessory lifts only. A
    /// lift the report already swaps keeps the report's swap.
    public func addingVariety(_ options: [BlockVariety.Option]) -> NextBlockAdjustments {
        var copy = self
        var added = 0
        for option in options where added < BlockVariety.maximumChanges {
            guard BlockVariety.isAccessory(option.fromID), !copy.swaps.contains(where: { $0.fromID == option.fromID }) else { continue }
            copy.swaps.append(Swap(fromID: option.fromID, fromName: option.fromName, toID: option.toID, toName: option.toName))
            added += 1
        }
        return copy
    }
}
