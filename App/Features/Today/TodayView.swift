import SwiftUI
import SwiftData
import AppCore

/// Home: score rings and coaching, the strain goal with ways to reach it,
/// nutrition and energy balance, and the health monitor.
struct TodayView: View {
    let askCoach: (String) -> Void

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(AppRefresher.self) private var refresher
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @State private var showingSettings = false
    @State private var showingHRVEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let active = sessions.first(where: \.isActive) {
                        ResumeWorkoutBanner(session: active) { launcher.activeSession = active }
                    }
                    if let error = metrics.errorMessage {
                        HealthAccessCard(message: error)
                    }
                    ScoresCard()
                    StrainGoalCard(sessions: sessions)
                    EnergyCard()
                    HealthMonitor(onEnterHRV: { showingHRVEntry = true })
                    askCoachCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .lockedToScreenWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.butter, Theme.Wash.sky])
            }
            .background(Theme.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { await refresher.refresh() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingHRVEntry) {
                HRVEntrySheet(existing: hrvReadings.first { Calendar.current.isDateInToday($0.date) })
                    .presentationDetents([.medium])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                GlassIconButton(systemName: "person.fill", label: "Settings") {
                    showingSettings = true
                }
                SyncChip(isLoading: metrics.isLoading, lastUpdated: metrics.lastUpdated)
                Spacer()
            }
            Text("Today, \(Date.now.formatted(.dateTime.month(.wide).day()))")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
    }

    private var askCoachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ask your coach", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(LinearGradient(colors: [Theme.sleep, Theme.lifting], startPoint: .leading, endPoint: .trailing))
            ForEach(CoachModel.suggestions.prefix(3), id: \.self) { question in
                Button {
                    askCoach(question)
                } label: {
                    HStack {
                        Text(question)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .padding(12)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .card(tint: Theme.sleep)
    }
}

// MARK: - Header pieces

private struct SyncChip: View {
    let isLoading: Bool
    let lastUpdated: Date?

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView().controlSize(.mini)
                Text("Syncing")
            } else {
                Circle().fill(Theme.recoveryHigh).frame(width: 8, height: 8)
                Text(lastUpdated == nil ? "Not synced" : "Synced")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(lastUpdated == nil && !isLoading ? Theme.secondaryText : Theme.recoveryHigh)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

struct ResumeWorkoutBanner: View {
    let session: WorkoutSession
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemName: "dumbbell.fill", color: Theme.lifting, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.name) in progress")
                        .font(.headline)
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(session.startedAt)).formatted(.time(pattern: .hourMinuteSecond)))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                Chip(text: "Resume", color: Theme.lifting, filled: true)
            }
            .foregroundStyle(Theme.primaryText)
            .card()
        }
        .buttonStyle(.plain)
    }
}

private struct HealthAccessCard: View {
    let message: String
    @Environment(\.healthClient) private var health

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Health", systemImage: "heart.text.square")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text("If you already answered, open the Health app → your profile picture → Apps → WorkoutApp, and tap Turn On All.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Button("Allow access") {
                Task { try? await health?.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
    }
}

// MARK: - Scores

private struct ScoresCard: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let coaching = TrainerSuggestions.coachingLine(metrics: metrics)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                ScoreRing(
                    title: "Strain",
                    value: metrics.strain.map { $0.strain.formatted(.number.precision(.fractionLength(1))) } ?? "--",
                    subtitle: "of 21",
                    progress: (metrics.strain?.strain ?? 0) / 21,
                    colors: Theme.strainColors,
                    size: 100
                )
                .frame(maxWidth: .infinity)
                ScoreRing(
                    title: "Recovery",
                    value: metrics.recovery.map { "\($0.score)" } ?? "--",
                    unit: metrics.recovery == nil ? "" : "%",
                    subtitle: metrics.recovery.map { $0.status.rawValue.capitalized },
                    progress: Double(metrics.recovery?.score ?? 0) / 100,
                    colors: Theme.recoveryColors(for: metrics.recovery?.score),
                    size: 100
                )
                .frame(maxWidth: .infinity)
                ScoreRing(
                    title: "Sleep",
                    value: metrics.sleep.map { "\($0.score)" } ?? "--",
                    unit: metrics.sleep == nil ? "" : "%",
                    subtitle: metrics.sleep.map { Duration.seconds($0.asleep).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
                    progress: Double(metrics.sleep?.score ?? 0) / 100,
                    colors: Theme.sleepColors,
                    size: 100
                )
                .frame(maxWidth: .infinity)
            }
            Divider().overlay(Theme.separator)
            VStack(alignment: .leading, spacing: 6) {
                Label("Coaching", systemImage: "sparkle")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.strain)
                if let highlight = coaching.highlight {
                    let lead = Text(coaching.text).foregroundStyle(Theme.primaryText)
                    let accent = Text(highlight).foregroundStyle(Theme.strain).fontWeight(.semibold)
                    Text("\(lead) \(accent)")
                        .font(.body)
                } else {
                    Text(coaching.text)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .card()
    }
}

