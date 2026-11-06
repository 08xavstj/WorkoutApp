import SwiftUI
import WatchKit
#if canImport(AppCore)
import AppCore
#endif

/// The experimental rep counter under a squat or deadlift set: the count
/// (after 3 reps; it only pre-fills the reps field, which stays editable), a
/// dot per rep shaded by bar speed, and one tap with "Slowing" once the bar has
/// slowed about 20 % (Hickmott 2022, see `RepDetection`). Shown only when the
/// phone says the setting is on and the exercise is a barbell squat or
/// deadlift. Counting starts only when you tap "Start set" under the bar (so
/// walking out and unracking aren't counted, app choice) and runs only while
/// the set is in progress: not during rest or a pause.
struct WatchRepCounterView: View {
    @Environment(WatchWorkoutModel.self) private var model
    /// `WatchSession.setKey` of the set being done.
    let setKey: String
    /// The set "Start set" was tapped for, and how many taps (a tap after the
    /// counter stopped on its own starts it again).
    @State private var startedKey: String?
    @State private var starts = 0

    private var counter: RepCounter { RepCounter.shared }

    private nonisolated struct RunKey: Hashable {
        var setKey: String
        var active: Bool
        var starts: Int
    }

    private var canRun: Bool { model.restEndsAt == nil && model.phase == .running }

    private var runKey: RunKey {
        RunKey(setKey: setKey, active: canRun && startedKey == setKey, starts: starts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WatchRepCountLine(count: shownCount, isRunning: isRunningHere, isAvailable: counter.isAvailable)
            if counter.isAvailable, canRun, !isRunningHere {
                Button {
                    startedKey = setKey
                    starts += 1
                } label: {
                    Label("Start set", systemImage: "play.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(WatchTheme.lifting)
                .accessibilityHint("Starts the experimental rep counter")
            }
            if shownCount != nil {
                WatchRepDots(speeds: speeds, losses: losses)
            }
            if isSlowingHere {
                WatchSlowingNote()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(WatchTheme.lifting.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .task(id: runKey) {
            await run(runKey)
        }
    }

    private var isThisSet: Bool { counter.setKey == setKey }
    private var shownCount: Int? { counter.countedReps(forSet: setKey) }
    private var isRunningHere: Bool { isThisSet && counter.isRunning }
    private var isSlowingHere: Bool { isThisSet && counter.hasSignalledSlowing }
    private var speeds: [Double] { isThisSet ? counter.analysis.relativeSpeeds : [] }
    private var losses: [Double] { isThisSet ? counter.analysis.losses : [] }

    /// Counts once started while the set is in progress; stops when it isn't,
    /// or when the view goes away (the task is cancelled).
    private func run(_ key: RunKey) async {
        guard key.active else {
            counter.stop()
            return
        }
        let token = counter.start(setKey: key.setKey)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
        }
        // Only this run: a newer one may already have started for the next set.
        counter.stop(run: token)
    }
}

private struct WatchRepCountLine: View {
    let count: Int?
    let isRunning: Bool
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.footnote)
                .foregroundStyle(WatchTheme.lifting)
            Text(title)
                .font(.headline)
                .monospacedDigit()
            Text("Beta")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var title: String {
        if let count { return count == 1 ? "1 rep" : "\(count) reps" }
        return isAvailable ? "Reps" : "No motion data"
    }

    private var status: String {
        guard isAvailable else { return "" }
        if isRunning { return count == nil ? "Counts from rep 3" : "Counting" }
        return count == nil ? "" : "Edit if wrong"
    }
}

/// One dot per rep: full colour at the set's best speed, fading as the bar
/// slows, orange once a rep is past the "slowing" loss.
private struct WatchRepDots: View {
    let speeds: [Double]
    let losses: [Double]

    /// Room for this many on the smallest Watch; older reps scroll off.
    private static let maximumDots = 12

    private struct Dot: Identifiable {
        var id: Int
        var speed: Double
        var loss: Double
    }

    private var shown: [Dot] {
        let all = speeds.indices.map { index in
            Dot(id: index, speed: speeds[index], loss: index < losses.count ? losses[index] : 0)
        }
        return Array(all.suffix(Self.maximumDots))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(shown) { dot in
                Circle()
                    .fill(color(loss: dot.loss).opacity(0.35 + 0.65 * min(1, max(0, dot.speed))))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(loss: Double) -> Color {
        loss >= RepDetection.slowingLoss ? WatchTheme.strain : WatchTheme.recovery
    }
}

/// The "slowing" hint: a cross-check for how hard it feels, not a verdict.
private struct WatchSlowingNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Slowing: about 1–2 reps left", systemImage: "arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchTheme.strain)
            Text("Bar speed dropped about 20%. Check it against how the set feels.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
