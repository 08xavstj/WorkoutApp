import SwiftUI
import WatchKit

/// e.g. "60 kg" / "135 lb".
nonisolated func watchFormat(_ kilograms: Double, unit: String) -> String {
    let value = unit == "lb" ? kilograms * 2.20462 : kilograms
    return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
}

/// A set about to be ticked off: what was planned, and the loads the gym can make.
struct PendingSet: Identifiable, Equatable {
    var exerciseIndex: Int
    var setIndex: Int
    var reps: Int
    var weightKg: Double
    var plannedRPE: Double?
    var isWarmup: Bool
    /// Achievable weights in kg, ascending; never empty.
    var loads: [Double]
    var unit: String

    var id: String { "\(exerciseIndex)-\(setIndex)" }

    init(session: WatchSession, exerciseIndex: Int, setIndex: Int, reps: Int, weightKg: Double) {
        let exercise = session.exercises[exerciseIndex]
        let set = exercise.sets[setIndex]
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.reps = reps
        self.weightKg = weightKg
        plannedRPE = set.rpe
        isWarmup = set.isWarmup
        unit = session.unit
        if let known = exercise.achievableLoadsKg, !known.isEmpty {
            loads = known
        } else {
            // No plate list for this exercise: step by the gym's smallest jump.
            let step = session.step
            let start = max(0, weightKg - 10 * step)
            loads = Array(stride(from: start, through: weightKg + 20 * step, by: step))
        }
    }
}

/// Reps and weight changed on the wrist before the set is ticked.
struct SetEdit: Equatable {
    var reps: Int
    var weightKg: Double
}

