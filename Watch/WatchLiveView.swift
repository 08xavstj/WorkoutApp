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
    /// Stable ids (`ExerciseSnapshot.id`, `SetSnapshot.order`) for the phone.
    var exerciseID: Int
    var setOrder: Int?
    /// The exercise's id that survives a reorder on the phone (`ExerciseSnapshot.key`).
    var exerciseKey: String?
    var reps: Int
    var weightKg: Double
    /// The reps and weight the snapshot had: what was changed on the wrist is
    /// told apart from what wasn't (`WatchCommand.completeSet`).
    var baseReps: Int
    var baseWeightKg: Double
    /// Effort to pre-select: 10 minus the target reps in reserve, else the planned RPE.
    var suggestedRPE: Int?
    var isWarmup: Bool
    /// A plank or side plank: `reps` are seconds and the weight isn't edited.
    var isHold: Bool
    /// Achievable weights in kg, ascending; never empty.
    var loads: [Double]
    var unit: String
    let id: String

    init(session: WatchSession, exerciseIndex: Int, setIndex: Int, reps: Int, weightKg: Double) {
        let exercise = session.exercises[exerciseIndex]
        let set = exercise.sets[setIndex]
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        exerciseID = exercise.id
        setOrder = set.order
        exerciseKey = exercise.key
        id = session.setKey(exercise: exerciseIndex, set: setIndex)
        self.reps = reps
        self.weightKg = weightKg
        baseReps = set.reps
        baseWeightKg = set.weightKg
        suggestedRPE = set.suggestedRPE
        isWarmup = set.isWarmup
        isHold = exercise.isHold == true
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
    @State private var editing: PendingSet?
    /// Edits made with "Edit" before Complete, by set key.
    @State private var edits: [String: SetEdit] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchElapsedLine()
                WatchVitalsLine()
                if let note = model.recordNote {
                    WatchRecordBanner(note: note) { model.dismissRecords() }
                }
                if let ends = model.restEndsAt {
                    WatchRestView(endsAt: ends, length: model.restLength)
                }
                // Asked after the tick, so the rest is already running; skip any time.
                if let pending = model.pendingRating {
                    WatchRatingPrompt(set: pending)
                }
                content
            }
            .padding(.horizontal, 4)
        }
        // Complete stays on screen on the smallest Watch, without scrolling.
        .safeAreaInset(edge: .bottom, spacing: 4) {
            if let target = completable {
                WatchCompleteButton { complete(target.session, target.index) }
            }
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

    /// The session and exercise whose open set Complete ticks (not during the warm-up).
    private var completable: (session: WatchSession, index: Int)? {
        guard let session = model.snapshot, session.currentWarmUpStep == nil,
              let index = shownIndex(in: session),
              session.exercises[index].sets.contains(where: { !$0.isCompleted }) else { return nil }
        return (session, index)
    }

    private func key(_ session: WatchSession, _ index: Int) -> String {
        guard let setIndex = session.exercises[index].sets.firstIndex(where: { !$0.isCompleted }) else { return "" }
        return session.setKey(exercise: index, set: setIndex)
    }

    private func pending(_ session: WatchSession, _ index: Int) -> PendingSet? {
        guard let setIndex = session.exercises[index].sets.firstIndex(where: { !$0.isCompleted }) else { return nil }
        let set = session.exercises[index].sets[setIndex]
        let key = session.setKey(exercise: index, set: setIndex)
        let edit = edits[key]
        // A hold's "reps" are seconds: never take them from the rep counter.
        let counted = session.exercises[index].isHold == true ? nil : RepCounter.shared.countedReps(forSet: key)
        return PendingSet(session: session, exerciseIndex: index, setIndex: setIndex,
                          reps: edit?.reps ?? counted ?? set.reps, weightKg: edit?.weightKg ?? set.weightKg)
    }

    /// Ticks the set at once, so the rest starts on Complete; a working set
    /// then asks "Reps left?" above the rest bar (`WatchRatingPrompt`), which
    /// can be skipped. Warm-ups, holds, drop stages and mini-sets aren't asked.
    private func complete(_ session: WatchSession, _ index: Int) {
        RepCounter.shared.stop()
        guard let set = pending(session, index) else { return }
        model.completeSet(set, reps: set.reps, weightKg: set.weightKg, rpe: nil)
        edits[set.id] = nil
    }
}

