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
                            GlassIcon(systemName: "calendar")
                        }
                        .accessibilityLabel("Workout history")
                    }
                    .padding(.top, 8)
                    WeekStrip(days: metrics.weekStrain)
                    DayStrainCard()
                    DeloadCard()
                    SectionTitle(text: "Muscles")
                    MuscleMapCard()
                    SectionTitle(text: "Training Load", trailing: "Last 7 days vs usual")
                    HStack(spacing: 12) {
                        LoadCard(title: "Cardio", result: metrics.cardioLoad, colors: [Theme.oxygenLight, Theme.oxygen, Theme.sleep])
                        LoadCard(title: "Muscular", result: metrics.muscularLoad, colors: [Theme.strainLight, Theme.strain, Theme.lifting])
                    }
                    SectionTitle(text: "Today's Activity")
                    ActivityCard()
                    SectionTitle(text: "Heart Rate Zones")
                    ZonesCard()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .lockedToScreenWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.rose, Theme.Wash.butter])
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
        // The last 7 days, today last.
        let dates = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        HStack(spacing: 6) {
            ForEach(dates, id: \.self) { date in
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let strain = days.first { calendar.isDate($0.date, inSameDayAs: date) }?.strain
                VStack(spacing: 6) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? Theme.strainTextColor : Theme.secondaryText)
                    if date > today {
                        Circle()
                            .strokeBorder(Theme.secondaryText.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                            .frame(width: 36, height: 36)
                    } else {
                        GradientRing(progress: (strain ?? 0) / StrainCalculator.maximum, colors: Theme.strainColors, lineWidth: 4, showsDisk: false) {
                            Text(strain.map { "\(whole($0))" } ?? "–")
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isToday ? "Today" : date.formatted(.dateTime.weekday(.wide).day())), strain \(strain.map { strainText($0) } ?? "no data")")
            }
        }
    }
}

// MARK: - Day strain gauge

