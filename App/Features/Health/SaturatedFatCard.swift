import SwiftUI
import AppCore

/// Saturated fat as a share of the week's energy, against WHO's under 10%
/// (`SaturatedFat`; evidence-audit-2026-11.md, Gaps, item 3). Shown with the
/// vitamins and minerals (sodium and fibre live there). Judged over the
/// week, never the day; nothing at all when the food app sends no saturated
/// fat, so a missing value never reads as zero.
struct SaturatedFatCard: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        if let week = metrics.saturatedFat {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel(text: "Saturated fat", color: Theme.nutrition)
                    Spacer()
                    Chip(text: chipText(week.status), color: week.status == .under ? Theme.recoveryHigh : Theme.recoveryModerate)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(week.percentText)%")
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text("of energy over the last \(week.days) logged days, about \(Int(week.gramsPerDay.rounded())) g a day")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(week.line)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Target: under 10% of energy over the week (WHO 2023). In trials of 2 years or more, eating less saturated fat cut heart attacks and strokes by about a sixth, with little change in overall deaths (Cochrane 2020). What replaces it matters: unsaturated fats or whole grains, not sugar.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nutrition-saturated-fat")
        }
    }

    private func chipText(_ status: SaturatedFat.Status) -> String {
        switch status {
        case .under: "Under 10%"
        case .close: "A little over"
        case .over: "Over 10%"
        }
    }
}
