import SwiftUI
import AppCore

/// Health › Key measures (ux-audit.md 4.6, the mockup's "Biomarkers"): one
/// list card of the long-term measures most tied to health, each pushing its
/// history. Rows with no data are left out, with one "Add data" hint at the
/// end, so the card never fills up with "No data" (ux-audit.md B2, P16).
struct KeyMeasuresSection: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(AppRouter.self) private var router

    /// Weight trend, resting heart rate, VO₂ max and blood pressure, then
    /// waist-to-height (or body fat when there's no waist reading). Only rows
    /// with a value.
    private var stats: [VitalsModel.Stat] {
        var result = ["weight", "rhr", "vo2", "bp"].compactMap { vitals.stat($0) }.filter { $0.value != nil }
        let extras = HealthExtraStats(biology: biology, metrics: metrics, settings: settings, measurements: measurements)
        let waist = extras.waistStat
        if waist.value != nil {
            result.append(waist)
        } else if let fat = vitals.stat("fat"), fat.value != nil {
            result.append(fat)
        }
        return result
    }

    /// Six rows when everything has data (five stats plus body age).
    private var isMissingRows: Bool {
        stats.count + (vitals.bodyAge == nil ? 0 : 1) < 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Key measures")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                    if index > 0 { Divider() }
                    KeyMeasureRow(stat: stat)
                }
                if let bodyAge = vitals.bodyAge {
                    if !stats.isEmpty { Divider() }
                    BodyAgeRow(result: bodyAge)
                }
                if !metrics.micronutrients.isEmpty {
                    if !stats.isEmpty || vitals.bodyAge != nil { Divider() }
                    MicronutrientsKeyRow(findings: metrics.micronutrients)
                }
                footer
            }
            .card()
        }
    }
}

extension KeyMeasuresSection {
    /// "Loading…" before the first refresh, else the "Add data" hint when a row is hidden.
    @ViewBuilder
    private var footer: some View {
        let hasRows = !stats.isEmpty || vitals.bodyAge != nil
        if vitals.isLoading && vitals.stats.isEmpty {
            Text("Loading your health stats…")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .padding(.vertical, 10)
        } else if let problem = vitals.readProblem {
            // A core read threw on the last refresh (`VitalsModel.readProblem`).
            if hasRows { Divider() }
            Text(problem)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .padding(.vertical, 10)
        } else if isMissingRows {
            if hasRows { Divider() }
            AddDataHint { router.selectedTab = .log }
        }
    }
}

/// One measure as a `MetricRow`, pushing its history.
private struct KeyMeasureRow: View {
    let stat: VitalsModel.Stat

    var body: some View {
        let colors = VitalTile.colors(for: stat.category)
        MetricRow(
            title: stat.title,
            value: stat.value,
            unit: stat.unit,
            spokenUnit: HealthSpokenUnit.words(for: stat.unit),
            verdict: stat.status.map { MetricVerdict($0, color: VitalTile.color(for: stat.tone)) },
            trend: Array(stat.series.suffix(30)),
            trendColor: colors.last ?? Theme.secondaryText,
            destination: VitalDetailView(stat: stat, colors: colors, pushed: true)
        )
    }
}

/// Body age shown as its ±5-year range, not one number: only the parts, not
/// the composite, have been validated (`BodyAge.uncertaintyYears`), and an
/// older-than-you headline is a nocebo risk (docs/research/behaviour-change.md,
/// "Body age"). The page behind it shows the estimate and what moves it.
private struct BodyAgeRow: View {
    let result: BodyAge.Result

    var body: some View {
        MetricRow(
            title: "Body age",
            value: "\(result.range.lowerBound)–\(result.range.upperBound)",
            unit: "years",
            verdict: MetricVerdict("Estimate"),
            hint: "Shows what's moving it",
            destination: BodyAgePage()
        )
    }
}

/// Vitamins and minerals from the food log (`Micronutrients`): how many are
/// low or above the upper limit this week, pushing the "What to fix" page.
/// Shown once 4 days of food are logged (`Micronutrients.assess` returns
/// nothing before that).
private struct MicronutrientsKeyRow: View {
    let findings: [Micronutrients.Finding]

    var body: some View {
        let low = Micronutrients.toFix(findings).count
        let high = findings.filter { $0.kind == .high }.count
        MetricRow(
            title: "Vitamins & minerals",
            value: "\(low > 0 || high == 0 ? low : high)",
            unit: Self.unit(low: low, high: high),
            verdict: Self.verdict(low: low, high: high),
            hint: "Shows what to fix",
            destination: MicronutrientsPage()
        )
    }

    private static func unit(low: Int, high: Int) -> String {
        if low > 0, high > 0 { return "low, \(high) too high" }
        return high > 0 ? "too high this week" : "low this week"
    }

    private static func verdict(low: Int, high: Int) -> MetricVerdict {
        if low == 0, high == 0 { return MetricVerdict("Near target", color: Theme.recoveryHigh) }
        return MetricVerdict(low == 0 ? "See what's high" : "See what to fix", color: Theme.recoveryModerate)
    }
}

/// The one hint at the end of Key measures: hidden rows have no data yet.
/// Opens the Log tab, where readings are added.
private struct AddDataHint: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add data")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Measures without readings are hidden. Add blood pressure or your waist in the Log tab, or let your watch and scale share with Apple Health.")
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Log tab")
    }
}
