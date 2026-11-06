import SwiftUI
import WatchKit

/// The warm-up on the wrist, one screen per step: first the overview (steps,
/// minutes, Start / Skip to lifting), then each step's name, dose, cue and
/// why. Rep steps advance on tap or a Digital Crown turn; the one timed step
/// counts down and auto-advances, with a tap at 5 s and at 0. Back is a
/// button or a swipe right. The phone owns the steps; taps here go to it as
/// `WatchCommand`s and show at once.
struct WatchWarmUpView: View {
    @Environment(WatchWorkoutModel.self) private var model
    let session: WatchSession
    let step: WatchWarmUpStep

    var body: some View {
        if session.isWarmUpOverview {
            WatchWarmUpOverview(session: session)
        } else {
            WatchWarmUpStepView(session: session, step: step)
        }
    }
}

/// Every step with its dose, then Start and Skip.
private struct WatchWarmUpOverview: View {
    @Environment(WatchWorkoutModel.self) private var model
    let session: WatchSession

    private var steps: [WatchWarmUpStep] { session.warmUp ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.warmUpMinutes.map { "Warm-up · \($0) min" } ?? "Warm-up")
                    .font(.headline)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .firstTextBaseline) {
                        Text(step.name)
                            .font(.caption2)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text(step.dose ?? "")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    model.warmUpNext()
                } label: {
                    Label("Start warm-up", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.lifting)
                Button("Skip to lifting") { model.warmUpFinish() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One step. The Digital Crown forward = Done, back = Back.
private struct WatchWarmUpStepView: View {
    @Environment(WatchWorkoutModel.self) private var model
    let session: WatchSession
    let step: WatchWarmUpStep
    @State private var crown = 0.0

    private var stepIndex: Int { session.warmUpStepIndex ?? 0 }
    private var stepCount: Int { session.warmUp?.count ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Warm-up \(stepIndex + 1) of \(stepCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(step.name)
                    .font(.headline)
                    .lineLimit(2)
                if let dose = step.dose {
                    Text(dose)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.lifting)
                }
                if let seconds = step.seconds, let ends = session.warmUpStepEndsAt {
                    WatchWarmUpCountdown(ends: ends, seconds: seconds) { model.warmUpTimedStepEnded(at: stepIndex) }
                }
                Text(step.cue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                if let why = step.why {
                    Text(why)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                }
                buttons
            }
        }
        .focusable()
        .digitalCrownRotation($crown, from: -1, through: 1, by: 1, sensitivity: .low,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { _, value in
            if value >= 1 {
                model.warmUpNext()
            } else if value <= -1 {
                model.warmUpBack()
            } else {
                return
            }
            crown = 0
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width > 60 { model.warmUpBack() }
            }
        )
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button {
                model.warmUpNext()
            } label: {
                Label(step.isTimed ? "Done early" : "Done", systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.lifting)
            HStack(spacing: 6) {
                Button {
                    model.warmUpBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Skip to lifting") { model.warmUpFinish() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Seconds left on the timed step. Tap at 5 s and at 0; at 0 the step ends.
private struct WatchWarmUpCountdown: View {
    let ends: Date
    let seconds: Int
    let onEnded: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, ends.timeIntervalSince(context.date))
            let left = Int(remaining.rounded(.up))
            VStack(spacing: 4) {
                Text(watchClock(Double(left)))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(WatchTheme.lifting)
                ProgressView(value: min(1, Double(left) / Double(max(1, seconds))))
                    .tint(WatchTheme.lifting)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Time left")
            .onChange(of: left, initial: true) { _, value in
                if value == 5 || value == 0 { WKInterfaceDevice.current().play(.notification) }
                if value == 0 { onEnded() }
            }
        }
    }
}
