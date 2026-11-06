import Foundation
import AppCore

/// How each lift progresses from session to session (`ProgressionMode`):
/// your choice per exercise, from the exercise's ⋯ menu or its Progress page,
/// else the suggestion for its equipment. Saved as JSON in UserDefaults, like
/// `RestPreferences`. The planner reads the choices through
/// `WorkoutPlanner.progressionModes` (`overrides()`).
enum ProgressionPreferences {
    private static let key = "progressionModeByExercise"

    /// Every exercise you picked a mode for, by exercise ID.
    static func overrides() -> [String: ProgressionMode] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: ProgressionMode].self, from: data) else { return [:] }
        return saved
    }

    /// Your own choice for an exercise; nil means the suggested one.
    static func mode(for exerciseID: String) -> ProgressionMode? {
        overrides()[exerciseID]
    }

    /// Saves your choice for an exercise (kept even when it matches the
    /// suggestion, which can change with the weight); nil clears it.
    static func set(_ mode: ProgressionMode?, for exerciseID: String) {
        var saved = overrides()
        saved[exerciseID] = mode
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// The mode the planner uses: yours, else the suggestion.
    static func resolved(for exerciseID: String, gym: GymProfile, atKilograms weightKg: Double = 0) -> ProgressionMode {
        mode(for: exerciseID) ?? suggested(for: exerciseID, gym: gym, atKilograms: weightKg)
    }

    /// The suggestion for the exercise's equipment (`ProgressionMode.suggested`),
    /// judged from the jump above `weightKg` (or the lightest load the gym has).
    static func suggested(for exerciseID: String, gym: GymProfile, atKilograms weightKg: Double = 0) -> ProgressionMode {
        let kind = ExerciseCatalog.exercise(id: exerciseID)?.load
        let compound = ExerciseCatalog.slot(for: exerciseID)?.isCompound ?? false
        var load = gym.unit.fromKilograms(weightKg)
        if load <= 0, let kind, let lightest = gym.achievableLoads(for: kind).first {
            load = lightest
        }
        return WorkoutPlanner(gym: gym).progressionMode(for: exerciseID, kind: kind, compound: compound, at: load)
    }
}
