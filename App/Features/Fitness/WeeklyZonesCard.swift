import AppCore
import Charts
import SwiftData
import SwiftUI

/// The last 12 weeks of cardio minutes: stacked minutes per heart-rate zone,
/// moderate-equivalent minutes (vigorous counted double) as a line, and WHO's
/// 150 and 300 as dashed lines (`WeeklyIntensity`; competitor-features-2026-11.md, B8).
/// Lifting is left out, as everywhere cardio minutes are counted.
struct WeeklyZonesCard: View {
    @Environment(\.healthClient) private var health
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @State private var weeks: [WeeklyIntensity.Week] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Last \(WeeklyIntensity.weeksShown) weeks")
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if weeks.allSatisfy({ !$0.hasHeartRate }) {
                Text("No heart rate in Apple Health for these weeks. Wear a watch during cardio to see your weekly minutes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                headline
                WeeklyZonesChart(weeks: weeks)
                    .frame(height: 220)
                legend
            }
            Text(WeeklyIntensity.evidenceNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .task { await load() }
    }

    /// "Last week: 186 min · 8 of 12 weeks at 150 or more".
    private var headline: some View {
        let met = WeeklyIntensity.weeksMet(weeks)
        let last = weeks.dropLast().last
        return VStack(alignment: .leading, spacing: 2) {
            if let last {
                Text("Last week: \(last.moderateEquivalent) min (\(last.standing.title))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
            Text("\(met.met) of \(met.of) weeks at 150 or more · this week so far \(weeks.last?.moderateEquivalent ?? 0) min")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var legendItems: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2).fill(Theme.zoneColors[index]).frame(width: 8, height: 8)
            }
            Text("Zones 1–5")
        }
        HStack(spacing: 4) {
            Circle().fill(Theme.primaryText).frame(width: 7, height: 7)
            Text("Moderate + 2 × vigorous")
        }
        HStack(spacing: 4) {
            Rectangle().fill(Theme.recoveryHighText).frame(width: 12, height: 1.5)
            Text("WHO 150 and 300")
        }
    }

    private func load() async {
        defer { loaded = true }
        let calendar = Calendar.current
        let starts = WeeklyIntensity.weekStarts(endingWith: .now, calendar: calendar)
        guard let first = starts.first, let current = starts.last else { return }
        let profile = metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)
        let scheme = await ZonePreferences.current(profile: profile, health: health).scheme
        let signature = WeeklyIntensity.signature(profile: profile, scheme: scheme)
        let lifting = sessions.filter { !$0.isActive && $0.startedAt >= first }
            .map { DateInterval(start: $0.startedAt, end: max($0.startedAt, $0.endedAt ?? $0.startedAt)) }
        var perWeek: [Date: Int] = [:]
        for interval in lifting {
            if let start = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start { perWeek[start, default: 0] += 1 }
        }
        let cached = WeeklyIntensityCache.weeks(signature: signature, liftingSessions: perWeek)
        // Heart rate from the first week not cached (the current week is always read).
        let missing = starts.filter { $0 == current || cached[$0] == nil }
        var counted: [Date: WeeklyIntensity.Week] = [:]
        if let from = missing.first, let health {
            let readings = (try? await health.heartRatePerMinute(from: from, to: .now)) ?? []
            let fresh = await Task.detached(priority: .userInitiated) {
                WeeklyIntensity.weeks(starts: starts.filter { $0 >= from }, heartRate: readings, lifting: lifting,
                                      profile: profile, scheme: scheme, calendar: calendar)
            }.value
            for week in fresh where missing.contains(week.start) { counted[week.start] = week }
        }
        weeks = starts.map { start in
            counted[start] ?? cached[start]
                ?? WeeklyIntensity.Week(start: start, zoneMinutes: [0, 0, 0, 0, 0], moderate: 0, vigorous: 0, hasHeartRate: false)
        }
        // Only weeks with heart rate that ended 3+ days ago are kept: a watch
        // can sync a day or two late (the app's choice), and a failed read
        // mustn't be kept as an empty week.
        let settled = calendar.date(byAdding: .day, value: -10, to: .now) ?? current
        WeeklyIntensityCache.store(weeks.filter { $0.start < min(current, settled) && $0.hasHeartRate },
                                   signature: signature, liftingSessions: perWeek)
    }
}

/// Stacked zone minutes per week, the WHO band and the moderate-equivalent line.
private struct WeeklyZonesChart: View {
    let weeks: [WeeklyIntensity.Week]

    var body: some View {
        Chart {
            // Bars at the same week stack.
            ForEach(weeks) { week in
                ForEach(0..<5, id: \.self) { zone in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear),
                            y: .value("Minutes", zone < week.zoneMinutes.count ? week.zoneMinutes[zone] : 0))
                        .foregroundStyle(Theme.zoneColors[zone])
                }
            }
            ForEach([WeeklyIntensity.guidelineLow, WeeklyIntensity.guidelineHigh], id: \.self) { minutes in
                RuleMark(y: .value("WHO", minutes))
                    .foregroundStyle(Theme.recoveryHighText.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            ForEach(weeks.filter(\.hasHeartRate)) { week in
                LineMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Moderate-equivalent", week.moderateEquivalent))
                    .foregroundStyle(Theme.primaryText)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Moderate-equivalent", week.moderateEquivalent))
                    .foregroundStyle(Theme.primaryText)
                    .symbolSize(24)
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly cardio minutes for \(weeks.count) weeks")
        .accessibilityValue(weeks.map { "\($0.start.formatted(.dateTime.day().month(.abbreviated))): \($0.moderateEquivalent) minutes" }.joined(separator: ", "))
    }
}
