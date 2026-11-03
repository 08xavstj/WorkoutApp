import Foundation
import SwiftData
import AppCore

/// Pairs a logged gym session with the workout a watch (Apple Watch, Garmin
/// via its app) recorded at the same time, so history and today's activities
/// show one entry with the watch's heart rate and calories attached. Nothing
/// is deleted from Apple Health; the match is only stored on the session
/// (`WorkoutLinking`: overlap of at least half the shorter workout).
enum WorkoutLinker {
    /// How far either side of a session to look for a watch workout.
    static let searchMargin: TimeInterval = 2 * 3600

    /// Finds and stores the overlapping external workout for one session.
    /// Returns true when a link was set.
    @discardableResult
    static func link(_ session: WorkoutSession, health: HealthKitClient) async -> Bool {
        guard let end = session.endedAt, session.linkedWorkoutUUID == nil else { return false }
        let found = (try? await health.externalWorkouts(
            from: session.startedAt.addingTimeInterval(-searchMargin), to: end.addingTimeInterval(searchMargin)
        )) ?? []
        return apply(found, to: session)
    }

    /// Links every finished, unlinked session since `since` with one Health
    /// query (used when history loads, because Garmin syncs late).
    static func linkRecent(_ sessions: [WorkoutSession], since: Date, health: HealthKitClient, context: ModelContext) async {
        let pending = sessions.filter { !$0.isActive && $0.linkedWorkoutUUID == nil && $0.startedAt >= since }
        guard let first = pending.map(\.startedAt).min(), let last = pending.compactMap(\.endedAt).max() else { return }
        let found = (try? await health.externalWorkouts(
            from: first.addingTimeInterval(-searchMargin), to: last.addingTimeInterval(searchMargin)
        )) ?? []
        guard !found.isEmpty else { return }
        var changed = false
        for session in pending where apply(found, to: session) { changed = true }
        if changed { try? context.save() }
    }

    private static func apply(_ workouts: [ExternalWorkout], to session: WorkoutSession) -> Bool {
        guard let end = session.endedAt, end > session.startedAt else { return false }
        let candidates = workouts.map(\.linkCandidate)
        guard let match = WorkoutLinking.match(session: DateInterval(start: session.startedAt, end: end), candidates: candidates) else {
            return false
        }
        session.linkedWorkoutUUID = match.id
        session.linkedWorkoutSource = match.source
        return true
    }
}
