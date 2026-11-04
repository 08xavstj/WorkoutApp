import SwiftUI
import AppCore

// The Home sleep-debt card was removed in the redesign (docs/research/ux-audit.md
// 4.3, H4: sleep showed three times on Home). Sleep debt, the bed-by window,
// regularity and the weekend shift now live in `LastNightSleepSheet` below,
// opened from the Sleep ring on Today; tonight's bed-by window is also an
// Up next row (`UpNextCard`).

/// The weekday/weekend sleep-midpoint shift from the last two weeks of nights
/// (`SleepRegularity.midpointShift`; Phillips et al., Sci Rep 2017).
enum SleepMidpointShift {
    static func current(_ nights: [SleepNight]) -> SleepRegularity.MidpointShift? {
        let recent = nights.suffix(14).map { SleepConsistency.Night(bedtime: $0.bedtime, wake: $0.wake) }
        return SleepRegularity.midpointShift(nights: recent)
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
                // UK Biobank median about 81; the benefit sat in the top quintiles, ~85+ (Windred 2024).
                row("Regularity", "\(regularity) / 100", detail: "Sleep Regularity Index over the last week. " + SleepRegularity.indexNote(regularity))
            }
            if let shift = SleepMidpointShift.current(metrics.sleepNights) {
                // Social jet lag: weekday vs weekend sleep midpoint, 1-hour target (Phillips 2017).
                row("Weekend shift", shift.text, detail: shift.note + " Target: within about 1 hour (\(shift.weekdayNights) weekday and \(shift.weekendNights) weekend nights).")
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