// MARK: - Strain goal

private struct StrainGoalCard: View {
    let sessions: [WorkoutSession]

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(WorkoutLauncher.self) private var launcher

    var body: some View {
        let current = metrics.strain?.strain ?? 0
        let target = metrics.targetStrain ?? 10...14
        let status = StrainPlanner().status(current: current, target: target)
        let suggestions = TrainerSuggestions.make(metrics: metrics, settings: settings, sessions: sessions)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CardLabel(text: "Strain goal")
                Spacer()
                switch status {
                case .below(let remaining):
                    Chip(text: "\(remaining.formatted(.number.precision(.fractionLength(1)))) to go")
                case .inRange:
                    Chip(text: "Target reached", color: Theme.recoveryHigh)
                case .above:
                    Chip(text: "Above target", color: Theme.recoveryModerate)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(current.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing))
                Text("/ target \(whole(target.lowerBound))–\(whole(target.upperBound))")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
            }
            StrainGoalBar(current: current, target: target)

            switch status {
            case .below:
                CardLabel(text: "Suggested to close the gap")
                ForEach(suggestions) { suggestion in
                    Button {
                        if suggestion.option.kind == .strength {
                            launcher.openBuilder(focus: suggestion.focus, minutes: suggestion.minutes)
                        }
                    } label: {
                        SuggestionRow(suggestion: suggestion)
                    }
                    .buttonStyle(.plain)
                    .disabled(suggestion.option.kind == .cardio)
                }
                Button {
                    let strength = suggestions.first { $0.option.kind == .strength }
                    launcher.openBuilder(focus: strength?.focus, minutes: strength?.minutes)
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(LinearGradient(colors: [Theme.strainLight, Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing), in: .capsule)
                        .shadow(color: Theme.strain.opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
            case .inRange:
                Text("You've hit today's target. Anything more is optional; recovery work and sleep will pay off tomorrow.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            case .above:
                Text("You're past today's target. Keep the rest of the day easy and get to bed early.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.strain)
    }
}

private struct SuggestionRow: View {
    let suggestion: TrainerSuggestions.Suggestion

    var body: some View {
        let isStrength = suggestion.option.kind == .strength
        HStack(spacing: 12) {
            IconBadge(
                systemName: isStrength ? "dumbbell.fill" : "bicycle",
                color: isStrength ? Theme.lifting : Theme.sleep,
                size: 42
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.option.title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(suggestion.option.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text("+\(suggestion.option.gain.formatted(.number.precision(.fractionLength(1))))")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.strain)
            if isStrength {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .background(Theme.cardRaised, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isStrength ? "Opens the workout builder" : "")
    }
}

// MARK: - Energy and nutrition

private struct EnergyCard: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let food = metrics.nutritionToday
        let energy = metrics.energy
        let eaten = food?.calories ?? 0
        let burn = energy?.projectedTotal
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CardLabel(text: "Energy & nutrition")
                Spacer()
                Text("From Cronometer")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(alignment: .center, spacing: 18) {
                GradientRing(
                    progress: burn.map { eaten / max($0, 1) } ?? 0,
                    colors: Theme.nutritionColors,
                    lineWidth: 13
                ) {
                    VStack(spacing: 0) {
                        Text(eaten.formatted(.number.precision(.fractionLength(0))))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                        Text(burn.map { "of \($0.formatted(.number.precision(.fractionLength(0)))) kcal" } ?? "kcal eaten")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 12) {
                    ProgressRow(label: "Protein", value: food?.proteinGrams ?? 0, goal: metrics.proteinTarget, color: Theme.nutrition)
                    ProgressRow(label: "Carbs", value: food?.carbsGrams ?? 0, color: Theme.strain)
                    ProgressRow(label: "Fat", value: food?.fatGrams ?? 0, color: Theme.sleep)
                }
            }
            if let energy {
                Divider().overlay(Theme.separator)
                HStack {
                    StatView(label: "Burned so far", value: energy.burnedSoFar.formatted(.number.precision(.fractionLength(0))), detail: "kcal")
                    StatView(label: "Projected today", value: energy.projectedTotal.formatted(.number.precision(.fractionLength(0))), detail: "kcal")
                    if let balance = energy.balance, eaten > 0 {
                        StatView(
                            label: balance < 0 ? "Deficit" : "Surplus",
                            value: abs(balance).formatted(.number.precision(.fractionLength(0))),
                            detail: "kcal",
                            color: balance < 0 ? Theme.strain : Theme.lifting
                        )
                    }
                }
                SegmentedBar(segments: [
                    .init(value: energy.restingFullDay, color: Theme.nutrition),
                    .init(value: energy.exercise, color: Theme.lifting),
                    .init(value: energy.everydayMovement, color: Theme.strain),
                    .init(value: energy.digestion, color: Theme.sleep)
                ])
                Text("Resting \(whole(energy.restingFullDay)) · Exercise \(whole(energy.exercise)) · Movement \(whole(energy.everydayMovement)) · Digestion \(whole(energy.digestion)). Estimate from \(energy.bmrMethod), heart rate and steps.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Add your weight in Apple Health (or Settings) to estimate calories burned.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if food == nil || food?.isEmpty == true {
                Text("No food logged today. Log meals in Cronometer with its Apple Health sync turned on.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.nutrition)
    }
}

// MARK: - Health monitor

private struct HealthMonitor: View {
    let onEnterHRV: () -> Void
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals

    var body: some View {
        VStack(spacing: 12) {
            SectionTitle(text: "Health Monitor", trailing: summary.text, trailingColor: summary.color)
            HStack(spacing: 12) {
                rhrTile
                hrvTile
            }
            HStack(spacing: 12) {
                respiratoryTile
                sleepTile
            }
            HStack(spacing: 12) {
                vitalTile("spo2", title: "Blood oxygen", color: Theme.oxygen, light: Theme.oxygenLight)
                vitalTile("hrr", title: "HR recovery", color: Theme.heart, light: Theme.heartLight)
            }
            HStack(spacing: 12) {
                vitalTile("stress", title: "Stress", color: Theme.recoveryModerate, light: Theme.recoveryHighLight)
                vitalTile("steps", title: "Steps", color: Theme.strain, light: Theme.strainLight)
            }
        }
    }

    private func vitalTile(_ id: String, title: String, color: Color, light: Color) -> some View {
        let stat = vitals.stat(id)
        return MonitorTile(
            title: title,
            value: stat?.value,
            unit: stat?.unit ?? "",
            status: stat?.status.map { TileStatus(text: $0, color: VitalTile.color(for: stat?.tone ?? .neutral)) },
            gauge: stat?.gauge,
            color: color,
            lightColor: light
        )
    }

    private var summary: (text: String?, color: Color) {
        guard let recovery = metrics.recovery, recovery.isCalibrated else { return (nil, Theme.secondaryText) }
        let flags = [(recovery.hrvChangePercent ?? 0) < -15, (recovery.restingHeartRateChange ?? 0) > 5].filter { $0 }.count
        return flags == 0 ? ("All normal", Theme.recoveryHigh) : ("\(flags) to watch", Theme.recoveryModerate)
    }

    /// Position of a value within baseline ± 2 SD, as 0...1.
    private func position(_ value: Double?, mean: Double?, sd: Double?) -> Double? {
        guard let value, let mean, let sd, sd > 0 else { return value == nil ? nil : 0.5 }
        return min(1, max(0, (value - (mean - 2 * sd)) / (4 * sd)))
    }

    private var rhrTile: some View {
        let change = metrics.recovery?.restingHeartRateChange
        return MonitorTile(
            title: "Resting HR",
            value: metrics.restingHeartRate.map { "\(whole($0.rounded()))" },
            unit: "bpm",
            status: change.map { delta in
                delta <= 0
                    ? TileStatus(text: "Lower", icon: "arrow.down", color: Theme.recoveryHigh)
                    : TileStatus(text: "Higher", icon: "arrow.up", color: delta > 5 ? Theme.recoveryModerate : Theme.secondaryText)
            },
            gauge: position(metrics.restingHeartRate, mean: metrics.baseline?.meanRHR, sd: metrics.baseline?.sdRHR),
            color: Theme.heart,
            lightColor: Theme.heartLight
        )
    }

    private var hrvTile: some View {
        let change = metrics.recovery?.hrvChangePercent
        let logValue = metrics.hrv.map { log($0) }
        return MonitorTile(
            title: "HRV",
            value: metrics.hrv.map { "\(whole($0.rounded()))" },
            unit: "ms",
            status: change.map { delta in
                delta >= 0
                    ? TileStatus(text: "Higher", icon: "arrow.up", color: Theme.recoveryHigh)
                    : TileStatus(text: "Lower", icon: "arrow.down", color: delta < -15 ? Theme.recoveryModerate : Theme.secondaryText)
            },
            gauge: position(logValue, mean: metrics.baseline?.meanLogHRV, sd: metrics.baseline?.sdLogHRV),
            color: Theme.recoveryHigh,
            lightColor: Theme.recoveryHighLight,
            actionTitle: metrics.hrv == nil ? "Add HRV" : (metrics.hrvIsManual ? "Edit" : nil),
            onAction: onEnterHRV
        )
    }

    private var respiratoryTile: some View {
        let rate = metrics.respiratoryRate
        let normal = rate.map { (12...20).contains($0) } ?? true
        return MonitorTile(
            title: "Respiratory",
            value: rate.map { $0.formatted(.number.precision(.fractionLength(1))) },
            unit: "rpm",
            status: rate.map { _ in
                normal ? TileStatus(text: "Normal", color: Theme.secondaryText) : TileStatus(text: "Check", color: Theme.recoveryModerate)
            },
            gauge: rate.map { min(1, max(0, ($0 - 8) / 16)) },
            color: Theme.oxygen,
            lightColor: Theme.oxygenLight
        )
    }

    private var sleepTile: some View {
        let sleep = metrics.sleep
        return MonitorTile(
            title: "Sleep",
            value: sleep.map { Duration.seconds($0.asleep).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            unit: "",
            status: sleep.map { night in
                night.asleep >= night.need * 0.9
                    ? TileStatus(text: "Normal", color: Theme.secondaryText)
                    : TileStatus(text: "Short", color: Theme.recoveryModerate)
            },
            gauge: sleep.map { min(1, $0.asleep / max($0.need * 1.3, 1)) },
            color: Theme.sleep,
            lightColor: Theme.sleepLight
        )
    }
}

private struct TileStatus {
    var text: String
    var icon: String?
    var color: Color
}

private struct MonitorTile: View {
    let title: String
    let value: String?
    let unit: String
    let status: TileStatus?
    let gauge: Double?
    let color: Color
    var lightColor: Color?
    var actionTitle: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(unit)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(Theme.primaryText)
                } else {
                    Text("No data")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText.opacity(0.7))
                }
                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if let status {
                    HStack(spacing: 3) {
                        if let icon = status.icon {
                            Image(systemName: icon)
                        }
                        Text(status.text)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.12), in: .capsule)
                }
            }
            Spacer(minLength: 0)
            VerticalRangeGauge(value: gauge, color: color, lightColor: lightColor)
                .frame(height: 78)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(RadialGradient(colors: [color.opacity(0.13), color.opacity(0)], center: .bottomTrailing, startRadius: 0, endRadius: 160))
                )
        }
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }
}
