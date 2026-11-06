import SwiftUI
import AppCore

/// Fitness › Progress › Strength: strength days with the health floor,
/// strength for health and, when one applies, the deload card (moved from
/// the Fitness tab; ux-audit.md 4.3, 4.6). The cards keep their research
/// notes (WHO 2020; Momma 2022; Shailendra 2022; Bell et al. 2023).
struct StrengthDetailView: View {
    var body: some View {
        FitnessDetailPage(title: "Strength") {
            DeloadCard()
            // Lift goals with the e1RM projection band (`LiftGoalProjection`; McEwan 2016, Swann 2021).
            LiftGoalsSection()
            StrengthDaysCard()
            StrengthForHealthCard()
        }
    }
}

/// Suggests a lighter week when lifts stall (and HRV is down), and names the
/// training block's planned deload when this is that week (`TrainingBlock`).
private struct DeloadCard: View {
    @Environment(MuscleModel.self) private var muscles
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        // Training block: the planned easier week (Bell et al. 2023 consensus; `TrainingBlock`).
        if let week = plans.projectedBlockWeek(hrvBelowNormal: metrics.trainEasyToday), week.isDeload {
            VStack(alignment: .leading, spacing: 8) {
                Label("Planned deload this week", systemImage: "arrow.down.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.oxygenText)
                Text("\(week.label). The trainer plans about half the sets at the same weights; your lifts should feel easy. The next block starts next week.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                Text(StrengthHealthFloor.deloadNote)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card()
        } else if let advice = muscles.deload {
            VStack(alignment: .leading, spacing: 8) {
                Label(advice.strong ? "Time for a deload week" : "Consider a lighter week", systemImage: "arrow.down.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(advice.strong ? Theme.recoveryModerateText : Theme.oxygenText)
                Text(advice.message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                Text("Stalled: " + advice.stalledLifts.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text("Deloads are standard in strength training (Bell et al., Sports Med Open 2023 consensus): keep the weights, cut sets by about half, for about a week.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                // 2+ days and 30+ min a week keep the mortality benefit (Momma 2022; `StrengthHealthFloor`).
                Text(StrengthHealthFloor.deloadNote)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card()
        }
    }
}
