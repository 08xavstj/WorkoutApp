import SwiftUI
import WatchKit
#if canImport(AppCore)
import AppCore
#endif

/// The experimental rep counter, inline on the Set page's reps line: a small
/// "Count" glyph button (44 pt hit area) starts it under the bar (so walking
/// out and unracking aren't counted, app choice). While it counts, the reps
/// value fills in live (it only pre-fills the reps, which stay editable with
/// the crown), dots under it show bar speed, and "Slowing" appears once the
/// bar has slowed about 20 % (Hickmott 2022, see `RepDetection`), with one
/// tap. Shown only when the phone says the setting is on and the exercise is
/// a barbell squat or deadlift; runs only while the set is in progress (no
/// rest, not paused).
struct RepCountControl: View {
    @Environment(WatchWorkoutModel.self) private var model
    /// `WatchSession.setKey` of the set being done.
    let setKey: String
    /// The set "Count" was tapped for, and how many taps (a tap after the
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

    private var isRunningHere: Bool { counter.setKey == setKey && counter.isRunning }

    var body: some View {
        Button {
            if isRunningHere {
                counter.stop()
                startedKey = nil
            } else {
                model.clearRepsEdit(setKey)
                startedKey = setKey
                starts += 1
            }
        } label: {
            Image(systemName: isRunningHere ? "stop.fill" : "waveform.path")
                .font(.footnote.weight(.bold))
                .foregroundStyle(isRunningHere ? WatchPalette.onTint : WatchPalette.lifting)
                .frame(width: 30, height: 30)
                .background(isRunningHere ? WatchPalette.lifting : WatchPalette.lifting.opacity(0.18), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!counter.isAvailable || !canRun)
        .opacity(counter.isAvailable ? 1 : 0.4)
        .accessibilityLabel(isRunningHere ? "Stop counting reps" : "Count reps")
        .accessibilityHint("Experimental rep counter for squats and deadlifts")
        .task(id: runKey) {
            await run(runKey)
        }
    }

    /// Counts once started while the set is in progress; stops when it isn't,
    /// or when the view goes away (the task is cancelled).
    private func run(_ key: RunKey) async {
        guard key.active else {
            if counter.setKey == key.setKey { counter.stop() }
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

/// Under the reps while counting: a dot per rep shaded by bar speed, and
/// "Slowing" once the bar has slowed (a cross-check for how hard it feels,
/// not a verdict).
struct RepCountDetail: View {
    let setKey: String

    private var counter: RepCounter { RepCounter.shared }
    private var isThisSet: Bool { counter.setKey == setKey }

    var body: some View {
        HStack(spacing: 6) {
            if isThisSet, counter.isRunning, counter.countedReps(forSet: setKey) == nil {
                Text("Counts from rep 3")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            WatchRepDots(speeds: isThisSet ? counter.analysis.relativeSpeeds : [],
                         losses: isThisSet ? counter.analysis.losses : [])
            if isThisSet, counter.hasSignalledSlowing {
                Text("Slowing")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchPalette.strain)
                    .accessibilityLabel("Slowing: about 1 to 2 reps left")
            }
        }
        .lineLimit(1)
    }

    /// True while there's something to show for this set.
    static func isActive(for setKey: String) -> Bool {
        let counter = RepCounter.shared
        return counter.setKey == setKey && (counter.isRunning || counter.count != nil)
    }
}

/// One dot per rep: full colour at the set's best speed, fading as the bar
/// slows, orange once a rep is past the "slowing" loss.
private struct WatchRepDots: View {
    let speeds: [Double]
    let losses: [Double]

    /// Room for this many on the smallest Watch; older reps scroll off.
    private static let maximumDots = 10

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
        loss >= RepDetection.slowingLoss ? WatchPalette.strain : WatchPalette.recovery
    }
}
