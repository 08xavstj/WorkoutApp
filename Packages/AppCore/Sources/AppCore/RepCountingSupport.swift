import Foundation

/// Which exercises the experimental Watch rep counter runs for (kept apart
/// from `RepDetection.swift`, which the Watch app compiles on its own).
extension RepDetection {
    /// Barbell squats and deadlifts only: wrist counts were accurate for squat
    /// and deadlift and poor for bench (Huber C, Lüthy S, Lorenzetti S. Sports
    /// 2021;9(9):118) [E19], and wrist velocity was validated in the barbell
    /// squat (Achermann B, et al. Sports 2023;11(7):125) [E18]. Leg presses,
    /// dumbbell and kettlebell work, swings and single-leg lifts are left out:
    /// the wrist doesn't travel with a bar there, or the motion is ballistic.
    public static func supports(exerciseID: String) -> Bool {
        if libraryExerciseIDs.contains(exerciseID) { return true }
        guard let slot = ExerciseCatalog.slot(for: exerciseID), slot == .squat || slot == .hinge else { return false }
        return ExerciseCatalog.exercise(id: exerciseID)?.load == .barbell
    }

    /// Barbell squat and deadlift variants from the exercise library that the
    /// planner's catalog (`ExerciseCatalog.options`) doesn't list.
    static let libraryExerciseIDs: Set<String> = [
        "Barbell_Deadlift", "Sumo_Deadlift", "Deficit_Deadlift", "Trap_Bar_Deadlift",
        "Barbell_Full_Squat", "Front_Barbell_Squat", "Box_Squat",
    ]
}
