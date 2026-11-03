import Foundation
import WidgetKit

/// Keeps the complications' data in the App Group (`WatchFaceStore`) and
/// redraws them when it changes.
enum WatchComplications {
    /// Stores the phone's latest data; reloads only when it's newer and different.
    static func store(_ data: WatchFaceData) {
        guard WatchFaceStore.save(data) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// A workout ended on the Watch: today's planned session counts as done.
    static func workoutEnded(at date: Date) {
        WatchFaceStore.markWorkoutEnded(at: date)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
