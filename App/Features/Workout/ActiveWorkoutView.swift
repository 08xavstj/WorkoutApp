import SwiftUI
import SwiftData
import AppCore

/// The live logging screen.
struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(GymStore.self) private var gym
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var showingPicker = false
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var restEndsAt: Date?
    @State private var restLength: TimeInterval = 90
    @State private var expanded: Set<PersistentIdentifier> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerBar
                    titleBlock
                    if let restEndsAt {
                        RestTimerPill(endsAt: restEndsAt, length: restLength) { change in
                            if let change {
                                self.restEndsAt = restEndsAt.addingTimeInterval(change)
                                restLength = max(15, restLength + change)
                            } else {
                                self.restEndsAt = nil
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
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.strain, Theme.lifting])
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
            .confirmationDialog("Discard this workout?", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
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
            .foregroundStyle(Theme.recoveryLow)
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
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Workout name", text: $session.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.primaryText)
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text("Elapsed · \(finishedExercises) of \(session.exercises.count) exercises")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                GradientRing(progress: liveStrain(elapsed: elapsed) / 8, colors: [Theme.strainLight, Theme.strain], lineWidth: 11) {
                    VStack(spacing: 0) {
                        Text("+\(liveStrain(elapsed: elapsed).formatted(.number.precision(.fractionLength(1))))")
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
                unit: settings.weightUnit,
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
                    unit: settings.weightUnit
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
        restLength = compound ? 150 : 90
        restEndsAt = .now.addingTimeInterval(restLength)
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

    var body: some View {
        let sets = exercise.orderedSets
        let currentSet = sets.first { !$0.isCompleted }
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
                        .foregroundStyle(Theme.lifting)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.lifting.opacity(0.12), in: .capsule)
                }
                Menu {
                    if !isCurrent {
                        Button("Collapse", systemImage: "chevron.up", action: onCollapse)
                    }
                    Button("Remove exercise", systemImage: "trash", role: .destructive) {
                        modelContext.delete(exercise)
                        try? modelContext.save()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Exercise options")
            }

            HStack(spacing: 6) {
                Text("SET").frame(width: 30, alignment: .leading)
                Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
                Text(unit.rawValue.uppercased()).frame(width: 64)
                Text("REPS").frame(width: 50)
                Text("RPE").frame(width: 50)
                Color.clear.frame(width: 34, height: 1)
            }
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)

            ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { index, set in
                SetRow(
                    set: set,
                    label: set.isWarmup ? "W" : "\(workingNumber(set, in: sets))",
                    previous: previousText(index: index),
                    unit: unit,
                    isCurrent: set.persistentModelID == currentSet?.persistentModelID,
                    onCompleted: onSetCompleted
                )
                .contextMenu {
                    Button(set.isWarmup ? "Make working set" : "Make warm-up set") { set.isWarmup.toggle() }
                    Button("Delete set", role: .destructive) {
                        modelContext.delete(set)
                        try? modelContext.save()
                    }
                }
            }

            if let currentSet, let hint = plateHint(for: currentSet) {
                Label(hint, systemImage: "circle.grid.2x1")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
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
    }

    private var isNewPR: Bool {
        guard bestBefore > 0 else { return false }
        let best = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.map(\.estimatedOneRepMax).max() ?? 0
        return best > bestBefore + 0.01
    }

    private func workingNumber(_ set: SetLog, in sets: [SetLog]) -> Int {
        (sets.filter { !$0.isWarmup }.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
    }

    private func previousText(index: Int) -> String {
        guard index < previous.count else { return "–" }
        let set = previous[index]
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

private struct SetRow: View {
    @Bindable var set: SetLog
    let label: String
    let previous: String
    let unit: WeightUnit
    let isCurrent: Bool
    let onCompleted: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.headline)
                .foregroundStyle(set.isWarmup ? Theme.recoveryModerate : Theme.primaryText)
                .frame(width: 30, alignment: .leading)
            Text(previous)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            field {
                TextField("0", value: weightBinding, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
            }
            .frame(width: 64)
            field {
                TextField("0", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
            }
            .frame(width: 50)
            Menu {
                Button("None") { set.rpe = nil }
                ForEach([6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { value in
                    Button(value.formatted()) { set.rpe = value }
                }
            } label: {
                field {
                    Text(set.rpe.map { $0.formatted() } ?? (set.isWarmup ? "—" : "RPE"))
                        .foregroundStyle(set.rpe == nil ? Theme.secondaryText : Theme.primaryText)
                }
            }
            .frame(width: 50)
            .accessibilityLabel("RPE")
            Button {
                set.completedAt = set.isCompleted ? nil : .now
                if set.isCompleted && !set.isWarmup { onCompleted() }
            } label: {
                ZStack {
                    Circle()
                        .fill(set.isCompleted ? Theme.recoveryHigh : Color.clear)
                        .strokeBorder(set.isCompleted ? Theme.recoveryHigh : Theme.secondaryText.opacity(0.4), lineWidth: 2)
                    if set.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: set.isCompleted) { _, completed in completed }
            .accessibilityLabel(set.isCompleted ? "Completed" : "Mark set complete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground, in: .rect(cornerRadius: 16))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lifting.opacity(0.6), lineWidth: 2)
            }
        }
    }

    private var rowBackground: Color {
        if set.isCompleted { return Theme.recoveryHigh.opacity(0.1) }
        if isCurrent { return Theme.lifting.opacity(0.07) }
        return Color.clear
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.headline)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator))
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { unit.display(set.weightKg) },
            set: { set.weightKg = unit.toKilograms($0) }
        )
    }
}

private struct CollapsedExerciseRow: View {
    let exercise: ExerciseLog
    let isDone: Bool
    let isNext: Bool
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 14) {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.recoveryHigh, in: .circle)
            } else {
                Text("\(exercise.order + 1)")
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
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [Theme.strain, Theme.strainLight], startPoint: .leading, endPoint: .trailing), in: .capsule)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.2), in: .capsule)
            .buttonStyle(.plain)
    }
}
