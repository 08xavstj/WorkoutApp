import SwiftUI
import AppCore

/// Home card for sleep debt, shown once there's at least an hour of it.
struct SleepDebtCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @State private var showingSleep = false

    var body: some View {
        if let debt = metrics.sleepDebt, debt.level != .none {
            Button { showingSleep = true } label: {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(systemName: "hourglass", color: Theme.sleep, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Sleep debt")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            Spacer()
                            Text(SleepText.hours(debt.hours))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(debt.level == .high ? Theme.recoveryLowText : Theme.primaryText)
                        }
                        Text(debt.plan ?? "You're close to caught up.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.leading)
                        if let window = metrics.bedtimeWindow {
                            // Tonight's bed-by window (`BedtimeWindow`): the wake time stays put
                            // (Windred et al., Sleep 2024) and the repayment comes from going earlier.
                            Text("In bed by \(window.windowText) tonight")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .card(tint: Theme.sleep)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingSleep) {
                LastNightSleepSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// Last night in detail: time asleep, efficiency, wake-ups, regularity, sleep
/// debt and the stages (marked as estimates).
struct LastNightSleepSheet: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let sleep = metrics.sleep {
                        summary(sleep)
                        stages(sleep)
                    } else {
                        Text("No sleep recorded last night. Wear your watch to bed and it appears here in the morning.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .card()
                    }
                    debtCard
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Last night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func summary(_ sleep: SleepCalculator.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(sleep.score)")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                Text("sleep score")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            row("Asleep", SleepText.hours(sleep.asleep / 3600), detail: "Your need: \(SleepText.hours(sleep.need / 3600))")
            if let bed = sleep.bedtime, let wake = sleep.wakeTime {
                row("Fell asleep – woke", "\(bed.formatted(date: .omitted, time: .shortened)) – \(wake.formatted(date: .omitted, time: .shortened))")
            }
            row("Efficiency", "\(Int((sleep.efficiency * 100).rounded()))%", detail: "Time asleep while in bed. 85% or more is good (National Sleep Foundation).")
            row("Woke up", "\(sleep.interruptions) time\(sleep.interruptions == 1 ? "" : "s")", detail: "Awake 5 minutes or more.")
            if let regularity = metrics.sleepConsistency {
                row("Regularity", "\(regularity) / 100", detail: "Sleep Regularity Index over the last week.")
            }
        }
        .card()
    }

    @ViewBuilder
    private func stages(_ sleep: SleepCalculator.Result) -> some View {
        if sleep.deep + sleep.rem + sleep.core > 0 {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "Sleep stages · estimates", color: Theme.sleep)
                row("Deep", SleepText.hours(sleep.deep / 3600))
                row("REM", SleepText.hours(sleep.rem / 3600))
                row("Core (light)", SleepText.hours(sleep.core / 3600))
                Text("Wrist trackers are good at telling sleep from wake but rough at stages (compared with a sleep lab, Chinoy et al., Sleep 2021), so stages count for only 10% of the sleep score. Watch the trend, not one night.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    @ViewBuilder
    private var debtCard: some View {
        if let debt = metrics.sleepDebt {
            VStack(alignment: .leading, spacing: 8) {
                CardLabel(text: "Sleep debt · 14 nights", color: Theme.sleep)
                Text(debt.level == .none ? "Caught up" : SleepText.hours(debt.hours))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                if let plan = debt.plan {
                    Text(plan)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                }
                Text("Based on a need of \(SleepText.hours(settings.sleepNeedHours)) a night (change it in Settings). Short nights add up and you feel it less than it affects you (Van Dongen et al., Sleep 2003); longer nights pay it back.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                bedByRows
            }
            .card(tint: Theme.sleep)
        }
    }

    /// Tonight's bed-by window and why: need, debt repayment (at most an hour
    /// a night, Kitamura et al., Sci Rep 2016) and your usual wake time, which
    /// stays put because regular timing predicted mortality better than sleep
    /// length (Windred et al., Sleep 2024); extra sleep improved sprint and
    /// reaction times in athletes (Mah et al., Sleep 2011).
    @ViewBuilder
    private var bedByRows: some View {
        if let window = metrics.bedtimeWindow {
            Divider().overlay(Theme.separator)
            Text("Tonight: in bed by \(window.windowText)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(window.reason + ". Earlier to bed, not later up: a regular wake time predicted lower mortality more strongly than sleep length (Windred 2024), and athletes who extended their sleep ran faster and reacted quicker (Mah 2011). Debt is repaid an hour a night at most (Kitamura 2016).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let note = window.regularityNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

enum SleepText {
    /// e.g. "7h 20m"
    static func hours(_ hours: Double) -> String {
        Duration.seconds(max(0, hours) * 3600).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
