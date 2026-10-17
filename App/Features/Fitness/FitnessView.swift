import SwiftUI
import SwiftData
import AppCore

/// Fitness: this week's strain, today's target gauge, training load,
/// today's activities, heart-rate zones and workout history.
struct FitnessView: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(AppRefresher.self) private var refresher

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Fitness")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        NavigationLink {
                            WorkoutHistoryView()
                        } label: {
                            Image(systemName: "calendar")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                                .frame(width: 46, height: 46)
                                .background(Theme.card, in: .circle)
                                .shadow(color: Color.black.opacity(0.07), radius: 9, y: 4)
                        }
                        .accessibilityLabel("Workout history")
                    }
                    .padding(.top, 8)
                    WeekStrip(days: metrics.weekStrain)
                    DayStrainCard()
                    SectionTitle(text: "Training Load")
                    HStack(spacing: 12) {
                        LoadCard(title: "Cardio", result: metrics.cardioLoad, colors: [Theme.strainLight, Theme.strain])
                        LoadCard(title: "Muscular", result: metrics.muscularLoad, colors: [Theme.liftingLight, Theme.lifting])
                    }
                    SectionTitle(text: "Today's Activity")
                    ActivityCard()
                    SectionTitle(text: "Heart Rate Zones")
                    ZonesCard()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.strain, Theme.sleep])
            }
            .background(Theme.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { await refresher.refresh() }
        }
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    let days: [DailyMetricsModel.DayStrain]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Three days back, today, three days ahead.
        let dates = (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        HStack(spacing: 6) {
            ForEach(dates, id: \.self) { date in
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let strain = days.first { calendar.isDate($0.date, inSameDayAs: date) }?.strain
                VStack(spacing: 6) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? Theme.strain : Theme.secondaryText)
                    if date > today {
                        Circle()
                            .strokeBorder(Theme.secondaryText.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                            .frame(width: 36, height: 36)
                    } else {
                        GradientRing(progress: (strain ?? 0) / 21, colors: [Theme.strainLight, Theme.strain], lineWidth: 4, showsDisk: false) {
                            Text(strain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.primaryText)
                        }
                        .frame(width: 36, height: 36)
                    }
                    Text(date.formatted(.dateTime.day()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isToday ? Theme.primaryText : Theme.secondaryText)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isToday ? Theme.card : Color.clear, in: .rect(cornerRadius: 18))
                .shadow(color: isToday ? Color.black.opacity(0.07) : .clear, radius: 9, y: 4)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Day strain gauge

private struct DayStrainCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(WorkoutLauncher.self) private var launcher

    var body: some View {
        let current = metrics.strain?.strain ?? 0
        let target = metrics.targetStrain
        VStack(spacing: 14) {
            HStack {
                CardLabel(text: "Day strain")
                Spacer()
                if let target {
                    Text("Target \(Int(target.lowerBound))–\(Int(target.upperBound))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.recoveryHigh)
                }
            }
            ArcGauge(
                value: current / 21,
                band: target.map { ($0.lowerBound / 21)...($0.upperBound / 21) },
                colors: [Theme.strainLight, Theme.strain],
                lineWidth: 22
            ) {
                VStack(spacing: 2) {
                    Text(current.formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text("of 21 strain")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 250, height: 250)
            .padding(.bottom, -40)

            encouragement(current: current, target: target)
        }
        .card()
    }

    @ViewBuilder
    private func encouragement(current: Double, target: ClosedRange<Double>?) -> some View {
        if let target {
            let status = StrainPlanner().status(current: current, target: target)
            let (lead, rest): (String, String) = {
                switch status {
                case .below(let remaining):
                    let amount = remaining.formatted(.number.precision(.fractionLength(1)))
                    return ("\(amount) to go:", metrics.activities.contains(where: \.isStrength)
                        ? "one more session today will get you there."
                        : "a workout today will get you into your target range.")
                case .inRange:
                    return ("Target reached:", "nice work. Anything more is a bonus; prioritise sleep tonight.")
                case .above:
                    return ("Above target:", "take it easy for the rest of the day so you recover for tomorrow.")
                }
            }()
            Button {
                if case .below = status { launcher.openBuilder() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(Theme.recoveryHigh)
                    let bold = Text(lead).fontWeight(.semibold).foregroundStyle(Theme.recoveryHigh)
                    Text("\(bold) \(rest)")
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .padding(14)
                .background(Theme.recoveryHigh.opacity(0.1), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else {
            Text("Wear your watch to sleep so the app can set a daily strain target from your recovery.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Training load

private struct LoadCard: View {
    let title: String
    let result: TrainingLoadCalculator.Result?
    let colors: [Color]

    var body: some View {
        let maximum = 21.0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Chip(text: statusText, color: statusColor)
            }
            ArcGauge(
                value: (result?.value ?? 0) / maximum,
                band: band(maximum: maximum),
                colors: colors,
                lineWidth: 12
            ) {
                VStack(spacing: 0) {
                    Text(result.map { $0.value.formatted(.number.precision(.fractionLength(0))) } ?? "–")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    if let result, result.status != .calibrating {
                        Text("optimal \(Int(result.optimal.lowerBound))–\(Int(result.optimal.upperBound.rounded(.up)))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .frame(width: 120, height: 120)
            .frame(maxWidth: .infinity)
            .padding(.bottom, -18)
            HStack {
                Text("0")
                Spacer()
                Text("max \(Int(maximum))")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private func band(maximum: Double) -> ClosedRange<Double>? {
        guard let result, result.status != .calibrating else { return nil }
        return (result.optimal.lowerBound / maximum)...(result.optimal.upperBound / maximum)
    }

    private var statusText: String {
        switch result?.status {
        case .optimal: "Optimal"
        case .low: "Low"
        case .high: "High"
        default: "Calibrating"
        }
    }

    private var statusColor: Color {
        switch result?.status {
        case .optimal: Theme.recoveryHigh
        case .high: Theme.recoveryModerate
        case .low: Theme.strain
        default: Theme.secondaryText
        }
    }
}

// MARK: - Activity and zones

private struct ActivityCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(WorkoutLauncher.self) private var launcher

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if metrics.activities.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(systemName: "zzz", color: Theme.secondaryText, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No workouts yet today")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Log a gym session or record one on your watch.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("Start") { launcher.openBuilder() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            ForEach(Array(metrics.activities.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().overlay(Theme.separator).padding(.vertical, 12)
                }
                HStack(spacing: 12) {
                    IconBadge(
                        systemName: item.isStrength ? "dumbbell.fill" : "figure.walk",
                        color: item.isStrength ? Theme.lifting : Theme.recoveryHigh,
                        size: 48
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("\(item.detail) · \(item.start.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Chip(text: "+\(item.strainAdded.formatted(.number.precision(.fractionLength(1))))")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}

private struct ZonesCard: View {
    @Environment(DailyMetricsModel.self) private var metrics

    private let names = ["Warm-up", "Fat burn", "Aerobic", "Threshold", "Max"]

    var body: some View {
        let minutes = metrics.strain?.zoneMinutes ?? [0, 0, 0, 0, 0]
        let total = minutes.reduce(0, +)
        let peak = max(minutes.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            Text(total > 0 ? "\(Int(total)) min in zones today" : "No time in heart-rate zones yet today")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text(minutes[index] > 0 ? "\(Int(minutes[index].rounded()))m" : "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.track)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: [Theme.zoneColors[index], Theme.zoneColors[index].opacity(0.75)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(6, 130 * minutes[index] / peak))
                        }
                        .frame(height: 130)
                        Text("Z\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                        Text(names[index])
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }
}
