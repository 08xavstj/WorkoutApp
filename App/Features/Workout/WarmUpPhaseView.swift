import SwiftUI
import AppCore

/// The movement warm-up at the top of a live session (`WarmUpStore`): the
/// current movement with its countdown, what's next, Next / Skip and "Done,
/// start lifting". Collapses to one line once it's done. Nothing is shown
/// for a session without one.
struct WarmUpPhaseCard: View {
    let sessionStart: Date
    /// Called after every step change, so the Watch gets the new step.
    let onChange: () -> Void

    private var store: WarmUpStore { WarmUpStore.shared }

    var body: some View {
        if let entry = store.entry(for: sessionStart) {
            if entry.isDone {
                WarmUpDoneLine(routine: entry.routine)
            } else if let movement = entry.current {
                WarmUpStepCard(
                    entry: entry,
                    movement: movement,
                    onNext: { advance() },
                    onSkip: { finish() },
                    onDone: { finish() }
                )
            }
        }
    }

    private func advance() {
        store.advance(for: sessionStart)
        onChange()
    }

    private func finish() {
        store.finish(for: sessionStart)
        onChange()
    }
}

private struct WarmUpDoneLine: View {
    let routine: WarmUpRoutine.Routine

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.recoveryHigh)
            Text("\(routine.title) done")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WarmUpStepCard: View {
    let entry: WarmUpEntry
    let movement: WarmUpRoutine.Movement
    let onNext: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    private var stepNumber: Int { entry.stepIndex + 1 }
    private var stepCount: Int { entry.routine.movements.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            // Same pattern as `RestTimerPill`: one tick a second from the shared clock.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let ends = entry.stepStartedAt.addingTimeInterval(Double(movement.seconds))
                let remaining = max(0, ends.timeIntervalSince(context.date))
                WarmUpCountdown(movement: movement, remaining: remaining)
                    .onChange(of: remaining == 0) { _, finished in
                        if finished { onNext() }
                    }
                    .sensoryFeedback(.selection, trigger: entry.stepIndex)
            }
            Text(movement.cue)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            upcomingLine
            buttons
        }
        .card()
    }

    private var header: some View {
        HStack {
            CardLabel(text: "Warm-up · step \(stepNumber) of \(stepCount)")
            Spacer()
            Text("\(entry.routine.minutes) min")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var upcomingLine: some View {
        let next = entry.upcoming.prefix(2).map(\.name)
        if !next.isEmpty {
            Text("Next: \(next.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
        }
    }

    /// Next, Skip and Done, each at least 44 pt tall (HIG; ux-audit.md 4.8).
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttonSet }
            VStack(spacing: 8) { buttonSet }
        }
    }

    @ViewBuilder
    private var buttonSet: some View {
        Button(action: onNext) {
            Label("Next", systemImage: "forward.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Theme.lifting)
        .accessibilityHint("Skips to the next movement")
        Button(action: onDone) {
            Text("Done, start lifting")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.ink)
        Button("Skip", action: onSkip)
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityLabel("Skip warm-up")
    }
}

/// Movement name, rep hint and the seconds left with a shrinking ring.
private struct WarmUpCountdown: View {
    let movement: WarmUpRoutine.Movement
    let remaining: TimeInterval

    private var fraction: Double {
        movement.seconds > 0 ? remaining / Double(movement.seconds) : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Theme.lifting.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.lifting, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(movement.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                if let reps = movement.reps {
                    Text(reps)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Duration.seconds(remaining.rounded(.up)).formatted(.units(allowed: [.minutes, .seconds], width: .wide)) + " left")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The builder's toggle: a movement warm-up before the first lift, on by
/// default. The footnote is the honest version of the evidence: dynamic
/// warm-ups help performance a little (Fradkin 2010; Behm 2016), injury
/// evidence is weak (Lauersen 2014), and long static holds cut strength
/// (Simic 2013; Kay & Blazevich 2012). See `WarmUpRoutine`.
struct WarmUpToggleRow: View {
    @AppStorage("warmUpBeforeWorkout") private var warmUpBeforeWorkout = true
    /// The routine the plan would get, for the title.
    let routine: WarmUpRoutine.Routine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $warmUpBeforeWorkout) {
                HStack(spacing: 12) {
                    IconBadge(systemName: "figure.flexibility", color: Theme.lifting, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.title)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(movementNames)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
            .tint(Theme.lifting)
            Text("Dynamic warm-ups improve lifting performance a little and may cut injury risk; long static stretches before lifting reduce strength, so these are movement-based.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var movementNames: String {
        routine.movements.dropFirst().prefix(4).map(\.name).joined(separator: " · ")
    }
}
