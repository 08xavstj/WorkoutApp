import SwiftUI
import SwiftData

/// The live logging screen: exercises, sets, a rest timer, and Finish.
struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettings.self) private var settings
    @State private var showingPicker = false
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var restEndsAt: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        HStack {
                            StatView(label: "Elapsed", value: elapsed(at: context.date))
                            StatView(label: "Sets", value: "\(session.workingSets.count)")
                            StatView(label: "Volume", value: "\(settings.weightUnit.format(session.totalVolumeKg)) \(settings.weightUnit.rawValue)")
                        }
                    }
                }
                .listRowBackground(Theme.card)

                ForEach(session.orderedExercises) { exercise in
                    ExerciseSection(exercise: exercise, unit: settings.weightUnit) {
                        restEndsAt = .now.addingTimeInterval(90)
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle($session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Minimize") { dismiss() }
                        Button("Discard workout", role: .destructive) { showingDiscard = true }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Workout options")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }
                        .disabled(session.workingSets.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let restEndsAt {
                    RestTimerBanner(endsAt: restEndsAt) { self.restEndsAt = nil }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in
                    add(exercise)
                }
            }
            .sheet(isPresented: $showingFinish) {
                FinishWorkoutSheet(session: session) {
                    dismiss()
                }
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

    private func elapsed(at date: Date) -> String {
        let seconds = Int(max(0, date.timeIntervalSince(session.startedAt)))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    private func add(_ exercise: Exercise) {
        let log = ExerciseLog(exerciseID: exercise.id, name: exercise.name, order: session.exercises.count)
        log.session = session
        modelContext.insert(log)
        let firstSet = SetLog(order: 0)
        firstSet.exercise = log
        modelContext.insert(firstSet)
        try? modelContext.save()
    }
}

private struct ExerciseSection: View {
    @Bindable var exercise: ExerciseLog
    let unit: WeightUnit
    let onSetCompleted: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Section {
            HStack {
                Text("Set").frame(width: 32, alignment: .leading)
                Text(unit.rawValue).frame(maxWidth: .infinity)
                Text("Reps").frame(maxWidth: .infinity)
                Text("RPE").frame(width: 52)
                Image(systemName: "checkmark").frame(width: 36)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)

            ForEach(exercise.orderedSets) { set in
                SetRow(set: set, index: set.order + 1, unit: unit, onCompleted: onSetCompleted)
            }
            .onDelete(perform: deleteSets)

            Button {
                addSet()
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(.subheadline)
            }
        } header: {
            Text(exercise.name)
                .font(.headline)
                .foregroundStyle(.white)
                .textCase(nil)
        }
    }

    private func addSet() {
        // Copy the last set's weight and reps - that's usually what you do next.
        let last = exercise.orderedSets.last
        let set = SetLog(order: (last?.order ?? -1) + 1, weightKg: last?.weightKg ?? 0, reps: last?.reps ?? 0, rpe: last?.rpe)
        set.exercise = exercise
        modelContext.insert(set)
        try? modelContext.save()
    }

    private func deleteSets(at offsets: IndexSet) {
        let ordered = exercise.orderedSets
        for index in offsets {
            modelContext.delete(ordered[index])
        }
        try? modelContext.save()
    }
}

private struct SetRow: View {
    @Bindable var set: SetLog
    let index: Int
    let unit: WeightUnit
    let onCompleted: () -> Void

    var body: some View {
        HStack {
            Button {
                set.isWarmup.toggle()
            } label: {
                Text(set.isWarmup ? "W" : "\(index)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(set.isWarmup ? Theme.recoveryModerate : .white)
            }
            .buttonStyle(.plain)
            .frame(width: 32, alignment: .leading)
            .accessibilityLabel(set.isWarmup ? "Warm-up set, tap to make a working set" : "Set \(index), tap to mark as warm-up")

            TextField("0", value: weightBinding, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.cardRaised, in: .rect(cornerRadius: 8))

            TextField("0", value: $set.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Theme.cardRaised, in: .rect(cornerRadius: 8))

            Menu {
                Button("None") { set.rpe = nil }
                ForEach([6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { value in
                    Button(value.formatted()) { set.rpe = value }
                }
            } label: {
                Text(set.rpe.map { $0.formatted() } ?? "-")
                    .frame(width: 52)
                    .padding(.vertical, 6)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 8))
            }
            .accessibilityLabel("RPE")

            Button {
                set.completedAt = set.isCompleted ? nil : .now
                if set.isCompleted && !set.isWarmup { onCompleted() }
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.isCompleted ? Theme.recoveryHigh : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .frame(width: 36)
            .sensoryFeedback(.success, trigger: set.isCompleted) { _, completed in completed }
            .accessibilityLabel(set.isCompleted ? "Completed" : "Mark set complete")
        }
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { unit.display(set.weightKg) },
            set: { set.weightKg = unit.toKilograms($0) }
        )
    }
}

private struct RestTimerBanner: View {
    let endsAt: Date
    let onDone: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.up)))
            HStack {
                Label("Rest", systemImage: "timer")
                    .font(.headline)
                Spacer()
                Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Button("Skip", action: onDone)
                    .buttonStyle(.bordered)
            }
            .padding()
            .background(Theme.cardRaised, in: .rect(cornerRadius: Theme.cornerRadius))
            .padding(.horizontal)
            .onChange(of: remaining == 0) { _, finished in
                if finished { onDone() }
            }
        }
    }
}