private struct DayStrainCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(WorkoutLauncher.self) private var launcher
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 60

    var body: some View {
        let current = metrics.strain?.strain ?? 0
        let target = metrics.targetStrain
        VStack(spacing: 14) {
            HStack {
                CardLabel(text: "Day strain")
                Spacer()
                if let target {
                    Text("Target \(strainRangeText(target))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.recoveryHighText)
                }
            }
            ArcGauge(
                value: current / StrainCalculator.maximum,
                band: target.map { ($0.lowerBound / StrainCalculator.maximum)...($0.upperBound / StrainCalculator.maximum) },
                colors: [Theme.strainLight, Theme.strain, Theme.lifting],
                lineWidth: 24
            ) {
                VStack(spacing: 2) {
                    Text(strainText(current))
                        .font(.system(size: min(heroSize, 76), weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: [Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing))
                    Text("day strain")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 250, height: 250)
            .padding(.bottom, -40)

            encouragement(current: current, target: target)
        }
        .card(tint: Theme.strain)
    }

    @ViewBuilder
    private func encouragement(current: Double, target: ClosedRange<Double>?) -> some View {
        if let target {
            let status = StrainPlanner().status(current: current, target: target)
            let (lead, rest): (String, String) = {
                switch status {
                case .below(let remaining):
                    let amount = strainText(remaining)
                    return ("\(amount) to go:", metrics.activities.contains(where: \.isStrength)
                        ? "one more session today will get you there."
                        : "a workout today will get you into your target range.")
                case .inRange:
                    return ("Target reached:", "nice work. Anything more is a bonus; prioritise sleep tonight.")
                case .above:
                    return ("Above target:", "take it easy for the rest of the day so you recover for tomorrow.")
                }
            }()
            let isBelow: Bool = { if case .below = status { return true } else { return false } }()
            let message = HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Theme.recoveryHigh)
                let bold = Text(lead).fontWeight(.semibold).foregroundStyle(Theme.recoveryHighText)
                Text("\(bold) \(rest)")
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isBelow {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .font(.subheadline)
            .padding(14)
            .background(Theme.recoveryHigh.opacity(0.1), in: .rect(cornerRadius: 16))
            if isBelow {
                Button { launcher.openBuilder() } label: { message }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plan a workout")
            } else {
                message
            }
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
        let maximum = StrainCalculator.maximum
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            TickDial(
                value: result.map { $0.value / maximum },
                band: band(maximum: maximum),
                colors: colors,
                tickCount: 36,
                tickLength: 10
            ) {
                VStack(spacing: 0) {
                    Text(result.map { $0.value.formatted(.number.precision(.fractionLength(0))) } ?? "–")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    Text("avg daily strain")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                    if let result, result.status != .calibrating {
                        Text("your usual \(whole(result.usual.lowerBound))–\(whole(result.usual.upperBound.rounded(.up)))")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 18)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 140)
            .frame(maxWidth: .infinity)
            .padding(.bottom, -14)
            HStack {
                Text("0")
                Spacer()
                Text("\(whole(maximum))%")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .card(tint: colors.last)
    }

    private func band(maximum: Double) -> ClosedRange<Double>? {
        guard let result, result.status != .calibrating else { return nil }
        return (result.usual.lowerBound / maximum)...(result.usual.upperBound / maximum)
    }

    /// A description of this week vs your usual 4 weeks (not an injury prediction).
    private var statusText: String {
        switch result?.status {
        case .lighter: return "Lighter than usual"
        case .steady: return "About your usual"
        case .building: return "A bit more than usual"
        case .spike: return "Much more than usual"
        default: return "Learning your usual"
        }
    }

    private var statusColor: Color {
        switch result?.status {
        case .steady: Theme.recoveryHighText
        case .building: Theme.strainTextColor
        case .spike: Theme.recoveryModerateText
        case .lighter: Theme.oxygen
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
                    IconBadge(systemName: "figure.run", color: Theme.secondaryText, size: 44)
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
                        color: item.isStrength ? Theme.lifting : Theme.oxygen,
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
                    Chip(text: "+\(strainText(item.strainAdded))")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}

private struct ZonesCard: View {
    @Environment(DailyMetricsModel.self) private var metrics

    private let names = ["Easy", "Light", "Aerobic", "Threshold", "Max"]

    /// Heart-rate range for zone 1-5 (50-60%, ... 90-100% of heart-rate reserve).
    private func bpmRange(_ index: Int) -> String? {
        guard let profile = metrics.heartRateProfile else { return nil }
        let reserve = profile.maxHeartRate - profile.restingHeartRate
        let low = profile.restingHeartRate + (0.5 + 0.1 * Double(index)) * reserve
        let high = profile.restingHeartRate + (0.6 + 0.1 * Double(index)) * reserve
        return "\(whole(low))–\(whole(high))"
    }

    var body: some View {
        let minutes = metrics.strain?.zoneMinutes ?? [0, 0, 0, 0, 0]
        let total = minutes.reduce(0, +)
        let peak = max(minutes.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            Text(total > 0 ? "\(whole(total)) min in zones today (numbers under each bar are bpm)" : "No time in heart-rate zones yet today")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text(minutes[index] > 0 ? "\(whole(minutes[index].rounded()))m" : "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.track)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: [Theme.zoneColors[index], Theme.zoneColors[index].opacity(0.45)], startPoint: .top, endPoint: .bottom))
                                .frame(height: max(6, 130 * minutes[index] / peak))
                                .shadow(color: Theme.zoneColors[index].opacity(minutes[index] > 0 ? 0.45 : 0), radius: 6)
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
                        if let range = bpmRange(index) {
                            Text(range)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }
}

/// Suggests a lighter week when lifts stall (and HRV is down).
private struct DeloadCard: View {
    @Environment(MuscleModel.self) private var muscles

    var body: some View {
        if let advice = muscles.deload {
            VStack(alignment: .leading, spacing: 8) {
                Label(advice.strong ? "Time for a deload week" : "Consider a lighter week", systemImage: "arrow.down.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(advice.strong ? Theme.recoveryModerate : Theme.oxygen)
                Text(advice.message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                Text("Stalled: " + advice.stalledLifts.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text("Deloads are standard in strength training (Bell et al., Sports Med Open 2023 consensus): keep the weights, cut sets by about half, for about a week.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card(tint: advice.strong ? Theme.recoveryModerate : Theme.oxygen)
        }
    }
}
