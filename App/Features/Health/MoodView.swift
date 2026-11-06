import SwiftUI
import Charts
import AppCore

/// Health › Patterns › "Mood": the 14-day average with a sparkline, pushing a
/// page that lists the last 30 days of moods with their words
/// (docs/research/watch-features.md 4.1; the entries come from Apple Health
/// and the check-ins, merged in `CheckInStore.refreshInsights`).
struct MoodRow: View {
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        MetricRow(
            title: "Mood",
            value: average.map(MoodScale.word(valence:)),
            verdict: verdict,
            trend: trend,
            trendColor: Theme.recoveryHigh,
            hint: "Shows the last 30 days",
            destination: MoodView()
        )
    }

    private var recent: [MoodSample] {
        let start = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return checkIns.moods.filter { $0.date >= start }
    }

    private var average: Double? { MoodHistory.averageValence(recent) }

    private var trend: [DatedValue] {
        MoodHistory.dailyValence(recent).map { DatedValue(date: $0.day, value: $0.valence) }
    }

    private var verdict: MetricVerdict? {
        let days = MoodHistory.dailyValence(recent).count
        guard days > 0, let average else { return MetricVerdict("Log a mood in a check-in") }
        return MetricVerdict("Mostly \(MoodScale.word(valence: average).lowercased()) · \(days) day\(days == 1 ? "" : "s")")
    }
}

/// The last 30 days of moods, newest first, with their words and what they were about.
struct MoodView: View {
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        HealthDetailPage(title: "Mood") {
            MoodChartCard(samples: checkIns.moods)
            MoodListCard(samples: checkIns.moods)
            Text("From Apple Health (any app that logs State of Mind) and your check-ins. Short sleep reliably lowers mood (Palmer et al. 2024, 154 experiments) and exercise lifts it (Heissel et al. 2023); when your own data shows those links, they appear under What affects you. Tracking mood by itself has weak evidence of helping; its value here is as a signal.")
                .font(Theme.Typography.context)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// The daily mood over 30 days, low to high.
private struct MoodChartCard: View {
    let samples: [MoodSample]

    private var points: [DatedValue] {
        MoodHistory.dailyValence(samples).map { DatedValue(date: $0.day, value: $0.valence) }
    }

    var body: some View {
        if points.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: "Daily mood")
                Chart(points) { point in
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Mood", point.value))
                        .foregroundStyle(Theme.recoveryHigh)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value("Mood", point.value))
                        .foregroundStyle(Theme.recoveryHigh)
                        .symbolSize(18)
                }
                // Valence runs from -1 (very unpleasant) to 1 (very pleasant).
                .chartYScale(domain: -1...1)
                .chartYAxis {
                    AxisMarks(values: [-1, 0, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(number < 0 ? "Low" : (number > 0 ? "Good" : "OK"))
                            }
                        }
                    }
                }
                .chartXScale(range: .plotDimension(endPadding: 12))
                .frame(height: 150)
                .accessibilityLabel("Daily mood over the last 30 days")
            }
            .card()
        }
    }
}

private struct MoodListCard: View {
    let samples: [MoodSample]

    /// Entries grouped by day, newest day first.
    private var days: [(day: Date, samples: [MoodSample])] {
        let grouped = Dictionary(grouping: samples) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, samples: (grouped[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Last 30 days")
            if samples.isEmpty {
                Text("No moods yet. Pick how you're feeling in the morning or evening check-in, or log a State of Mind in Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(days, id: \.day) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.day, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    ForEach(entry.samples) { sample in
                        MoodEntryRow(sample: sample)
                    }
                }
            }
        }
        .card()
    }
}

private struct MoodEntryRow: View {
    let sample: MoodSample

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(MoodScale.word(valence: sample.valence))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text(sample.kind == .daily ? "Whole day" : sample.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Happy, calm · Training, friends" with Apple's names made readable.
    private var detail: String {
        var parts: [String] = []
        if !sample.labels.isEmpty { parts.append(sample.labels.map(MoodScale.readable).joined(separator: ", ")) }
        if !sample.associations.isEmpty { parts.append(sample.associations.map(MoodScale.readable).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private var color: Color {
        switch sample.valence {
        case ..<(-0.2): Theme.recoveryLow
        case ..<0.2: Theme.recoveryModerate
        default: Theme.recoveryHigh
        }
    }
}
