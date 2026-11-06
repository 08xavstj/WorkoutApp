import SwiftUI
import AppCore

/// Health › Patterns: what your own data shows about your habits, each row
/// pushing its page (ux-audit.md 4.3, 4.6). Patterns, not live measures, so
/// they sit apart from the numbers above (ux-audit.md B3).
struct PatternsSection: View {
    @Environment(CheckInStore.self) private var checkIns
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Patterns")
            VStack(spacing: 0) {
                HealthNavigationRow(title: "What affects you", detail: insightsDetail, icon: "chart.line.uptrend.xyaxis") {
                    InsightsPage()
                }
                Divider()
                // Mood (watch-features.md 4.1): 14-day average with a sparkline; `MoodView.swift`.
                MoodRow()
                Divider()
                HealthNavigationRow(title: "Alcohol and your sleep", detail: alcoholDetail, icon: "wineglass.fill") {
                    AlcoholPage()
                }
                // Key measures carries Vitamins & minerals once there are 4 days of food logs.
                if metrics.micronutrients.isEmpty {
                    Divider()
                    HealthNavigationRow(title: "Vitamins & minerals", detail: micronutrientsDetail, icon: "leaf.fill", color: Theme.nutrition) {
                        MicronutrientsPage()
                    }
                }
                // Garmin help is under Settings › Data sources (ux-audit.md 4.3, B5).
            }
            .card()
        }
    }

    private var insightsDetail: String {
        let count = checkIns.insights.count
        // Alcohol patterns can come from Health's drinks log as well as the check-ins.
        let usesDrinks = checkIns.insights.contains { CheckInInsights.alcoholFactors.contains($0.factor) }
        let source = usesDrinks ? "from your check-ins and drinks log" : "from your check-ins"
        if count > 0 { return "\(count) pattern\(count == 1 ? "" : "s") \(source)" }
        let days = checkIns.daysUntilInsights
        return days > 0 ? "Check in for \(days) more day\(days == 1 ? "" : "s")" : "No clear patterns yet"
    }

    private var alcoholDetail: String {
        let nights = checkIns.alcoholNightsLogged
        guard nights > 0 else { return "Log drinks in the evening check-in" }
        return "\(nights) night\(nights == 1 ? "" : "s") logged"
    }

    private var micronutrientsDetail: String {
        let findings = metrics.micronutrients
        guard !findings.isEmpty else { return "Needs 4 days of food logs" }
        let low = findings.filter { $0.kind == .low }.count
        let high = findings.filter { $0.kind == .high }.count
        var parts: [String] = []
        if low > 0 { parts.append("\(low) low") }
        if high > 0 { parts.append("\(high) too high") }
        return (parts.isEmpty ? "All near target" : parts.joined(separator: ", ")) + " · 7-day average"
    }
}

private struct InsightsPage: View {
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        HealthDetailPage(title: "What affects you") {
            InsightsCard(insights: checkIns.insights, daysLeft: checkIns.daysUntilInsights, progress: checkIns.habitProgress)
        }
    }
}

private struct AlcoholPage: View {
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        HealthDetailPage(title: "Alcohol and your sleep") {
            AlcoholEffectCard(findings: checkIns.alcoholFindings, nightsLogged: checkIns.alcoholNightsLogged)
        }
    }
}

/// The "What to fix" page (`MicronutrientsCard`); pushed from Patterns and from Key measures.
struct MicronutrientsPage: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        HealthDetailPage(title: "Vitamins & minerals") {
            MicronutrientsCard(findings: metrics.micronutrients)
        }
    }
}
