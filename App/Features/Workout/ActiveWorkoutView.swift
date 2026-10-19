import SwiftUI
import SwiftData
import UIKit
import AppCore

/// The live logging screen.
struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(GymStore.self) private var gym
    @Environment(LiveWorkoutRecorder.self) private var recorder
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var showingPicker = false
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var expanded: Set<PersistentIdentifier> = []
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 52

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerBar
                    titleBlock
                    LiveHeartRateBar(recorder: recorder, profile: metrics.heartRateProfile)
                    // Reads the shared timer each second, so +15s / Skip on the
                    // Lock Screen show up here too.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let ends = RestTimerStore.endsAt {
                            RestTimerPill(endsAt: ends, length: RestTimerStore.length) { change in
                                if let change {
                                    RestTimerStore.adjust(by: change)
                                } else {
                                    RestTimerStore.stop()
                                }
                                Task { await WorkoutLiveActivity.refresh() }
                            }
                        }
                    }
                    ForEach(session.orderedExercises) { exercise in
                        exerciseCard(exercise)
                    }
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.card, in: .capsule)
                            .overlay(Capsule().strokeBorder(Theme.separator))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .lockedToScreenWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollDismissesKeyboard(.interactively)
            // One keyboard "Done" for the whole screen (each set editor used to add its own).
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.rose, Theme.Wash.butter])
            }
            .background(Theme.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in add(exercise) }
            }
            .sheet(isPresented: $showingFinish) {
                FinishWorkoutSheet(session: session) { dismiss() }
                    .presentationDetents([.medium])
            }
            .task {
                guard session.isActive else { return }
                // Lock Screen / Dynamic Island: elapsed time, next set and rest timer.
                let next = nextSetText()
                await WorkoutActivityController.startIfNeeded(
                    name: session.name, startedAt: session.startedAt, exercise: next.exercise, detail: next.detail
                )
                // Live heart rate from AirPods Pro 3 or a Bluetooth strap while this workout runs.
                if !recorder.isRecording {
                    await recorder.start(at: session.startedAt)
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    if recorder.sessionStart == session.startedAt { recorder.discard() }
                    Task { await WorkoutLiveActivity.endAll() }
                    modelContext.delete(session)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack {
            Menu {
                Button("Minimize", systemImage: "chevron.down") { dismiss() }
                Button("Discard workout", systemImage: "trash", role: .destructive) { showingDiscard = true }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: .circle)
                    .shadow(color: Color.black.opacity(0.07), radius: 9, y: 4)
            }
            .accessibilityLabel("Workout options")
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Theme.recoveryLow).frame(width: 8, height: 8)
                Text("LIVE").tracking(1.5)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.recoveryLowText)
            Spacer()
            Button {
                showingFinish = true
            } label: {
                Text("Finish")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Theme.lifting, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(session.workingSets.isEmpty)
            .opacity(session.workingSets.isEmpty ? 0.5 : 1)
        }
        .padding(.top, 8)
    }

    private var titleBlock: some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
            let live = liveStrain(elapsed: elapsed)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Workout name", text: $session.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.primaryText)
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                        .font(.system(size: timerSize, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text("Elapsed · \(finishedExercises) of \(session.exercises.count) exercises")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    if session.workingSets.isEmpty {
                        Text("Tick off a set to finish.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                GradientRing(progress: live / 40, colors: [Theme.strainLight, Theme.strain], lineWidth: 11) {
                    VStack(spacing: 0) {
                        Text("+\(strainText(live))")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("strain")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(Theme.primaryText)
                }
                .frame(width: 112, height: 112)
                .accessibilityLabel("Strain added so far")
            }
        }
    }

    private var finishedExercises: Int {
        session.exercises.filter { !$0.sets.isEmpty && $0.sets.allSatisfy(\.isCompleted) }.count
    }

    /// Strain this session has added on top of today's strain, from time and effort.
    private func liveStrain(elapsed: TimeInterval) -> Double {
        let rpes = session.workingSets.compactMap(\.rpe)
        let rpe = rpes.isEmpty ? 7 : rpes.reduce(0, +) / Double(rpes.count)
        let load = StrainPlanner().liftingLoad(minutes: elapsed / 60, rpe: rpe)
        return metrics.strainGain(addedLoad: load)
    }

    // MARK: Exercises

    private var currentExerciseID: PersistentIdentifier? {
        session.orderedExercises.first { exercise in exercise.sets.contains { !$0.isCompleted } }?.persistentModelID
    }

    /// Weights in a workout show in the gym's unit, so the numbers, the +/-
    /// steps and the plates to load all match what's on the bar.
    private var workoutUnit: WeightUnit { gym.profile.unit == .kg ? .kilograms : .pounds }

    @ViewBuilder
    private func exerciseCard(_ exercise: ExerciseLog) -> some View {
        let isCurrent = exercise.persistentModelID == currentExerciseID
        let isDone = !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted)
        if isCurrent || expanded.contains(exercise.persistentModelID) || exercise.sets.isEmpty {
            ExerciseCard(
                exercise: exercise,
                isCurrent: isCurrent,
                previous: LiftHistory.previousSets(for: exercise.exerciseID, before: session.startedAt, in: sessions),
                bestBefore: LiftHistory.bestOneRepMax(for: exercise.exerciseID, before: session.startedAt, in: sessions),
                unit: workoutUnit,
                gym: gym.profile,
                onSetCompleted: { startRest(for: exercise) },
                onCollapse: { expanded.remove(exercise.persistentModelID) }
            )
        } else {
            Button {
                expanded.insert(exercise.persistentModelID)
            } label: {
                CollapsedExerciseRow(
                    exercise: exercise,
                    isDone: isDone,
                    isNext: isNext(exercise),
                    unit: workoutUnit,
                    position: (session.orderedExercises.firstIndex(where: { $0.persistentModelID == exercise.persistentModelID }) ?? 0) + 1
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func isNext(_ exercise: ExerciseLog) -> Bool {
        let ordered = session.orderedExercises
        guard let currentIndex = ordered.firstIndex(where: { $0.persistentModelID == currentExerciseID }),
              let index = ordered.firstIndex(where: { $0.persistentModelID == exercise.persistentModelID }) else { return false }
        return index == currentIndex + 1
    }

    private func startRest(for exercise: ExerciseLog) {
        let compound = ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound ?? false
        RestTimerStore.start(seconds: compound ? 150 : 90)
        let next = nextSetText()
        Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
    }

    /// The next set to do, for the Live Activity ("Bench Press", "Set 3 of 4 · 135 lb × 8").
    private func nextSetText() -> (exercise: String, detail: String) {
        for exercise in session.orderedExercises {
            let sets = exercise.orderedSets
            guard let index = sets.firstIndex(where: { !$0.isCompleted }) else { continue }
            let set = sets[index]
            var detail = "Set \(index + 1) of \(sets.count)"
            if set.weightKg > 0 || set.reps > 0 {
                detail += " · \(workoutUnit.format(set.weightKg)) \(workoutUnit.rawValue) × \(set.reps)"
            }
            return (exercise.name, detail)
        }
        return ("All sets done", "Tap Finish when you're ready")
    }

    private func add(_ exercise: Exercise) {
        let log = ExerciseLog(exerciseID: exercise.id, name: exercise.name, order: session.exercises.count)
        log.session = session
        modelContext.insert(log)
        let firstSet = SetLog(order: 0)
        firstSet.exercise = log
        modelContext.insert(firstSet)
        try? modelContext.save()
        expanded.insert(log.persistentModelID)
    }
}

// MARK: - Exercise card

private struct ExerciseCard: View {
    @Bindable var exercise: ExerciseLog
    let isCurrent: Bool
    let previous: [SetLog]
    let bestBefore: Double
    let unit: WeightUnit
    let gym: GymProfile
    let onSetCompleted: () -> Void
    let onCollapse: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ExerciseLibrary.self) private var library
    /// The set open in the editor (defaults to the next set to do).
    @State private var focusedSetID: PersistentIdentifier?
    @State private var showingRPEGuide = false
    @State private var confirmingRemove = false

    var body: some View {
        let sets = exercise.orderedSets
        let currentSet = sets.first { !$0.isCompleted }
        let editing = sets.first { $0.persistentModelID == focusedSetID } ?? currentSet
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: "dumbbell.fill", color: Theme.lifting, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    if let info = library.exercise(id: exercise.exerciseID) {
                        Text([info.equipment?.capitalized, info.primaryMuscleLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                if isNewPR {
                    Label("New PR", systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.liftingText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.lifting.opacity(0.12), in: .capsule)
                }
                Menu {
                    if !isCurrent {
                        Button("Collapse", systemImage: "chevron.up", action: onCollapse)
                    }
                    Button("Remove exercise", systemImage: "trash", role: .destructive) {
                        confirmingRemove = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Exercise options")
                .confirmationDialog("Remove \(exercise.name) and its sets?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        modelContext.delete(exercise)
                        try? modelContext.save()
                    }
                }
            }

            ForEach(sets, id: \.persistentModelID) { set in
                SetRow(
                    set: set,
                    label: set.isWarmup ? "W" : "\(workingNumber(set, in: sets))",
                    previous: set.isWarmup ? "" : previousText(index: workingNumber(set, in: sets) - 1),
                    unit: unit,
                    isEditing: set.persistentModelID == editing?.persistentModelID,
                    onTap: { focusedSetID = set.persistentModelID },
                    onToggle: { toggle(set) }
                )
                .contextMenu {
                    Button(set.isWarmup ? "Make working set" : "Make warm-up set") { set.isWarmup.toggle() }
                    Button("Delete set", role: .destructive) {
                        modelContext.delete(set)
                        try? modelContext.save()
                    }
                }
            }

            if let editing {
                SetEditor(
                    set: editing,
                    title: editing.isWarmup ? "Warm-up" : "Set \(workingNumber(editing, in: sets))",
                    unit: unit,
                    step: { up in step(editing, up: up) },
                    plateHint: plateHint(for: editing),
                    onComplete: { toggle(editing) },
                    onShowGuide: { showingRPEGuide = true }
                )
            }

            Button {
                addSet()
            } label: {
                Text("+ Add set")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if !previous.isEmpty {
                Text("Last time: \(previous.map { "\(unit.format($0.weightKg)) × \($0.reps)" }.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
        .sheet(isPresented: $showingRPEGuide) {
            RPEGuideView()
                .presentationDetents([.medium, .large])
        }
    }

    /// Completes (or un-completes) a set; completing starts rest and moves to the next set.
    private func toggle(_ set: SetLog) {
        set.completedAt = set.isCompleted ? nil : .now
        try? modelContext.save()
        if set.isCompleted {
            focusedSetID = nil
            if !set.isWarmup { onSetCompleted() }
        }
    }

    /// Next/previous weight you can actually load with your gym's plates,
    /// dumbbells or stacks (falls back to 5 lb / 2.5 kg).
    private func step(_ set: SetLog, up: Bool) {
        let kind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load ?? libraryLoadKind
        let current = gym.unit.fromKilograms(set.weightKg)
        var next: Double?
        if let kind, gym.has(kind) {
            next = up ? gym.nextLoad(above: current + 0.001, on: kind) : gym.load(atMost: current - 0.001, on: kind)
        }
        let fallback = gym.unit == .kg ? 2.5 : 5
        let value = next ?? max(0, current + (up ? fallback : -fallback))
        set.weightKg = gym.unit.toKilograms(value)
    }

    private var isNewPR: Bool {
        guard bestBefore > 0 else { return false }
        let best = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.map(\.estimatedOneRepMax).max() ?? 0
        return best > bestBefore + 0.01
    }

    private func workingNumber(_ set: SetLog, in sets: [SetLog]) -> Int {
        (sets.filter { !$0.isWarmup }.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
    }

    /// Last session's working set with the same number (warm-ups don't count).
    private func previousText(index: Int) -> String {
        let working = previous.filter { !$0.isWarmup }
        guard index >= 0, index < working.count else { return "" }
        let set = working[index]
        return "\(unit.format(set.weightKg)) × \(set.reps)"
    }

    /// "45 + 25 per side" for barbell lifts, using your gym's plates.
    private func plateHint(for set: SetLog) -> String? {
        let plateKinds: [EquipmentKind] = [.barbell, .ezBar, .smithMachine]
        guard set.weightKg > 0,
              let kind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load ?? libraryLoadKind,
              plateKinds.contains(kind) else { return nil }
        let total = (gym.unit.fromKilograms(set.weightKg) * 4).rounded() / 4
        guard let plates = gym.plateBreakdown(total: total, on: kind) else {
            return "Can't make \(total.formatted()) \(gym.unit.rawValue) with your plates"
        }
        if plates.isEmpty { return "Empty bar" }
        return "Load \(plates.map { $0.formatted() }.joined(separator: " + ")) \(gym.unit.rawValue) per side"
    }

    private var libraryLoadKind: EquipmentKind? {
        switch library.exercise(id: exercise.exerciseID)?.equipment {
        case "barbell": .barbell
        case "e-z curl bar": .ezBar
        default: nil
        }
    }

    private func addSet() {
        let last = exercise.orderedSets.last
        let set = SetLog(order: (last?.order ?? -1) + 1, weightKg: last?.weightKg ?? 0, reps: last?.reps ?? 0, rpe: nil)
        set.exercise = exercise
        modelContext.insert(set)
        try? modelContext.save()
    }
}

/// One set as a compact line; tap to edit it in the SetEditor.
private struct SetRow: View {
    @Bindable var set: SetLog
    let label: String
    let previous: String
    let unit: WeightUnit
    let isEditing: Bool
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.headline)
                .foregroundStyle(set.isWarmup ? Theme.recoveryModerate : Theme.primaryText)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(set.weightKg > 0 || set.reps > 0 ? "\(unit.format(set.weightKg)) \(unit.rawValue) × \(set.reps)" : "Not set")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(set.weightKg > 0 || set.reps > 0 ? Theme.primaryText : Theme.secondaryText)
                if !previous.isEmpty {
                    Text("Last: \(previous)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let rpe = set.rpe {
                Text("RPE \(rpe.formatted())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.liftingText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.lifting.opacity(0.12), in: .capsule)
            }
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(set.isCompleted ? Theme.recoveryHigh : Color.clear)
                    Circle()
                        .strokeBorder(set.isCompleted ? Theme.recoveryHigh : Theme.secondaryText.opacity(0.4), lineWidth: 2)
                    if set.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: set.isCompleted) { _, completed in completed }
            .accessibilityLabel(set.isCompleted ? "Completed, tap to undo" : "Mark set complete")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground, in: .rect(cornerRadius: 16))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lifting.opacity(0.7), lineWidth: 2)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edit this set")
    }

    private var rowBackground: Color {
        if set.isCompleted { return Theme.recoveryHigh.opacity(0.1) }
        if isEditing { return Theme.lifting.opacity(0.07) }
        return Theme.cardRaised.opacity(0.5)
    }
}

/// Big, thumb-friendly controls for the set you're on: weight and reps with
/// +/- (weights step to what your gym can load), RPE buttons and Complete.
private struct SetEditor: View {
    @Bindable var set: SetLog
    let title: String
    let unit: WeightUnit
    let step: (Bool) -> Void
    let plateHint: String?
    let onComplete: () -> Void
    let onShowGuide: () -> Void

    @FocusState private var typing: Field?
    private enum Field { case weight, reps }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.liftingText)
            HStack(spacing: 12) {
                NumberStepper(label: unit.rawValue) {
                    TextField("0", value: weightBinding, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .focused($typing, equals: .weight)
                } minus: { step(false) } plus: { step(true) }
                NumberStepper(label: "reps") {
                    TextField("0", value: $set.reps, format: .number)
                        .keyboardType(.numberPad)
                        .focused($typing, equals: .reps)
                } minus: { set.reps = max(0, set.reps - 1) } plus: { set.reps += 1 }
            }
            if let plateHint {
                Label(plateHint, systemImage: "circle.grid.2x1")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !set.isWarmup {
                RPEPicker(rpe: $set.rpe, onShowGuide: onShowGuide)
            }
            Button(action: {
                typing = nil
                onComplete()
            }) {
                Label(set.isCompleted ? "Completed · tap to undo" : "Complete set", systemImage: set.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    .font(.headline)
                    .foregroundStyle(set.isCompleted ? Theme.primaryText : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(set.isCompleted
                                ? AnyShapeStyle(Theme.cardRaised)
                                : AnyShapeStyle(LinearGradient(colors: Theme.recoveryButtonColors, startPoint: .leading, endPoint: .trailing)),
                                in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.lifting.opacity(0.05), in: .rect(cornerRadius: 20))
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { unit.display(set.weightKg) },
            set: { set.weightKg = unit.toKilograms($0) }
        )
    }
}

/// [-]  value  [+] with large tap targets; tap the number to type.
private struct NumberStepper<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                stepButton("minus", action: minus)
                field
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.6)
                stepButton("plus", action: plus)
            }
            .padding(4)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.separator))
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.lifting)
                .frame(width: 44, height: 44)
                .background(Theme.lifting.opacity(0.12), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "plus" ? "Increase \(label)" : "Decrease \(label)")
    }
}

/// Big 6-10 buttons plus a ½ toggle, with what the number means.
private struct RPEPicker: View {
    @Binding var rpe: Double?
    let onShowGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Effort (RPE)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button(action: onShowGuide) {
                    Label("What's RPE?", systemImage: "questionmark.circle")
                        .font(.caption.weight(.semibold))
                }
            }
            HStack(spacing: 6) {
                ForEach([6, 7, 8, 9, 10], id: \.self) { value in
                    let selected = rpe.map { Int($0.rounded(.down)) == value } ?? false
                    Button {
                        if selected && rpe == Double(value) { rpe = nil } else { rpe = Double(value) }
                    } label: {
                        Text("\(value)")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(selected ? .white : Theme.primaryText)
                            .background(selected
                                        ? AnyShapeStyle(LinearGradient(colors: Theme.strainButtonColors, startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.clear : Theme.separator))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("RPE \(value)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button {
                    guard let current = rpe, current < 10 else { return }
                    rpe = current.truncatingRemainder(dividingBy: 1) == 0 ? current + 0.5 : current - 0.5
                } label: {
                    Text("½")
                        .font(.title3.weight(.bold))
                        .frame(width: 44, height: 48)
                        .foregroundStyle(isHalf ? .white : Theme.primaryText)
                        .background(isHalf ? AnyShapeStyle(Theme.lifting) : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isHalf ? Color.clear : Theme.separator))
                }
                .buttonStyle(.plain)
                .disabled(rpe == nil || rpe == 10)
                .accessibilityLabel("Add a half point")
            }
            .sensoryFeedback(.selection, trigger: rpe)
            Text(rpe.map { value in
                let level = RPEScale.level(for: value)
                return "\(RPEScale.summary(value)). \(level?.feel ?? "")"
            } ?? "Optional. Pick how hard the set was: 8 means you had 2 reps left, 10 means none.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var isHalf: Bool {
        rpe.map { $0.truncatingRemainder(dividingBy: 1) != 0 } ?? false
    }
}

private struct CollapsedExerciseRow: View {
    let exercise: ExerciseLog
    let isDone: Bool
    let isNext: Bool
    let unit: WeightUnit
    /// 1-based position in the workout.
    var position: Int

    var body: some View {
        HStack(spacing: 14) {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.recoveryHigh, in: .circle)
            } else {
                Text("\(position)")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(Theme.cardRaised, in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if isNext {
                Chip(text: "Up next")
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private var summary: String {
        let working = exercise.sets.filter { !$0.isWarmup }
        if isDone, let best = working.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) {
            return "\(working.count) sets · \(unit.format(best.weightKg)) \(unit.rawValue) × \(best.reps) · done"
        }
        let first = exercise.orderedSets.first
        let reps = first.map { "\($0.reps)" } ?? "–"
        return "\(working.count) × \(reps)" + (first.map { $0.weightKg > 0 ? " · \(unit.format($0.weightKg)) \(unit.rawValue)" : "" } ?? "")
    }
}

private struct RestTimerPill: View {
    let endsAt: Date
    let length: TimeInterval
    /// +/- seconds, or nil to skip.
    let onChange: (TimeInterval?) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: length > 0 ? remaining / length : 0)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 32, height: 32)
                Text("Rest \(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                pillButton("−15s") { onChange(-15) }
                pillButton("+15s") { onChange(15) }
                Button("Skip") { onChange(nil) }
                    .font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing), in: .capsule)
            .shadow(color: Theme.strain.opacity(0.3), radius: 12, y: 6)
            .onChange(of: remaining == 0) { _, finished in
                if finished { onChange(nil) }
            }
            .sensoryFeedback(.warning, trigger: remaining == 0) { _, finished in finished }
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.white.opacity(0.2), in: .capsule)
            .contentShape(.capsule)
            .buttonStyle(.plain)
    }
}

