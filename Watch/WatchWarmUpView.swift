import SwiftUI

/// The current warm-up movement on the wrist: name, rep hint, the countdown
/// the phone runs, the cue, then Next and Start lifting. The phone owns the
/// steps; taps here go to it as `WatchCommand`s and show at once.
struct WatchWarmUpView: View {
    @Environment(WatchWorkoutModel.self) private var model
    let session: WatchSession
    let step: WatchWarmUpStep

    private var stepNumber: Int { (session.warmUpStepIndex ?? 0) + 1 }
    private var stepCount: Int { session.warmUp?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warm-up \(stepNumber) of \(stepCount)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(step.name)
                .font(.headline)
                .lineLimit(2)
            if let reps = step.reps {
                Text(reps)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            countdown
            Text(step.cue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button {
                model.warmUpNext()
            } label: {
                Label(stepNumber < stepCount ? "Next" : "Done", systemImage: "forward.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.lifting)
            Button("Start lifting") { model.warmUpFinish() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if let ends = session.warmUpStepEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, ends.timeIntervalSince(context.date))
                VStack(spacing: 4) {
                    Text(watchClock(remaining.rounded(.up)))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.lifting)
                    ProgressView(value: min(1, remaining / Double(max(1, step.seconds))))
                        .tint(WatchTheme.lifting)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Time left")
            }
        }
    }
}