struct WatchElapsedLine: View {
    @Environment(WatchWorkoutModel.self) private var model

    var body: some View {
        if let start = model.clockStart {
            TimelineView(.periodic(from: start, by: 1)) { context in
                HStack {
                    Text(workoutElapsedText(context.date.timeIntervalSince(start)))
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
        VStack(alignment: .leading, spacing: 2) {
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
            // Machine settings at this gym ("Seat 4 · Pin 7"), from the phone.
            if let machineNote = exercise.machineNote {
                Text(machineNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        // "Drop 1 of 2" for a drop stage or mini-set (from the phone); older phones send no title.
        let fallback = "\(set.isWarmup ? "Warm-up" : "Set") \(number) of \(same.count)"
        Text(set.title ?? fallback)
            .font(.footnote)
            .foregroundStyle(set.isStage ? WatchTheme.lifting : .secondary)
        HStack {
            // "8 × 60 kg", "10 × 20 kg each" (per hand), "30 s" for a plank.
            Text(exercise.setText(reps: reps, weightKg: weightKg, unit: session.unit))
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
            WatchSetGhost(set: set, unit: session.unit, isHold: exercise.isHold == true)
        }
        // Never for a hold: there are no reps to count.
        if exercise.repCounting == true, exercise.isHold != true, !set.isWarmup {
            WatchRepCounterView(setKey: session.setKey(exercise: index, set: setIndex))
        }
        if exercise.supersetLabel?.hasSuffix("1") == true, let partner = session.partnerIndex(of: index) {
            Text("then \(session.exercises[partner].name)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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

/// Under the set: the plan's target and last session's same set on one line
/// ("Target 8 · 2 in reserve · Last 60 kg × 8"), and the phone's set-by-set
/// change, if any, on one more. A hold reads in seconds ("Target 30 s · Last 30 s").
private struct WatchSetGhost: View {
    let set: WatchSession.SetSnapshot
    let unit: String
    var isHold = false

    private var guide: String? {
        let parts = isHold
            ? [set.holdTargetLine, set.holdGhostLine].compactMap { $0 }
            : [set.targetLine, set.ghostLine(unit: unit)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        if let guide {
            Text(guide)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        if let note = set.note {
            Text(note)
                .font(.caption2)
                .foregroundStyle(WatchTheme.lifting)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

extension WatchSession.SetSnapshot {
    /// "Target 30 s" for a plank or side plank, whose reps are seconds. Reps in
    /// reserve don't apply to a hold, so they're left out.
    nonisolated var holdTargetLine: String? {
        guard let targetReps, targetReps > 0 else { return nil }
        return "Target \(targetReps) s"
    }

    /// "Last 30 s" (with "· RPE 8" when rated), or nil without a matching set last time.
    nonisolated var holdGhostLine: String? {
        guard let lastReps, lastReps > 0 else { return nil }
        var line = "Last \(lastReps) s"
        if let lastRPE { line += " · RPE \(lastRPE.formatted())" }
        return line
    }
}

/// "Reps left?" for the set just ticked, as 0 / 1 / 2 / 3 / 4+ (the plan's
/// number outlined), above the running rest. One tap logs RPE = 10 − reps
/// left (Zourdos et al., J Strength Cond Res 2016); Skip leaves it unrated.
private struct WatchRatingPrompt: View {
    @Environment(WatchWorkoutModel.self) private var model
    let set: PendingSet

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Reps left?")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button("Skip") { model.skipRating() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            WatchRepsLeftGrid(plan: set.suggestedRPE.map { min(4, max(0, 10 - $0)) }) { left in
                model.rateSet(set, rpe: Double(10 - left))
            }
        }
        .padding(8)
        .background(WatchTheme.lifting.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Complete, pinned under the live page.
private struct WatchCompleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Complete", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.recovery)
        .padding(.horizontal, 4)
    }
}

/// New records after the exercise finished on the wrist; tap to close.
private struct WatchRecordBanner: View {
    let note: WatchRecordNote
    let onClose: () -> Void

    private var spoken: String {
        (["New record"] + note.lines).joined(separator: ". ")
    }

    var body: some View {
        Button(action: onClose) {
            VStack(alignment: .leading, spacing: 2) {
                Label("New record", systemImage: "trophy.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchTheme.lifting)
                ForEach(note.lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(WatchTheme.lifting.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityHint("Closes the banner")
    }
}
