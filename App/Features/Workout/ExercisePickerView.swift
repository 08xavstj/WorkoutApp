import SwiftUI

/// Searchable list of the bundled exercise library.
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var muscle: String?
    @State private var detailExercise: Exercise?

    var body: some View {
        NavigationStack {
            List {
                if let error = library.loadError {
                    Text(error).foregroundStyle(Theme.recoveryLowText)
                }
                ForEach(library.search(searchText, muscle: muscle)) { exercise in
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
                        Picker("Muscle", selection: $muscle) {
                            Text("All muscles").tag(String?.none)
                            ForEach(library.muscles, id: \.self) { name in
                                Text(name.capitalized).tag(String?.some(name))
                            }
                        }
                    } label: {
                        Image(systemName: muscle == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter by muscle")
                }
            }
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
