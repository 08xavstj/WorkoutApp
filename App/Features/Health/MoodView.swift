import SwiftUI
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
        guard days > 0 else { return MetricVerdict("Log a mood in a check-in") }
        return MetricVerdict("14-day average · \(days) day\(days == 1 ? "" : "s")")
    }
}

/// The last 30 days of moods, newest first, with their words and what they were about.
struct MoodView: View {
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        HealthDetailPage(title: "Mood") {
            MoodListCard(samples: checkIns.moods)
            Text("From Apple Health (any app that logs State of Mind) and your check-ins. Short sleep reliably lowers mood (Palmer et al. 2024, 154 experiments) and exercise lifts it (Heissel et al. 2023); when your own data shows those links, they appear under What affects you. Tracking mood by itself has weak evidence of helping; its value here is as a signal.")
                .font(Theme.Typography.context)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct MoodListCard: View {
    let samples: [MoodSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Last 30 days")
            if samples.isEmpty {
                Text("No moods yet. Pick how you're feeling in the morning or evening check-in, or log a State of Mind in Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(samples.sorted { $0.date > $1.date }) { sample in
                MoodEntryRow(sample: sample)
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
                    Text(sample.date, format: dateFormat)
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

    /// Daily moods show the day; momentary ones the time too.
    private var dateFormat: Date.FormatStyle {
        let day = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return sample.kind == .daily ? day : day.hour().minute()
    }

    /// "Happy, calm · Training, friends" with Apple's names made readable.
    private var detail: String {
        var parts: [String] = []
        if !sample.labels.isEmpty { parts.append(sample.labels.map(MoodScale.readable).joined(separator: ", ")) }
        if !sample.associations.isEmpty { parts.append(sample.associations.map(MoodScale.readable).joined(separator: ", ")) }
        if sample.kind == .momentary { parts.append("In the moment") }
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
