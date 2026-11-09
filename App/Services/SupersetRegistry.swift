import Foundation
import AppCore

/// Which exercises of a live session are paired as supersets, keyed by the
/// session's start time, in UserDefaults. `ExerciseLog` has no field for it
/// (adding one would need a schema migration), and the pairing only matters
/// while the session is open, so entries older than two days are dropped.
enum SupersetRegistry {
    private static let key = "supersetGroups"
    private static let keepSeconds: TimeInterval = 2 * 86_400

    /// Exercise `order` → superset group, as `Supersets.pair` assigned them.
    static func groups(for sessionStart: Date) -> [Int: Int] {
        let all = load()
        guard let entry = all[id(sessionStart)] else { return [:] }
        var result: [Int: Int] = [:]
        for (order, group) in entry {
            if let index = Int(order) { result[index] = group }
        }
        return result
    }

    /// Saves the pairing for a session (nothing is written for an empty one).
    static func save(_ groups: [Int: Int], for sessionStart: Date) {
        var all = load()
        let cutoff = Date.now.addingTimeInterval(-keepSeconds)
        all = all.filter { Double($0.key).map { Date(timeIntervalSince1970: $0) >= cutoff } ?? false }
        if !groups.isEmpty {
            all[id(sessionStart)] = Dictionary(uniqueKeysWithValues: groups.map { (String($0.key), $0.value) })
        } else {
            // The last pair went (an exercise removed): clear the session's entry too.
            all.removeValue(forKey: id(sessionStart))
        }
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Groups for a planned list, by position: exercise index → group.
    static func groups(in exercises: [PlannedExercise]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (index, exercise) in exercises.enumerated() {
            if let group = exercise.supersetGroup { result[index] = group }
        }
        return result
    }

    /// "A1" / "A2" for the exercise at `order`, or nil when it isn't paired.
    static func label(order: Int, groups: [Int: Int]) -> String? {
        guard let group = groups[order] else { return nil }
        let first = groups.filter { $0.value == group }.keys.min() ?? order
        return Supersets.label(group: group, position: order == first ? 1 : 2)
    }

    /// The other exercise's order in the same superset, if any.
    static func partner(of order: Int, groups: [Int: Int]) -> Int? {
        guard let group = groups[order] else { return nil }
        return groups.first { $0.value == group && $0.key != order }?.key
    }

    private static func id(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }

    private static func load() -> [String: [String: Int]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]] ?? [:]
    }
}
