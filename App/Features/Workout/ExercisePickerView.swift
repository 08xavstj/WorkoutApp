import SwiftUI
import AppCore

/// Searchable list of the bundled exercise library.
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(ExerciseLibrary.self) private var library
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    @State private var onlyMyGym = false
    @State private var searchText = ""
    @State private var region: MuscleRegion?
    @State private var detailExercise: Exercise?

    var body: some View {
        NavigationStack {
            List {
                if let error = library.loadError {
                    Text(error).foregroundStyle(Theme.recoveryLowText)
                }
                Section {
                    RegionChips(selection: $region)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                if sections.isEmpty && !library.exercises.isEmpty {
                    Text("No exercises match. Try another muscle group or turn off \"Only my gym's equipment\".")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.exercises) { exercise in
                            row(exercise)
                        }
                    } header: {
                        Text("\(section.muscle.capitalized) · \(section.exercises.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .textCase(nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search 750+ exercises")
            .navigationDestination(item: $detailExercise) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Only my gym's equipment", isOn: $onlyMyGym)
                    } label: {
                        Image(systemName: onlyMyGym ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter exercises")
                }
            }
        }
    }

    private func row(_ exercise: Exercise) -> some View {
                    HStack {
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .foregroundStyle(Theme.primaryText)
                                Text([exercise.primaryMuscleLabel, exercise.equipment?.capitalized].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        Button {
                            detailExercise = exercise
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("About \(exercise.name)")
                    }
                    .listRowBackground(Theme.card)
    }
}

extension ExercisePickerView {
    /// Results grouped by main muscle, in head-to-toe order.
    fileprivate var sections: [MuscleSection] {
        let grouped = Dictionary(grouping: results) { $0.primaryMuscles.first ?? "other" }
        let muscles = grouped.keys.sorted { a, b in
            let orderA = MuscleRegion.order(a)
            let orderB = MuscleRegion.order(b)
            return orderA == orderB ? a < b : orderA < orderB
        }
        return muscles.map { muscle in
            MuscleSection(muscle: muscle, exercises: (grouped[muscle] ?? []).sorted { $0.name < $1.name })
        }
    }

    /// Search results; with "Only my gym's equipment" on, exercises needing
    /// equipment the gym doesn't have (or that isn't recognised) are hidden.
    fileprivate var results: [Exercise] {
        let found = library.search(searchText, muscle: nil).filter { exercise in
            guard let region else { return true }
            return region.contains(exercise.primaryMuscles.first ?? exercise.category)
        }
        guard onlyMyGym else { return found }
        return found.filter { exercise in
            guard let equipment = exercise.equipment else { return true }
            guard let kind = EquipmentKind.fromLibrary(equipment) else { return false }
            return gym.profile.has(kind)
        }
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(exercise.imageURLs, id: \.self) { url in
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 260, height: 200)
                            .background(Theme.cardRaised)
                            .clipShape(.rect(cornerRadius: 12))
                            .accessibilityHidden(true)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                HStack {
                    StatView(label: "Primary", value: exercise.primaryMuscles.map(\.capitalized).joined(separator: ", "))
                    StatView(label: "Equipment", value: exercise.equipment?.capitalized ?? "None")
                }
                .card()

                NavigationLink {
                    LiftProgressView(exerciseID: exercise.id, name: exercise.name)
                } label: {
                    HStack {
                        Label("Your progress", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(minHeight: 44)
                    .card()
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    Text("How to").font(.headline)
                    ForEach(exercise.instructions.enumerated(), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .frame(width: 22, height: 22)
                                .background(Theme.strain.opacity(0.2), in: .circle)
                            Text(step).font(.subheadline)
                        }
                    }
                }
                .card()
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One muscle's exercises in the picker.
struct MuscleSection: Identifiable {
    var muscle: String
    var exercises: [Exercise]
    var id: String { muscle }
}

/// Body regions for browsing the exercise library. Muscle names are the
/// library's (free-exercise-db) primary muscles.
enum MuscleRegion: String, CaseIterable, Identifiable {
    case chest, back, shoulders, arms, legs, core

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var muscles: [String] {
        switch self {
        case .chest: ["chest"]
        case .back: ["lats", "middle back", "lower back", "traps"]
        case .shoulders: ["shoulders", "neck"]
        case .arms: ["biceps", "triceps", "forearms"]
        case .legs: ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]
        case .core: ["abdominals"]
        }
    }

    func contains(_ muscle: String) -> Bool { muscles.contains(muscle) }

    /// Head-to-toe position of a muscle, for ordering sections.
    static func order(_ muscle: String) -> Int {
        let all = allCases.flatMap(\.muscles)
        return all.firstIndex(of: muscle) ?? all.count
    }
}

/// "All · Chest · Back · ..." chips across the top of the picker.
private struct RegionChips: View {
    @Binding var selection: MuscleRegion?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", selected: selection == nil) { selection = nil }
                ForEach(MuscleRegion.allCases) { region in
                    chip(region.title, selected: selection == region) {
                        selection = selection == region ? nil : region
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? .white : Theme.primaryText)
                .background(selected ? AnyShapeStyle(Theme.lifting) : AnyShapeStyle(Theme.cardRaised), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
