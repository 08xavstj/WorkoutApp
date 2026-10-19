import SwiftUI
import SwiftData
import AppCore

/// Asks how hard the session felt (this feeds strain), then saves it.
struct FinishWorkoutSheet: View {
    @Bindable var session: WorkoutSession
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthClient) private var health
    @Environment(LiveWorkoutRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Double = 7
    @State private var saveToHealth = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingRPEGuide = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("How hard was it?")
                            Spacer()
                            Text("\(Int(rpe)) / 10 · \(RPEScale.sessionLabel(Int(rpe)))")
                                .monospacedDigit()
                                .foregroundStyle(Theme.liftingText)
                        }
                        Slider(value: $rpe, in: 1...10, step: 1)
                            .tint(Theme.lifting)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rate the whole workout, not your last set. Lifting doesn't raise your heart rate much, so this rating is how your gym work counts toward strain.")
                        Button("What do the numbers mean?") { showingRPEGuide = true }
                            .font(.footnote.weight(.semibold))
                    }
                }
                Section {
                    Toggle("Save to Apple Health", isOn: $saveToHealth)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.recoveryLowText)
                }
            }
            .navigationTitle("Finish workout")
            .sheet(isPresented: $showingRPEGuide) {
                RPEGuideView()
                    .presentationDetents([.medium, .large])
            }
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
        if let end = session.endedAt {
            if recorder.isRecording {
                // The live session already holds the heart rate (AirPods / strap); save it with the workout.
                if saveToHealth {
                    do {
                        try await recorder.finish(at: end)
                        session.savedToHealth = true
                    } catch {
                        recorder.discard()
                    }
                } else {
                    recorder.discard()
                }
            } else if saveToHealth, let health {
                do {
                    try await health.saveStrengthWorkout(start: session.startedAt, end: end)
                    session.savedToHealth = true
                } catch {
                    // The workout is saved in the app either way.
                }
            }
            try? modelContext.save()
        }
        await WorkoutLiveActivity.endAll()
        dismiss()
        onFinished()
    }
}
