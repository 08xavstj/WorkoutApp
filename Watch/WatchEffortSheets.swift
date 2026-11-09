import SwiftUI
import WatchKit

/// Reps and weight before Complete ("Edit" on the set); seconds only for a hold.
struct WatchSetEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let set: PendingSet
    let onDone: (SetEdit) -> Void
    @State private var reps: Int
    @State private var weightKg: Double

    init(set: PendingSet, onDone: @escaping (SetEdit) -> Void) {
        self.set = set
        self.onDone = onDone
        _reps = State(initialValue: set.reps)
        _weightKg = State(initialValue: set.weightKg)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if set.isHold {
                    // A plank's "reps" are seconds and it has no weight to set.
                    WatchHoldAdjuster(seconds: $reps)
                } else {
                    WatchSetAdjuster(reps: $reps, weightKg: $weightKg, loads: set.loads, unit: set.unit)
                }
                Button("Done") {
                    onDone(SetEdit(reps: reps, weightKg: weightKg))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.lifting)
            }
        }
    }
}

/// A hold's time with −/+ in 5-second steps (an app choice: fine enough for
/// a plank, few taps on the wrist); no weight.
struct WatchHoldAdjuster: View {
    @Binding var seconds: Int

    /// Seconds per tap (app choice).
    private static let step = 5

    var body: some View {
        HStack {
            stepButton("minus", label: "Shorter") { seconds = Self.down(seconds) }
            Text("\(seconds) sec")
                .font(.headline)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            stepButton("plus", label: "Longer") { seconds = Self.up(seconds) }
        }
    }

    /// To the next lower multiple of 5 (32 → 30, 30 → 25), not below 0.
    private static func down(_ value: Int) -> Int {
        max(0, ((value - 1) / step) * step)
    }

    /// To the next higher multiple of 5 (32 → 35, 30 → 35).
    private static func up(_ value: Int) -> Int {
        (max(0, value) / step + 1) * step
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .tint(WatchTheme.lifting)
        .accessibilityLabel(label)
    }
}

/// Reps with −/+, weight with −/+ stepping through the gym's loads; the
/// Digital Crown turns the weight too.
struct WatchSetAdjuster: View {
    @Binding var reps: Int
    @Binding var weightKg: Double
    let loads: [Double]
    let unit: String
    @State private var crown: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                stepButton("minus", label: "Fewer reps") { reps = max(0, reps - 1) }
                Text("\(reps) reps")
                    .font(.headline)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                stepButton("plus", label: "More reps") { reps += 1 }
            }
            HStack {
                stepButton("minus", label: "Lighter") { step(-1) }
                Text(watchFormat(weightKg, unit: unit))
                    .font(.headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                stepButton("plus", label: "Heavier") { step(1) }
            }
            .focusable()
            .digitalCrownRotation($crown, from: 0, through: Double(max(0, loads.count - 1)), by: 1,
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, value in
                let index = Int(value.rounded())
                if loads.indices.contains(index) { weightKg = loads[index] }
            }
            .onAppear { crown = Double(nearestIndex) }
        }
    }

    private var nearestIndex: Int {
        loads.indices.min { abs(loads[$0] - weightKg) < abs(loads[$1] - weightKg) } ?? 0
    }

    private func step(_ direction: Int) {
        let index = nearestIndex + direction
        guard loads.indices.contains(index) else { return }
        weightKg = loads[index]
        crown = Double(index)
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .tint(WatchTheme.lifting)
        .accessibilityLabel(label)
    }
}

/// Reps-left buttons 0, 1, 2 / 3, 4+ (stored as RPE 10 … 6), the plan's
/// number marked "plan". A tap clicks (haptic) and fires `action` with the reps left.
struct WatchRepsLeftGrid: View {
    /// The plan's reps left, 0-4; nil without one.
    let plan: Int?
    let action: (Int) -> Void
    private static let rows: [[Int]] = [[0, 1, 2], [3, 4]]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { left in
                        button(left)
                    }
                }
            }
        }
    }

    private func button(_ left: Int) -> some View {
        let isPlan = left == plan
        let label = left >= 4 ? "4+" : "\(left)"
        return Button {
            WKInterfaceDevice.current().play(.click)
            action(left)
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.headline)
                if isPlan {
                    Text("plan")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            // The plan's number is outlined, not filled: filled reads as already chosen.
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isPlan {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(WatchTheme.lifting, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(left >= 4 ? "4 or more reps left" : (left == 1 ? "1 rep left" : "\(left) reps left"))
        .accessibilityHint(isPlan ? "The plan's target" : "")
    }
}

/// Effort buttons in rows of three (room for the labels on a 41 mm Watch),
/// with a short label under each number. A tap clicks (haptic) and fires `action`.
struct WatchRPEGrid: View {
    let choices: [WatchRPEChoice]
    let selected: Int?
    let action: (Int) -> Void
    private static let perRow = 3

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(stride(from: 0, to: choices.count, by: Self.perRow)), id: \.self) { start in
                HStack(spacing: 4) {
                    ForEach(choices[start..<min(start + Self.perRow, choices.count)]) { choice in
                        WatchRPEButton(choice: choice, isSelected: choice.value == selected) {
                            WKInterfaceDevice.current().play(.click)
                            action(choice.value)
                        }
                    }
                }
            }
        }
    }
}

private struct WatchRPEButton: View {
    let choice: WatchRPEChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(choice.value)")
                    .font(.headline)
                Text(choice.label)
                    .font(.caption2)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? WatchTheme.lifting.opacity(0.55) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Effort \(choice.value), \(choice.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// At Finish: the whole session's effort, 1-10 (`RPEScale.sessionLabel`).
struct WatchSessionEffortSheet: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("How was the whole session?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                WatchRPEGrid(choices: WatchRPEChoice.session, selected: nil) { value in
                    end(value)
                }
                Button("End without rating") { end(nil) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func end(_ rpe: Int?) {
        dismiss()
        Task { await model.finish(sessionRPE: rpe) }
    }
}
