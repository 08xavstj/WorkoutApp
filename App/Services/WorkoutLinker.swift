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

    /// A session the app made from an Apple Watch recording alone ("Watch
    /// workout, N min", no exercises) exists only because of that recording,
    /// so when the recording is deleted from Apple Health (e.g. in Apple's
    /// Fitness app) the session goes too. A logged session that pointed to a
    /// deleted recording only loses the link. Acts only when other workouts
    /// can be read (a denied read looks like a deletion), and only on sessions
    /// that ended over an hour ago, so a recording still syncing from the
    /// Watch isn't mistaken for a deleted one.
    static func dropDeletedWatchWorkouts(_ sessions: [WorkoutSession], health: HealthKitClient, context: ModelContext) async {
        let settled = Date.now.addingTimeInterval(-3600)
        let window = Date.now.addingTimeInterval(-60 * 86_400)
        let linked = sessions.filter { session in
            guard let end = session.endedAt, session.watchWorkoutUUID != nil else { return false }
            return end < settled && session.startedAt > window
        }
        let ids = Set(linked.compactMap(\.watchWorkoutUUID))
        guard !ids.isEmpty,
              let result = try? await health.workoutsStillPresent(ids, readableSince: Date.now.addingTimeInterval(-90 * 86_400)),
              result.canRead else { return }
        var changed = false
        for session in linked {
            guard let id = session.watchWorkoutUUID, !result.present.contains(id) else { continue }
            if session.exercises.isEmpty {
                context.delete(session)
            } else {
                session.watchWorkoutUUID = nil
            }
            changed = true
        }
        if changed { try? context.save() }
    }
}
