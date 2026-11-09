import SwiftUI
import SwiftData
import AppCore

/// Asks how hard the session felt (this feeds strain), then saves it.
struct FinishWorkoutSheet: View {
    @Bindable var session: WorkoutSession
    /// Personal records not shown during the workout (`SetFeedback.records`).
    var records: [RecordBanner] = []
    /// The end to use instead of now: "End at 6:42 PM" from "Still training?".
    var endOverride: Date? = nil
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
                if !records.isEmpty {
                    recordsSection
                }
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
            // Opaque at the medium detent (a part-height sheet is see-through glass by default).
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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
            .confirmationDialog(uncheckedTitle, isPresented: $confirmingUnticked, titleVisibility: .visible) {
                // Leaving them out comes first: a set you changed but didn't tick usually wasn't done.
                Button(untickedWithData.count == 1 ? "Leave it out" : "Leave them out") {
                    Task { await finish() }
                }
                Button(untickedWithData.count == 1 ? "Log it as done" : "Log them as done") {
                    let sets = untickedWithData
                    Task { await finish(markingDone: sets) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationBackground(Theme.background)
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

    /// Quiet and factual, like the banner during the workout (behaviour-change.md).
    private var recordsSection: some View {
        Section("Personal records") {
            ForEach(records, id: \.order) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.exercise)
                        .font(.headline)
                    ForEach(record.lines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Working sets whose weight or reps you changed by hand but didn't tick
    /// (`LiveSessionStore.markTouched`). Sets still as the plan prefilled them
    /// weren't done, and warm-ups aren't asked about: those just go.
    private var untickedWithData: [SetLog] {
        session.exercises.flatMap { exercise in
            exercise.sets.filter { set in
                !set.isCompleted && !set.isWarmup && (set.weightKg > 0 || set.reps > 0)
                    && LiveSessionStore.isTouched(order: exercise.order, setOrder: set.order, for: session.startedAt)
            }
        }
    }

    private var uncheckedTitle: String {
        let count = untickedWithData.count
        return count == 1 ? "1 set you changed wasn't ticked off" : "\(count) sets you changed weren't ticked off"
    }

    /// When the workout ended: the "Still training?" choice, else when the Apple
    /// Watch finished it (heard late when the phone was away), else now
    /// (`LiveWorkoutRules.endDate`).
    private var endDate: Date {
        if let endOverride { return min(.now, max(session.startedAt, endOverride)) }
        let lastTick = session.exercises.flatMap(\.sets).compactMap(\.completedAt).max()
        return LiveWorkoutRules.endDate(start: session.startedAt,
                                        watchFinishedAt: LiveSessionStore.entry(for: session.startedAt).watchFinishedAt,
                                        lastTick: lastTick, now: .now)
    }

    /// Saves to Apple Health first, then ends the session: a Health error leaves
    /// the workout open and unchanged (try again, or untick Save to Apple Health),
    /// instead of ending it with its sets gone under a screen still showing it.
    private func finish(markingDone: [SetLog] = []) async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let end = endDate
        let watchRecords = WatchSync.shared.watchOwnsWorkout(session)
        let ownRecording = recorder.isRecording && recorder.sessionStart == session.startedAt
        if session.savedToHealth || watchRecords || !saveToHealth {
            // Not saving, already saved, or the Apple Watch's workout is the Health
            // record (`WatchSync`): one workout in Health, not two.
            if ownRecording { recorder.discard() }
        } else if ownRecording {
            // The live session already holds the heart rate (AirPods / strap); save it with the workout.
            do {
                try await recorder.finish(at: end)
                session.savedToHealth = true
            } catch {
                errorMessage = healthSaveMessage(error)
                return
            }
        } else if let health {
            do {
                try await health.saveStrengthWorkout(start: session.startedAt, end: end)
                session.savedToHealth = true
            } catch {
                errorMessage = healthSaveMessage(error)
                return
            }
        }
        // Now end it: the sets you chose to log, unticked ones dropped, and
        // exercises left with nothing logged dropped too (so "Add to saved
        // workouts" doesn't save a skipped exercise as 1 × 8-12).
        for set in markingDone where !set.isCompleted { set.completedAt = end }
        for exercise in session.exercises {
            for set in exercise.sets where !set.isCompleted {
                modelContext.delete(set)
            }
            if !exercise.sets.contains(where: \.isCompleted) {
                modelContext.delete(exercise)
            }
        }
        session.sessionRPE = Int(rpe)
        session.endedAt = end
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            return
        }
        // Stop the Apple Watch now, so its workout ends with the phone's and its
        // summary can join this session. (`onFinished` sends it again; repeats are harmless.)
        WatchSync.shared.sessionFinished(session)
        if saveAsTemplate, !templateSaved {
            _ = WorkoutTemplate.from(session, in: modelContext)
            templateSaved = true
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
        await WorkoutLiveActivity.endAll()
        // The summary opens once the workout screen has closed (`WorkoutSummaryPresenter`).
        CoachNudges.shared.workoutFinished(session)
        WorkoutSummaryPresenter.shared.pending = session
        dismiss()
        onFinished()
    }

    private func healthSaveMessage(_ error: any Error) -> String {
        "Couldn't save to Apple Health: \(error.localizedDescription) The workout is saved in Tensile. Try again, or untick Save to Apple Health."
    }
}
