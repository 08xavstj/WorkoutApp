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
    @State private var confirmingUnticked = false
    @State private var saveAsTemplate = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Workout effort (1–10)")
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
                    Toggle("Save as one of my workouts", isOn: $saveAsTemplate)
                } footer: {
                    if saveAsTemplate {
                        Text("You can start it again from Add → My workouts, with weights suggested from today.")
                    }
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
                    Button("Save") {
                        if untickedWithData.isEmpty {
                            Task { await finish() }
                        } else {
                            confirmingUnticked = true
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "\(untickedWithData.count) set\(untickedWithData.count == 1 ? "" : "s") with weights or reps weren't ticked off",
                isPresented: $confirmingUnticked,
                titleVisibility: .visible
            ) {
                Button("Mark \(untickedWithData.count == 1 ? "it" : "them") as done") {
                    for set in untickedWithData { set.completedAt = .now }
                    Task { await finish() }
                }
                Button("Discard \(untickedWithData.count == 1 ? "it" : "them")", role: .destructive) {
                    Task { await finish() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Sets the user filled in but didn't tick.
    private var untickedWithData: [SetLog] {
        session.exercises.flatMap(\.sets).filter { !$0.isCompleted && ($0.weightKg > 0 || $0.reps > 0) }
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
        if saveAsTemplate {
            _ = WorkoutTemplate.from(session, in: modelContext)
        }
        if let end = session.endedAt {
            if recorder.isRecording && recorder.sessionStart == session.startedAt {
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
