import SwiftUI
import SwiftData

/// Asks how hard the session felt (this feeds strain), then saves it.
struct FinishWorkoutSheet: View {
    @Bindable var session: WorkoutSession
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Double = 7
    @State private var saveToHealth = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("How hard was it?")
                            Spacer()
                            Text("\(Int(rpe)) / 10 · \(label(for: Int(rpe)))")
                                .monospacedDigit()
                                .foregroundStyle(Theme.lifting)
                        }
                        Slider(value: $rpe, in: 1...10, step: 1)
                            .tint(Theme.lifting)
                    }
                } footer: {
                    Text("Lifting doesn't raise your heart rate much, so this rating is how your gym work counts toward strain.")
                }
                Section {
                    Toggle("Save to Apple Health", isOn: $saveToHealth)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.recoveryLow)
                }
            }
            .navigationTitle("Finish workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await finish() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func label(for value: Int) -> String {
        switch value {
        case ...3: "Easy"
        case 4...6: "Moderate"
        case 7...8: "Hard"
        default: "Max effort"
        }
    }

    private func finish() async {
        isSaving = true
        defer { isSaving = false }
        // Drop sets that were never ticked off.
        for exercise in session.exercises {
            for set in exercise.sets where !set.isCompleted {
                modelContext.delete(set)
            }
        }
        session.sessionRPE = Int(rpe)
        session.endedAt = .now
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            return
        }
        if saveToHealth, let health, let end = session.endedAt {
            do {
                try await health.saveStrengthWorkout(start: session.startedAt, end: end)
                session.savedToHealth = true
                try? modelContext.save()
            } catch {
                // The workout is saved in the app either way.
            }
        }
        dismiss()
        onFinished()
    }
}
