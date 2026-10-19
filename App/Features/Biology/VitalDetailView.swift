import SwiftUI
import Charts
import AppCore

/// A stat's history: pick a range, see each day, the average for that range
/// (dashed line), the typical range or goal, and tap any day for its value.
struct VitalDetailView: View {
    let stat: VitalsModel.Stat
    let colors: [Color]
    @Environment(\.dismiss) private var dismiss
    @State private var days: Int
    @State private var selectedDate: Date?

    init(stat: VitalsModel.Stat, colors: [Color]) {
        self.stat = stat
        self.colors = colors
        _days = State(initialValue: stat.defaultDays)
    }

    private var main: Color { colors.last ?? Theme.strain }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if hasHistory {
                        if rangeOptions.count > 1 {
                            Picker("Range", selection: $days) {
                                ForEach(rangeOptions, id: \.self) { option in
                                    Text(rangeLabel(option)).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        chartCard
                        summaryRow
                        dayByDay
                    } else if stat.value != nil {
                        Text("History appears here once there are a few days of readings.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let about = stat.about {
                        VStack(alignment: .leading, spacing: 6) {
                            CardLabel(text: "What it means", color: main)
                            Text(about)
                                .font(.subheadline)
                                .foregroundStyle(Theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                    if let footnote = stat.footnote {
                        Text(footnote)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if stat.value == nil && !hasHistory {
                        Text("Nothing in Apple Health yet. If your watch records this, check that its app shares with Apple Health and that WorkoutApp can read it (Health app → profile → Apps → WorkoutApp).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle(stat.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: days) { selectedDate = nil }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stat.value ?? "No data")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(stat.unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            if let status = stat.status {
                Chip(text: status, color: VitalTile.color(for: stat.tone))
            }
        }
    }

    // MARK: Data in range

    private var calendar: Calendar { .current }

    private var rangeStart: Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }

    private var points: [DatedValue] { stat.series.filter { $0.date >= rangeStart } }
    private var secondaryPoints: [DatedValue] { stat.secondary.filter { $0.date >= rangeStart } }
    private var nights: [SleepNight] { stat.nights.filter { $0.date >= rangeStart } }
    private var isWindows: Bool { stat.chart == .sleepWindows }

    private var hasHistory: Bool {
        isWindows ? stat.nights.count > 1 : stat.series.count > 1
    }

    /// Ranges that show something new: 7 days always, longer ones only when
    /// the data goes back further.
    private var rangeOptions: [Int] {
        let earliest = isWindows ? stat.nights.first?.date : stat.series.first?.date
        guard let earliest else { return [stat.defaultDays] }
        let span = (calendar.dateComponents([.day], from: earliest, to: .now).day ?? 0) + 1
        var options = [7]
        for (previous, option) in zip([7, 30, 90], [30, 90, 180]) where span > previous {
            options.append(option)
        }
        if !options.contains(stat.defaultDays) { options.append(stat.defaultDays) }
        return options.sorted()
    }

    private func rangeLabel(_ days: Int) -> String {
        switch days {
        case 7: "7 days"
        case 30: "30 days"
        case 90: "3 months"
        default: "6 months"
        }
    }

    private var average: Double? {
        let values = points.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private var secondaryAverage: Double? {
        guard !stat.secondaryAsPoints else { return nil }
        let values = secondaryPoints.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    // MARK: Formatting

    private var valueUnit: String { stat.historyUnit ?? stat.unit }

    private func number(_ value: Double) -> String {
        if stat.isHours {
            return Duration.seconds(value * 3600).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }
        return value.formatted(.number.precision(.fractionLength(stat.digits)))
    }

    private func text(_ value: Double) -> String {
        let shown = number(value)
        return stat.isHours || valueUnit.isEmpty ? shown : "\(shown) \(valueUnit)"
    }

    /// Hours from the night's midnight (negative = the evening before) as a clock time.
    private func clock(_ offset: Double) -> String {
        let midnight = calendar.startOfDay(for: .now)
        return midnight.addingTimeInterval(offset * 3600).formatted(date: .omitted, time: .shortened)
    }

    private func offset(_ date: Date, night: Date) -> Double {
        date.timeIntervalSince(night) / 3600
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            selectionLine
            Group {
                if isWindows {
                    windowsChart
                } else {
                    valuesChart
                }
            }
            .frame(height: 220)
            legend
        }
        .card()
    }

    /// The tapped day's value, or a hint.
    @ViewBuilder
    private var selectionLine: some View {
        if let selectedDate {
            if isWindows, let night = nearestNight(to: selectedDate) {
                Text("\(night.date.formatted(.dateTime.weekday(.wide).month().day())): \(clock(offset(night.bedtime, night: night.date)))–\(clock(offset(night.wake, night: night.date))) · \(text(night.hoursAsleep)) asleep")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            } else if let point = nearestPoint(to: selectedDate) {
                Text("\(point.date.formatted(.dateTime.weekday(.wide).month().day())): \(dayText(point))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
        } else {
            Text("Touch the chart to see a day")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var valuesChart: some View {
        Chart {
            if let range = stat.normalRange {
                RectangleMark(yStart: .value("Typical low", range.lowerBound), yEnd: .value("Typical high", range.upperBound))
                    .foregroundStyle(Theme.recoveryHigh.opacity(0.10))
            }
            ForEach(points) { point in
                if stat.chart == .bars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value(stat.title, point.value))
                        .foregroundStyle(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                        .cornerRadius(4)
                        .opacity(selectedDate == nil || isSelected(point.date) ? 1 : 0.4)
                } else {
                    if stat.secondary.isEmpty {
                        AreaMark(x: .value("Day", point.date, unit: .day), y: .value(stat.title, point.value))
                            .foregroundStyle(LinearGradient(colors: [main.opacity(0.25), main.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value(stat.title, point.value), series: .value("Line", "main"))
                        .foregroundStyle(main)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    if points.count <= 31 {
                        PointMark(x: .value("Day", point.date, unit: .day), y: .value(stat.title, point.value))
                            .foregroundStyle(main)
                            .symbolSize(isSelected(point.date) ? 80 : 18)
                    }
                }
            }
            ForEach(secondaryPoints) { point in
                if stat.secondaryAsPoints {
                    PointMark(x: .value("Day", point.date, unit: .day), y: .value(stat.secondaryLabel ?? "Other", point.value))
                        .foregroundStyle(Theme.secondaryText.opacity(0.45))
                        .symbolSize(16)
                } else {
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value(stat.secondaryLabel ?? "Other", point.value), series: .value("Line", "secondary"))
                        .foregroundStyle(colors.first ?? main)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if let goal = stat.goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.recoveryHigh)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(number(goal))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.recoveryHighText)
                    }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Theme.primaryText.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Avg \(number(average))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.card.opacity(0.9), in: .capsule)
                    }
            }
            if let selectedDate, let point = nearestPoint(to: selectedDate) {
                RuleMark(x: .value("Selected", point.date, unit: .day))
                    .foregroundStyle(Theme.secondaryText.opacity(0.35))
            }
        }
        .chartYScale(domain: .automatic(includesZero: stat.chart == .bars))
        .chartXScale(domain: rangeStart...rangeEnd)
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride)) { _ in
                AxisGridLine()
                AxisValueLabel(format: xFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(stat.isHours ? "\(Int(number))h" : number.formatted(.number.notation(.compactName)))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
    }

    private var windowsChart: some View {
        let bedtimes = nights.map { offset($0.bedtime, night: $0.date) }
        let wakes = nights.map { offset($0.wake, night: $0.date) }
        let averageBed = bedtimes.isEmpty ? nil : bedtimes.reduce(0, +) / Double(bedtimes.count)
        let averageWake = wakes.isEmpty ? nil : wakes.reduce(0, +) / Double(wakes.count)
        return Chart {
            ForEach(nights) { night in
                BarMark(
                    x: .value("Night", night.date, unit: .day),
                    yStart: .value("Asleep", offset(night.bedtime, night: night.date)),
                    yEnd: .value("Awake", offset(night.wake, night: night.date))
                )
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                .cornerRadius(5)
                .opacity(selectedDate == nil || isSelected(night.date) ? 1 : 0.4)
            }
            if let averageBed {
                RuleMark(y: .value("Usual bedtime", averageBed))
                    .foregroundStyle(Theme.primaryText.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .bottom, alignment: .leading) {
                        Text("Avg asleep \(clock(averageBed))").font(.caption2.weight(.bold)).foregroundStyle(Theme.primaryText)
                    }
            }
            if let averageWake {
                RuleMark(y: .value("Usual wake", averageWake))
                    .foregroundStyle(Theme.primaryText.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Avg wake \(clock(averageWake))").font(.caption2.weight(.bold)).foregroundStyle(Theme.primaryText)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(domain: rangeStart...rangeEnd)
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride)) { _ in
                AxisGridLine()
                AxisValueLabel(format: xFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 2)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(clock(hours))
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
    }

    private var xStride: Calendar.Component {
        days <= 7 ? .day : (days <= 30 ? .weekOfYear : .month)
    }

    private var xFormat: Date.FormatStyle {
        days <= 7 ? .dateTime.weekday(.narrow) : (days <= 30 ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated))
    }

    private var rangeEnd: Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? .now
    }

    private struct LegendItem: Identifiable {
        var title: String
        var color: Color
        var isLine: Bool
        var id: String { title }
    }

    private var legendItems: [LegendItem] {
        var items: [LegendItem] = []
        if average != nil && !isWindows {
            items.append(LegendItem(title: "Average for this range", color: Theme.primaryText.opacity(0.6), isLine: true))
        }
        if stat.goal != nil {
            items.append(LegendItem(title: "Goal", color: Theme.recoveryHigh, isLine: true))
        }
        if stat.normalRange != nil {
            items.append(LegendItem(title: "Typical range", color: Theme.recoveryHigh.opacity(0.35), isLine: false))
        }
        if !stat.secondary.isEmpty {
            items.append(LegendItem(
                title: stat.secondaryLabel ?? "Other",
                color: stat.secondaryAsPoints ? Theme.secondaryText.opacity(0.5) : (colors.first ?? main),
                isLine: !stat.secondaryAsPoints
            ))
        }
        return items
    }

    @ViewBuilder
    private var legend: some View {
        if !legendItems.isEmpty {
            HStack(spacing: 12) {
                ForEach(legendItems) { item in
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(item.color)
                            .frame(width: 14, height: item.isLine ? 2 : 6)
                        Text(item.title)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .minimumScaleFactor(0.8)
        }
    }

    // MARK: Summary and day list

    private var summaryRow: some View {
        HStack(spacing: 0) {
            if isWindows {
                let hours = nights.map(\.hoursAsleep)
                summaryItem("Avg asleep", hours.isEmpty ? "–" : text(hours.reduce(0, +) / Double(hours.count)))
                summaryItem("Nights", "\(nights.count)")
                summaryItem("Score", stat.value.map { "\($0)/100" } ?? "–")
            } else {
                let values = points.map(\.value)
                let averageText: String = {
                    guard let average else { return "–" }
                    if let secondaryAverage { return "\(number(average))/\(number(secondaryAverage))" }
                    return number(average)
                }()
                summaryItem(stat.chart == .bars ? "Daily avg" : "Average", averageText)
                summaryItem("Lowest", values.min().map(number) ?? "–")
                summaryItem("Highest", values.max().map(number) ?? "–")
                summaryItem("Days", "\(values.count)")
            }
        }
        .card()
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var dayByDay: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "Day by day", color: main)
                .padding(.bottom, 8)
            if isWindows {
                ForEach(Array(nights.reversed().prefix(31))) { night in
                    dayRow(night.date, "\(clock(offset(night.bedtime, night: night.date)))–\(clock(offset(night.wake, night: night.date))) · \(text(night.hoursAsleep))")
                }
            } else {
                ForEach(Array(points.reversed().prefix(31))) { point in
                    dayRow(point.date, dayText(point), delta: average.map { point.value - $0 })
                }
            }
            if (isWindows ? nights.count : points.count) > 31 {
                Text("Showing the latest 31 days.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 8)
            }
        }
        .card()
    }

    private func dayRow(_ date: Date, _ value: String, delta: Double? = nil) -> some View {
        HStack {
            Text(calendar.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            if let delta, abs(delta) > 0 {
                Text("\(delta > 0 ? "+" : "−")\(number(abs(delta)))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 52, alignment: .trailing)
                    .accessibilityLabel("\(delta > 0 ? "above" : "below") average by \(number(abs(delta)))")
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.5)
        }
    }

    private func dayText(_ point: DatedValue) -> String {
        if !stat.secondaryAsPoints,
           let other = stat.secondary.first(where: { calendar.isDate($0.date, inSameDayAs: point.date) }) {
            return "\(number(point.value))/\(number(other.value)) \(valueUnit)"
        }
        return text(point.value)
    }

    // MARK: Selection

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func nearestPoint(to date: Date) -> DatedValue? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func nearestNight(to date: Date) -> SleepNight? {
        nights.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
