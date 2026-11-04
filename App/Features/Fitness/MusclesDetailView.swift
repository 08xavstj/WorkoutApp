import SwiftUI
import AppCore

/// Fitness › Progress › Muscles: the body map (rest status or this week's
/// sets) and hard sets per muscle against the 10-20 range, with their
/// research notes (Schoenfeld et al., J Sports Sci 2017; Pelland et al.,
/// Sports Med 2026; ux-audit.md 4.3, 4.6).
struct MusclesDetailView: View {
    var body: some View {
        FitnessDetailPage(title: "Muscles") {
            MuscleMapCard()
            WeeklySetsCard()
        }
    }
}
