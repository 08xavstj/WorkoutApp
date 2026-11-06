import SwiftUI
import AppCore

/// The movement warm-up at the top of a live session (`WarmUpStore`): first
/// a pre-flight overview of every step with the total minutes, then one
/// step at a time (name, dose, cue, why, Done or a countdown, Back), then
/// one line once it's done. Nothing is shown for a session without one.
///
/// Rep steps never count down: they advance on Done only. The raise is the
/// one timed step; it auto-advances at 0 with a haptic at 5 s and 0, and
/// has "Done early". See `WarmUpRoutine` for the evidence.
struct WarmUpPhaseCard: View {
    let sessionStart: Date
    /// Called after every change, so the Watch gets the new step.
    let onChange: () -> Void

    private var store: WarmUpStore { WarmUpStore.shared }

    var body: some View {
        if let entry = store.entry(for: sessionStart) {
            if entry.isDone {
                WarmUpDoneLine(routine: entry.routine)
            } else if !entry.hasStarted {
                WarmUpOverviewCard(routine: entry.routine, onStart: { change { $0.start(for: sessionStart) } },
                                   onSkip: { change { $0.finish(for: sessionStart) } })
            } else if let step = entry.current {
                WarmUpStepCard(
                    entry: entry,
                    step: step,
                    onDone: { change { $0.advance(for: sessionStart, fromStep: entry.stepIndex) } },
                    onBack: { change { $0.back(for: sessionStart) } },
                    onSkip: { change { $0.finish(for: sessionStart) } }
                )
            }
        }
    }

    private func change(_ action: (WarmUpStore) -> Void) {
        action(store)
        onChange()
    }
}

private struct WarmUpDoneLine: View {
    let routine: WarmUpRoutine.Routine

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.recoveryHigh)
            Text("Warm-up done. Ramp sets next, then your first working set.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Overview

/// Every step with its dose, the total minutes, Start and Skip.
private struct WarmUpOverviewCard: View {
    let routine: WarmUpRoutine.Routine
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Warm-up")
                Spacer()
                Text("\(routine.minutes) min · \(routine.steps.count) steps")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(routine.steps) { step in
                    WarmUpOverviewRow(step: step)
                }
            }
            Text("Then the ramp sets of your first lift, which matter most.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            WarmUpButtonPair(primary: "Start warm-up", primaryIcon: "play.fill", onPrimary: onStart, onSkip: onSkip)
        }
        .card()
    }
}

private struct WarmUpOverviewRow: View {
    let step: WarmUpRoutine.Step

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: step.phase == .raise ? "timer" : "repeat")
                .font(.caption)
                .foregroundStyle(Theme.lifting)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(step.name)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Text(step.dose.text)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One step

private struct WarmUpStepCard: View {
    let entry: WarmUpEntry
    let step: WarmUpRoutine.Step
    let onDone: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    private var stepCount: Int { entry.routine.steps.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            WarmUpProgressDots(count: stepCount, current: entry.stepIndex)
            WarmUpStepTitle(step: step)
            WarmUpStepText(step: step)
            if let seconds = step.dose.seconds {
                WarmUpCountdown(startedAt: entry.stepStartedAt, seconds: seconds, onFinished: onDone)
            }
            controls
        }
        .card()
        .sensoryFeedback(.selection, trigger: entry.stepIndex)
    }

    private var header: some View {
        HStack {
            CardLabel(text: "Warm-up · step \(entry.stepIndex + 1) of \(stepCount)")
            Spacer()
            Text("\(entry.routine.minutes) min")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            WarmUpButtonPair(
                primary: step.isTimed ? "Done early" : "Done",
                primaryIcon: "checkmark",
                onPrimary: onDone,
                onSkip: onSkip
            )
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHint(entry.stepIndex == 0 ? "Back to the warm-up overview" : "Back to the previous step")
        }
    }
}