/// What you're doing now: the exercise, set x of y, the target, Complete and the rest timer.
struct WatchLiveView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @State private var rating: PendingSet?
    @State private var editing: PendingSet?
    /// Edits made with "Edit" before Complete, by set key.
    @State private var edits: [String: SetEdit] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchElapsedLine()
                WatchVitalsLine()
                if let ends = model.restEndsAt {
                    WatchRestView(endsAt: ends, length: model.restLength)
                }
                content
            }
            .padding(.horizontal, 4)
        }
        .sheet(item: $rating) { set in
            WatchSetEffortSheet(set: set)
        }
        .sheet(item: $editing) { set in
            WatchSetEditSheet(set: set) { edit in edits[set.id] = edit }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session = model.snapshot, let step = session.currentWarmUpStep {
            // The movement warm-up runs before the first set (`WatchWarmUpView`).
            WatchWarmUpView(session: session, step: step)
        } else if let session = model.snapshot, let index = shownIndex(in: session) {
            WatchExerciseBlock(
                session: session,
                index: index,
                edit: edits[key(session, index)],
                onComplete: { complete(session, index) },
                onEdit: { editing = pending(session, index) },
                onNext: { model.selectedExercise = nil }
            )
        } else if model.snapshot == nil {
            Text("Recording")
                .font(.headline)
            Text("No sets to log: your iPhone has no workout running.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("All sets done")
                .font(.headline)
            Text("Finish from the controls page.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func shownIndex(in session: WatchSession) -> Int? {
        let index = model.selectedExercise ?? session.nextExerciseIndex
        guard let index, index < session.exercises.count else { return nil }
        return index
    }

    private func key(_ session: WatchSession, _ index: Int) -> String {
        guard let setIndex = session.exercises[index].sets.firstIndex(where: { !$0.isCompleted }) else { return "" }
        return "\(index)-\(setIndex)"
    }

    private func pending(_ session: WatchSession, _ index: Int) -> PendingSet? {
        guard let setIndex = session.exercises[index].sets.firstIndex(where: { !$0.isCompleted }) else { return nil }
        let set = session.exercises[index].sets[setIndex]
        let edit = edits["\(index)-\(setIndex)"]
        return PendingSet(session: session, exerciseIndex: index, setIndex: setIndex,
                          reps: edit?.reps ?? RepCounter.shared.countedReps(forSet: "\(index)-\(setIndex)") ?? set.reps, weightKg: edit?.weightKg ?? set.weightKg)
    }

    /// Working sets ask how hard it was first; warm-ups are ticked straight away.
    private func complete(_ session: WatchSession, _ index: Int) {
        RepCounter.shared.stop()
        guard let set = pending(session, index) else { return }
        if set.isWarmup {
            model.completeSet(exerciseIndex: set.exerciseIndex, setIndex: set.setIndex, reps: set.reps, weightKg: set.weightKg, rpe: nil)
        } else {
            rating = set
        }
    }
}

struct WatchElapsedLine: View {
    @Environment(WatchWorkoutModel.self) private var model

    var body: some View {
        if let start = model.clockStart {
            TimelineView(.periodic(from: start, by: 1)) { context in
                HStack {
                    Text(watchClock(context.date.timeIntervalSince(start)))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(WatchTheme.strain)
                    Spacer()
                    if model.phase == .paused {
                        Text("Paused")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Rest countdown with +15s and Skip. The haptic at the end comes from the model.
struct WatchRestView: View {
    @Environment(WatchWorkoutModel.self) private var model
    let endsAt: Date
    let length: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            VStack(spacing: 6) {
                HStack {
                    Text("Rest")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text(watchClock(remaining.rounded(.up)))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                ProgressView(value: min(1, remaining / Double(max(1, length))))
                    .tint(WatchTheme.strain)
                HStack {
                    Button("+15s") { model.extendRest(by: 15) }
                    Button("Skip") { model.skipRest() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(8)
            .background(WatchTheme.strain.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct WatchExerciseBlock: View {
    let session: WatchSession
    let index: Int
    let edit: SetEdit?
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onNext: () -> Void

    private var exercise: WatchSession.ExerciseSnapshot { session.exercises[index] }
    private var setIndex: Int? { exercise.sets.firstIndex { !$0.isCompleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            if let setIndex {
                setLines(setIndex)
            } else {
                doneLines
            }
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(exercise.name)
                .font(.headline)
                .lineLimit(2)
            if let label = exercise.supersetLabel {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WatchTheme.lifting.opacity(0.3), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func setLines(_ setIndex: Int) -> some View {
        let set = exercise.sets[setIndex]
        let same = exercise.sets.filter { $0.isWarmup == set.isWarmup }
        let number = exercise.sets[..<setIndex].filter { $0.isWarmup == set.isWarmup }.count + 1
        let reps = edit?.reps ?? set.reps
        let weightKg = edit?.weightKg ?? set.weightKg
        Text("\(set.isWarmup ? "Warm-up" : "Set") \(number) of \(same.count)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        HStack {
            Text(reps > 0 || weightKg > 0 ? "\(reps) × \(watchFormat(weightKg, unit: session.unit))" : "Not set")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Spacer()
            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        if !set.isWarmup {
            WatchSetGhost(set: set, unit: session.unit)
        }
        if exercise.repCounting == true, !set.isWarmup {
            WatchRepCounterView(setKey: "\(index)-\(setIndex)")
        }
        if exercise.supersetLabel?.hasSuffix("1") == true, let partner = session.partnerIndex(of: index) {
            Text("then \(session.exercises[partner].name)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        Button(action: onComplete) {
            Label("Complete", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.recovery)
    }

    @ViewBuilder
    private var doneLines: some View {
        Text("Done")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(WatchTheme.recovery)
        if let next = session.nextExerciseIndex, next != index {
            Button(action: onNext) {
                Label("Next: \(session.exercises[next].name)", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Under the target: the plan's reps and reps in reserve, last session's
/// same set in grey ("ghost"), and the phone's set-by-set change, if any.
private struct WatchSetGhost: View {
    let set: WatchSession.SetSnapshot
    let unit: String

    var body: some View {
        if let target = set.targetLine {
            Text(target)
                .font(.caption2.weight(.semibold))
        }
        if let ghost = set.ghostLine(unit: unit) {
            Text(ghost)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        if let note = set.note {
            Text(note)
                .font(.caption2)
                .foregroundStyle(WatchTheme.lifting)
                .lineLimit(3)
        }
    }
}
