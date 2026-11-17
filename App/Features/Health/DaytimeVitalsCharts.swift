import SwiftUI
import Charts
import AppCore

/// Daytime vitals › Hour by hour: heart rate for each hour of the day (the
/// lowest to highest minute as a bar, the average as a line), HRV under it
/// where there are readings, with sleep and workouts shaded and a dash for
/// what is usual for that hour.
struct DaytimeChartCard: View {
    let summary: DaytimeVitals.Summary
    let day: DaytimeVitalsView.DayChoice

    private var hasHRV: Bool { summary.profile.contains { $0.hrv != nil } }
    private var hasUsual: Bool { summary.profile.contains { $0.usualHeartRate != nil || $0.usualHRV != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Hour by hour")
            Text("Heart rate")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            DaytimeHeartRateChart(summary: summary, dayWord: day.word)
                .frame(height: 180)
            if hasHRV {
                Text(summary.hrvMetric.map { "HRV (\($0.rawValue))" } ?? "HRV")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                DaytimeHRVChart(summary: summary, dayWord: day.word)
                    .frame(height: 120)
            }
            legend
        }
        .card()
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Side by side when they fit, stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legendItems }
                VStack(alignment: .leading, spacing: 4) { legendItems }
            }
            Text("Bars run from the lowest to the highest minute of each hour. The line is the hour's average.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension DaytimeChartCard {
    @ViewBuilder
    private var legendItems: some View {
        DaytimeLegendItem(text: "Asleep", color: Theme.sleep.opacity(DaytimeChartStyle.sleepOpacity * 2.5))
        if !summary.workouts.isEmpty {
            DaytimeLegendItem(text: "Workout", color: Theme.strain.opacity(DaytimeChartStyle.workoutOpacity * 2.5))
        }
        if hasUsual {
            DaytimeLegendItem(text: "Usual for the hour", color: Theme.primaryText.opacity(0.55), isDash: true)
        }
    }
}

/// A colour swatch (or a short dash) and a word.
private struct DaytimeLegendItem: View {
    let text: String
    let color: Color
    var isDash = false

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: isDash ? 12 : 10, height: isDash ? 2 : 10)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// What the two charts share.
enum DaytimeChartStyle {
    static let sleepOpacity = 0.10
    static let workoutOpacity = 0.16

    /// A shaded stretch of the day.
    struct Stretch: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let isWorkout: Bool
    }

    /// One hour's value with the unbroken run of hours it belongs to, so a
    /// line stops at a gap (the watch off) instead of bridging it.
    struct HourValue: Identifiable {
        let id: Int
        let date: Date
        let value: Double
        let run: String
    }

    static func dayEnd(_ start: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    static func bands(_ summary: DaytimeVitals.Summary) -> [Stretch] {
        let sleep = summary.sleep.enumerated().map { Stretch(id: $0.offset, start: $0.element.start, end: $0.element.end, isWorkout: false) }
        let workouts = summary.workouts.enumerated().map { Stretch(id: 1_000 + $0.offset, start: $0.element.start, end: $0.element.end, isWorkout: true) }
        return sleep + workouts
    }

    /// The middle of each hour that has a value, grouped into runs of consecutive hours.
    static func marks(_ profile: [DaytimeVitals.HourPoint], value: (DaytimeVitals.HourPoint) -> Double?) -> [HourValue] {
        var result: [HourValue] = []
        var run = 0
        var previous: Int?
        for point in profile {
            guard let number = value(point) else { continue }
            if let previous, point.hour - previous > 1 { run += 1 }
            previous = point.hour
            result.append(HourValue(id: point.hour, date: point.start.addingTimeInterval(1800), value: number, run: "run \(run)"))
        }
        return result
    }

    /// "4 AM" (or "04" on a 24-hour clock).
    static func hourText(_ date: Date) -> String {
        date.formatted(.dateTime.hour())
    }
}

/// Heart rate by hour.
private struct DaytimeHeartRateChart: View {
    let summary: DaytimeVitals.Summary
    let dayWord: String

    private var hours: [DaytimeVitals.HourPoint] { summary.profile.filter { $0.heartRate != nil } }
    private var usualHours: [DaytimeVitals.HourPoint] { summary.profile.filter { $0.usualHeartRate != nil } }

    private var domain: ClosedRange<Double> {
        var values: [Double] = []
        for point in summary.profile {
            if let low = point.lowHeartRate { values.append(low) }
            if let high = point.highHeartRate { values.append(high) }
            if let usual = point.usualHeartRate { values.append(usual) }
        }
        // At least 30 bpm tall, so a quiet day doesn't turn 3 bpm into a mountain (`ChartScale`; app's choice).
        return ChartScale.domain(values, minimumSpan: 30) ?? 40...120
    }