/// Name and dose ("10 each side", "90 s"), plus an equipment chip if needed.
private struct WarmUpStepTitle: View {
    let step: WarmUpRoutine.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(step.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            HStack(spacing: 8) {
                Text(step.dose.text)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.liftingText)
                if let kind = step.requires, kind != .bodyweight {
                    Chip(text: kind.label, color: Theme.lifting)
                }
                if step.phase == .potentiate {
                    Chip(text: "After ramp sets", color: Theme.strain)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The cue and the why, one line each.
private struct WarmUpStepText: View {
    let step: WarmUpRoutine.Step

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.cue)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Label {
                Text(step.why)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// One dot per step; the current one is filled and wider.
private struct WarmUpProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.lifting : Theme.track)
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// The raise step's countdown: seconds left with a shrinking ring. Haptic at
/// 5 s and at 0; at 0 it advances (once: `fromStep` in the store).
private struct WarmUpCountdown: View {
    let startedAt: Date
    let seconds: Int
    let onFinished: () -> Void

    var body: some View {
        // Same pattern as `RestTimerPill`: one tick a second from the shared clock.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let ends = startedAt.addingTimeInterval(Double(seconds))
            let remaining = max(0, ends.timeIntervalSince(context.date))
            let left = Int(remaining.rounded(.up))
            WarmUpCountdownRing(left: left, fraction: Double(left) / Double(max(1, seconds)))
                .sensoryFeedback(.impact(weight: .medium), trigger: left) { _, value in value == 5 || value == 0 }
                .onChange(of: left == 0, initial: true) { _, finished in
                    if finished { onFinished() }
                }
        }
    }
}

private struct WarmUpCountdownRing: View {
    let left: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Theme.lifting.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.lifting, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
            Text(left == 0 ? "Time" : "Keep moving until the timer ends.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Duration.seconds(left).formatted(.units(allowed: [.minutes, .seconds], width: .wide)) + " left")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A prominent action and "Skip to ramp sets", each at least 44 pt tall
/// (HIG; ux-audit.md 4.8).
private struct WarmUpButtonPair: View {
    let primary: String
    let primaryIcon: String
    let onPrimary: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(spacing: 8) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onPrimary) {
            Label(primary, systemImage: primaryIcon)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.ink)
        Button(action: onSkip) {
            Text("Skip to ramp sets")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Theme.lifting)
        .accessibilityHint("Ends the movement warm-up and goes to the first lift")
    }
}

// MARK: - Builder row

/// The planner's warm-up row: the tier for this focus (a menu changes it for
/// this focus only, saved in `UserSettings.warmUpTierByFocus`), the step
/// names, the total minutes, and the honest footnote: ramp sets have the
/// evidence (Ribeiro 2020, 2021); movement prep is small and mostly
/// feel-based (Behm 2016: +1.3%, no injury data).
struct WarmUpPlanRow: View {
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    /// The plan's focus; nil edits the general setting instead.
    let focus: WorkoutFocus?
    /// The plan's exercises' movement slots, in order (`WarmUpRoutine.slots(of:)`).
    let slots: [MovementSlot]

    private var tier: WarmUpRoutine.Tier { settings.warmUpTier(for: focus) }
    private var routine: WarmUpRoutine.Routine { WarmUpRoutine.make(tier: tier, firstSlots: slots, gym: gym.profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                IconBadge(systemName: "figure.flexibility", color: Theme.lifting, size: 42)
                WarmUpPlanSummary(tier: tier, routine: routine)
                Spacer(minLength: 8)
                tierMenu
            }
            Text("Ramp sets have the best evidence. Movement prep adds a small, mostly feel-based benefit.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var tierMenu: some View {
        Menu {
            Picker("Warm-up", selection: tierBinding) {
                ForEach(WarmUpRoutine.Tier.allCases) { option in
                    Text(option.menuLabel).tag(option)
                }
            }
            if let focus, settings.warmUpTierByFocus[focus.rawValue] != nil {
                Button("Use my general setting") { settings.setWarmUpTier(nil, for: focus) }
            }
        } label: {
            Label("Change", systemImage: "chevron.up.chevron.down")
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .frame(minHeight: 44)
        }
        .tint(Theme.lifting)
        .accessibilityLabel(focus.map { "Change warm-up for \($0.shortTitle) days" } ?? "Change warm-up")
    }

    private var tierBinding: Binding<WarmUpRoutine.Tier> {
        Binding(
            get: { tier },
            set: { newValue in
                if let focus {
                    settings.setWarmUpTier(newValue, for: focus)
                } else {
                    settings.warmUpTier = newValue
                }
            }
        )
    }
}

private struct WarmUpPlanSummary: View {
    let tier: WarmUpRoutine.Tier
    let routine: WarmUpRoutine.Routine

    private var title: String {
        tier.hasSteps ? "Warm-up · \(tier.label) · \(routine.minutes) min" : "Warm-up · \(tier.label)"
    }

    private var detail: String {
        switch tier {
        case .off: "Straight into the first set."
        case .rampOnly: "Ramp sets of the first lift, then your working sets."
        case .short, .full: routine.drillNames.joined(separator: " · ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(3)
        }
    }
}

/// Compatibility for the old builder call site: forwards to `WarmUpPlanRow`
/// with no focus (the general setting). Switch to
/// `WarmUpPlanRow(focus: plan.focus, slots: WarmUpRoutine.slots(of: plan))`.
struct WarmUpToggleRow: View {
    let routine: WarmUpRoutine.Routine

    var body: some View {
        WarmUpPlanRow(focus: nil, slots: routine.slots)
    }
}
