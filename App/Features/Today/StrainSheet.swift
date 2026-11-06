import SwiftUI
import AppCore

/// Today's range in detail, opened from the Strain ring: today's strain
/// against its range, where the range comes from, the breathing offer and
/// the sessions that fit. It was a card on Home, which showed strain twice
/// next to the ring (docs/research/ux-audit.md 4.3, H2, H3).
///
/// `start` opens the workout builder. The sheet passes the request up and
/// closes first, because the builder is a sheet too and only one sheet shows
/// at a time (HIG Sheets; ux-audit.md P5).
struct StrainSheet: View {
    let sessions: [WorkoutSession]
    let start: (WorkoutFocus?, Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                StrainGoalCard(sessions: sessions, start: start)
                    .padding()
                    .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Today's range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Today's range

/// Today's strain against the planned range, shown as information rather
/// than a target to chase. "x% to go" and "close the gap" are controlling,
/// outcome-framed feedback that lowers autonomous motivation (Ntoumanis et
/// al. 2021; Swann et al. 2021; docs/research/behaviour-change.md §5), and
/// HRV-guided training supports "train as planned / go easy", not a daily
/// load quota.
private struct StrainGoalCard: View {
    let sessions: [WorkoutSession]
    let start: (WorkoutFocus?, Int?) -> Void

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings

    var body: some View {
        if let target = metrics.targetStrain {
            content(target: target)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "Today's range")
                Text(metrics.restMode
                     ? "Rest mode is on: no strain range until you feel better. Turn it off from the rest mode card on Today, or in Settings."
                     : "No range yet. Wear your watch to sleep so the app can set today's strain range from your recovery.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    private func content(target: ClosedRange<Double>) -> some View {
        let current = metrics.strain?.strain ?? 0
        let status = StrainPlanner().status(current: current, target: target)
        let suggestions = TrainerSuggestions.make(metrics: metrics, settings: settings, sessions: sessions)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                CardLabel(text: "Today's range")
                Spacer()
                StrainStatusChip(status: status)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(strainText(current))
                    .heroNumberFont()
                    .foregroundStyle(LinearGradient(colors: [Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing))
                Text("today · range \(strainRangeText(target))")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            StrainGoalBar(current: current, target: target)
            Text(rangeNote(target: target))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            // No study sets a daily strain range (`StrainCalculator.targetStrain`).
            Text("The range is an app estimate from your own training days, not a published target.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let note = movementNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BreathingOfferRow() // easy days and stressful evenings (BreathingView.swift; Laborde 2022)
            StrainStatusAdvice(
                status: status,
                suggestions: suggestions,
                trainedToday: !metrics.activities.isEmpty,
                easyDay: metrics.trainEasyToday,
                start: start
            )
        }
        .card()
    }

    /// Shown when Apple Watch exercise minutes filled gaps in heart rate
    /// (`StrainCalculator.movementReserveFraction`).
    private var movementNote: String? {
        let minutes = whole(metrics.strain?.movementMinutes ?? 0)
        guard minutes > 0 else { return nil }
        return "Includes \(minutes) exercise \(minutes == 1 ? "minute" : "minutes") from your Apple Watch that heart rate missed, counted as moderate effort."
    }

    /// Where today's range comes from, in one line.
    private func rangeNote(target: ClosedRange<Double>) -> String {
        // With a weekly plan, the plan says what kind of day it is (`TrainingDayPlanner`).
        if let guidance = metrics.dayGuidance, guidance.kind != .training {
            return guidance.reason
        }
        if metrics.trainEasyToday {
            return "Easy day: your 7-day HRV is below your normal range, so anything in \(strainRangeText(target)) is fine."
        }
        return metrics.usualTrainingStrain.map { "Based on your usual training days (\(whole($0))%)." }
            ?? "Adapts to you after 6 training days."
    }
}

/// "In range" / "Below range" / "Above range" (ux-audit.md 4.7).
private struct StrainStatusChip: View {
    let status: StrainPlanner.Status

    var body: some View {
        switch status {
        case .below:
            Chip(text: "Below range", color: Theme.secondaryText)
        case .inRange:
            Chip(text: "In range", color: Theme.recoveryHigh)
        case .above:
            Chip(text: "Above range", color: Theme.recoveryModerate)
        }
    }
}

/// What the status means for the rest of the day.
private struct StrainStatusAdvice: View {
    let status: StrainPlanner.Status
    let suggestions: [TrainerSuggestions.Suggestion]
    let trainedToday: Bool
    let easyDay: Bool
    let start: (WorkoutFocus?, Int?) -> Void

    var body: some View {
        switch status {
        case .below:
            StrainOptions(suggestions: suggestions, trainedToday: trainedToday, easyDay: easyDay, start: start)
        case .inRange:
            Text("You're in today's range. Anything more is optional; recovery work and sleep do the rest.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        case .above:
            Text("You're above today's range. The rest of the day suits going easy, and an early night helps you recover for tomorrow.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Sessions that fit today's range, offered as options to take or leave,
/// never as what's needed to reach a number (autonomy support: Teixeira et
/// al. 2020, cited from memory in docs/research/behaviour-change.md).
private struct StrainOptions: View {
    let suggestions: [TrainerSuggestions.Suggestion]
    let trainedToday: Bool
    let easyDay: Bool
    let start: (WorkoutFocus?, Int?) -> Void

    var body: some View {
        Text(intro)
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(suggestions) { suggestion in
            if suggestion.option.kind == .strength {
                Button {
                    start(suggestion.focus, suggestion.minutes)
                } label: {
                    SuggestionRow(suggestion: suggestion)
                }
                .buttonStyle(.plain)
            } else {
                // Cardio is done on the watch, so this row is information only.
                SuggestionRow(suggestion: suggestion)
            }
        }
        Button {
            let strength = suggestions.first { $0.option.kind == .strength }
            start(strength?.focus, strength?.minutes)
        } label: {
            Label("Start workout", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing), in: .capsule)
                .shadow(color: Theme.strain.opacity(0.35), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the workout builder")
    }

    private var intro: String {
        if trainedToday {
            return "You've trained today, so anything more is optional. If a second session is part of your plan, these fit:"
        }
        if easyDay {
            return "If you want to move today, these fit an easy day:"
        }
        return "If you want to train today, these fit:"
    }
}

/// One session that fits today's range, with its expected strain.
private struct SuggestionRow: View {
    let suggestion: TrainerSuggestions.Suggestion

    var body: some View {
        let isStrength = suggestion.option.kind == .strength
        HStack(spacing: 12) {
            IconBadge(
                systemName: isStrength ? "dumbbell.fill" : "bicycle",
                color: isStrength ? Theme.lifting : Theme.strain,
                size: 42
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(isStrength ? suggestion.option.title : "Easy ride (you can still talk)")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(isStrength ? suggestion.option.detail : "\(suggestion.minutes) min · track it on your watch")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text("+\(strainText(suggestion.option.gain))")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.strainTextColor)
            if isStrength {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .background(Theme.cardRaised, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isStrength ? "Opens the workout builder" : "")
    }
}