    var body: some View {
        let scale = domain
        let averages = DaytimeChartStyle.marks(summary.profile) { $0.heartRate }
        Chart {
            ForEach(DaytimeChartStyle.bands(summary)) { band in
                RectangleMark(
                    xStart: .value("From", band.start),
                    xEnd: .value("To", band.end),
                    yStart: .value("Bottom", scale.lowerBound),
                    yEnd: .value("Top", scale.upperBound)
                )
                .foregroundStyle(band.isWorkout ? Theme.strain.opacity(DaytimeChartStyle.workoutOpacity) : Theme.sleep.opacity(DaytimeChartStyle.sleepOpacity))
            }
            ForEach(hours) { point in
                BarMark(
                    x: .value("Hour", point.start.addingTimeInterval(1800)),
                    yStart: .value("Lowest minute", point.lowHeartRate ?? 0),
                    yEnd: .value("Highest minute", point.highHeartRate ?? 0),
                    width: .fixed(5)
                )
                .foregroundStyle(Theme.heart.opacity(0.28))
                .cornerRadius(2.5)
            }
            ForEach(usualHours) { point in
                RuleMark(
                    xStart: .value("From", point.start.addingTimeInterval(600)),
                    xEnd: .value("To", point.start.addingTimeInterval(3000)),
                    y: .value("Usual", point.usualHeartRate ?? 0)
                )
                .foregroundStyle(Theme.primaryText.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            ForEach(averages) { mark in
                LineMark(x: .value("Hour", mark.date), y: .value("Average", mark.value), series: .value("Run", mark.run))
                    .foregroundStyle(Theme.heart)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(averages) { mark in
                PointMark(x: .value("Hour", mark.date), y: .value("Average", mark.value))
                    .foregroundStyle(Theme.heart)
                    .symbolSize(14)
            }
        }
        .chartYScale(domain: scale)
        .chartXScale(domain: summary.date...DaytimeChartStyle.dayEnd(summary.date))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
        }
        // A chart states its message for VoiceOver too (HIG Charts; ux-audit.md P15).
        .accessibilityLabel("Heart rate by hour, \(dayWord)")
        .accessibilityValue(spokenSummary)
    }

    private var spokenSummary: String {
        let awake = hours.filter { $0.state != .asleep }
        guard let lowest = awake.min(by: { ($0.heartRate ?? 0) < ($1.heartRate ?? 0) }),
              let highest = awake.max(by: { ($0.heartRate ?? 0) < ($1.heartRate ?? 0) }) else {
            return hours.isEmpty ? "No readings" : "Asleep for every hour with readings"
        }
        var text = "While awake, lowest hour \(whole(lowest.heartRate ?? 0)) beats per minute at \(DaytimeChartStyle.hourText(lowest.start)), highest \(whole(highest.heartRate ?? 0)) at \(DaytimeChartStyle.hourText(highest.start))"
        if !summary.workouts.isEmpty {
            text += ", \(summary.workouts.count) workout\(summary.workouts.count == 1 ? "" : "s")"
        }
        return text
    }
}

/// HRV by hour: the median of each hour's readings as a dot. A watch that
/// takes a reading every few hours shows a few dots and no line through them.
private struct DaytimeHRVChart: View {
    let summary: DaytimeVitals.Summary
    let dayWord: String

    private var usualHours: [DaytimeVitals.HourPoint] { summary.profile.filter { $0.usualHRV != nil } }

    private var domain: ClosedRange<Double> {
        var values: [Double] = []
        for point in summary.profile {
            if let value = point.hrv { values.append(value) }
            if let usual = point.usualHRV { values.append(usual) }
        }
        // At least 20 ms tall (`ChartScale`; app's choice).
        return ChartScale.domain(values, minimumSpan: 20) ?? 0...100
    }

    var body: some View {
        let scale = domain
        let medians = DaytimeChartStyle.marks(summary.profile) { $0.hrv }
        Chart {
            ForEach(DaytimeChartStyle.bands(summary)) { band in
                RectangleMark(
                    xStart: .value("From", band.start),
                    xEnd: .value("To", band.end),
                    yStart: .value("Bottom", scale.lowerBound),
                    yEnd: .value("Top", scale.upperBound)
                )
                .foregroundStyle(band.isWorkout ? Theme.strain.opacity(DaytimeChartStyle.workoutOpacity) : Theme.sleep.opacity(DaytimeChartStyle.sleepOpacity))
            }
            ForEach(usualHours) { point in
                RuleMark(
                    xStart: .value("From", point.start.addingTimeInterval(600)),
                    xEnd: .value("To", point.start.addingTimeInterval(3000)),
                    y: .value("Usual", point.usualHRV ?? 0)
                )
                .foregroundStyle(Theme.primaryText.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            ForEach(medians) { mark in
                LineMark(x: .value("Hour", mark.date), y: .value("HRV", mark.value), series: .value("Run", mark.run))
                    .foregroundStyle(Theme.recoveryHigh.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(medians) { mark in
                PointMark(x: .value("Hour", mark.date), y: .value("HRV", mark.value))
                    .foregroundStyle(Theme.recoveryHigh)
                    .symbolSize(20)
            }
        }
        .chartYScale(domain: scale)
        .chartXScale(domain: summary.date...DaytimeChartStyle.dayEnd(summary.date))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
        }
        .accessibilityLabel("HRV by hour, \(dayWord)")
        .accessibilityValue(spokenSummary)
    }

    private var spokenSummary: String {
        let hours = summary.profile.filter { $0.hrv != nil }
        let awake = hours.filter { $0.state == .awake }.compactMap(\.hrv)
        let asleep = hours.filter { $0.state == .asleep }.compactMap(\.hrv)
        var parts = ["Readings in \(hours.count) hour\(hours.count == 1 ? "" : "s")"]
        if let low = awake.min(), let high = awake.max() {
            parts.append("awake \(whole(low)) to \(whole(high)) milliseconds")
        }
        if let low = asleep.min(), let high = asleep.max() {
            parts.append("asleep \(whole(low)) to \(whole(high))")
        }
        return parts.joined(separator: ", ")
    }
}
