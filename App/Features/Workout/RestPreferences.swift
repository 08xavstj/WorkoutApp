import Foundation
import AppCore

/// How long the rest timer runs: your choice for an exercise, else your
/// choice in Settings, else a default from your goal (see `RestTimer`).
enum RestPreferences {
    /// Settings → Rest timer. 0 = automatic (from your goal).
    static let globalKey = "restTimerSeconds"
    private static let perExerciseKey = "restSecondsByExercise"

    static var global: Int {
        UserDefaults.standard.integer(forKey: globalKey)
    }

    static func seconds(for exerciseID: String) -> Int? {
        let saved = UserDefaults.standard.dictionary(forKey: perExerciseKey) as? [String: Int]
        return saved?[exerciseID]
    }

    /// nil clears the exercise's own setting.
    static func set(_ seconds: Int?, for exerciseID: String) {
        var saved = (UserDefaults.standard.dictionary(forKey: perExerciseKey) as? [String: Int]) ?? [:]
        saved[exerciseID] = seconds
        UserDefaults.standard.set(saved, forKey: perExerciseKey)
    }

    static func resolved(for exerciseID: String, style: TrainingStyle) -> Int {
        if let own = seconds(for: exerciseID), own > 0 { return own }
        if global > 0 { return global }
        let compound = ExerciseCatalog.slot(for: exerciseID)?.isCompound ?? false
        return RestTimer.defaultSeconds(style: style, compound: compound)
    }

    static func label(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        return seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s"
    }
}
