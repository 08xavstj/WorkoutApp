import SwiftUI
import SwiftData
import AppCore

/// Health › Highlights: the two pages built on top of everything else in the
/// tab. Insights is this week against your usual (`DailyInsights`);
/// Longevity is the handful of measures most strongly linked with living
/// longer and better, and where you stand (`Longevity`). Two rows, so the
/// tab's front page stays short (docs/research/cleanup-2026-11.md: details
/// behind a tap).
struct HealthHighlightsSection: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(CheckInStore.self) private var checkIns
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(LabsModel.self) private var labs
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var models: LongevityAssembler.Models {
        LongevityAssembler.Models(vitals: vitals, biology: biology, metrics: metrics, settings: settings,
                                  checkIns: checkIns, measurements: measurements, labs: labs)
    }

    /// What the feed is worked out from, in a few numbers: when one changes
    /// (a refresh finished, a check-in was saved, a session was logged, the
    /// day turned), the feed is worked out again.
    private var refreshKey: String {
        let day = Int(Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate)
        return "\(vitals.stats.count)|\(vitals.isLoading)|\(biology.hrvSeries.count)|\(checkIns.insights.count)|\(checkIns.moods.count)|\(metrics.sleepConsistency ?? -1)|\(sessions.count)|\(day)"
    }

    var body: some View {
        let dates = LongevitySessions.dates(sessions)
        let assessment = LongevityAssembler.assessment(models, sessionDates: dates)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Highlights")
            VStack(spacing: 0) {
                HealthNavigationRow(title: "Insights", detail: insightsDetail, icon: "lightbulb.fill",
                                    hint: "Shows this week's changes") {
                    InsightsFeedPage()
                }
                Divider()
                HealthNavigationRow(title: "Longevity", detail: assessment.summary ?? "What's linked with a longer life, and where you stand",
                                    icon: "tree.fill", hint: "Shows each measure and its sources") {
                    LongevityPage()
                }
            }
            .card()
        }
        .task(id: refreshKey) {
            // Not while the stats are still loading: half a refresh would read as a quiet week.
            guard !vitals.isLoading else { return }
            InsightsFeedStore.shared.refresh(LongevityAssembler.insightInputs(models, sessionDates: dates, assessment: assessment))
        }
    }

    /// The top line of the feed, so the row says something before it's opened.
    private var insightsDetail: String {
        guard let feed = InsightsFeedStore.shared.feed else { return "This week against your usual" }
        if let first = feed.today.first {
            let more = feed.today.count - 1
            return more > 0 ? "\(first.title) · \(more) more" : first.title
        }
        return feed.emptyReason ?? "This week against your usual"
    }
}

/// Finished sessions logged in the app, newest first, as the strength-day
/// measures count them (the Health tab does the same for `VitalsModel`).
enum LongevitySessions {
    static func dates(_ sessions: [WorkoutSession]) -> [Date] {
        let cutoff = Date.now.addingTimeInterval(-120 * 86_400)
        return sessions.filter { !$0.isActive && $0.startedAt >= cutoff }.map(\.startedAt)
    }
}

// MARK: - Longevity page

