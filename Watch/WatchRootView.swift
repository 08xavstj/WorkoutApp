import SwiftUI

/// Start screen → the lifting pages (`LiftPagesView`) → summary
/// (`LiftSummaryView`). Cardio runs its own pages and summary.
struct WatchRootView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(WatchCardioModel.self) private var cardio

    var body: some View {
        // A cardio workout (`WatchCardioModel`) has its own pages and end screen;
        // only one of the two models records at a time.
        if cardio.isActive {
            CardioPagesView()
        } else if cardio.phase == .ended {
            CardioSummaryView()
        } else {
            switch model.phase {
            case .idle, .starting:
                WatchStartView()
            case .running, .paused:
                LiftPagesView()
            case .ended:
                LiftSummaryView()
            }
        }
    }
}
