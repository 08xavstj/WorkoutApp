import Foundation
import HealthKit

nonisolated extension HealthKitClient {
    /// Removes from Apple Health what Tensile saved for one gym session, after
    /// the user confirmed deleting or discarding it: the iPhone's workout (this
    /// app's own source, inside the session's time), its effort score, and the
    /// Tensile Watch app's workout by its UUID. Workouts from other apps
    /// (Garmin, Apple's Workout app) are never touched: HealthKit only lets an
    /// app delete what it saved itself. Returns how many workouts went; a
    /// failure (no permission, nothing found) just counts none. `includePhone`
    /// false removes only the Watch's workout (a discarded live session, which
    /// the iPhone never saved).
    @concurrent
    func deleteOwnWorkouts(start: Date, end: Date, watchWorkoutUUID: UUID?, includePhone: Bool = true) async -> Int {
        if DemoHealth.active != nil { return 0 } // demo mode: nothing was written to Health
        guard isAvailable else { return 0 }
        let window = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-60),
                                                 end: max(start, end).addingTimeInterval(60))
        let own = HKQuery.predicateForObjects(from: HKSource.default())
        let ownInWindow = NSCompoundPredicate(andPredicateWithSubpredicates: [window, own])
        var deleted = 0
        if includePhone {
            if let removed = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: ownInWindow) {
                deleted += removed
            }
            // The session effort score (`saveWorkoutEffort`) would otherwise stay on its own.
            _ = try? await store.deleteObjects(of: HKQuantityType(.workoutEffortScore), predicate: ownInWindow)
        }
        if let watchWorkoutUUID {
            let byID = HKQuery.predicateForObject(with: watchWorkoutUUID)
            if let removed = try? await store.deleteObjects(of: HKObjectType.workoutType(), predicate: byID) {
                deleted += removed
            }
        }
        return deleted
    }
}
