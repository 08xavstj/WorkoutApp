import SwiftUI
import SwiftData
import AppCore

/// Workouts you built yourself: start, edit, duplicate or delete them, or
/// start an empty workout and add exercises as you go.
struct MyWorkoutsView: View {
    /// Called after a workout starts (e.g. to close the sheet this is shown in).
    var onStart: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(GymStore.self) private var gym
    @Environment(ExerciseLibrary.self) private var library
    @Query(sort: \WorkoutTemplate.createdAt, order: .reverse) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var editing: EditorRequest?
    @State private var pendingDelete: WorkoutTemplate?

    struct EditorRequest: Identifiable {
        let id = UUID()
        var template: WorkoutTemplate?
    }

    /// Most recently used first, then newest.
    private var sorted: [WorkoutTemplate] {
        templates.sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    bigButton("Create a workout", icon: "plus", colors: [Theme.lifting, Theme.sleep]) {
                        editing = EditorRequest(template: nil)
                    }
                    bigButton("Start empty", icon: "dumbbell.fill", colors: [Theme.strain, Theme.lifting]) {
                        launcher.startEmpty(in: modelContext)
                        onStart?()
                    }
                }
                if sorted.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Build your own")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Pick any exercises, sets, reps and effort. Weights you leave blank are suggested from what you've lifted before. You can also save any workout you've done from its menu.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                ForEach(sorted) { template in
                    TemplateRow(
                        template: template,
                        onStart: { start(template) },
                        onEdit: { editing = EditorRequest(template: template) },
                        onDuplicate: { duplicate(template) },
                        onDelete: { pendingDelete = template }
                    )
                }
            }
            .padding()
            .lockedToScreenWidth()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Theme.background)
        .navigationTitle("My workouts")
        .sheet(item: $editing) { request in
            TemplateEditorView(template: request.template)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "this workout")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let template = pendingDelete {
                    modelContext.delete(template)
                    try? modelContext.save()
                }
                pendingDelete = nil
            }
        } message: {
            Text("Workouts you've already done with it stay in your history.")
        }
    }

    private func start(_ template: WorkoutTemplate) {
        launcher.start(template, gym: gym, sessions: sessions, library: library, in: modelContext)
        onStart?()
    }

    private func duplicate(_ template: WorkoutTemplate) {
        let copy = WorkoutTemplate(name: "\(template.name) copy")
        modelContext.insert(copy)
        for exercise in template.orderedExercises {
            let item = TemplateExercise(
                exerciseID: exercise.exerciseID, name: exercise.name, order: exercise.order,
                sets: exercise.sets, repsLow: exercise.repsLow, repsHigh: exercise.repsHigh,
                targetRPE: exercise.targetRPE, weightKg: exercise.weightKg
            )
            item.template = copy
            modelContext.insert(item)
        }
        try? modelContext.save()
    }

    private func bigButton(_ title: String, icon: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

private struct TemplateRow: View {
    let template: WorkoutTemplate
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let exercises = template.orderedExercises
        let totalSets = exercises.reduce(0) { $0 + $1.sets }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s") · \(totalSets) sets")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Menu {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Options for \(template.name)")
            }
            Text(exercises.map(\.name).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            HStack {
                if let used = template.lastUsedAt {
                    Text("Last done \(used.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Theme.ink, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(exercises.isEmpty)
            }
        }
        .card()
    }
}

// MARK: - Editor

/// Build or edit your own workout. Changes are kept in a draft until you save.
struct TemplateEditorView: View {
    let template: WorkoutTemplate?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    @State private var name = ""
    @State private var items: [DraftItem] = []
    @State private var showingPicker = false
    @State private var showingRPEGuide = false
    @State private var loaded = false

    struct DraftItem: Identifiable, Equatable {
        let id = UUID()
        var exerciseID: String
        var name: String
        var sets: Int
        var repsLow: Int
        var repsHigh: Int
        var useRange: Bool
        var rpe: Double?
        /// In the display unit; nil = suggested.
        var weight: Double?
    }

    private var unit: WeightUnit { settings.weightUnit }

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField("e.g. Upper A, Leg day", text: $name)
                }
                Section {
                    ForEach($items) { $item in
                        DraftItemRow(item: $item, unit: unit, onShowGuide: { showingRPEGuide = true })
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(minHeight: 44)
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        if items.count > 1 {
                            EditButton()
                                .font(.caption.weight(.semibold))
                        }
                    }
                } footer: {
                    Text("Leave weight blank and the app suggests one from your history each time, so it keeps progressing. Swipe left to remove; tap Edit to reorder.")
                }
            }
            .navigationTitle(template == nil ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(items.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in add(exercise) }
            }
            .sheet(isPresented: $showingRPEGuide) {
                RPEGuideView().presentationDetents([.medium, .large])
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let template else { return }
        name = template.name
        items = template.orderedExercises.map { exercise in
            DraftItem(
                exerciseID: exercise.exerciseID, name: exercise.name, sets: exercise.sets,
                repsLow: exercise.repsLow, repsHigh: exercise.repsHigh,
                useRange: exercise.repsLow != exercise.repsHigh, rpe: exercise.targetRPE,
                weight: exercise.weightKg.map { unit.display($0) }
            )
        }
    }

    /// Default sets and reps for a new exercise, from your goal.
    private func add(_ exercise: Exercise) {
        let compound = ExerciseCatalog.slot(for: exercise.id)?.isCompound ?? (exercise.mechanic == "compound")
        let reps: ClosedRange<Int> = switch gym.style {
        case .strength: compound ? 3...6 : 8...10
        case .muscle: compound ? 6...10 : 10...15
        case .endurance: compound ? 10...15 : 12...20
        case .balanced: compound ? 6...8 : 10...12
        }
        items.append(DraftItem(
            exerciseID: exercise.id, name: exercise.name, sets: 3,
            repsLow: reps.lowerBound, repsHigh: reps.upperBound, useRange: true, rpe: nil, weight: nil
        ))
        if name.isEmpty { name = "My workout" }
    }

    private func save() {
        let target: WorkoutTemplate
        if let template {
            target = template
            for old in template.exercises { modelContext.delete(old) }
        } else {
            target = WorkoutTemplate(name: name)
            modelContext.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        for (order, item) in items.enumerated() {
            let high = item.useRange ? max(item.repsLow, item.repsHigh) : item.repsLow
            let exercise = TemplateExercise(
                exerciseID: item.exerciseID, name: item.name, order: order,
                sets: item.sets, repsLow: item.repsLow, repsHigh: high,
                targetRPE: item.rpe,
                weightKg: item.weight.flatMap { $0 > 0 ? unit.toKilograms($0) : nil }
            )
            exercise.template = target
            modelContext.insert(exercise)
        }
        try? modelContext.save()
        dismiss()
    }
}

