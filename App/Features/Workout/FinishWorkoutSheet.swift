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
    /// Set once the template is made, so a retry after a Health error doesn't make a second one.
    @State private var templateSaved = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        effortHeader
                        Slider(value: $rpe, in: 1...10, step: 1)
                            .tint(Theme.lifting)
                            .accessibilityLabel("Workout effort")
                            .accessibilityValue("\(Int(rpe)) of 10, \(RPEScale.sessionLabel(Int(rpe)))")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rate the whole workout, not your last set. Lifting doesn't raise your heart rate much, so this rating is how your gym work counts toward strain.")
                        Button("What do the numbers mean?") { showingRPEGuide = true }
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                }
                Section {
                    Toggle("Save to Apple Health", isOn: $saveToHealth)
                    Toggle("Add to saved workouts", isOn: $saveAsTemplate)
                } footer: {
                    if saveAsTemplate {
                        Text("You can start it again from Log › Saved workouts, with weights suggested from today.")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.recoveryLowText)
                }
            }
            .navigationTitle("Finish workout")
            // Effort already rated on the Apple Watch (`WatchSync`) pre-fills the slider.
            .task { if let rated = session.sessionRPE { rpe = Double(max(1, min(10, rated))) } }
            .sheet(isPresented: $showingRPEGuide) {
                RPEGuideView()
                    .presentationDetents([.medium, .large])
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // HIG: a sheet closes with Cancel, not Back (ux-audit W3).
                    Button("Cancel") { dismiss() }
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

    /// "Workout effort (1–10)" and the rating; stacked at accessibility text
    /// sizes so the rating isn't squeezed (ux-audit.md 4.8, P22).
    private var effortHeader: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
        return layout {
            Text("Workout effort (1–10)")
            if !stacked { Spacer() }
            Text("\(Int(rpe)) / 10 · \(RPEScale.sessionLabel(Int(rpe)))")
                .monospacedDigit()
                .foregroundStyle(Theme.liftingText)
        }
        .accessibilityHidden(true)
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
        // Stop the Apple Watch now, not after the Health saves below, so its
        // workout ends with the phone's and its summary can join this session.
        // (`onFinished` sends it again; repeats are harmless.)
        WatchSync.shared.sessionFinished(session)
        if saveAsTemplate, !templateSaved {
            _ = WorkoutTemplate.from(session, in: modelContext)
            templateSaved = true
        }
        if let end = session.endedAt {
            // Apple Watch (`WatchSync`): when the Watch records this session, its HKWorkout is
            // the record, so the phone saves no bare workout of its own. An AirPods
            // recording is still finished (discarding it would drop its heart-rate
            // samples); the linker pairs the two and the merge dedupes the minutes.
            let watchRecords = WatchSync.shared.watchOwnsWorkout(session)
            if recorder.isRecording && recorder.sessionStart == session.startedAt {
                // The live session already holds the heart rate (AirPods / strap); save it with the workout.
                if saveToHealth {
                    do {
                        try await recorder.finish(at: end)
                        session.savedToHealth = true
                    } catch {
                        // Stay open: the session is saved; the Health write can be retried or skipped.
                        errorMessage = healthSaveMessage(error)
                        return
                    }
                } else {
                    recorder.discard()
                }
            } else if saveToHealth, !watchRecords, let health {
                do {
                    try await health.saveStrengthWorkout(start: session.startedAt, end: end)
                    session.savedToHealth = true
                } catch {
                    errorMessage = healthSaveMessage(error)
                    return
                }
            }
            // Session RPE → Apple Health workout effort score, linked to the
            // workout just saved so Apple's Training Load counts lifting
            // (iOS 18 type; HealthKitClient+Writes; competitors.md §1g).
            if session.savedToHealth, let health {
                try? await health.saveWorkoutEffort(score: Int(rpe), start: session.startedAt, end: end)
            }
            // Pair the session with the workout a watch recorded alongside it, so
            // history shows one entry with the watch's heart rate (`WorkoutLinker`).
            if let health {
                await WorkoutLinker.link(session, health: health)
            }
            try? modelContext.save()
        }
        await WorkoutLiveActivity.endAll()
        dismiss()
        onFinished()
    }

    private func healthSaveMessage(_ error: any Error) -> String {
        "Couldn't save to Apple Health: \(error.localizedDescription) The workout is saved in Tensile. Try again, or untick Save to Apple Health."
    }
}
