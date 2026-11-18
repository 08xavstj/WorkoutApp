import SwiftUI
import WatchKit

/// The movement warm-up on the Set page, one card per step that doesn't
/// scroll: first the overview (steps, minutes, Start / Skip to lifting), then
/// each step's name and dose with a 60 pt Done. The cue and why sit behind an
/// info button, with Back and Skip. The one timed step counts down with a `Text` timer (kept
/// current in Always On) and moves on by itself, with a tap at 5 s and at 0.
/// The Digital Crown isn't used here: the pages swipe
/// sideways and nothing on the card needs adjusting. The phone owns the
/// steps; taps here go to it as `WatchCommand`s and show at once.
struct WatchWarmUpView: View {
    let session: WatchSession
    let step: WatchWarmUpStep
    var isFront = true

    var body: some View {
        if session.isWarmUpOverview {
            WatchWarmUpOverview(session: session, isFront: isFront)
        } else {
            WatchWarmUpStepCard(session: session, step: step, isFront: isFront)
        }
    }
}

/// How long the warm-up is and how many steps, then Start and Skip.
private struct WatchWarmUpOverview: View {
    @Environment(WatchWorkoutModel.self) private var model
    let session: WatchSession
    let isFront: Bool
    @State private var showingSteps = false

    private var steps: [WatchWarmUpStep] { session.warmUp ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.warmUpMinutes.map { "Warm-up · \($0) min" } ?? "Warm-up")
                .font(.headline)
            Button {
                showingSteps = true
            } label: {
                HStack(spacing: 4) {
                    Text("\(steps.count) steps, first \(steps.first?.name ?? "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                        .foregroundStyle(WatchPalette.lifting)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(steps.count) warm-up steps")
            .accessibilityHint("Lists them")
            Spacer(minLength: 0)
            PrimaryWideButton(title: "Start warm-up", systemImage: "play.fill", tint: WatchPalette.lifting,
                              primaryAction: isFront) {
                model.warmUpNext()
            }
            Button("Skip to lifting") { model.warmUpFinish() }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingSteps) {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.name)
                            .font(.headline)
                        if let dose = step.dose {
                            Text(dose)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// One step: "Warm-up 2 of 6", the name, the dose (or the countdown) and
/// Done. The cue, why, Back and Skip are behind the info button.
private struct WatchWarmUpStepCard: View {
    @Environment(WatchWorkoutModel.self) private var model
    let session: WatchSession
    let step: WatchWarmUpStep
    let isFront: Bool
    @State private var showingCue = false

    private var stepIndex: Int { session.warmUpStepIndex ?? 0 }
    private var stepCount: Int { session.warmUp?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Warm-up \(stepIndex + 1) of \(stepCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    showingCue = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.headline)
                        .foregroundStyle(WatchPalette.lifting)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How to do it")
            }
            Text(step.name)
                .font(.headline)
                .lineLimit(2)
            if let seconds = step.seconds, let ends = session.warmUpStepEndsAt {
                WatchWarmUpCountdown(ends: ends, seconds: seconds) { model.warmUpTimedStepEnded(at: stepIndex) }
            } else if let dose = step.dose {
                Text(dose)
                    .numeral(.secondary)
                    .alwaysOnPrimary(WatchPalette.lifting)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            PrimaryWideButton(title: step.isTimed ? "Done early" : "Done", systemImage: "checkmark",
                              tint: WatchPalette.lifting, primaryAction: isFront) {
                model.warmUpNext()
            }
        }
        // The cue, why, Back and Skip: one tap away, so the card itself never scrolls.
        .sheet(isPresented: $showingCue) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(step.name)
                        .font(.headline)
                    Text(step.cue)
                        .font(.body)
                    if let why = step.why {
                        Text(why)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showingCue = false
                        model.warmUpBack()
                    } label: {
                        Label("Back a step", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button {
                        showingCue = false
                        model.warmUpFinish()
                    } label: {
                        Label("Skip to lifting", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
    }
}

/// Seconds left on the timed step. Tap at 5 s and at 0; at 0 the step ends.
/// The digits are a `Text` timer; the taps come from a task, not the redraw,
/// so they land on time with the wrist down.
private struct WatchWarmUpCountdown: View {
    let ends: Date
    let seconds: Int
    let onEnded: () -> Void

    /// The tap before the end (the existing app's choice).
    private static let warningSeconds = 5.0

    var body: some View {
        Text(timerInterval: min(ends.addingTimeInterval(-Double(seconds)), ends)...ends, countsDown: true)
            .numeral(.primary)
            .alwaysOnPrimary(WatchPalette.lifting)
            .accessibilityLabel("Time left")
            .task(id: ends) {
                let warning = ends.addingTimeInterval(-Self.warningSeconds)
                if warning > .now {
                    try? await Task.sleep(for: .seconds(warning.timeIntervalSinceNow))
                    guard !Task.isCancelled else { return }
                    WKInterfaceDevice.current().play(.notification)
                }
                try? await Task.sleep(for: .seconds(max(0, ends.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                WKInterfaceDevice.current().play(.notification)
                onEnded()
            }
    }
}
