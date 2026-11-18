import SwiftUI
import AppCore

/// Fitness › Progress › Strength: strength days with the health floor,
/// strength standards and, when one applies, the deload card (moved from
/// the Fitness tab; ux-audit.md 4.3, 4.6). The cards keep their research
/// notes (WHO 2020; Momma 2022; Shailendra 2022; Bell et al. 2023).
struct StrengthDetailView: View {
    var body: some View {
        FitnessDetailPage(title: "Strength") {
            DeloadCard()
            // The goal cards live on Fitness › Progress › Lift goals; one line links there.
            LiftGoalsLink()
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
        // The block's last week: carry on, or an easier week if run down (evidence audit, should-change 4).
        if let week = plans.projectedBlockWeek(hrvBelowNormal: metrics.trainEasyToday), week.offersEasier {
            LastBlockWeekCard(week: week)
        // Training block: the planned easier week of a block saved before that (Bell et al. 2023 consensus; `TrainingBlock`).
        } else if let week = plans.projectedBlockWeek(hrvBelowNormal: metrics.trainEasyToday), week.isDeload {
            VStack(alignment: .leading, spacing: 8) {
                Label("Planned deload this week", systemImage: "arrow.down.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.oxygenText)
                // Bell et al. 2023: fewer sets and an easier effort. Keeping the reps at RIR 3
                // makes the planner's weights a little lighter (about 5%).
                Text("\(week.label). The trainer plans about half the sets, a little lighter, with 3 reps left; your lifts should feel easy. The next block starts next week.")
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
                Text("Coaches commonly use deloads (Bell et al., Sports Med Open 2023, an expert consensus): keep the weights, cut sets by about half, for about a week.")
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

/// The block's last week (`TrainingBlock.lastWeek(easier:)`): it carries on
/// unless you take the easier week, and you can switch back. Not a planned
/// deload: a week off mid-programme cost some strength in the one trial
/// (Coleman et al., PeerJ 2024), so the easier week is for when you feel run
/// down (evidence audit, should-change 4).
private struct LastBlockWeekCard: View {
    @Environment(WeeklyPlanStore.self) private var plans
    let week: TrainingBlock.WeekState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(week.isDeload ? "Easier week" : "Last week of the block", systemImage: "arrow.down.right.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.oxygenText)
            Text(week.isDeload
                 ? "\(week.label). The trainer plans about half the sets, a little lighter. The next block starts next week."
                 : week.note)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(week.isDeload ? "Carry on instead" : "Take an easier week") {
                plans.setEasierWeek(!week.isDeload)
            }
            .buttonStyle(.bordered)
            .tint(Theme.oxygen)
            .accessibilityIdentifier("strength.easierWeek")
            Text("A planned easier week isn't shown to help: in one trial, a week off mid-programme gave less strength gain and the same muscle growth (Coleman 2024). Take one when you feel run down.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if week.isDeload {
                Text(StrengthHealthFloor.deloadNote)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }
}