/// Health › Highlights › Longevity. Reads as "the things most strongly
/// linked with living longer and better, and where you stand": one next
/// step, then each area with its measured rows, with the evidence and
/// sources a tap away. No score: none has been validated (`Longevity`).
struct LongevityPage: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(CheckInStore.self) private var checkIns
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(LabsModel.self) private var labs
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var current: Longevity.Assessment {
        let models = LongevityAssembler.Models(vitals: vitals, biology: biology, metrics: metrics, settings: settings,
                                               checkIns: checkIns, measurements: measurements, labs: labs)
        return LongevityAssembler.assessment(models, sessionDates: LongevitySessions.dates(sessions))
    }

    var body: some View {
        let assessment = current
        let measuredAreas = assessment.areas.filter { !$0.measured.isEmpty }
        let missing = assessment.measures.filter { $0.status == .noData }
        HealthDetailPage(title: "Longevity") {
            LongevityIntroCard(summary: assessment.summary)
            if let focus = assessment.focus {
                LongevityFocusCard(measure: focus)
            }
            ForEach(measuredAreas) { area in
                LongevityAreaCard(title: area.area.title, measures: area.measured)
            }
            if !missing.isEmpty {
                LongevityMissingCard(measures: missing)
            }
            Text("Each target comes from published research on large groups of people. It shows where you stand, not what will happen to you, and it isn't a diagnosis.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct LongevityIntroCard: View {
    let summary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The few things most strongly linked with living longer and better, and where you stand.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            if let summary {
                Text(summary)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityIdentifier("longevity-summary")
            }
            Text("Linked with, not proven to cause: most of this research followed people over time. Tap a row for the evidence and sources.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

/// The one most useful next step: the off-target measure with the strongest evidence.
private struct LongevityFocusCard: View {
    let measure: Longevity.Measure

    var body: some View {
        NavigationLink {
            LongevityMeasurePage(measure: measure)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    CardLabel(text: "Most useful next step")
                    Text(measure.valueText.map { "\(measure.title): \($0)" } ?? measure.title)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(measure.nextStep)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                LongevityChevron()
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the evidence and sources")
        .accessibilityIdentifier("longevity-focus")
        .card(tint: LongevityStyle.color(for: measure.status))
    }
}

/// One area ("Sleep") with a row for each measure that has a value.
private struct LongevityAreaCard: View {
    let title: String
    let measures: [Longevity.Measure]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: title)
            VStack(spacing: 0) {
                ForEach(Array(measures.enumerated()), id: \.element.id) { index, measure in
                    if index > 0 { Divider() }
                    LongevityMeasureRow(measure: measure)
                }
            }
        }
        .card()
    }
}

/// Title, your value and the target; a status pill only when it is close or
/// off (cleanup-2026-11.md: status only where something is off), a quiet
/// tick when it is on target.
private struct LongevityMeasureRow: View {
    let measure: Longevity.Measure

    var body: some View {
        NavigationLink {
            LongevityMeasurePage(measure: measure)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(measure.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text(measure.valueText ?? measure.status.label)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Text("Target: \(measure.targetText)")
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                LongevityStatusMark(status: measure.status)
                LongevityChevron()
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(measure.title), \(measure.valueText ?? measure.status.label), \(measure.status.label). Target: \(measure.targetText)")
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the evidence and sources")
        .accessibilityIdentifier("longevity-row-\(measure.id.rawValue)")
    }
}

/// Measures with no data, in one quiet card at the end, each pushing the
/// page that says how to add it.
private struct LongevityMissingCard: View {
    let measures: [Longevity.Measure]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: "Not measured yet")
            VStack(spacing: 0) {
                ForEach(Array(measures.enumerated()), id: \.element.id) { index, measure in
                    if index > 0 { Divider() }
                    NavigationLink {
                        LongevityMeasurePage(measure: measure)
                    } label: {
                        HStack(spacing: 12) {
                            Text(measure.title)
                                .font(.subheadline)
                                .foregroundStyle(Theme.primaryText)
                            Spacer(minLength: 8)
                            LongevityChevron()
                        }
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows how to add it")
                    .accessibilityIdentifier("longevity-row-\(measure.id.rawValue)")
                }
            }
        }
        .card()
    }
}

// MARK: - One measure

/// A measure's own page: where you stand, the next step, why it's on the
/// list with how strong the evidence is, and the sources.
struct LongevityMeasurePage: View {
    let measure: Longevity.Measure

    var body: some View {
        HealthDetailPage(title: measure.title) {
            standing
            nextStep
            evidence
            sources
        }
    }

    private var standing: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardLabel(text: "Where you stand")
                Spacer()
                LongevityStatusMark(status: measure.status, showsOnTarget: true)
            }
            if let value = measure.valueText {
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
            }
            Text(measure.standing)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Text("Target: \(measure.targetText)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var nextStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Next step")
            Text(measure.nextStep)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardLabel(text: "Why it's here")
                Spacer()
                Text(measure.grade.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(measure.why)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Text(measure.gradeNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Sources")
            ForEach(measure.sources) { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.citation)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(source.verified ? source.kind : "\(source.kind) · not re-verified")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Text(source.finding)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Checked against the published record in November 2026, except where marked.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

// MARK: - Pieces

enum LongevityStyle {
    static func color(for status: Longevity.Status) -> Color {
        switch status {
        case .onTarget: Theme.recoveryHigh
        case .close: Theme.recoveryModerate
        case .off: Theme.recoveryLow
        case .tracking, .noData: Theme.secondaryText
        }
    }
}

/// A pill for close and off; a tick (or, on the measure page, the words) for on target; nothing otherwise.
private struct LongevityStatusMark: View {
    let status: Longevity.Status
    var showsOnTarget = false

    var body: some View {
        switch status {
        case .close, .off:
            Chip(text: status.label, color: LongevityStyle.color(for: status))
        case .onTarget:
            if showsOnTarget {
                Chip(text: status.label, color: LongevityStyle.color(for: status))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(Theme.recoveryHigh)
                    .accessibilityHidden(true)
            }
        case .tracking, .noData:
            EmptyView()
        }
    }
}

private struct LongevityChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }
}
