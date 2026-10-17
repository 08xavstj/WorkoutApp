import SwiftUI
import SwiftData
import AppCore

/// Home screen: sleep, recovery and strain rings, then a card for each.
struct TodayView: View {
    let askCoach: (String) -> Void

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    rings
                    if let error = metrics.errorMessage {
                        HealthAccessCard(message: error)
                    }
                    StrainCard(result: metrics.strain, target: metrics.targetStrain)
                    RecoveryCard(result: metrics.recovery, hrv: metrics.hrv, restingHeartRate: metrics.restingHeartRate)
                    SleepCard(result: metrics.sleep)
                    NutritionCard(day: metrics.nutritionToday, proteinTarget: metrics.proteinTarget)
                    TodayLiftsCard(sessions: todaysSessions, unit: settings.weightUnit)
                    askCoachCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
            .refreshable { await refresh() }
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
            .onChange(of: sessions.count) {
                Task { await refresh() }
            }
        }
    }

    private var todaysSessions: [WorkoutSession] {
        sessions.filter { Calendar.current.isDateInToday($0.startedAt) && !$0.isActive }
    }

    private var rings: some View {
        HStack(spacing: 12) {
            ScoreRing(
                title: "Sleep",
                valueText: metrics.sleep.map { "\($0.score)%" } ?? "--",
                progress: Double(metrics.sleep?.score ?? 0) / 100,
                color: Theme.sleep
            )
            .frame(maxWidth: .infinity)
            ScoreRing(
                title: "Recovery",
                valueText: metrics.recovery.map { "\($0.score)%" } ?? "--",
                progress: Double(metrics.recovery?.score ?? 0) / 100,
                color: Theme.recoveryColor(for: metrics.recovery?.score),
                size: 120
            )
            .frame(maxWidth: .infinity)
            ScoreRing(
                title: "Strain",
                valueText: metrics.strain.map { $0.strain.formatted(.number.precision(.fractionLength(1))) } ?? "--",
                progress: (metrics.strain?.strain ?? 0) / 21,
                color: Theme.strain
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private var askCoachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ask your coach", systemImage: "sparkles")
                .font(.headline)
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
                    .padding(12)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func refresh() async {
        guard let health else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
        let recent = sessions
            .filter { !$0.isActive && $0.startedAt >= cutoff }
            .map(\.strainSummary)
        await metrics.refresh(health: health, settings: settings, sessions: recent)
    }
}

// MARK: - Cards

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
            Button("Allow access") {
                Task { try? await health?.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
    }
}

private struct StrainCard: View {
    let result: StrainCalculator.Result?
    let target: ClosedRange<Double>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Strain", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.strain)
                Spacer()
                if let target {
                    Text("Target \(Int(target.lowerBound))-\(Int(target.upperBound))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.strain.opacity(0.15), in: .capsule)
                }
            }
            if let result, result.totalLoad > 0 {
                HStack {
                    StatView(label: "Cardio", value: result.cardioLoad.formatted(.number.precision(.fractionLength(0))), detail: "heart-rate load", color: Theme.strain)
                    StatView(label: "Lifting", value: result.liftingLoad.formatted(.number.precision(.fractionLength(0))), detail: "gym load", color: Theme.lifting)
                }
                SegmentedBar(segments: [
                    .init(value: result.cardioLoad, color: Theme.strain),
                    .init(value: result.liftingLoad, color: Theme.lifting)
                ])
                VStack(alignment: .leading, spacing: 6) {
                    Text("Heart-rate zones")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    SegmentedBar(segments: result.zoneMinutes.enumerated().map { index, minutes in
                        SegmentedBar.Segment(value: minutes, color: Theme.zoneColors[index])
                    })
                    HStack {
                        ForEach(0..<5, id: \.self) { index in
                            Text("Z\(index + 1) \(Int(result.zoneMinutes[index].rounded()))m")
                                .font(.caption2)
                                .foregroundStyle(Theme.zoneColors[index])
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                Text("No strain yet today. Wear your Apple Watch or log a gym session.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }
}

private struct RecoveryCard: View {
    let result: RecoveryCalculator.Result?
    let hrv: Double?
    let restingHeartRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Recovery", systemImage: "bolt.heart.fill")
                .font(.headline)
                .foregroundStyle(Theme.recoveryColor(for: result?.score))
            HStack {
                StatView(
                    label: "HRV",
                    value: hrv.map { "\(Int($0.rounded())) ms" } ?? "--",
                    detail: result?.hrvChangePercent.map { change in
                        "\(change >= 0 ? "+" : "")\(Int(change.rounded()))% vs normal"
                    }
                )
                StatView(
                    label: "Resting HR",
                    value: restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--",
                    detail: result?.restingHeartRateChange.map { change in
                        "\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) vs normal"
                    }
                )
            }
            if let result, !result.isCalibrated {
                Text("Building your baseline. Recovery gets more accurate after a few nights of wearing your watch to bed.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else if result == nil {
                Text("Wear your Apple Watch to sleep to see recovery.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }
}

private struct SleepCard: View {
    let result: SleepCalculator.Result?

    private func hours(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sleep", systemImage: "moon.zzz.fill")
                .font(.headline)
                .foregroundStyle(Theme.sleep)
            if let result {
                HStack {
                    StatView(label: "Asleep", value: hours(result.asleep), detail: "need \(hours(result.need))")
                    StatView(label: "Efficiency", value: result.efficiency.formatted(.percent.precision(.fractionLength(0))), detail: "\(result.interruptions) interruptions")
                }
                SegmentedBar(segments: [
                    .init(value: result.deep, color: Theme.sleep),
                    .init(value: result.rem, color: Theme.sleep.opacity(0.7)),
                    .init(value: result.core, color: Theme.sleep.opacity(0.4)),
                    .init(value: result.awake, color: Theme.recoveryModerate.opacity(0.8))
                ])
                HStack(spacing: 12) {
                    legend("Deep", result.deep, Theme.sleep)
                    legend("REM", result.rem, Theme.sleep.opacity(0.7))
                    legend("Core", result.core, Theme.sleep.opacity(0.4))
                    legend("Awake", result.awake, Theme.recoveryModerate)
                }
            } else {
                Text("No sleep recorded last night.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private func legend(_ name: String, _ value: TimeInterval, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption2).foregroundStyle(Theme.secondaryText)
            Text(hours(value)).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NutritionCard: View {
    let day: NutritionDay?
    let proteinTarget: Double?

    private func grams(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) g" } ?? "--"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Nutrition", systemImage: "fork.knife")
                .font(.headline)
                .foregroundStyle(Theme.recoveryHigh)
            if let day, !day.isEmpty {
                HStack {
                    StatView(label: "Calories", value: day.calories.map { "\(Int($0.rounded()))" } ?? "--", detail: "kcal")
                    StatView(
                        label: "Protein",
                        value: grams(day.proteinGrams),
                        detail: proteinTarget.map { "target \(Int($0)) g" },
                        color: Theme.recoveryHigh
                    )
                }
                if let proteinTarget, let protein = day.proteinGrams {
                    ProgressView(value: min(protein, proteinTarget), total: proteinTarget)
                        .tint(Theme.recoveryHigh)
                        .accessibilityLabel("Protein toward target")
                }
                HStack {
                    StatView(label: "Carbs", value: grams(day.carbsGrams))
                    StatView(label: "Fat", value: grams(day.fatGrams))
                    StatView(label: "Fiber", value: grams(day.fiberGrams))
                }
            } else {
                Text("No food logged today. Log meals in Cronometer and turn on its Apple Health sync to see them here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }
}

private struct TodayLiftsCard: View {
    let sessions: [WorkoutSession]
    let unit: WeightUnit

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Today's training", systemImage: "dumbbell.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.lifting)
                ForEach(sessions) { session in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(session.name).font(.subheadline.weight(.semibold))
                            Text("\(session.workingSets.count) sets · \(unit.format(session.totalVolumeKg)) \(unit.rawValue)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text(Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }
            }
            .card()
        }
    }
}
