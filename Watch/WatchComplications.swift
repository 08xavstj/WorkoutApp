import Foundation
import WidgetKit

/// Keeps the complications' data in the App Group (`WatchFaceStore`) and
/// redraws them when it changes.
enum WatchComplications {
    /// The complications' kinds (`NextSessionComplication`, `RecoveryStrainComplication`
    /// in WatchWidgets, which this target doesn't compile).
    static let relevanceKinds = ["NextSession", "RecoveryStrain"]

    /// Stores the phone's latest data; reloads only when it's newer and different.
    static func store(_ data: WatchFaceData) {
        let changed = WatchFaceStore.save(data)
        // Home shows the newest data even when the face wouldn't change.
        FaceFeed.shared.reload()
        guard changed else { return }
        reload()
    }

    /// A workout ended on the Watch: today's planned session counts as done.
    static func workoutEnded(at date: Date) {
        WatchFaceStore.markWorkoutEnded(at: date)
        FaceFeed.shared.reload()
        reload()
    }

    /// New timelines, and new Smart Stack windows: a reload alone doesn't ask
    /// for `relevance()` again, so a done session or a new plan would keep
    /// being offered at its old times (WidgetKit, `invalidateRelevance(ofKind:)`).
    private static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
        for kind in relevanceKinds {
            WidgetCenter.shared.invalidateRelevance(ofKind: kind)
        }
    }
}