/// Live heart rate from the iPhone workout session (AirPods Pro 3 or a chest strap).
private struct LiveHeartRateBar: View {
    let recorder: LiveWorkoutRecorder
    let profile: HeartRateProfile?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundStyle(Theme.recoveryLow)
                .symbolEffect(.pulse, isActive: recorder.heartRate != nil)
            if let bpm = recorder.heartRate {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(whole(bpm))")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("bpm").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(Theme.primaryText)
                    Text(zoneText(bpm))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                StatView(label: "Avg", value: recorder.averageHeartRate.map { "\(whole($0))" } ?? "–")
                    .frame(width: 56)
                StatView(label: "Max", value: recorder.maximumHeartRate.map { "\(whole($0))" } ?? "–")
                    .frame(width: 56)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recorder.isRecording ? "Waiting for heart rate…" : "Live heart rate off")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(recorder.problem ?? "Wear AirPods Pro 3 (or connect a Bluetooth chest strap) to see heart rate here. It's saved with the workout so you can compare it with your watch.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func zoneText(_ bpm: Double) -> String {
        guard let profile else { return "Live" }
        guard let zone = profile.zone(for: bpm) else { return "Below zone 1" }
        return "Zone \(zone) · \(whole(profile.reserveFraction(for: bpm) * 100))% of reserve"
    }
}
