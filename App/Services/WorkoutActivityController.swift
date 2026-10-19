import ActivityKit
import Foundation

/// Starts the workout Live Activity (only the app can start one).
enum WorkoutActivityController {
    static func startIfNeeded(name: String, startedAt: Date, exercise: String, detail: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if Activity<WorkoutActivityAttributes>.activities.contains(where: { $0.attributes.startedAt == startedAt }) {
            await WorkoutLiveActivity.refresh(exercise: exercise, detail: detail)
            return
        }
        // A workout from earlier that didn't end cleanly.
        for old in Activity<WorkoutActivityAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        let state = WorkoutActivityAttributes.ContentState(
            restEndsAt: RestTimerStore.endsAt, restLength: RestTimerStore.length, exercise: exercise, detail: detail
        )
        _ = try? Activity.request(
            attributes: WorkoutActivityAttributes(workoutName: name, startedAt: startedAt),
            content: ActivityContent(state: state, staleDate: RestTimerStore.endsAt),
            pushType: nil
        )
    }
}
