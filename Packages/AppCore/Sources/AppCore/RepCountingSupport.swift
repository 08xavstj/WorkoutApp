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
    /// An explicit list, not "any barbell squat or hinge slot": that slot
    /// also holds hip thrusts and glute bridges, where the wrist barely moves
    /// with the bar and the studies above didn't test.
    public static func supports(exerciseID: String) -> Bool {
        supportedExerciseIDs.contains(exerciseID)
    }

    /// Barbell squat and deadlift variants, from the planner's catalog
    /// (`ExerciseCatalog.options`, pain regressions included) and the
    /// exercise library.
    static let supportedExerciseIDs: Set<String> = [
        // Squats
        "Barbell_Squat", "Barbell_Full_Squat", "Front_Barbell_Squat", "Box_Squat",
        // Deadlifts
        "Barbell_Deadlift", "Romanian_Deadlift", "Sumo_Deadlift", "Deficit_Deadlift", "Trap_Bar_Deadlift",
    ]
}