private struct DraftItemRow: View {
    @Binding var item: TemplateEditorView.DraftItem
    let unit: WeightUnit
    let onShowGuide: () -> Void

    private static let efforts: [Double] = [6, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    /// Blank = suggested from history.
    private var weightText: Binding<String> {
        Binding(
            get: { item.weight.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? "" },
            set: { text in
                let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
                item.weight = cleaned.isEmpty ? nil : Double(cleaned)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Stepper("Sets: \(item.sets)", value: $item.sets, in: 1...10)
            Toggle("Rep range", isOn: $item.useRange)
            if item.useRange {
                Stepper("From \(item.repsLow) reps", value: $item.repsLow, in: 1...50)
                Stepper("To \(max(item.repsLow, item.repsHigh)) reps", value: $item.repsHigh, in: item.repsLow...50)
            } else {
                Stepper("Reps: \(item.repsLow)", value: $item.repsLow, in: 1...50)
            }
            HStack {
                Picker("Effort", selection: $item.rpe) {
                    Text("Default · \(RPEScale.summary(WorkoutPlanner.defaultTemplateRPE))").tag(Double?.none)
                    ForEach(Self.efforts, id: \.self) { rpe in
                        Text(RPEScale.summary(rpe)).tag(Double?.some(rpe))
                    }
                }
                Button(action: onShowGuide) {
                    Image(systemName: "questionmark.circle")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("What's RPE?")
            }
            HStack {
                Text("Weight")
                Spacer()
                TextField("Suggested", text: weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                Text(unit.rawValue)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .onChange(of: item.repsLow) {
            if item.repsHigh < item.repsLow { item.repsHigh = item.repsLow }
        }
    }
}
