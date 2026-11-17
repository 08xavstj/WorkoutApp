import SwiftUI
import SwiftData
import AppCore

/// Health › Highlights › Insights: a short list of what changed this week
/// against your usual, then one or two longer-running suggestions
/// (`DailyInsights`; worked out by `HealthHighlightsSection`). Each card is
/// one observation: what changed, compared with what, and at most one thing
/// to try. Week-scale only: today's training call stays on Today.
struct InsightsFeedPage: View {
    var body: some View {
        let feed = InsightsFeedStore.shared.feed
        HealthDetailPage(title: "Insights") {
            if let feed {
                ForEach(feed.today) { insight in
                    InsightFeedCard(insight: insight)
                }
                if feed.today.isEmpty {
                    Text(feed.emptyReason ?? "Nothing new today.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .card()
                }
                if !feed.forYou.isEmpty {
                    InsightsForYouCard(suggestions: feed.forYou)
                }
            } else {
                Text("Working it out…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .card()
            }
            Text("Your last 7 days against the 4 weeks before. A line shows for up to three days, then rests. Observations from your own data, not medical advice.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// One observation: its area, what changed, compared with what, and the one action if there is one.
private struct InsightFeedCard: View {
    let insight: DailyInsights.Insight

    var body: some View {
        let color = InsightStyle.color(for: insight.category)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: InsightStyle.icon(for: insight.category))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                CardLabel(text: insight.category.title)
                Spacer()
                // A pill only when it is worth a look (cleanup-2026-11.md).
                if insight.tone == .watch {
                    Chip(text: "Worth a look", color: Theme.recoveryModerate)
                }
            }
            Text(insight.title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(insight.comparison)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let action = insight.action {
                Label {
                    Text(action)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("insight-\(insight.id)")
    }
}

/// "For you": the longer-running suggestions, from the Longevity page's
/// off-target measures. A row with a measure behind it pushes that measure.
private struct InsightsForYouCard: View {
    let suggestions: [DailyInsights.Suggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: "For you")
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 { Divider() }
                    InsightsForYouRow(suggestion: suggestion)
                }
            }
        }
        .card()
    }
}

private struct InsightsForYouRow: View {
    let suggestion: DailyInsights.Suggestion
    @Environment(VitalsModel.self) private var vitals
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(CheckInStore.self) private var checkIns
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    /// The Longevity measure behind the suggestion, as it stands now.
    private var measure: Longevity.Measure? {
        guard let id = suggestion.measure else { return nil }
        let models = LongevityAssembler.Models(vitals: vitals, biology: biology, metrics: metrics, settings: settings,
                                               checkIns: checkIns, measurements: measurements)
        return LongevityAssembler.assessment(models, sessionDates: LongevitySessions.dates(sessions)).measure(id)
    }

    var body: some View {
        if let measure {
            NavigationLink {
                LongevityMeasurePage(measure: measure)
            } label: {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the evidence and sources")
            .accessibilityIdentifier("foryou-\(suggestion.id)")
        } else {
            content(showsChevron: false)
                .accessibilityIdentifier("foryou-\(suggestion.id)")
        }
    }

    private func content(showsChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(suggestion.detail)
                    .font(Theme.Typography.context)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Icon and accent for each area of the feed, from the app's score colours.
enum InsightStyle {
    static func icon(for category: DailyInsights.Category) -> String {
        switch category {
        case .heart: "heart.fill"
        case .sleep: "bed.double.fill"
        case .recovery: "waveform.path.ecg"
        case .fitness: "figure.run"
        case .vitals: "lungs.fill"
        case .nutrition: "fork.knife"
        case .habits: "checklist"
        }
    }

    static func color(for category: DailyInsights.Category) -> Color {
        switch category {
        case .heart: Theme.heart
        case .sleep: Theme.sleep
        case .recovery: Theme.recoveryHigh
        case .fitness: Theme.strain
        case .vitals: Theme.oxygen
        case .nutrition: Theme.nutrition
        case .habits: Theme.secondaryText
        }
    }
}
