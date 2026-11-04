import SwiftUI
import AppCore

/// Fitness › Progress › Cardio fitness: the VO₂ max card with its 90-day
/// trend and, for health, stamina and weight-loss goals, the weekly active
/// minutes card (ux-audit.md 4.3, 4.6). For muscle and strength goals the
/// minutes stay a line on the Strength page (`WeeklyActivityBand.emphasis`).
/// The cards keep their research notes (Mandsager 2018; Kokkinos 2022;
/// Kaminsky 2015; WHO 2020, Bull et al.; Lee et al., Circulation 2022).
struct CardioDetailView: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        FitnessDetailPage(title: "Cardio fitness") {
            CardioFitnessCard()
            if WeeklyActivityBand.emphasis(for: metrics.goals) == .primary {
                WeeklyMinutesCard()
            }
        }
    }
}
