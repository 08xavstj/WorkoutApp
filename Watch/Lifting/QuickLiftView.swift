import SwiftUI

/// Quick lift with the phone out of reach: pick exercises from the library
/// the phone sent (recent exercises, with last time's sets as today's plan
/// and the loads the gym can make), then Start. The Watch logs the session
/// and the phone makes it when it hears (`WatchWorkoutSummary.loggedExercises`).
/// "Heart rate only" records the workout without sets, as before.
/// A list the crown scrolls, so no double-tap action (HIG Gestures).
struct QuickLiftView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(WatchCardioModel.self) private var cardio
    @State private var chosen: [Int] = []

    private var exercises: [WatchSession.ExerciseSnapshot] { model.library?.exercises ?? [] }
    private var isStarting: Bool { model.phase == .starting || cardio.phase == .starting }

    var body: some View {
        List {
            if !chosen.isEmpty {
                Button {
                    let picked = chosen.compactMap { id in exercises.first { $0.id == id } }
                    Task { await model.startQuickLift(picked) }
                } label: {
                    Label("Start \(chosen.count) \(chosen.count == 1 ? "exercise" : "exercises")", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(WatchPalette.onTint)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(WatchPalette.recovery))
                .disabled(isStarting)
            }
            if exercises.isEmpty {
                Text("Open Tensile on your iPhone once, and your recent exercises appear here for lifting without it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Section("Recent exercises") {
                    ForEach(exercises) { exercise in
                        Button {
                            toggle(exercise.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(exercise.name)
                                        .font(.headline)
                                        .lineLimit(2)
                                    if let last = lastLine(exercise) {
                                        Text(last)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 4)
                                if let position = chosen.firstIndex(of: exercise.id) {
                                    Text("\(position + 1)")
                                        .font(.headline)
                                        .foregroundStyle(WatchPalette.onTint)
                                        .frame(width: 28, height: 28)
                                        .background(WatchPalette.lifting, in: Circle())
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityAddTraits(chosen.contains(exercise.id) ? .isSelected : [])
                    }
                }
            }
            Section {
                Button {
                    Task { await model.start(sessionID: nil) }
                } label: {
                    Label("Heart rate only", systemImage: "heart.fill")
                        .frame(minHeight: 44)
                }
                .disabled(isStarting)
            } footer: {
                Text("Records heart rate and calories with no sets.")
            }
        }
        .navigationTitle("Quick lift")
    }

    private func toggle(_ id: Int) {
        if let index = chosen.firstIndex(of: id) {
            chosen.remove(at: index)
        } else {
            chosen.append(id)
        }
    }

    /// "Last 3 × 8 · 60 kg".
    private func lastLine(_ exercise: WatchSession.ExerciseSnapshot) -> String? {
        guard let first = exercise.sets.first else { return nil }
        let unit = model.library?.unit ?? "kg"
        return "Last \(exercise.sets.count) × \(exercise.setText(reps: first.reps, weightKg: first.weightKg, unit: unit))"
    }
}

/// Adds an exercise from the library to a session the Watch runs on its own.
struct AddExerciseView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            let inSession = Set(model.snapshot?.exercises.compactMap(\.catalogID) ?? [])
            ForEach((model.library?.exercises ?? []).filter { !inSession.contains($0.catalogID ?? "") }) { exercise in
                Button {
                    model.addExercise(exercise)
                    dismiss()
                } label: {
                    Text(exercise.name)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            if model.library?.exercises.isEmpty ?? true {
                Text("No exercises from your iPhone yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add exercise")
    }
}
